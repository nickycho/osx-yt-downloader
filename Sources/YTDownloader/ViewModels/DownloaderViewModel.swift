import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DownloaderViewModel {
    private enum FailurePresentation {
        case localizedKey(String)
        case dependencies([DependencyIssue])
        case service(YTDLPServiceError)
        case raw(String)

        @MainActor func message(using settings: LanguageSettings) -> String {
            switch self {
            case let .localizedKey(key):
                settings.string(key)
            case let .dependencies(issues):
                issues.map { $0.localizedMessage(using: settings) }.joined(separator: "\n\n")
            case let .service(error):
                error.localizedMessage(using: settings)
            case let .raw(message):
                message
            }
        }
    }

    var urlText = ""
    var destinationDirectory: URL
    var selectedQuality: VideoQuality?
    var videoInfo: VideoInfo?
    var state: AppState = .idle
    var previewError: String?

    private(set) var toolchainStatus: ToolchainStatus
    private(set) var isCheckingTools: Bool
    private let languageSettings: LanguageSettings
    private var ytdlpService: YTDLPService
    private var loadRequestCount = 0
    private var failurePresentation: FailurePresentation?

    var failureMessage: String? {
        guard case .failed = state, let failurePresentation else { return nil }
        return failurePresentation.message(using: languageSettings)
    }

    var canStartDownload: Bool {
        guard toolchainStatus.canDownload, videoInfo != nil, selectedQuality != nil else { return false }
        if case .loading = state { return false }
        if isDownloading { return false }
        return true
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    var isBusy: Bool {
        if case .loading = state { return true }
        return isDownloading
    }

    init(toolchainStatus: ToolchainStatus? = nil, languageSettings: LanguageSettings = .shared) {
        self.languageSettings = languageSettings
        let resolvedToolchain = toolchainStatus ?? ToolchainStatus(ytDLPURL: nil, ffmpegURL: nil, ffprobeURL: nil, denoURL: nil, issues: [])
        self.toolchainStatus = resolvedToolchain
        self.ytdlpService = YTDLPService(toolchain: resolvedToolchain)
        self.isCheckingTools = toolchainStatus == nil
        self.destinationDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
        if toolchainStatus == nil {
            Task { [weak self] in
                let status = await Task.detached(priority: .utility) { ToolchainLocator().locate() }.value
                guard let self else { return }
                self.toolchainStatus = status
                self.ytdlpService = YTDLPService(toolchain: status)
                self.isCheckingTools = false
            }
        }
    }

    func loadVideo() async {
        guard !isBusy, !isCheckingTools else { return }
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              YTDLPService.isSupportedVideoURL(url) else {
            videoInfo = nil
            selectedQuality = nil
            fail(.localizedKey("error.invalidURL"))
            return
        }

        loadRequestCount += 1
        guard toolchainStatus.canLoadMetadata else {
            let requiredIssues = toolchainStatus.issues.filter { ["yt-dlp", "Deno"].contains($0.toolName) }
            fail(.dependencies(requiredIssues))
            return
        }

        failurePresentation = nil
        state = .loading
        videoInfo = nil
        selectedQuality = nil
        previewError = nil

        do {
            let result = try await ytdlpService.loadVideo(url: url)
            videoInfo = result
            selectedQuality = result.qualities.first
            state = .ready
        } catch {
            if let serviceError = error as? YTDLPServiceError {
                fail(.service(serviceError))
            } else {
                fail(.raw(error.localizedDescription))
            }
        }
    }

    func autoLoadVideo(after delay: Duration = .milliseconds(400)) async {
        let pendingText = urlText
        guard let url = URL(string: pendingText.trimmingCharacters(in: .whitespacesAndNewlines)),
              YTDLPService.isSupportedVideoURL(url) else { return }
        let requestCount = loadRequestCount

        do {
            try await Task.sleep(for: delay)
            while isCheckingTools {
                try await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, urlText == pendingText, loadRequestCount == requestCount else { return }
            }
        } catch {
            return
        }

        guard !Task.isCancelled, urlText == pendingText, loadRequestCount == requestCount else { return }
        await loadVideo()
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = languageSettings.string("folder.panelTitle")
        panel.prompt = languageSettings.string("folder.panelPrompt")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationDirectory

        if panel.runModal() == .OK, let selectedURL = panel.url {
            destinationDirectory = selectedURL
        }
    }

    func startDownload() async {
        guard !isBusy else { return }
        guard let videoInfo, let selectedQuality else { return }
        guard toolchainStatus.canDownload else {
            fail(.dependencies(toolchainStatus.issues))
            return
        }

        failurePresentation = nil
        state = .downloading(DownloadProgress(
            downloadedBytes: 0,
            totalBytes: nil,
            fraction: nil,
            bytesPerSecond: nil,
            etaSeconds: nil
        ))

        do {
            let outputURL = try await ytdlpService.download(
                video: videoInfo,
                quality: selectedQuality,
                directory: destinationDirectory,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(progress)
                    }
                }
            )
            state = .completed(outputURL)
        } catch {
            if let serviceError = error as? YTDLPServiceError {
                fail(.service(serviceError))
            } else {
                fail(.raw(error.localizedDescription))
            }
        }
    }

    private func fail(_ presentation: FailurePresentation) {
        failurePresentation = presentation
        state = .failed(presentation.message(using: languageSettings))
    }
}
