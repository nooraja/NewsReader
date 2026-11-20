@MainActor
final class CategoriesPresenter: NewsListPresenting {
    private let interactor = CategoriesInteractor()
    private let render: (ListState) -> Void
    private let openCategory: (NewsCategory) -> Void

    init(render: @escaping (ListState) -> Void, openCategory: @escaping (NewsCategory) -> Void) {
        self.render = render
        self.openCategory = openCategory
    }

    func start() {
        let rows = interactor.categories.map { category in
            ListRow(id: category.rawValue, title: category.title, subtitle: nil, symbol: category.symbol)
        }
        render(ListState(rows: rows, phase: .ready))
    }

    func select(_ id: String) {
        guard let category = NewsCategory(rawValue: id) else { return }
        openCategory(category)
    }

    func search(_ text: String) {}
    func reachedEnd() {}
    func retry() {}
}

private struct CategoriesInteractor {
    var categories: [NewsCategory] { NewsCategory.allCases }
}

private extension NewsCategory {
    var symbol: String {
        switch self {
        case .general: "newspaper"
        case .business: "chart.line.uptrend.xyaxis"
        case .entertainment: "film"
        case .health: "heart.text.clipboard"
        case .science: "flask"
        case .sports: "sportscourt"
        case .technology: "cpu"
        }
    }
}
