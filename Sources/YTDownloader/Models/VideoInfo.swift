import Foundation

struct VideoQuality: Identifiable, Hashable, Sendable {
    let height: Int
    let label: String
    let formatSelector: String

    var id: Int { height }
}

struct VideoInfo: Identifiable, Sendable {
    let id: String
    let webpageURL: URL
    let title: String
    let uploader: String
    let duration: TimeInterval?
    let thumbnailURL: URL?
    let qualities: [VideoQuality]
}
