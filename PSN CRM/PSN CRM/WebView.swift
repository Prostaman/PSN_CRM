import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Start loading immediately
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Avoid reloading if the same page is already loaded
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        // MARK: - Helpers
        private let downloadableExtensions: Set<String> = [
            "pdf", "zip", "rar", "7z", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "ics"
        ]

        private func isHTMLorText(_ response: WKNavigationResponse) -> Bool {
            let contentType = (response.response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")?
                .lowercased() ?? ""
            return contentType.contains("text/html") || contentType.contains("text/plain")
        }

        @available(iOS 15.0, *)
        private func shouldDownload(_ response: WKNavigationResponse) -> Bool {
            // Do not download HTML/text content
            if isHTMLorText(response) { return false }
            // Download by known file extensions
            if let url = response.response.url,
               downloadableExtensions.contains(url.pathExtension.lowercased()) {
                return true
            }
            // Fallback based on WebKit capability or suggested filename
            return response.canShowMIMEType == false || response.response.suggestedFilename != nil
        }

        @available(iOS 15.0, *)
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let requestURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = requestURL.scheme?.lowercased()

            // Handle links that try to open a new window (target="_blank") by loading in current webView
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            // External app schemes and App Store links
            let externalSchemes: Set<String> = [
                "tel", "mailto", "sms", "tg", "viber", "whatsapp", "fb", "facebook", "instagram", "twitter", "itms-apps", "itms-services"
            ]

            if let scheme = scheme, externalSchemes.contains(scheme) {
                UIApplication.shared.open(requestURL, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }

            // Allow http/https and universal links to proceed inside the web view
            if scheme == "https" {
                decisionHandler(.allow)
                return
            }
            
            if scheme == "http" {
                // Вариант 1: полностью блокировать
//                decisionHandler(.cancel)
//                return
                // Вариант 2: открыть во внешнем Safari
                 UIApplication.shared.open(requestURL)
                 decisionHandler(.cancel)
                 return
            }

            // For any other custom scheme, try opening via the system
            if UIApplication.shared.canOpenURL(requestURL) {
                UIApplication.shared.open(requestURL, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Handle responses that should trigger a download (e.g., Content-Disposition: attachment)
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if #available(iOS 15.0, *) {
                if shouldDownload(navigationResponse) {
                    decisionHandler(.download)
                    return
                }
            } else {
                // On older iOS versions, just allow (no WKDownload support)
            }
            decisionHandler(.allow)
        }

        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // Handle window.open and target=_blank creating new web views
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

@available(iOS 15.0, *)
extension WebView.Coordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // Save into a temporary location; present Share Sheet afterwards
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent(suggestedFilename)
        // Remove if exists
        try? FileManager.default.removeItem(at: destinationURL)
        // Remember destination to present later
        let key = ObjectIdentifier(download)
        self.downloadDestinations[key] = destinationURL
        completionHandler(destinationURL)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // You might want to surface an alert; for now, just log
        print("WKDownload failed: \(error)")
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard let fileURL = self.downloadDestinations.removeValue(forKey: key) else { return }
        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }),
               let presenter = window.rootViewController {
                activityVC.popoverPresentationController?.sourceView = presenter.view
                presenter.present(activityVC, animated: true)
            } else {
                let top = UIApplication.shared.keyWindowPresentedController
                top?.present(activityVC, animated: true)
            }
        }
    }
}

extension UIApplication {
    var keyWindowPresentedController: UIViewController? {
        guard let scene = connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) else { return nil }
        var top = keyWindow.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

#if DEBUG
#Preview {
    WebView(url: URL(string: "https://crm.poehalisnami.ua")!)
}
#endif
