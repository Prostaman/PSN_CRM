import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    private let homeURL: URL

    init(url: URL) {
        self.url = url
        self.homeURL = url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.currentWebView = webView

        let container = UIView(frame: .zero)
        container.backgroundColor = .systemBackground

        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let homeImage = UIImage(systemName: "house")
        let homeItem = UIBarButtonItem(image: homeImage, style: .plain, target: context.coordinator, action: #selector(Coordinator.goHome))
        homeItem.accessibilityLabel = "Домой"
        let refreshItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: context.coordinator, action: #selector(Coordinator.reloadPage))
        let shareItem = UIBarButtonItem(barButtonSystemItem: .action, target: context.coordinator, action: #selector(Coordinator.sharePage))
        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.setItems([homeItem, flexible, refreshItem, flexible, shareItem], animated: false)

        let webContainer = UIView()
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(toolbar)
        container.addSubview(webContainer)
        webContainer.addSubview(webView)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.backgroundColor = .clear
        container.addSubview(spacer)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            spacer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            spacer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            spacer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spacer.heightAnchor.constraint(equalToConstant: 10),

            webContainer.topAnchor.constraint(equalTo: spacer.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])

        let request = URLRequest(url: url)
        webView.load(request)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Find WKWebView inside container
        let webView: WKWebView? = (uiView.subviews.compactMap { sub in
            if let subview = sub as? WKWebView { return subview }
            if let inner = sub.subviews.first(where: { $0 is WKWebView }) as? WKWebView { return inner }
            return nil
        }).first
        guard let webView = webView else { return }
        context.coordinator.currentWebView = webView
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        let homeURL: URL
        weak var currentWebView: WKWebView?
        init(_ parent: WebView) { self.parent = parent; self.homeURL = parent.homeURL }

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
        
        private func hideSiteOverlayAndSpinner(in webView: WKWebView) {
            let js = """
            (function() {
              try {
                var clearNodeStyles = function(el) {
                  if (!el || !el.style) return;
                  el.style.overflow = '';
                  el.style.pointerEvents = '';
                  el.style.filter = '';
                  el.style.backdropFilter = '';
                  el.style.webkitBackdropFilter = '';
                  el.style.opacity = '';
                  el.style.background = '';
                  el.style.backgroundColor = '';
                  el.style.zIndex = '';
                  if (el.style.position === 'fixed') { el.style.position = ''; }
                };

                // 1) Снять классы загрузки и сбросить стили на html/body
                if (document.body) {
                  document.body.classList.remove('loading','busy','is-loading','modal-open','dialog-open','overflow-hidden');
                  clearNodeStyles(document.body);
                }
                if (document.documentElement) {
                  document.documentElement.classList.remove('loading','busy','is-loading','modal-open','dialog-open','overflow-hidden');
                  clearNodeStyles(document.documentElement);
                }

                // 2) Скрыть типовые оверлеи/бекдропы/спиннеры/модалки
                var selectors = [
                  '.loading', '.loader', '.spinner', '.preloader',
                  '.modal-backdrop', '.modal-backdrop.show', '.modal', '.modal.show',
                  '.dialog-backdrop', '.popup-backdrop', '.overlay', '.ui-dialog', '.ui-dialog-open',
                  '[role=\"dialog\"]', '[aria-modal=\"true\"]', '[role=\"progressbar\"]',
                  '.backdrop', '.backdrop.show', '.backdrop-blur', '.scrim', '.blocking-overlay'
                ];
                var nodes = document.querySelectorAll(selectors.join(','));
                nodes.forEach(function(el){
                  el.style.display = 'none';
                  el.style.visibility = 'hidden';
                  el.classList.add('hidden');
                  el.setAttribute('aria-hidden', 'true');
                  clearNodeStyles(el);
                });

                // 3) Хард-скидка для полноэкранных перекрытий без известных классов
                var all = Array.from(document.querySelectorAll('body *')).slice(-2000);
                all.forEach(function(el) {
                  try {
                    var cs = getComputedStyle(el);
                    if (!cs) return;
                    var isFixedOrAbs = (cs.position === 'fixed' || cs.position === 'absolute');
                    var fullWidth = (cs.left === '0px' && (cs.width === '100vw' || cs.width === '100%' || cs.right === '0px'));
                    var fullHeight = (cs.top === '0px' && (cs.height === '100vh' || cs.height === '100%' || cs.bottom === '0px'));
                    var isFull = isFixedOrAbs && fullWidth && fullHeight;

                    var hasBackdrop = (cs.backgroundColor && cs.backgroundColor !== 'rgba(0, 0, 0, 0)')
                      || (cs.backdropFilter && cs.backdropFilter !== 'none')
                      || (cs.webkitBackdropFilter && cs.webkitBackdropFilter !== 'none');

                    var z = parseInt(cs.zIndex || '0', 10);

                    if (isFull && hasBackdrop && z >= 10) {
                      el.style.display = 'none';
                      el.style.visibility = 'hidden';
                      el.setAttribute('aria-hidden', 'true');
                    }
                  } catch (e) {}
                });

                // 4) Закрыть модальные, если у них есть публичные методы
                if (window.$ && $.fn && $.fn.modal) { $('.modal').modal('hide'); }
                if (window.hideSpinner) { window.hideSpinner(); }
                if (window.closePopup) { window.closePopup(); }

                // 5) Сигнал на страницу
                if (window.postMessage) { window.postMessage({type:'download-finished'}, '*'); }
              } catch (e) {}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        @objc func goHome() {
            guard let webView = currentWebView else { return }
            webView.load(URLRequest(url: homeURL))
        }

        @objc func reloadPage() {
            currentWebView?.reload()
        }

        @objc func sharePage() {
            guard let webView = currentWebView else { return }
            let shareURL = webView.url ?? homeURL
            let activityVC = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
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

        var downloadDestinations: [ObjectIdentifier: URL] = [:]

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            self.currentWebView = webView
            
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
                "tel", "mailto", "sms", "tg", "viber", "whatsapp", "fb", "facebook", "instagram", "twitter", "itms-apps"
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
            self.currentWebView = webView
            
            if #available(iOS 15.0, *) {
                if shouldDownload(navigationResponse) {
                    hideSiteOverlayAndSpinner(in: webView)
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
            self.currentWebView = webView
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
        
        print("downloadDidFinish")
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
