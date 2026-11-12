import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: DownloaderViewModel
    @Environment(LanguageSettings.self) private var languageSettings

    var body: some View {
        VStack(spacing: 20) {
            header

            if viewModel.isCheckingTools {
                ProgressView(languageSettings.string("tools.checking"))
                    .controlSize(.small)
            }

            if !viewModel.toolchainStatus.issues.isEmpty {
                dependencyBanner
            }

            Divider()

            if let video = viewModel.videoInfo {
                videoContent(video)
            } else {
                emptyContent
            }
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 660)
        .task(id: viewModel.urlText) {
            await viewModel.autoLoadVideo()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.red)
            TextField(languageSettings.string("url.placeholder"), text: $viewModel.urlText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit { loadVideo() }
                .disabled(viewModel.isBusy)
            Button(action: loadVideo) {
                if viewModel.state == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 88)
                } else {
                    Label(languageSettings.string("url.load"), systemImage: "arrow.down.circle")
                        .frame(width: 88)
                }
            }
            .controlSize(.large)
            .disabled(viewModel.isBusy || !viewModel.toolchainStatus.canLoadMetadata)
        }
    }

    private var dependencyBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(languageSettings.string("dependency.heading"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(viewModel.toolchainStatus.issues) { issue in
                HStack(alignment: .firstTextBaseline) {
                    Text(issue.localizedMessage(using: languageSettings))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if let url = issue.installationURL {
                        Link(languageSettings.string("dependency.installGuide"), destination: url)
                            .font(.callout)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(languageSettings.string("loading.video"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label(languageSettings.string("error.loadTitle"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(viewModel.failureMessage ?? "")
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            ContentUnavailableView {
                Label(languageSettings.string("empty.title"), systemImage: "play.rectangle")
            } description: {
                Text(languageSettings.string("empty.description"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func videoContent(_ video: VideoInfo) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                YouTubePreview(videoID: video.id, errorMessage: $viewModel.previewError)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }

                if let previewError = viewModel.previewError {
                    Label(languageSettings.string(previewError), systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(languageSettings.string("preview.embedHint"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        if !video.uploader.isEmpty {
                            Text(video.uploader)
                        }
                        if let duration = video.duration {
                            Text("·")
                            Text(durationText(duration))
                        }
                        Spacer()
                        Link(languageSettings.string("video.openYoutube"), destination: video.webpageURL)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            downloadSettings(for: video)
                .frame(width: 300)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func downloadSettings(for video: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(languageSettings.string("download.settings"), systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(languageSettings.string("download.quality"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker(languageSettings.string("download.quality"), selection: $viewModel.selectedQuality) {
                    ForEach(video.qualities) { quality in
                        Text(quality.label).tag(Optional(quality))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(viewModel.isDownloading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(languageSettings.string("download.location"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(viewModel.destinationDirectory.path)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                Button(languageSettings.string("download.chooseFolder"), systemImage: "folder.badge.gearshape") {
                    viewModel.chooseDestination()
                }
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }

            Spacer(minLength: 4)

            Button(languageSettings.string("download.start"), systemImage: "arrow.down.to.line") {
                Task { await viewModel.startDownload() }
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.canStartDownload)

            downloadStatus

            Text(languageSettings.string("download.qualityHint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var downloadStatus: some View {
        switch viewModel.state {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 7) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(progressDescription(progress))
                    Spacer(minLength: 8)
                    if let speed = progress.bytesPerSecond {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case let .completed(fileURL):
            VStack(alignment: .leading, spacing: 8) {
                Label(languageSettings.string("download.complete"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button(languageSettings.string("download.showInFinder"), systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .controlSize(.small)
            }
        case .failed where viewModel.videoInfo != nil:
            Text(viewModel.failureMessage ?? "")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        default:
            EmptyView()
        }
    }

    private func loadVideo() {
        Task { await viewModel.loadVideo() }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration), 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func progressDescription(_ progress: DownloadProgress) -> String {
        let downloaded = ByteCountFormatter.string(fromByteCount: progress.downloadedBytes, countStyle: .file)
        if let totalBytes = progress.totalBytes {
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(downloaded) / \(total)"
        }
        return languageSettings.format("download.progressAmount", downloaded)
    }
}
