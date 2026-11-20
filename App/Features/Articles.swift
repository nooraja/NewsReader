import Foundation

private struct ArticlesInteractor {
    let sourceID: NewsSource.ID
    let service: any NewsService

    func load(query: String, page: Int, pageSize: Int) async throws -> ArticlePage {
        try await service.articles(
            sourceID: sourceID,
            query: query.isEmpty ? nil : query,
            page: page,
            pageSize: pageSize
        )
    }
}

@MainActor
final class ArticlesPresenter: NewsListPresenting {
    private static let pageSize = 20

    private let interactor: ArticlesInteractor
    private let debounce: Duration
    private let render: @MainActor (ListState) -> Void
    private let openArticle: @MainActor (NewsArticle) -> Void

    private var started = false
    private var phase: ListPhase = .loading
    private var request: Task<Void, Never>?
    private var generation = 0
    private var query = ""
    private var nextPage = 1
    private var hasMore = true
    private var articles: [NewsArticle] = []
    private var articleIDs = Set<NewsArticle.ID>()

    init(
        source: NewsSource,
        service: any NewsService,
        debounce: Duration = .milliseconds(400),
        render: @escaping @MainActor (ListState) -> Void,
        openArticle: @escaping @MainActor (NewsArticle) -> Void
    ) {
        interactor = ArticlesInteractor(sourceID: source.id, service: service)
        self.debounce = debounce
        self.render = render
        self.openArticle = openArticle
    }

    deinit {
        request?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        load(delay: .zero)
    }

    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newQuery = String(trimmed.prefix(500))
        guard newQuery != query else { return }
        query = newQuery
        guard started else { return }

        request?.cancel()
        generation += 1
        nextPage = 1
        hasMore = true
        articles.removeAll()
        articleIDs.removeAll()
        load(delay: debounce)
    }

    func reachedEnd() {
        guard phase == .ready, hasMore else { return }
        load(delay: .zero)
    }

    func select(_ id: String) {
        guard let article = articles.first(where: { $0.id.absoluteString == id }) else { return }
        openArticle(article)
    }

    func retry() {
        switch phase {
        case .failure(_, retryable: true), .nextFailure(_, retryable: true):
            load(delay: .zero)
        default:
            break
        }
    }

    private func load(delay: Duration) {
        let isAppend = !articles.isEmpty
        var page = nextPage
        let query = query
        let generation = generation
        setPhase(isAppend ? .loadingNext : .loading)

        request = Task { [weak self, interactor] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                while true {
                    try Task.checkCancellation()
                    let result = try await interactor.load(query: query, page: page, pageSize: Self.pageSize)
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    guard self.apply(result, at: page) else { return }
                    page = self.nextPage
                }
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.showFailure(error as? NewsError ?? .connection, isAppend: isAppend)
            }
        }
    }

    private func apply(_ result: ArticlePage, at page: Int) -> Bool {
        let added = result.articles.filter { articleIDs.insert($0.id).inserted }
        articles.append(contentsOf: added)
        nextPage = page + 1

        let lastPage = (max(result.totalResults, 1) - 1) / Self.pageSize + 1
        hasMore = result.rawCount >= Self.pageSize && page < lastPage

        // A page with no new rows cannot trigger the next scroll event.
        if added.isEmpty && hasMore {
            return true
        }

        if articles.isEmpty {
            setPhase(.empty(query.isEmpty ? "No articles are available." : "No articles match your search."))
        } else {
            setPhase(.ready)
        }
        return false
    }

    private func showFailure(_ error: NewsError, isAppend: Bool) {
        if isAppend, case .maximumResultsReached = error {
            hasMore = false
            setPhase(.ready)
            return
        }

        setPhase(isAppend
            ? .nextFailure(error.message, retryable: error.canRetry)
            : .failure(error.message, retryable: error.canRetry))
    }

    private func setPhase(_ phase: ListPhase) {
        self.phase = phase
        let rows = articles.map {
            ListRow(
                id: $0.id.absoluteString,
                title: $0.title,
                subtitle: $0.description ?? $0.publishedAt?.formatted(date: .abbreviated, time: .omitted),
                symbol: nil
            )
        }
        render(ListState(rows: rows, phase: phase))
    }
}
