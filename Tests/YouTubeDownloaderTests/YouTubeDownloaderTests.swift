import Foundation
import Testing
@testable import YouTubeDownloader

private let videoURL = URL(string: "https://www.youtube.com/watch?v=M7lc1UVf-VE")!

private func metadata(_ fields: [String: Any] = [:]) throws -> String {
    var value: [String: Any] = [
        "id": "M7lc1UVf-VE", "title": "Sample", "live_status": "not_live",
        "formats": [["height": 720, "vcodec": "h264", "acodec": "aac"]]
    ]
    value.merge(fields) { _, new in new }
    return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
}

@Test func progressHandlesSplitChunksAndIndependentStreams() {
    let parser = YTDLPProgressParser()
    #expect(parser.append("YT_PROGRESS|50|100|NA|10|", from: .stdout).isEmpty)
    let stderr = parser.append("YT_PROGRESS|20|NA|NA|NA|NA\n", from: .stderr)
    #expect(stderr.first?.fraction == nil)
    #expect(stderr.first?.downloadedBytes == 20)
    let stdout = parser.append("5\n", from: .stdout)
    #expect(stdout.first?.fraction == 0.5)
    #expect(stdout.first?.bytesPerSecond == 10)
    #expect(stdout.first?.etaSeconds == 5)
    #expect(YTDLPProgressParser.template.hasPrefix("download:YT_PROGRESS|"))
}

@Test(arguments: ["is_live", "is_upcoming"])
func rejectsActiveAndUpcomingStreams(status: String) throws {
    do {
        _ = try YTDLPService.decodeMetadata(stdout: metadata(["live_status": status]), stderr: "", originalURL: videoURL)
        Issue.record("A stream was accepted")
    } catch YTDLPServiceError.unsupportedLiveStream { }
}

@Test func allowsArchivedLivestreamWithVODFormats() throws {
    let info = try YTDLPService.decodeMetadata(stdout: metadata(["live_status": "was_live"]), stderr: "", originalURL: videoURL)
    #expect(info.qualities.map(\.height) == [720])
}

@Test func excludesUnpairedVideoAndDRMFormats() throws {
    let json = try metadata(["formats": [
        ["height": 1080, "vcodec": "h264", "acodec": "none"],
        ["height": 720, "vcodec": "h264", "acodec": "aac"],
        ["height": 2160, "vcodec": "h264", "acodec": "aac", "has_drm": true]
    ]])
    let info = try YTDLPService.decodeMetadata(stdout: json, stderr: "", originalURL: videoURL)
    #expect(info.qualities.map(\.height) == [720])
}

@Test func audioOnlyStreamEnablesVideoOnlyHeights() throws {
    let json = try metadata(["formats": [
        ["height": 1080, "vcodec": "h264", "acodec": "none"],
        ["height": 720, "vcodec": "h264", "acodec": "none"],
        ["vcodec": "none", "acodec": "aac"]
    ]])
    let info = try YTDLPService.decodeMetadata(stdout: json, stderr: "", originalURL: videoURL)
    #expect(info.qualities.map(\.height) == [1080, 720])
}

@Test func successfulExtractionStillReportsMissingEJS() throws {
    do {
        _ = try YTDLPService.decodeMetadata(
            stdout: metadata(), stderr: "WARNING: challenge solver script distribution was not found", originalURL: videoURL
        )
        Issue.record("Missing EJS warning was ignored")
    } catch YTDLPServiceError.missingEJS { }
}

@Test(arguments: ["https://youtu.be/x", "https://www.youtube.com/embed/videoseries?list=PL1", "https://www.youtube.com/playlist?list=PL1", "https://example.com/watch?v=M7lc1UVf-VE"])
func rejectsInvalidVideoLinks(link: String) {
    #expect(!YTDLPService.isSupportedVideoURL(URL(string: link)!))
}

@MainActor
@Test func autoLoadsValidURLAfterDebounce() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appending(path: "yt-dlp")
    let script = """
    #!/bin/sh
    printf 'call\\n' >> "$(dirname "$0")/calls"
    printf '%s\\n' '{"id":"M7lc1UVf-VE","title":"Sample","formats":[{"height":720,"vcodec":"h264","acodec":"aac"}]}'
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let tool = URL(fileURLWithPath: "/usr/bin/true")
    let model = DownloaderViewModel(toolchainStatus: ToolchainStatus(ytDLPURL: executable, ffmpegURL: tool, ffprobeURL: tool, denoURL: tool, issues: []))
    model.urlText = videoURL.absoluteString

    await model.autoLoadVideo(after: .milliseconds(5))

    #expect(model.state == .ready)
    let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)
    #expect(calls.split(separator: "\\n").count == 1)
}

@MainActor
@Test func duplicateLoadDoesNotStartAnotherProcess() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appending(path: "yt-dlp")
    let script = """
    #!/bin/sh
    printf 'call\\n' >> "$(dirname "$0")/calls"
    sleep 0.15
    printf '%s\\n' '{"id":"M7lc1UVf-VE","title":"Sample","formats":[{"height":720,"vcodec":"h264","acodec":"aac"}]}'
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let tool = URL(fileURLWithPath: "/usr/bin/true")
    let model = DownloaderViewModel(toolchainStatus: ToolchainStatus(ytDLPURL: executable, ffmpegURL: tool, ffprobeURL: tool, denoURL: tool, issues: []))
    model.urlText = videoURL.absoluteString
    let first = Task { await model.loadVideo() }
    while !model.isBusy { await Task.yield() }
    await model.loadVideo()
    await first.value
    #expect(model.state == .ready)
    let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)
    #expect(calls.split(separator: "\n").count == 1)
}

@Test func downloadUsesMP4AndDecodesJSONPath() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let destination = root.appending(path: "%(title)s\nliteral")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let outputURL = destination.appending(path: "sample.mp4")
    let encodedPath = String(decoding: try JSONEncoder().encode(outputURL.path), as: UTF8.self)
    let quotedLine = "'" + ("YT_OUTPUT|" + encodedPath).replacingOccurrences(of: "'", with: "'\\''") + "'"
    let executable = root.appending(path: "yt-dlp")
    let script = """
    #!/bin/sh
    target=''
    recode_format=''
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --paths) shift; target="$1" ;;
        --output) shift; case "$1" in */*) exit 42 ;; esac ;;
        --recode-video) shift; recode_format="$1" ;;
      esac
      shift
    done
    [ -n "$target" ] || exit 43
    [ "$recode_format" = mp4 ] || exit 44
    touch "$target/sample.mp4"
    printf '%s\\n' 'YT_PROGRESS|50|100|NA|10|5'
    printf '%s\\n' \(quotedLine)
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let tool = URL(fileURLWithPath: "/usr/bin/true")
    let service = YTDLPService(toolchain: ToolchainStatus(ytDLPURL: executable, ffmpegURL: tool, ffprobeURL: tool, denoURL: tool, issues: []))
    let video = try YTDLPService.decodeMetadata(stdout: metadata(), stderr: "", originalURL: videoURL)
    try await confirmation("download progress", expectedCount: 1) { confirm in
        let result = try await service.download(video: video, quality: video.qualities[0], directory: destination) { progress in
            confirm()
            #expect(progress.fraction == 0.5)
        }
        #expect(result.path == outputURL.path)
    }
}
