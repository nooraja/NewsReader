import UIKit
import WebKit

final class ArticleDetailViewController: UIViewController {
    private let presenter: ArticleDetailPresenter
    private let webView = WKWebView()

    init(article: NewsArticle, demoMode: Bool) {
        presenter = ArticleDetailPresenter(article: article, demoMode: demoMode)
        super.init(nibName: nil, bundle: nil)
        title = article.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.accessibilityIdentifier = "article-web-view"
        webView.navigationDelegate = self
        view.addSubview(webView)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
        ])
        presenter.render = { [weak self] in self?.render($0) }
        presenter.start()
    }

    private func render(_ state: ArticleDetailPresenter.State) {
        switch state {
        case .load(let page):
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
            switch page {
            case .publisher(let url):
                webView.load(URLRequest(url: url))
            case .demo(let html):
                webView.loadHTMLString(html, baseURL: nil)
            }
        case .loading:
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        case .loaded:
            contentUnavailableConfiguration = nil
        case .failure(let message, let retryable):
            let retry: (@MainActor () -> Void)? =
                retryable ? { @MainActor [weak self] in
                    guard let self else { return }
                    self.presenter.start()
                } : nil
            contentUnavailableConfiguration = NewsAppearance.failure(
                title: "Unable to open article",
                message: message,
                retry: retry
            )
        }
    }
}

extension ArticleDetailViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        guard presenter.allows(navigationAction.request.url, isMainFrame: isMainFrame) else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            presenter.failed()
            decisionHandler(.cancel)
            return
        }
        if navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType {
            presenter.failed()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        presenter.loading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        presenter.loaded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        presenter.failed(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        presenter.failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        presenter.failed()
    }
}

@MainActor
private final class ArticleDetailPresenter {
    enum State {
        case load(ArticleDetailInteractor.Page)
        case loading
        case loaded
        case failure(String, retryable: Bool)
    }

    private let interactor: ArticleDetailInteractor
    var render: ((State) -> Void)?

    init(article: NewsArticle, demoMode: Bool) {
        interactor = ArticleDetailInteractor(article: article, demoMode: demoMode)
    }

    func start() {
        guard let page = interactor.page else {
            render?(.failure("The publisher link is invalid.", retryable: false))
            return
        }
        render?(.load(page))
    }

    func allows(_ url: URL?, isMainFrame: Bool) -> Bool {
        interactor.allows(url, isMainFrame: isMainFrame)
    }

    func loading() {
        render?(.loading)
    }

    func loaded() {
        render?(.loaded)
    }

    func failed(_ error: (any Error)? = nil) {
        if let error, (error as? URLError)?.code == .cancelled {
            return
        }
        render?(.failure("Check your connection or try opening the publisher’s page again.", retryable: true))
    }
}

private struct ArticleDetailInteractor {
    enum Page {
        case publisher(URL)
        case demo(String)
    }

    let article: NewsArticle
    let demoMode: Bool

    var page: Page? {
        if demoMode {
            return .demo("""
            <!doctype html>
            <html lang="en">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                html { color-scheme: light dark; }
                body { margin: 2rem; font: -apple-system-body; line-height: 1.6; }
            </style>
            <body>
                <h1>Sample article</h1>
                <p>This article is provided by NewsReader's demo data.</p>
            </body>
            </html>
            """)
        }
        guard allows(article.url, isMainFrame: true) else { return nil }
        return .publisher(article.url)
    }

    func allows(_ url: URL?, isMainFrame: Bool) -> Bool {
        guard let url else { return false }
        if url.absoluteString == "about:blank" {
            return demoMode || !isMainFrame
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }
}
