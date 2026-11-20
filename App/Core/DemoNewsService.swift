#if DEBUG
import Foundation

struct DemoNewsService: NewsService {
    func sources(in category: NewsCategory) async throws -> [NewsSource] {
        let desks = (1...32).map { number in
            NewsSource(
                id: "\(category.rawValue)-desk-\(number)",
                name: "\(category.title) Desk \(String(format: "%02d", number))",
                description: "Reports and analysis from the \(category.title.lowercased()) desk."
            )
        }
        return desks + [NewsSource(id: "global-wire", name: "Global Wire", description: "A roundup of coverage from around the world.")]
    }

    func articles(sourceID: String, query: String?, page: Int, pageSize: Int) async throws -> ArticlePage {
        let articles = (1...33).compactMap { number -> NewsArticle? in
            var components = URLComponents()
            components.scheme = "https"
            components.host = "example.com"
            components.path = "/demo/\(sourceID)/\(number)"
            guard let url = components.url else { return nil }

            let title = number == 33 ? "Field Notes 33" : "Daily Briefing \(String(format: "%02d", number))"
            let description = number == 33
                ? "What reporters observed on the ground."
                : "A short look at the stories shaping today's coverage."
            return NewsArticle(title: title, description: description, url: url, publishedAt: nil)
        }
        let matches = query.map { query in
            articles.filter { $0.title.localizedStandardContains(query) }
        } ?? articles
        let items = Array(matches.dropFirst((page - 1) * pageSize).prefix(pageSize))
        return ArticlePage(articles: items, rawCount: items.count, totalResults: matches.count)
    }
}
#endif
