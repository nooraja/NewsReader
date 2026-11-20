import UIKit

final class NewsListViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchPlaceholder: String?
    private let intro: String?
    private var rowsByID: [String: ListRow] = [:]
    private var phase: ListPhase = .loading
    private var searchText = ""

    private lazy var dataSource = UITableViewDiffableDataSource<Int, String>(tableView: tableView) {
        [weak self] tableView, _, id in
        guard let row = self?.rowsByID[id] else { return nil }
        let cell = tableView.dequeueReusableCell(withIdentifier: "NewsRow") ?? UITableViewCell()
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.secondaryText = row.subtitle
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 2
        content.image = row.symbol.flatMap { UIImage(systemName: $0) }
        content.imageProperties.tintColor = NewsAppearance.accent
        content.imageProperties.reservedLayoutSize = CGSize(width: 30, height: 28)
        content.imageToTextPadding = 14
        content.textToSecondaryTextVerticalPadding = 4
        content.directionalLayoutMargins.top = 15
        content.directionalLayoutMargins.bottom = 15
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "row-\(id)"
        return cell
    }

    var presenter: (any NewsListPresenting)?

    init(title: String, searchPlaceholder: String? = nil, intro: String? = nil) {
        self.searchPlaceholder = searchPlaceholder
        self.intro = intro
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.backButtonDisplayMode = .minimal
        configureTable()
        configureSearch()
        presenter?.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeTableSupplementaryViews()
    }

    func render(_ state: ListState) {
        phase = state.phase
        let oldRows = rowsByID
        rowsByID = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id, $0) })
        let itemIDs = state.rows.map(\.id)
        let oldIDs = dataSource.snapshot().itemIdentifiers
        let reconfiguredIDs = state.rows.compactMap { row -> String? in
            guard let oldRow = oldRows[row.id], oldRow != row else { return nil }
            return row.id
        }
        if itemIDs != oldIDs || !reconfiguredIDs.isEmpty {
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(itemIDs)
            snapshot.reconfigureItems(reconfiguredIDs)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        tableView.tableFooterView = nil
        switch state.phase {
        case .loading:
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        case .ready:
            contentUnavailableConfiguration = nil
        case .empty(let message):
            var empty = UIContentUnavailableConfiguration.empty()
            empty.image = UIImage(systemName: "magnifyingglass")
            empty.text = "No results"
            empty.secondaryText = message
            contentUnavailableConfiguration = empty
        case .failure(let message, let retryable):
            contentUnavailableConfiguration = NewsAppearance.failure(
                title: "Unable to load news",
                message: message,
                retry: retryable ? retry : nil
            )
        case .loadingNext:
            contentUnavailableConfiguration = nil
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            tableView.tableFooterView = makeFooter([indicator])
        case .nextFailure(let message, let retryable):
            contentUnavailableConfiguration = nil
            tableView.tableFooterView = makeFailureFooter(message: message, retryable: retryable)
        }
        resizeTableSupplementaryViews()
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "news-list"
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NewsRow")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.keyboardDismissMode = .onDrag
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        _ = dataSource

        if let intro {
            let label = UILabel()
            label.text = intro
            label.textColor = .secondaryLabel
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            let header = makeFooter([label])
            header.directionalLayoutMargins = .init(top: 0, leading: 28, bottom: 12, trailing: 28)
            header.alignment = .fill
            tableView.tableHeaderView = header
        }
    }

    private func configureSearch() {
        guard let searchPlaceholder else { return }
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = searchPlaceholder
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func retry() {
        presenter?.retry()
    }

    private func makeFailureFooter(message: String, retryable: Bool) -> UIStackView {
        let label = UILabel()
        label.text = message
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0

        let footer = makeFooter([label])
        if retryable {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = "Try again"
            let button = UIButton(
                configuration: configuration,
                primaryAction: UIAction { [weak self] _ in self?.retry() }
            )
            footer.addArrangedSubview(button)
        }
        return footer
    }

    private func makeFooter(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 28, bottom: 16, trailing: 28)
        return stack
    }

    private func resizeTableSupplementaryViews() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        if let header = tableView.tableHeaderView, resize(header, toWidth: width) {
            tableView.tableHeaderView = header
        }
        if let footer = tableView.tableFooterView, resize(footer, toWidth: width) {
            tableView.tableFooterView = footer
        }
    }

    private func resize(_ view: UIView, toWidth width: CGFloat) -> Bool {
        let height = ceil(view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height)
        let size = CGSize(width: width, height: height)
        guard view.frame.size != size else { return false }
        view.frame.size = size
        return true
    }
}

extension NewsListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        presenter?.select(id)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard phase == .ready, indexPath.row >= rowsByID.count - 3 else { return }
        Task { @MainActor [weak self] in
            guard let self, self.phase == .ready,
                  self.tableView.indexPathsForVisibleRows?.contains(where: { $0.row >= self.rowsByID.count - 3 }) == true
            else { return }
            self.presenter?.reachedEnd()
        }
    }
}

extension NewsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        guard text != searchText else { return }
        searchText = text
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        presenter?.search(text)
    }
}

@MainActor
enum NewsAppearance {
    static let accent = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 1, green: 0.60, blue: 0.51, alpha: 1)
        }
        return UIColor(red: 0.60, green: 0.19, blue: 0.16, alpha: 1)
    }

    static func failure(
        title: String,
        message: String,
        retry: (@MainActor () -> Void)?
    ) -> UIContentUnavailableConfiguration {
        var failure = UIContentUnavailableConfiguration.empty()
        failure.image = UIImage(systemName: "exclamationmark.circle")
        failure.imageProperties.tintColor = accent
        failure.text = title
        failure.secondaryText = message
        if let retry {
            failure.button = .tinted()
            failure.button.title = "Try again"
            failure.buttonProperties.primaryAction = UIAction { _ in retry() }
        }
        return failure
    }
}
