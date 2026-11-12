import Foundation

struct DependencyIssue: Identifiable, Hashable, Sendable {
    let toolName: String
    let message: String
    var localizationKey: String? = nil
    let installationURL: URL?

    var id: String { toolName }
}

struct ToolchainStatus: Sendable {
    let ytDLPURL: URL?
    let ffmpegURL: URL?
    let ffprobeURL: URL?
    let denoURL: URL?
    let issues: [DependencyIssue]

    var isReady: Bool { issues.isEmpty }

    var canLoadMetadata: Bool {
        ytDLPURL != nil && denoURL != nil
    }

    var canDownload: Bool {
        canLoadMetadata && ffmpegURL != nil && ffprobeURL != nil
    }
}

struct ToolchainLocator {
    private let fileManager = FileManager.default

    func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ToolchainStatus {
        let searchPaths = candidateDirectories(environment: environment, homeDirectory: homeDirectory)
        let ytDLPURL = findExecutable(named: "yt-dlp", in: searchPaths)
        let ffmpegURL = findExecutable(named: "ffmpeg", in: searchPaths)
        let ffprobeURL = findExecutable(named: "ffprobe", in: searchPaths)
        let denoCandidate = findExecutable(named: "deno", in: searchPaths)
        let denoURL = denoCandidate.flatMap { supportsRequiredDenoVersion(at: $0) ? $0 : nil }

        var issues: [DependencyIssue] = []
        if ytDLPURL == nil {
            issues.append(DependencyIssue(
                toolName: "yt-dlp",
                message: "找不到 yt-dlp。請依官方安裝說明安裝後重新開啟 app。",
                localizationKey: "dependency.ytdlp",
                installationURL: URL(string: "https://github.com/yt-dlp/yt-dlp/wiki/Installation")
            ))
        }
        if ffmpegURL == nil || ffprobeURL == nil {
            issues.append(DependencyIssue(
                toolName: "ffmpeg / ffprobe",
                message: "找不到 ffmpeg 或 ffprobe；合併影片與音訊需要這兩個工具。",
                localizationKey: "dependency.ffmpeg",
                installationURL: URL(string: "https://ffmpeg.org/download.html")
            ))
        }
        if denoURL == nil {
            let message = denoCandidate == nil
                ? "找不到 Deno 2.3 或更新版本；YouTube 解析需要 JavaScript runtime。"
                : "無法確認 Deno 版本或版本過舊；請確認已安裝 2.3 或更新版本。"
            issues.append(DependencyIssue(
                toolName: "Deno",
                message: message,
                localizationKey: denoCandidate == nil ? "dependency.denoMissing" : "dependency.denoOutdated",
                installationURL: URL(string: "https://deno.com/install")
            ))
        }

        return ToolchainStatus(
            ytDLPURL: ytDLPURL,
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffprobeURL,
            denoURL: denoURL,
            issues: issues
        )
    }

    private func candidateDirectories(environment: [String: String], homeDirectory: URL) -> [URL] {
        var paths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }

        paths += [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            homeDirectory.appending(path: ".deno/bin", directoryHint: .isDirectory),
            homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory),
            homeDirectory.appending(path: "bin", directoryHint: .isDirectory)
        ]

        let pythonBinRoot = homeDirectory.appending(path: "Library/Python", directoryHint: .isDirectory)
        if let pythonVersions = try? fileManager.contentsOfDirectory(at: pythonBinRoot, includingPropertiesForKeys: nil) {
            paths += pythonVersions.map { $0.appending(path: "bin", directoryHint: .isDirectory) }
        }

        var seen = Set<String>()
        return paths.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func findExecutable(named name: String, in directories: [URL]) -> URL? {
        directories
            .map { $0.appending(path: name) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func supportsRequiredDenoVersion(at executable: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            defer { timeout.cancel() }
            let versionOutput = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let firstLine = String(data: versionOutput, encoding: .utf8)?.split(separator: "\n").first else {
                return false
            }
            let versionString = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let components = versionString.split(separator: ".").compactMap { Int($0) }
            guard components.count >= 2 else { return false }
            let major = components[0]
            let minor = components[1]
            return major > 2 || (major == 2 && minor >= 3)
        } catch {
            return false
        }
    }
}
