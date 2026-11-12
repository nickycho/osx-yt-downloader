import Foundation

enum AppState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case downloading(DownloadProgress)
    case completed(URL)
    case failed(String)
}
