# YouTube Downloader for macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox syntax for tracking.

**Goal:** Build a native macOS app that previews a YouTube video, lets the user select a resolution, and downloads it to a chosen folder.

**Architecture:** Use a Swift Package Manager SwiftUI app. A focused service layer locates local command-line tools and uses `Process` to call yt-dlp; the view model owns the loading/download states, and a WKWebView embeds the YouTube preview.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, Foundation `Process`, yt-dlp, ffmpeg/ffprobe, Deno.

**Spec:** `docs/superpowers/specs/2026-11-11-youtube-downloader-design.md`

## Global Constraints

- Target local use on Apple Silicon Macs running macOS 14 or later.
- Only public or otherwise directly accessible videos supported by the installed yt-dlp version are in scope. The app will not attempt to bypass access controls.
- Locate required tools and show installation guidance; do not install software automatically.
- The initial target is local macOS use, not Mac App Store submission. Signing and notarization are outside the local-use MVP.
- The first version uses one active download at a time and does not resume interrupted downloads.

## Files and Responsibilities

- `Package.swift` — macOS 14+ executable target and product definition.
- `Sources/YTDownloader/YTDownloaderApp.swift` — SwiftUI app entry and main-window configuration.
- `Sources/YTDownloader/Models/VideoInfo.swift` — parsed metadata and quality options.
- `Sources/YTDownloader/Models/DownloadProgress.swift` — byte counts, fraction, and speed for the current download.
- `Sources/YTDownloader/Models/AppState.swift` — user-visible loading, ready, downloading, completed, and failed states.
- `Sources/YTDownloader/Services/ProcessRunner.swift` — safe argument-based process execution with separate stdout/stderr capture.
- `Sources/YTDownloader/Services/ToolchainLocator.swift` — locate required executables and produce dependency guidance.
- `Sources/YTDownloader/Services/YTDLPService.swift` — metadata/format extraction and download operations.
- `Sources/YTDownloader/ViewModels/DownloaderViewModel.swift` — URL, selection, destination, progress, and user-visible state.
- `Sources/YTDownloader/Views/ContentView.swift` — URL input, preview/info, quality, destination, download, and status controls.
- `Sources/YTDownloader/Views/YouTubePreview.swift` — WKWebView wrapper for the privacy-enhanced YouTube embed.
- `Scripts/package-app.sh` — wrap the built executable in `build/YouTubeDownloader.app`.
- `README.md` — dependency setup, build, packaging, and known limits.

## Interfaces

- `ProcessRunner.run(executable: URL, arguments: [String], environment: [String: String] = [:], onStdout: (@Sendable (String) -> Void)? = nil, onStderr: (@Sendable (String) -> Void)? = nil) async throws -> ProcessResult`; `ProcessResult` stores `stdout`, `stderr`, and `exitCode: Int32`.
- `ToolchainLocator.locate() -> ToolchainStatus`, where `ToolchainStatus` contains optional `ytDLPURL`, `ffmpegURL`, `ffprobeURL`, and `denoURL`, plus `[DependencyIssue]` messages. Each `DependencyIssue` contains `toolName`, `message`, and `installationURL: URL?`.
- `VideoQuality` contains `height: Int`, `label: String`, and `formatSelector: String` for that resolution.
- `VideoInfo` contains `id`, `webpageURL`, `title`, `uploader`, `duration: TimeInterval?`, `thumbnailURL: URL?`, and sorted `qualities: [VideoQuality]`.
- `DownloadProgress` contains `downloadedBytes: Int64`, optional `totalBytes: Int64`, optional `fraction: Double`, optional `bytesPerSecond: Double`, and optional `etaSeconds: Double`.
- `AppState` is `idle`, `loading`, `ready`, `downloading(DownloadProgress)`, `completed(URL)`, or `failed(String)`.
- `YTDLPService.loadVideo(url: URL) async throws -> VideoInfo`
- `YTDLPService.download(video: VideoInfo, quality: VideoQuality, directory: URL, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL`
- `DownloaderViewModel` exposes the current URL, destination, selected quality, `AppState`, and async load/download actions to the view.

## Review Focus

These behavior cases remain explicit in the owning service or view-model states. Targeted regression checks were added after review when the session's validation instructions were updated; see `Tests/YouTubeDownloaderTests/`.

- Invalid URL or playlist link: reject before starting yt-dlp and keep the URL editable.
- Missing yt-dlp, ffmpeg/ffprobe, Deno, or yt-dlp-ejs: show the specific missing requirement and setup guidance.
- Video unavailable or no downloadable video format: show an actionable error and do not enable Download.
- Quality becomes unavailable between preview and download: fail visibly without reporting success.
- yt-dlp progress on stdout or stderr, and unknown total size: keep the UI responsive and use indeterminate progress when needed.

---

### Task 1: Establish the SwiftPM app and process/tool foundations

**Files:** Create `Package.swift`, `Sources/YTDownloader/YTDownloaderApp.swift`, `Models/VideoInfo.swift`, `Models/DownloadProgress.swift`, `Models/AppState.swift`, `Services/ProcessRunner.swift`, and `Services/ToolchainLocator.swift`.

**Interfaces:** Define the shared types and exact process/tool interfaces listed above. `ProcessRunner` must pass arguments directly to `Process` without a shell and collect both output streams without blocking. `ToolchainLocator` searches inherited PATH, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.deno/bin`, and `~/Library/Python/*/bin` locations.

- [x] Create the Swift package with one executable product named `YouTubeDownloader`, macOS 14 minimum, and a SwiftUI app entry point.
- [x] Add `VideoInfo`, `VideoQuality`, `DownloadProgress`, `ProcessResult`, `ToolchainStatus`, `DependencyIssue`, and `AppState` with the fields and cases defined above.
- [x] Implement `ProcessRunner.run(...)` with asynchronous completion, separate stdout/stderr callbacks, exit-code checking, and captured stderr in thrown errors.
- [x] Implement tool discovery for yt-dlp, ffmpeg, ffprobe, and Deno; parse Deno's major/minor version and require 2.3 or newer. Surface yt-dlp-ejs guidance when yt-dlp reports the component is missing.
- [x] Run `swift build` and resolve compiler diagnostics before the service layer is added.

### Task 2: Load video metadata and available resolutions

**Files:** Create `Sources/YTDownloader/Services/YTDLPService.swift`; modify the model and toolchain files from Task 1 only when needed for this interface.

**Interfaces:** Implement `YTDLPService.loadVideo(url:) async throws -> VideoInfo`. Return sorted distinct resolutions based on yt-dlp's structured `formats` data; each option selects best compatible video+audio at that exact height, falling back to a combined format at the same height.

- [x] Invoke yt-dlp with `--dump-single-json`, `--no-playlist`, and `--ignore-config`, passing the URL as a distinct process argument.
- [x] Decode the JSON title, ID, uploader, duration, thumbnail, and downloadable formats; exclude DRM formats and entries without a video codec or height.
- [x] Map extraction errors for unsupported URLs, unavailable videos, no formats, missing JavaScript runtime, and missing yt-dlp-ejs into clear localized messages.
- [x] Run `swift build` and resolve compiler diagnostics.

### Task 3: Build the preview and metadata workflow

**Files:** Create `Sources/YTDownloader/ViewModels/DownloaderViewModel.swift`, `Sources/YTDownloader/Views/ContentView.swift`, and `Sources/YTDownloader/Views/YouTubePreview.swift`.

**Interfaces:** The view model owns `urlText`, `destinationDirectory`, `selectedQuality`, `videoInfo`, `state`, `loadVideo()`, and `startDownload()`. `YouTubePreview` accepts a YouTube video ID and displays the privacy-enhanced embed in WKWebView.

- [x] Implement URL validation for supported single-video YouTube links (`youtube.com` and `youtu.be`) and reject playlist-only links.
- [x] Add the URL field and Load action; show loading, ready, and error states while preserving the entered URL for retry.
- [x] Display the embedded preview, title, uploader, duration, and a quality picker populated only after metadata loads.
- [x] Default the destination to `~/Downloads` and add a folder picker using `NSOpenPanel`.
- [x] Run `swift build` and resolve compiler diagnostics.

### Task 4: Implement download progress and completion UI

**Files:** Modify `Sources/YTDownloader/Services/YTDLPService.swift`, `Sources/YTDownloader/ViewModels/DownloaderViewModel.swift`, and `Sources/YTDownloader/Views/ContentView.swift`.

**Interfaces:** Implement `YTDLPService.download(video:quality:directory:onProgress:) async throws -> URL`; progress is delivered as `DownloadProgress` and completion returns the final path reported by yt-dlp.

- [x] Invoke yt-dlp with the selected resolution selector, output template `%(title).200B [<height>p] [%(id)s].%(ext)s`, destination directory, `--ffmpeg-location`, `--js-runtimes deno:<path>`, `--no-playlist`, `--no-overwrites`, `--no-continue`, `--newline`, a progress template with downloaded bytes and total/estimated bytes, and path printing before and after merge.
- [x] Parse progress from both process output streams; produce determinate progress when total bytes exist and indeterminate progress otherwise.
- [x] Disable conflicting controls while one download is active; show progress, success/failure, filename, and a Reveal in Finder action.
- [x] Run `swift build` and resolve compiler diagnostics.

### Task 5: Package a launchable app and document setup

**Files:** Create `Scripts/package-app.sh` and `README.md`.

**Interfaces:** The script builds the SwiftPM release executable, creates `build/YouTubeDownloader.app/Contents/MacOS`, writes the app `Info.plist`, and copies the executable. README documents local tool setup and `open build/YouTubeDownloader.app`.

- [x] Add an executable packaging script that creates a macOS app bundle with a stable bundle identifier and version fields.
- [x] Document the minimum macOS/architecture, required tools, yt-dlp-ejs setup for Python-installed yt-dlp, build/package commands, and unsupported content types.
- [x] Run `Scripts/package-app.sh` to produce `build/YouTubeDownloader.app` and confirm the bundle contains the executable and `Info.plist`.

## Final review corrections

- Use a distinct `YT_PROGRESS|` output marker after yt-dlp's `download:` template type selector.
- Load a privacy-enhanced iframe inside a page with the app origin as base URL; bridge IFrame API playback errors to the native UI.
- Enforce one active operation in the view model as well as disabling conflicting controls.
- Reject active/upcoming live streams; retain archived streams with normal VOD formats.
- Check successful stderr for missing EJS warnings and list only heights with compatible audio.
- Validate video IDs, locate tools in the background, and separate destination paths from yt-dlp filename templates.
