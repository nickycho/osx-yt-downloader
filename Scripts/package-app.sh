#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

swift build --configuration release
BIN_DIR="$(swift build --configuration release --show-bin-path)"
EXECUTABLE="$BIN_DIR/YouTubeDownloader"
RESOURCE_BUNDLE="$BIN_DIR/YouTubeDownloader_YouTubeDownloader.bundle"
APP_DIR="$PROJECT_DIR/build/YouTubeDownloader.app"
CONTENTS_DIR="$APP_DIR/Contents"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Release executable not found: $EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$EXECUTABLE" "$CONTENTS_DIR/MacOS/YouTubeDownloader"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Swift package resource bundle not found: $RESOURCE_BUNDLE" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$CONTENTS_DIR/Resources/"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>YouTube Downloader</string>
	<key>CFBundleExecutable</key>
	<string>YouTubeDownloader</string>
	<key>CFBundleIdentifier</key>
	<string>com.nickycho.youtube-downloader</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>YouTube Downloader</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"
test -x "$CONTENTS_DIR/MacOS/YouTubeDownloader"
test -f "$CONTENTS_DIR/Resources/AppIcon.icns"
echo "Packaged app: $APP_DIR"
