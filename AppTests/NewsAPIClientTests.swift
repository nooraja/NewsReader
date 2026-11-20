import Foundation
import Testing
@testable import NewsReader

struct NewsAPIClientTests {
    @Test func fetchesSourcesForSelectedCategory() async throws {
        let service = NewsAPIClient(apiKey: "stub-key") { request in
            let url = try #require(request.url)
            #expect(url.path == "/v2/top-headlines/sources")
            #expect(queryItems(url) == ["category": "science"])
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "stub-key")
            return try response(request, status: 200, body: """
                {"status":"ok","sources":[
                  {"id":"science-weekly","name":"Science Weekly","description":"Research news"},
                  {"id":null,"name":"Unknown"}
                ]}
                """)
        }

        let sources = try await service.sources(in: .science)
        #expect(sources == [NewsSource(id: "science-weekly", name: "Science Weekly", description: "Research news")])
    }

    @Test func articleRequestPreservesQueryAndPageAndCountsRawRows() async throws {
        let service = NewsAPIClient(apiKey: "stub-key") { request in
            let url = try #require(request.url)
            #expect(url.path == "/v2/everything")
            #expect(queryItems(url) == [
                "sources": "weekly", "q": "C++ & café", "page": "2", "pageSize": "20", "sortBy": "publishedAt"
            ])
            #expect(url.absoluteString.contains("C%2B%2B"))
            return try response(request, status: 200, body: """
                {"status":"ok","totalResults":42,"articles":[
                  {"title":"Valid","url":"https://example.com/article","description":null,"publishedAt":"2026-11-20T00:00:00.123Z"},
                  {"title":"Bad URL","url":"javascript:alert(1)"},
                  {"title":"Missing URL"},
                  {"title":"[Removed]","url":"https://example.com/removed"}
                ]}
                """)
        }

        let page = try await service.articles(sourceID: "weekly", query: " C++ & café ", page: 2, pageSize: 20)
        #expect(page.totalResults == 42)
        #expect(page.rawCount == 4)
        let article = try #require(page.articles.first)
        #expect(page.articles.count == 1)
        #expect(article.title == "Valid")
        #expect(article.publishedAt != nil)
        #expect(article.description == nil)
    }

    @Test func emptyResultsAreSuccessfulAndBlankSearchIsOmitted() async throws {
        let service = NewsAPIClient(apiKey: "stub-key") { request in
            let url = try #require(request.url)
            #expect(queryItems(url)["q"] == nil)
            return try response(request, status: 200, body: """
                {"status":"ok","totalResults":0,"articles":[]}
                """)
        }

        let page = try await service.articles(sourceID: "wire", query: " ", page: 1, pageSize: 20)
        #expect(page.articles.isEmpty)
        #expect(page.rawCount == 0)
    }

    @Test func missingKeyFailsBeforeTransport() async {
        let service = NewsAPIClient(apiKey: " \n ") { _ in
            Issue.record("A request without a key reached the transport.")
            throw URLError(.unknown)
        }

        await #expect(throws: NewsError.missingKey) {
            _ = try await service.sources(in: .general)
        }
    }

    @Test(arguments: [
        (401, #"{"status":"error","code":"apiKeyInvalid"}"#, NewsError.invalidKey),
        (429, #"{"status":"error","code":"rateLimited"}"#, NewsError.rateLimited),
        (400, #"{"status":"error","code":"maximumResultsReached"}"#, NewsError.maximumResultsReached),
        (503, "Service unavailable", NewsError.server),
        (200, #"{"status":"ok","sources":{}}"#, NewsError.invalidResponse),
        (200, "broken JSON", NewsError.invalidResponse)
    ])
    func reportsAPIAndDecodingFailures(status: Int, body: String, expected: NewsError) async {
        let service = NewsAPIClient(apiKey: "stub-key") { request in
            try response(request, status: status, body: body)
        }

        await #expect(throws: expected) {
            _ = try await service.sources(in: .general)
        }
    }

    @Test func mapsTransportFailureAndPreservesCancellation() async {
        let offline = NewsAPIClient(apiKey: "stub-key") { _ in
            throw URLError(.notConnectedToInternet)
        }
        let cancelled = NewsAPIClient(apiKey: "stub-key") { _ in
            throw URLError(.cancelled)
        }

        await #expect(throws: NewsError.connection) {
            _ = try await offline.sources(in: .general)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.sources(in: .general)
        }
    }
}

private func queryItems(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return items.reduce(into: [:]) { $0[$1.name] = $1.value }
}

private func response(_ request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    return (Data(body.utf8), response)
}
