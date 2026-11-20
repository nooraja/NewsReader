import Foundation

private struct SourcesInteractor {
    let category: NewsCategory
    let service: any NewsService

    func load() async throws -> [NewsSource] {
        let sources = try await service.sources(in: category)
        var seen = Set<NewsSource.ID>()
        return sources
            .filter { seen.insert($0.id).inserted }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }
}

@MainActor
final class SourcesPresenter: NewsListPresenting {
    private static let batchSize = 20

    private let interactor: SourcesInteractor
    private let render: @MainActor (ListState) -> Void
    private let openSource: @MainActor (NewsSource) -> Void

    private var started = false
    private var phase: ListPhase = .loading
    private var request: Task<Void, Never>?
    private var sources: [NewsSource]?
    private var visibleSources: [NewsSource] = []
    private var query = ""
    private var visibleCount = batchSize

    init(
        category: NewsCategory,
        service: any NewsService,
        render: @escaping @MainActor (ListState) -> Void,
        openSource: @escaping @MainActor (NewsSource) -> Void
    ) {
        interactor = SourcesInteractor(category: category, service: service)
        self.render = render
        self.openSource = openSource
    }

    deinit {
        request?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        load()
    }

    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query else { return }
        query = trimmed
        visibleCount = Self.batchSize
        updateVisibleSources()
    }

    func reachedEnd() {
        guard phase == .ready, visibleSources.count == visibleCount else { return }
        visibleCount += Self.batchSize
        updateVisibleSources()
    }

    func select(_ id: String) {
        guard let source = visibleSources.first(where: { $0.id == id }) else { return }
        openSource(source)
    }

    func retry() {
        guard case .failure(_, retryable: true) = phase else { return }
        load()
    }

    private func load() {
        phase = .loading
        render(ListState(rows: [], phase: phase))
        request = Task { [weak self, interactor] in
            do {
                let sources = try await interactor.load()
                guard !Task.isCancelled, let self else { return }
                self.sources = sources
                self.updateVisibleSources()
            } catch {
                guard !Task.isCancelled, let self else { return }
                let failure = error as? NewsError ?? .connection
                self.phase = .failure(failure.message, retryable: failure.canRetry)
                self.render(ListState(rows: [], phase: self.phase))
            }
        }
    }

    private func updateVisibleSources() {
        guard let sources else { return }
        let matching = query.isEmpty ? sources : sources.filter {
            $0.name.localizedStandardContains(query) || $0.description.localizedStandardContains(query)
        }
        visibleSources = Array(matching.prefix(visibleCount))
        let rows = visibleSources.map {
            ListRow(id: $0.id, title: $0.name, subtitle: $0.description.isEmpty ? nil : $0.description, symbol: nil)
        }
        if rows.isEmpty {
            phase = .empty(query.isEmpty ? "No sources are available." : "No sources match your search.")
        } else {
            phase = .ready
        }
        render(ListState(rows: rows, phase: phase))
    }
}
