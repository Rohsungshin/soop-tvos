import UIKit
import WebKit

// MARK: - iOS WKWebView 브라우저

class iOSViewController: UIViewController, WKNavigationDelegate, LoginManager.WebViewProviding {

    private var webView: WKWebView!
    private var loginManager: LoginManager!
    private var overlayView: OverlayView!
    private var progressView: UIProgressView!
    private var currentURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupOverlay()
        loadCredentialsAndStart()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.customUserAgent = config.applicationNameForUserAgent

        view.addSubview(webView)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress", let progress = webView?.estimatedProgress {
            progressView.setProgress(Float(progress), animated: true)
            progressView.isHidden = progress >= 1.0
        }
    }

    private func setupOverlay() {
        overlayView = OverlayView()
        overlayView.delegate = self
        view.addSubview(overlayView)

        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemBlue
        progressView.trackTintColor = .clear
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    private func loadCredentialsAndStart() {
        guard let creds = LoginManager.loadCredentials() else {
            showError("인증 정보를 찾을 수 없습니다.\n.env 파일을 확인해주세요.")
            return
        }
        loginManager = LoginManager(id: creds.id, password: creds.password, webViewProvider: self)
        let url = URL(string: "https://www.sooplive.com/")!
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "오류", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    // MARK: - LoginManager.WebViewProviding

    func loadURL(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func evaluateJavaScript(_ js: String, completion: ((Any?, Error?) -> Void)?) {
        webView.evaluateJavaScript(js, completionHandler: completion)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        overlayView.updateURL(urlString)
        loginManager?.tryAutoLogin(url: urlString)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url
        overlayView.updateURL(webView.url?.absoluteString ?? "")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Navigation failed: \(error.localizedDescription)")
    }
}

extension iOSViewController: OverlayViewDelegate {
    func overlayDidRequestGoBack() { webView?.goBack() }
    func overlayDidRequestGoForward() { webView?.goForward() }
    func overlayDidRequestReload() {
        if let url = currentURL { webView?.load(URLRequest(url: url)) }
    }
    func overlayDidRequestHome() {
        let url = URL(string: "https://www.sooplive.com/")!
        currentURL = url
        webView?.load(URLRequest(url: url))
    }
    func overlayDidRequestLogin() { loginManager?.forceLogin() }
}
