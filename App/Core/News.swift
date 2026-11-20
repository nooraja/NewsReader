import Foundation

enum NewsCategory: String, CaseIterable, Sendable {
    case general, business, entertainment, health, science, sports, technology

    var title: String { rawValue.capitalized }
}

struct NewsSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
}

struct NewsArticle: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let title: String
    let description: String?
    let url: URL
    let publishedAt: Date?
}

struct ArticlePage: Sendable {
    let articles: [NewsArticle]
    let rawCount: Int
    let totalResults: Int
}

protocol NewsService: Sendable {
    func sources(in category: NewsCategory) async throws -> [NewsSource]
    func articles(sourceID: String, query: String?, page: Int, pageSize: Int) async throws -> ArticlePage
}

enum NewsError: Error {
    case missingKey, invalidKey, rateLimited, maximumResultsReached, connection
    case invalidResponse, server, requestRejected

    var message: String {
        switch self {
        case .missingKey: "Set NEWSAPI_KEY in your local Xcode scheme, or run the Offline Demo scheme."
        case .invalidKey: "Check the NewsAPI key in your local Xcode scheme."
        case .rateLimited: "NewsAPI has reached its request limit. Try again later."
        case .maximumResultsReached: "You've reached the last article available on your NewsAPI plan."
        case .connection: "Check your connection and try again."
        case .invalidResponse: "NewsAPI returned a response the app couldn't read."
        case .server: "NewsAPI is temporarily unavailable."
        case .requestRejected: "NewsAPI couldn't complete this request."
        }
    }

    var canRetry: Bool {
        switch self {
        case .connection, .invalidResponse, .server, .rateLimited: true
        case .missingKey, .invalidKey, .maximumResultsReached, .requestRejected: false
        }
    }
}

@MainActor
protocol NewsListPresenting: AnyObject {
    func start()
    func search(_ text: String)
    func reachedEnd()
    func select(_ id: String)
    func retry()
}

struct ListRow: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String?
}

enum ListPhase: Equatable {
    case loading
    case ready
    case empty(String)
    case failure(String, retryable: Bool)
    case loadingNext
    case nextFailure(String, retryable: Bool)
}

struct ListState {
    var rows: [ListRow]
    var phase: ListPhase
}
