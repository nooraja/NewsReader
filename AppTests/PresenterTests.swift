import Foundation
import Testing
@testable import NewsReader

@MainActor
struct PresenterTests {
    @Test
    func sourceSearchCoversUnrevealedRowsAndScrollingStaysLocal() async throws {
        let ordinarySources = (1...24).map {
            NewsSource(id: "source-\($0)", name: "Source \($0)", description: "")
        }
        let lastSource = NewsSource(id: "z", name: "Zeta", description: "Café openings")
        let service = StubNewsService(sourceResponses: [.success([lastSource] + ordinarySources + [lastSource])])
        let states = RenderedStates()
        var openedSource: NewsSource?
        let presenter = SourcesPresenter(category: .general, service: service, render: states.record) {
            openedSource = $0
        }

        presenter.start()
        let firstPage = try await states.waitFor { $0.phase == .ready }
        #expect(firstPage.rows.count == 20)
        #expect(firstPage.rows.first?.title == "Source 1")
        #expect(firstPage.rows.allSatisfy { $0.id != lastSource.id })

        presenter.search("  CAFE  ")
        #expect(states.last?.rows.map(\.id) == [lastSource.id])
        presenter.select(lastSource.id)
        #expect(openedSource == lastSource)

        presenter.search("no matching source")
        #expect(states.last?.phase == .empty("No sources match your search."))
        presenter.search("")
        #expect(states.last?.rows.count == 20)
        presenter.reachedEnd()
        #expect(states.last?.rows.count == 25)
        #expect(states.last?.rows.last?.id == lastSource.id)
        presenter.reachedEnd()
        #expect(states.last?.rows.count == 25)
        #expect(await service.sourceRequests == [.general])
    }

    @Test
    func sourceFailureCanBeRetriedIntoAnEmptyState() async throws {
        let service = StubNewsService(sourceResponses: [.failure(.connection), .success([])])
        let states = RenderedStates()
        let presenter = SourcesPresenter(category: .science, service: service, render: states.record) { _ in }

        presenter.start()
        let error = try await states.waitFor { $0.phase == .failure(NewsError.connection.message, retryable: true) }
        #expect(error.rows.isEmpty)
        presenter.retry()
        presenter.retry()
        let empty = try await states.waitFor { $0.phase == .empty("No sources are available.") }
        #expect(empty.rows.isEmpty)
        #expect(await service.sourceRequests == [.science, .science])
    }

    @Test
    func articleRetryKeepsRowsAndSkipsAnEntirePageOfDuplicates() async throws {
        let source = NewsSource(id: "example", name: "Example", description: "")
        let first = try article("first")
        let last = try article("last")
        let page1 = ArticleRequest(sourceID: source.id, query: nil, page: 1)
        let page2 = ArticleRequest(sourceID: source.id, query: nil, page: 2)
        let page3 = ArticleRequest(sourceID: source.id, query: nil, page: 3)
        let service = StubNewsService(articleResponses: [
            page1: [.success(ArticlePage(articles: [first], rawCount: 20, totalResults: 41))],
            page2: [
                .failure(.server),
                .success(ArticlePage(articles: [first], rawCount: 20, totalResults: 41))
            ],
            page3: [.success(ArticlePage(articles: [last], rawCount: 1, totalResults: 41))]
        ])
        let states = RenderedStates()
        var openedArticle: NewsArticle?
        let presenter = ArticlesPresenter(source: source, service: service, render: states.record) {
            openedArticle = $0
        }

        presenter.start()
        _ = try await states.waitFor { $0.phase == .ready }
        presenter.reachedEnd()
        presenter.reachedEnd()
        let failure = try await states.waitFor { $0.phase == .nextFailure(NewsError.server.message, retryable: true) }
        #expect(failure.rows.map(\.id) == [first.id.absoluteString])

        presenter.retry()
        let loaded = try await states.waitFor { $0.phase == .ready && $0.rows.count == 2 }
        #expect(loaded.rows.map(\.id) == [first.id.absoluteString, last.id.absoluteString])
        presenter.select(last.id.absoluteString)
        #expect(openedArticle == last)
        presenter.reachedEnd()
        #expect(await service.articleRequests == [page1, page2, page2, page3])
    }

    @Test
    func articleSearchReplacesARequestThatCompletesAfterCancellation() async throws {
        let source = NewsSource(id: "example", name: "Example", description: "")
        let stale = try article("stale")
        let match = try article("matching")
        let service = SearchRaceNewsService(match: match)
        let states = RenderedStates()
        let presenter = ArticlesPresenter(source: source, service: service, debounce: .zero, render: states.record) { _ in }

        presenter.start()
        try await service.waitForInitialRequest()

        presenter.search("  new query  ")
        let result = try await states.waitFor { $0.rows.map(\.id) == [match.id.absoluteString] }
        #expect(result.phase == .ready)
        #expect(await service.queries == [nil, "new query"])

        await service.finishInitial(with: stale)
        try await Task.sleep(for: .milliseconds(30))
        #expect(states.last?.rows.map(\.id) == [match.id.absoluteString])
    }

    private func article(_ slug: String) throws -> NewsArticle {
        let url = try #require(URL(string: "https://example.com/\(slug)"))
        return NewsArticle(title: slug, description: nil, url: url, publishedAt: nil)
    }
}

@MainActor
private final class RenderedStates {
    private(set) var last: ListState?

    func record(_ state: ListState) {
        last = state
    }

    func waitFor(_ matches: (ListState) -> Bool) async throws -> ListState {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if let last, matches(last) { return last }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TestTimeout()
    }
}

private struct TestTimeout: Error {}

private struct ArticleRequest: Hashable, Sendable {
    let sourceID: String
    let query: String?
    let page: Int
}

private actor StubNewsService: NewsService {
    private var sourceResponses: [Result<[NewsSource], NewsError>]
    private var articleResponses: [ArticleRequest: [Result<ArticlePage, NewsError>]]
    private(set) var sourceRequests: [NewsCategory] = []
    private(set) var articleRequests: [ArticleRequest] = []

    init(
        sourceResponses: [Result<[NewsSource], NewsError>] = [],
        articleResponses: [ArticleRequest: [Result<ArticlePage, NewsError>]] = [:]
    ) {
        self.sourceResponses = sourceResponses
        self.articleResponses = articleResponses
    }

    func sources(in category: NewsCategory) async throws -> [NewsSource] {
        sourceRequests.append(category)
        guard !sourceResponses.isEmpty else { throw NewsError.invalidResponse }
        return try sourceResponses.removeFirst().get()
    }

    func articles(sourceID: String, query: String?, page: Int, pageSize: Int) async throws -> ArticlePage {
        let request = ArticleRequest(sourceID: sourceID, query: query, page: page)
        articleRequests.append(request)
        guard let result = articleResponses[request]?.first else { throw NewsError.invalidResponse }
        articleResponses[request]?.removeFirst()
        return try result.get()
    }
}

private actor SearchRaceNewsService: NewsService {
    let match: NewsArticle
    private var initial: CheckedContinuation<ArticlePage, Never>?
    private(set) var queries: [String?] = []

    init(match: NewsArticle) {
        self.match = match
    }

    func sources(in category: NewsCategory) async throws -> [NewsSource] { [] }

    func articles(sourceID: String, query: String?, page: Int, pageSize: Int) async throws -> ArticlePage {
        queries.append(query)
        guard query == nil else {
            return ArticlePage(articles: [match], rawCount: 1, totalResults: 1)
        }
        return await withCheckedContinuation { initial = $0 }
    }

    func waitForInitialRequest() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while initial == nil {
            guard ContinuousClock.now < deadline else { throw TestTimeout() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func finishInitial(with article: NewsArticle) {
        initial?.resume(returning: ArticlePage(articles: [article], rawCount: 1, totalResults: 1))
        initial = nil
    }
}
