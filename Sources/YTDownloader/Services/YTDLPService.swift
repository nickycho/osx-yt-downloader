import Foundation

struct YTDLPService {
    private let toolchain: ToolchainStatus
    private let processRunner: ProcessRunner

    init(toolchain: ToolchainStatus, processRunner: ProcessRunner = ProcessRunner()) {
        self.toolchain = toolchain
        self.processRunner = processRunner
    }

    static func isSupportedVideoURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathParts = url.pathComponents.filter { $0 != "/" }

        func validID(_ value: String?) -> Bool {
            guard let value else { return false }
            guard value != "videoseries" else { return false }
            return value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
        }
        if host == "youtu.be" || host == "www.youtu.be" {
            return pathParts.count == 1 && validID(pathParts.first)
        }

        let supportedHosts: Set<String> = [
            "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"
        ]
        guard supportedHosts.contains(host) else { return false }

        if url.path == "/watch" {
            return validID(components?.queryItems?.first(where: { $0.name == "v" })?.value)
        }

        let videoRoutes: Set<String> = ["shorts", "live", "embed"]
        return pathParts.count == 2 && videoRoutes.contains(pathParts[0]) && validID(pathParts[1])
    }

    func loadVideo(url: URL) async throws -> VideoInfo {
        guard Self.isSupportedVideoURL(url) else {
            throw YTDLPServiceError.unsupportedURL
        }
        let metadataIssues = toolchain.issues.filter { ["yt-dlp", "Deno"].contains($0.toolName) }
        guard metadataIssues.isEmpty, let ytDLPURL = toolchain.ytDLPURL, let denoURL = toolchain.denoURL else {
            throw YTDLPServiceError.missingTools(metadataIssues)
        }

        do {
            let result = try await processRunner.run(
                executable: ytDLPURL,
                arguments: [
                    "--dump-single-json",
                    "--no-playlist",
                    "--ignore-config",
                    "--js-runtimes",
                    "deno:\(denoURL.path)",
                    url.absoluteString
                ],
                environment: processEnvironment()
            )

            return try Self.decodeMetadata(stdout: result.stdout, stderr: result.stderr, originalURL: url)
        } catch let runnerError as ProcessRunnerError {
            if let processResult = runnerError.processResult {
                throw Self.mapExtractionError(processResult.stderr + "\n" + processResult.stdout)
            }
            throw YTDLPServiceError.toolLaunch(runnerError.localizedDescription)
        } catch let serviceError as YTDLPServiceError {
            throw serviceError
        } catch {
            throw YTDLPServiceError.extractionFailed(error.localizedDescription)
        }
    }

    func download(
        video: VideoInfo,
        quality: VideoQuality,
        directory: URL,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        guard toolchain.canDownload,
              let ytDLPURL = toolchain.ytDLPURL,
              let ffmpegURL = toolchain.ffmpegURL,
              let denoURL = toolchain.denoURL else {
            throw YTDLPServiceError.missingTools(toolchain.issues)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw YTDLPServiceError.destinationUnavailable(error.localizedDescription)
        }

        let outputTemplate = "%(title).200B [\(quality.height)p] [%(id)s].%(ext)s"
        let progressParser = YTDLPProgressParser()

        do {
            let result = try await processRunner.run(
                executable: ytDLPURL,
                arguments: [
                    "--format", quality.formatSelector,
                    "--paths", directory.path,
                    "--output", outputTemplate,
                    "--ffmpeg-location", ffmpegURL.deletingLastPathComponent().path,
                    "--recode-video", "mp4",
                    "--js-runtimes", "deno:\(denoURL.path)",
                    "--no-playlist",
                    "--ignore-config",
                    "--no-overwrites",
                    "--no-continue",
                    "--no-simulate",
                    "--no-colors",
                    "--newline",
                    "--progress",
                    "--progress-template", YTDLPProgressParser.template,
                    "--print", "YT_OUTPUT|%(filename)j",
                    "--print", "after_move:YT_OUTPUT|%(filepath)j",
                    video.webpageURL.absoluteString
                ],
                environment: processEnvironment(),
                onStdout: { chunk in
                    progressParser.append(chunk, from: .stdout).forEach(onProgress)
                },
                onStderr: { chunk in
                    progressParser.append(chunk, from: .stderr).forEach(onProgress)
                }
            )

            try Self.checkDependencies(in: result.stderr)
            let outputURLs = result.stdout.components(separatedBy: .newlines).compactMap { line -> URL? in
                guard line.hasPrefix("YT_OUTPUT|"),
                      let data = String(line.dropFirst("YT_OUTPUT|".count)).data(using: .utf8),
                      let path = try? JSONDecoder().decode(String.self, from: data) else { return nil }
                return URL(fileURLWithPath: path)
            }
            if let outputURL = outputURLs.reversed().first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return outputURL
            }
            throw YTDLPServiceError.outputPathUnavailable
        } catch let runnerError as ProcessRunnerError {
            if let processResult = runnerError.processResult {
                throw Self.mapDownloadError(processResult.stderr + "\n" + processResult.stdout)
            }
            throw YTDLPServiceError.toolLaunch(runnerError.localizedDescription)
        } catch let serviceError as YTDLPServiceError {
            throw serviceError
        } catch {
            throw YTDLPServiceError.downloadFailed(error.localizedDescription)
        }
    }

    static func decodeMetadata(stdout: String, stderr: String, originalURL: URL) throws -> VideoInfo {
        try checkDependencies(in: stderr)
        guard let data = stdout.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPServiceError.invalidMetadata
        }
        return try parseVideoInfo(json: json, originalURL: originalURL)
    }

    private static func parseVideoInfo(json: [String: Any], originalURL: URL) throws -> VideoInfo {
        guard let id = json["id"] as? String, !id.isEmpty,
              let title = json["title"] as? String, !title.isEmpty else {
            throw YTDLPServiceError.invalidMetadata
        }

        let liveStatus = json["live_status"] as? String
        if (json["is_live"] as? Bool) == true || ["is_live", "is_upcoming"].contains(liveStatus ?? "") {
            throw YTDLPServiceError.unsupportedLiveStream
        }
        let formats = (json["formats"] as? [[String: Any]] ?? []).filter { ($0["has_drm"] as? Bool) != true }
        let hasAudioOnly = formats.contains {
            ($0["vcodec"] as? String) == "none" && ($0["acodec"] as? String).map { $0 != "none" } == true
        }
        let combinedHeights = Set(formats.compactMap { format -> Int? in
            guard (format["vcodec"] as? String).map({ $0 != "none" }) == true,
                  (format["acodec"] as? String).map({ $0 != "none" }) == true else { return nil }
            return format["height"] as? Int
        })
        let heights = Set(formats.compactMap { format -> Int? in
            guard (format["has_drm"] as? Bool) != true,
                  let videoCodec = format["vcodec"] as? String,
                  videoCodec != "none",
                  let height = format["height"] as? Int,
                  height > 0 else {
                return nil
            }
            return hasAudioOnly || combinedHeights.contains(height) ? height : nil
        })

        guard !heights.isEmpty else {
            throw YTDLPServiceError.noFormats
        }

        let qualities = heights
            .sorted(by: >)
            .map { height in
                VideoQuality(
                    height: height,
                    label: "\(height)p",
                    formatSelector: "bestvideo[height=\(height)]+bestaudio/best[height=\(height)]"
                )
            }

        let webpageURL = (json["webpage_url"] as? String).flatMap(URL.init(string:)) ?? originalURL
        let thumbnailURL = (json["thumbnail"] as? String).flatMap(URL.init(string:))

        return VideoInfo(
            id: id,
            webpageURL: webpageURL,
            title: title,
            uploader: (json["uploader"] as? String) ?? (json["channel"] as? String) ?? "",
            duration: json["duration"] as? TimeInterval,
            thumbnailURL: thumbnailURL,
            qualities: qualities
        )
    }

    private func processEnvironment() -> [String: String] {
        let processInfo = ProcessInfo.processInfo
        var paths = (processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)

        [toolchain.ytDLPURL, toolchain.ffmpegURL, toolchain.ffprobeURL, toolchain.denoURL]
            .compactMap { $0?.deletingLastPathComponent().path }
            .forEach { paths.append($0) }

        return ["PATH": Array(NSOrderedSet(array: paths))
            .compactMap { $0 as? String }
            .joined(separator: ":")]
    }

    private static func mapExtractionError(_ output: String) -> YTDLPServiceError {
        let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = details.lowercased()

        if let dependencyError = dependencyError(in: normalized) { return dependencyError }
        if normalized.contains("unsupported url") {
            return .unsupportedURL
        }
        if normalized.contains("video unavailable") || normalized.contains("private video") || normalized.contains("members-only") {
            return .videoUnavailable
        }
        if normalized.contains("no video formats") || normalized.contains("requested format is not available") {
            return .noFormats
        }
        return .extractionFailed(details.isEmpty ? "請確認網址和網路連線後重試。" : details)
    }

    private static func checkDependencies(in output: String) throws {
        if let error = dependencyError(in: output) { throw error }
    }

    private static func dependencyError(in output: String) -> YTDLPServiceError? {
        let normalized = output.lowercased()
        let missingWords = ["missing", "not found", "not installed", "not available", "unavailable", "failed", "no supported"]
        let reportsMissing = missingWords.contains { normalized.contains($0) }
        if normalized.contains("no ejs script") || normalized.contains("challenge solver script distribution") ||
            (normalized.contains("yt-dlp-ejs") && reportsMissing) {
            return .missingEJS
        }
        if (normalized.contains("javascript runtime") || normalized.contains("js runtime")) && reportsMissing {
            return .missingJavaScriptRuntime
        }
        return nil
    }

    private static func mapDownloadError(_ output: String) -> YTDLPServiceError {
        let mapped = mapExtractionError(output)
        if case let .extractionFailed(message) = mapped {
            return .downloadFailed(message)
        }
        return mapped
    }
}

enum YTDLPServiceError: LocalizedError {
    case unsupportedURL
    case missingTools([DependencyIssue])
    case missingJavaScriptRuntime
    case missingEJS
    case videoUnavailable
    case noFormats
    case unsupportedLiveStream
    case invalidMetadata
    case toolLaunch(String)
    case extractionFailed(String)
    case downloadFailed(String)
    case destinationUnavailable(String)
    case outputPathUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "請貼上 YouTube 單一影片網址，例如 youtube.com/watch 或 youtu.be。"
        case let .missingTools(issues):
            return issues.map(\.message).joined(separator: "\n\n")
        case .missingJavaScriptRuntime:
            return "yt-dlp 找不到 JavaScript runtime。請安裝 Deno 2.3 或更新版本後再試。"
        case .missingEJS:
            return "yt-dlp 缺少 YouTube JavaScript 支援套件 yt-dlp-ejs。若使用 Python 安裝，請在 yt-dlp 所用的 Python 環境安裝 `yt-dlp[default]`。\n\n安裝說明：https://github.com/yt-dlp/yt-dlp/wiki/EJS"
        case .videoUnavailable:
            return "影片目前無法取得，可能已下架、設為私人，或受到地區限制。"
        case .noFormats:
            return "yt-dlp 沒有找到可下載的影片畫質。"
        case .unsupportedLiveStream:
            return "目前不支援直播或即將開始的直播。請在直播結束並轉為一般影片後重新載入。"
        case .invalidMetadata:
            return "無法讀取影片資訊，請更新 yt-dlp 後重試。"
        case let .toolLaunch(message):
            return message
        case let .extractionFailed(message):
            return "載入影片失敗：\(message)"
        case let .downloadFailed(message):
            return "下載失敗：\(message)"
        case let .destinationUnavailable(message):
            return "無法使用下載資料夾：\(message)"
        case .outputPathUnavailable:
            return "下載完成後找不到輸出檔案。"
        }
    }
}

final class YTDLPProgressParser: @unchecked Sendable {
    static let marker = "YT_PROGRESS|"
    static let template = "download:YT_PROGRESS|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s"

    enum Stream {
        case stdout
        case stderr
    }

    private let lock = NSLock()
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    func append(_ chunk: String, from stream: Stream) -> [DownloadProgress] {
        lock.lock()
        defer { lock.unlock() }

        switch stream {
        case .stdout:
            stdoutBuffer.append(chunk)
            return consumeLines(from: &stdoutBuffer)
        case .stderr:
            stderrBuffer.append(chunk)
            return consumeLines(from: &stderrBuffer)
        }
    }

    private func consumeLines(from buffer: inout String) -> [DownloadProgress] {
        var progressValues: [DownloadProgress] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let progress = parseProgressLine(line) {
                progressValues.append(progress)
            }
        }
        return progressValues
    }

    private func parseProgressLine(_ line: String) -> DownloadProgress? {
        guard line.hasPrefix(Self.marker) else { return nil }
        let values = line.dropFirst(Self.marker.count).split(separator: "|", omittingEmptySubsequences: false)
        guard values.count >= 5,
              let downloadedBytes = Int64(values[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let totalBytes = parseInt64(values[1]) ?? parseInt64(values[2])
        let fraction = totalBytes.flatMap { total -> Double? in
            guard total > 0 else { return nil }
            return min(Double(downloadedBytes) / Double(total), 1)
        }

        return DownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            fraction: fraction,
            bytesPerSecond: parseDouble(values[3]),
            etaSeconds: parseDouble(values[4])
        )
    }

    private func parseInt64(_ value: Substring) -> Int64? {
        Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseDouble(_ value: Substring) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "NA", trimmed != "None", !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}
