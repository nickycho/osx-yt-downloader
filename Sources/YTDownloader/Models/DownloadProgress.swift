import Foundation

struct DownloadProgress: Equatable, Sendable {
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let fraction: Double?
    let bytesPerSecond: Double?
    let etaSeconds: Double?
}
