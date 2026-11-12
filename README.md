# YouTube Downloader for macOS

A native macOS app for previewing YouTube videos, choosing a resolution, and downloading the result as an MP4 file.

## Features

- Paste a single YouTube video URL and automatically load its preview and metadata.
- View the title, channel, duration, and available video qualities.
- Choose a resolution and download folder.
- Track download progress and reveal completed files in Finder.
- Support English, Traditional Chinese, Japanese, and Korean. The app follows the macOS preferred language when supported, falls back to English otherwise, and lets you override the language in Settings.

## Requirements

- macOS 14 or later on Apple Silicon.
- Swift 6 and Xcode Command Line Tools to build the app.
- `yt-dlp`, `ffmpeg`, `ffprobe`, and Deno 2.3 or later.

Install the main tools with Homebrew:

```sh
brew install yt-dlp ffmpeg deno
```

If yt-dlp reports missing YouTube JavaScript support and was installed with Python, install its default dependencies in the same Python environment:

```sh
python3 -m pip install -U "yt-dlp[default]"
```

Requirements vary by yt-dlp installation method. See the [yt-dlp EJS installation guide](https://github.com/yt-dlp/yt-dlp/wiki/EJS) and [dependency documentation](https://github.com/yt-dlp/yt-dlp#dependencies). The app does not install or update these tools for you.

## Build and Run

From the project directory, run:

```sh
Scripts/package-app.sh
open build/YouTubeDownloader.app
```

The packaged app is created at `build/YouTubeDownloader.app`. It is ad-hoc signed for local use; it is not Developer ID signed or notarized.

## Usage

1. Paste a single YouTube video URL. The app loads it automatically.
2. Review the preview, video details, and available qualities.
3. Choose a resolution and destination folder, then select **Download Video**.
4. When the download finishes, select **Show in Finder** to locate the MP4 file.

Available resolutions depend on the source video. If embedding is disabled, you can still use the video details and download settings or open the video on YouTube.

## Limitations

- Downloads one video at a time. Playlists, live streams, cookies or sign-in, private or age-restricted videos, and resuming partial downloads are not supported.
- The app relies on yt-dlp and does not bypass access restrictions.
- YouTube formats and access behavior can change. If extraction fails, update yt-dlp and try again.

## Development

Run the test suite with:

```sh
swift test
```

The tests cover URL validation, automatic loading behavior, MP4 output, progress parsing, live-stream filtering, format selection, and dependency errors.
