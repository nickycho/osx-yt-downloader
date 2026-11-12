# YouTube Downloader for macOS — Design

## Intent

Build a small native macOS app that lets a user paste a YouTube URL, inspect and preview the video, choose a download resolution, and save the result locally. The project directory is currently empty, so the first release establishes the app structure as well as the requested workflow.

## Goals

- Accept standard YouTube video URLs and load the video on demand.
- Show a playable YouTube preview alongside basic metadata such as title, channel, and duration.
- Offer the available video resolutions as clear quality choices.
- Download the selected resolution, combine video and audio when needed, and show progress and completion state.
- Default the destination to the user's Downloads folder and let them choose another folder.
- Keep the app native to macOS and make failures understandable, including invalid links, unavailable videos, and missing command-line tools.
- Target local use on Apple Silicon Macs running macOS 14 or later.

## Non-goals for the first version

- Playlists, channels, live streams, batch queues, audio-only conversion, subtitle controls, or format/container tuning.
- Browser-cookie import, account login, or handling age-restricted/private videos.
- App Store distribution, automatic dependency installation, or automatic updates.

## Proposed user flow

1. The user pastes a YouTube URL and selects **Load** (Return in the field may do the same).
2. The app validates that it is a supported YouTube URL, loads metadata and format information, and displays a YouTube player preview with title, channel, and duration.
3. The user selects a resolution from a quality menu. The app pairs the best compatible video and audio streams for that resolution.
4. The user optionally changes the destination folder, then starts the download.
5. The app shows progress, then a success state with the saved filename and an action to reveal it in Finder. Errors leave the URL available for retry.

## Implementation choices

- Use Swift and SwiftUI for a native macOS window. Build with Swift Package Manager so the project stays lightweight and can be opened in Xcode.
- Use `WKWebView` with YouTube's privacy-enhanced embed host for the actual in-app preview.
- Use `yt-dlp` to extract metadata and available resolutions and to perform downloads. Prefer structured JSON output for metadata and progress output for download status; do not parse the human-readable format table.
- Use `ffmpeg` through yt-dlp for merging separate video and audio streams.
- Locate `yt-dlp`, `ffmpeg`/`ffprobe`, and a supported JavaScript runtime (Deno preferred) through the app's PATH plus common macOS Homebrew and user-local locations. Check that yt-dlp-ejs YouTube support is available as well. If a required component is missing, explain which tool is needed and show installation guidance; do not install software automatically.
- Provide a small packaging script to wrap the executable as a launchable `.app`. The initial target is local macOS use, not Mac App Store submission.
- Build for Apple Silicon with macOS 14 as the minimum deployment target; signing and notarization are outside the local-use MVP.

## Constraints and failure behavior

- Only public or otherwise directly accessible videos supported by the installed yt-dlp version are in scope. The app will not attempt to bypass access controls.
- Current yt-dlp documentation recommends ffmpeg/ffprobe and requires yt-dlp-ejs plus a supported JavaScript runtime for full YouTube support, so dependency checks must account for them.
- Dependency behavior follows the [official yt-dlp dependencies documentation](https://github.com/yt-dlp/yt-dlp#dependencies) and may change as yt-dlp updates.
- YouTube embeds can be disabled by an uploader or fail because of network, regional, or content restrictions; show a useful preview error while retaining any metadata and download options that loaded successfully.
- Format availability varies by video. Show only resolutions for which yt-dlp reports a compatible download choice, and report a clear error if that choice becomes unavailable before download.
- The first version uses one active download at a time and does not resume interrupted downloads.
- Downloads are saved with a sanitized video title and a suitable container selected by yt-dlp.

## Visual direction

Use a focused single-window layout: URL field and Load action at the top; a video preview with title and channel in the main area; quality, destination, and Download controls beside or below it; progress and status near the Download action. Keep the screen quiet and make the next action obvious.

## Calls left to the builder

- Exact spacing, typography, iconography, and window dimensions.
- The precise user-local executable search paths, filename collision behavior, and progress parsing details.
- The final `.app` identifier and packaging mechanics.

## Approval checkpoint

This document reflects the user's choices of local-only use and macOS 14+ on Apple Silicon. Implementation starts after the user approves this complete first-release description or corrects any part of it.
