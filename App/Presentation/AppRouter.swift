import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var router: AppRouter?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let process = ProcessInfo.processInfo
        #if DEBUG
        let demoMode = process.arguments.contains("-demo")
        let service: any NewsService = demoMode
            ? DemoNewsService()
            : NewsAPIClient(apiKey: process.environment["NEWSAPI_KEY"])
        #else
        let demoMode = false
        let service: any NewsService = NewsAPIClient(apiKey: process.environment["NEWSAPI_KEY"])
        #endif

        let router = AppRouter(service: service, demoMode: demoMode)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = router.makeRootViewController()
        window.tintColor = NewsAppearance.accent
        self.window = window
        self.router = router
        window.makeKeyAndVisible()
    }
}

@MainActor
final class AppRouter {
    private let service: any NewsService
    private let demoMode: Bool
    private let navigationController = UINavigationController()

    init(service: any NewsService, demoMode: Bool) {
        self.service = service
        self.demoMode = demoMode
    }

    func makeRootViewController() -> UIViewController {
        let categories = NewsListViewController(
            title: "Categories",
            intro: "Choose a topic to browse news sources."
        )
        categories.presenter = CategoriesPresenter(
            render: { [weak categories] in categories?.render($0) },
            openCategory: { [weak self] in self?.openSources(in: $0) }
        )
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.setViewControllers([categories], animated: false)
        return navigationController
    }

    private func openSources(in category: NewsCategory) {
        let sources = NewsListViewController(title: category.title, searchPlaceholder: "Search sources")
        sources.presenter = SourcesPresenter(
            category: category,
            service: service,
            render: { [weak sources] in sources?.render($0) },
            openSource: { [weak self] in self?.openArticles(from: $0) }
        )
        navigationController.pushViewController(sources, animated: true)
    }

    private func openArticles(from source: NewsSource) {
        let articles = NewsListViewController(title: source.name, searchPlaceholder: "Search articles")
        articles.presenter = ArticlesPresenter(
            source: source,
            service: service,
            render: { [weak articles] in articles?.render($0) },
            openArticle: { [weak self] in self?.openDetail(for: $0) }
        )
        navigationController.pushViewController(articles, animated: true)
    }

    private func openDetail(for article: NewsArticle) {
        let detail = ArticleDetailViewController(article: article, demoMode: demoMode)
        navigationController.pushViewController(detail, animated: true)
    }
}
