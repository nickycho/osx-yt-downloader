import SwiftUI

@main
struct YouTubeDownloaderApp: App {
    @State private var viewModel = DownloaderViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 1120, height: 720)
    }
}
