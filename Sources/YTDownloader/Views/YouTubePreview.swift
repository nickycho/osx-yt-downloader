import SwiftUI
import WebKit

struct YouTubePreview: NSViewRepresentable {
    let videoID: String
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(videoID: videoID) { errorMessage = $0 }
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "previewEvent")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        loadPlayer(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onError = { errorMessage = $0 }
        guard context.coordinator.videoID != videoID else { return }
        context.coordinator.videoID = videoID
        loadPlayer(in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "previewEvent")
    }

    private func loadPlayer(in webView: WKWebView) {
        let bundleID = (Bundle.main.bundleIdentifier ?? "com.nickycho.youtube-downloader").lowercased()
        let origin = URL(string: "https://\(bundleID)")!
        var components = URLComponents(string: "https://www.youtube-nocookie.com")!
        components.path = "/embed/\(videoID)"
        components.queryItems = [
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: origin.absoluteString),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0")
        ]
        let source = components.url!.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        let html = """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;width:100%;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe id="player" src="\(source)" referrerpolicy="strict-origin-when-cross-origin"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        <script>
        function onYouTubeIframeAPIReady() {
          new YT.Player('player', {events: {
            onReady: function() { window.webkit.messageHandlers.previewEvent.postMessage(0); },
            onError: function(event) { window.webkit.messageHandlers.previewEvent.postMessage(event.data); }
          }});
        }
        </script>
        <script src="https://www.youtube.com/iframe_api"
          onerror="window.webkit.messageHandlers.previewEvent.postMessage(-1)"></script>
        </body></html>
        """
        // The base URL supplies the app's identity as the enclosing page's Referer.
        webView.loadHTMLString(html, baseURL: origin)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var videoID: String
        var onError: (String?) -> Void

        init(videoID: String, onError: @escaping (String?) -> Void) {
            self.videoID = videoID
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let code = message.body as? Int else { return }
            switch code {
            case 0: onError(nil)
            case 101, 150: onError("preview.embeddingDisabled")
            case 100: onError("preview.removed")
            case 153: onError("preview.playerUnknown")
            default: onError("preview.playbackError")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportNavigationError(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportNavigationError(error)
        }

        private func reportNavigationError(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onError("preview.error")
        }
    }
}
