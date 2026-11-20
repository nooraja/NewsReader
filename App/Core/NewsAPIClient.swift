import Foundation

struct NewsAPIClient: NewsService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let apiKey: String?
    private let transport: Transport

    init(apiKey: String?, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.init(apiKey: apiKey) { request in
            try await session.data(for: request)
        }
    }

    init(apiKey: String?, transport: @escaping Transport) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    func sources(in category: NewsCategory) async throws -> [NewsSource] {
        let response: SourcesResponse = try await fetch(
            path: "/v2/top-headlines/sources",
            query: [URLQueryItem(name: "category", value: category.rawValue)]
        )
        return response.sources.compactMap { source in
            guard let id = source.id?.nonBlank, let name = source.name?.nonBlank else { return nil }
            return NewsSource(id: id, name: name, description: source.description?.nonBlank ?? "")
        }
    }

    func articles(sourceID: String, query: String?, page: Int, pageSize: Int) async throws -> ArticlePage {
        var parameters = [
            URLQueryItem(name: "sources", value: sourceID),
            URLQueryItem(name: "sortBy", value: "publishedAt"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        if let query = query?.nonBlank {
            parameters.append(URLQueryItem(name: "q", value: query))
        }

        let response: ArticlesResponse = try await fetch(path: "/v2/everything", query: parameters)
        guard response.totalResults >= 0 else { throw NewsError.invalidResponse }

        let articles = response.articles.compactMap { article -> NewsArticle? in
            guard let title = article.title?.nonBlank, title != "[Removed]",
                  let rawURL = article.url?.nonBlank,
                  let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host?.isEmpty == false else { return nil }
            return NewsArticle(
                title: title,
                description: article.description?.nonBlank,
                url: url,
                publishedAt: article.publishedAt.flatMap { date in
                    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(date))
                        ?? (try? Date.ISO8601FormatStyle().parse(date))
                }
            )
        }
        return ArticlePage(articles: articles, rawCount: response.articles.count, totalResults: response.totalResults)
    }

    private func fetch<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        guard let apiKey, !apiKey.isEmpty else { throw NewsError.missingKey }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "newsapi.org"
        components.path = path
        components.queryItems = query
        // NewsAPI treats a literal plus in a query value as a space unless it is escaped.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        guard let url = components.url else { throw NewsError.requestRejected }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled || Task.isCancelled {
            throw CancellationError()
        } catch {
            throw NewsError.connection
        }
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else { throw NewsError.invalidResponse }
        let decoder = JSONDecoder()
        let envelope = try? decoder.decode(Envelope.self, from: data)
        guard (200..<300).contains(http.statusCode), envelope?.status == "ok" else {
            throw Self.failure(status: http.statusCode, envelope: envelope)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NewsError.invalidResponse
        }
    }

    private static func failure(status: Int, envelope: Envelope?) -> NewsError {
        switch envelope?.code {
        case "maximumResultsReached": return .maximumResultsReached
        case "apiKeyMissing", "apiKeyDisabled", "apiKeyInvalid": return .invalidKey
        case "apiKeyExhausted", "rateLimited": return .rateLimited
        default:
            switch status {
            case 401: return .invalidKey
            case 429: return .rateLimited
            case 500...599: return .server
            case 200..<300: return envelope?.status == "error" ? .requestRejected : .invalidResponse
            default: return .requestRejected
            }
        }
    }
}

private struct Envelope: Decodable {
    let status: String
    let code: String?
}

private struct SourcesResponse: Decodable {
    struct Source: Decodable {
        let id: String?
        let name: String?
        let description: String?
    }

    let sources: [Source]
}

private struct ArticlesResponse: Decodable {
    struct Article: Decodable {
        let title: String?
        let description: String?
        let url: String?
        let publishedAt: String?
    }

    let articles: [Article]
    let totalResults: Int
}

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
