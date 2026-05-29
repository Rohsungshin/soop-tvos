import UIKit

// MARK: - 검색 화면 (v2 신규)
//
// 기획서 v2 3.2 — 클라이언트 사이드 필터링 기반.
// 전체 카테고리의 라이브를 메모리에 적재 후 nick/title 필터링.
// 최근 검색어는 UserDefaults에 저장 (최대 10개).

final class SearchViewController: UIViewController {

    private var headerView: SectionHeaderView!
    private var searchBar: UISearchBar!
    private var recentBox: UIStackView!
    private var resultsCollectionView: UICollectionView!
    private var emptyLabel: UILabel!

    private var allBroadcasts: [LiveBroadcast] = []
    private var filtered: [LiveBroadcast] = []
    private var recentQueries: [String] = []

    private var hasLoadedAll = false
    private var loadingOverlay: LoadingOverlayView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = "검색"
        loadRecentQueries()
        setupUI()
        loadAllBroadcasts()
    }

    private func setupUI() {
        headerView = SectionHeaderView(title: "검색", subtitle: "BJ 닉네임 또는 방송 제목으로 찾기")
        view.addSubview(headerView)

        // v3: tvOS 17은 navigationItem.searchController 미지원 → UISearchBar 그대로 사용
        // (tvOS native UX는 UISearchBar + 큰 입력 영역으로 잘 동작)
        searchBar = UISearchBar()
        searchBar.placeholder = "검색어를 입력하세요"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        recentBox = UIStackView()
        recentBox.axis = .horizontal
        recentBox.spacing = DS.Spacing.sm
        recentBox.alignment = .center
        recentBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recentBox)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.itemSize = DS.CardSize.searchResult
        layout.minimumInteritemSpacing = DS.Spacing.md
        layout.minimumLineSpacing = DS.Spacing.lg
        layout.sectionInset = UIEdgeInsets(
            top: DS.Layout.gridTopInset,
            left: DS.Layout.contentSideMargin,
            bottom: DS.Layout.gridBottomInset,
            right: DS.Layout.contentSideMargin
        )

        resultsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        resultsCollectionView.backgroundColor = DS.Colors.background
        resultsCollectionView.dataSource = self
        resultsCollectionView.delegate = self
        resultsCollectionView.register(LiveBroadcastCell.self, forCellWithReuseIdentifier: "cell")
        resultsCollectionView.remembersLastFocusedIndexPath = true
        resultsCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultsCollectionView)

        emptyLabel = UILabel()
        emptyLabel.text = "검색어를 입력해 보세요"
        emptyLabel.textColor = DS.Colors.textSecondary
        emptyLabel.font = DS.Typography.subsection
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Layout.headerTopOffset),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Layout.contentSideMargin),

            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: DS.Spacing.md),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Layout.contentSideMargin),
            searchBar.heightAnchor.constraint(equalToConstant: 64),

            recentBox.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: DS.Spacing.sm),
            recentBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
            recentBox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -DS.Layout.contentSideMargin),
            recentBox.heightAnchor.constraint(equalToConstant: 50),

            resultsCollectionView.topAnchor.constraint(equalTo: recentBox.bottomAnchor, constant: DS.Spacing.md),
            resultsCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.statusSideMargin),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Layout.statusSideMargin),
        ])

        refreshRecentBox()
    }

    private func loadAllBroadcasts() {
        // 상위 5개 카테고리의 방송을 머지해서 검색 풀로 사용
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let cats) = result else { return }
                let group = DispatchGroup()
                var combined: [LiveBroadcast] = []
                let queue = DispatchQueue(label: "search.merge")
                // v3.2: 상위 15개 카테고리로 확장 — 검색 풀 커버리지 개선
                for cat in cats.prefix(15) {
                    group.enter()
                    SOOPAPIClient.shared.fetchBroadcasts(byCategory: cat.code) { res in
                        if case .success(let list) = res {
                            queue.sync { combined.append(contentsOf: list) }
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    self.allBroadcasts = combined
                    self.hasLoadedAll = true
                }
            }
        }
    }

    private func loadRecentQueries() {
        recentQueries = UserDefaults.standard.stringArray(forKey: "soop.search.recent") ?? []
    }

    private func persistRecentQueries() {
        UserDefaults.standard.set(recentQueries, forKey: "soop.search.recent")
    }

    private func addRecent(_ q: String) {
        guard !q.isEmpty else { return }
        recentQueries.removeAll { $0 == q }
        recentQueries.insert(q, at: 0)
        if recentQueries.count > 10 { recentQueries = Array(recentQueries.prefix(10)) }
        persistRecentQueries()
        refreshRecentBox()
    }

    private func refreshRecentBox() {
        recentBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if recentQueries.isEmpty {
            let label = UILabel()
            label.text = "최근 검색어가 없습니다"
            label.textColor = DS.Colors.textTertiary
            label.font = DS.Typography.caption
            recentBox.addArrangedSubview(label)
        } else {
            let title = UILabel()
            title.text = "최근:"
            title.textColor = DS.Colors.textSecondary
            title.font = DS.Typography.subcaption
            recentBox.addArrangedSubview(title)
            for q in recentQueries.prefix(6) {
                let chip = RecentChipButton(query: q)
                chip.onTap = { [weak self] query in
                    self?.searchBar.text = query
                    self?.runSearch(query)
                }
                recentBox.addArrangedSubview(chip)
            }
        }
    }

    private func runSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filtered = []
            emptyLabel.isHidden = false
            emptyLabel.text = "검색어를 입력해 보세요"
            resultsCollectionView.reloadData()
            return
        }
        if !hasLoadedAll {
            ToastView.show(in: view, message: "데이터 준비 중입니다. 잠시 후 다시 시도해 주세요", duration: 2.0)
            return
        }
        filtered = allBroadcasts.filter {
            $0.bjNick.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
        emptyLabel.isHidden = !filtered.isEmpty
        if filtered.isEmpty {
            emptyLabel.text = "\"\(query)\"에 대한 결과가 없습니다"
        }
        resultsCollectionView.reloadData()
        addRecent(query)
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        runSearch(searchBar.text ?? "")
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // tvOS 리모컨 키패드는 입력이 한 글자씩 들어와도 비교적 빠름.
        // v3.1: 2글자 이상이면 즉시 필터링하여 인터랙티브하게 결과 갱신.
        if searchText.count >= 2 {
            runSearch(searchText)
        } else if searchText.isEmpty {
            filtered = []
            emptyLabel.isHidden = false
            emptyLabel.text = "검색어를 입력해 보세요"
            resultsCollectionView.reloadData()
        }
    }
}

extension SearchViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { filtered.count }
    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LiveBroadcastCell
        cell.configure(with: filtered[indexPath.item])
        return cell
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let bc = filtered[indexPath.item]
        let overlay = LoadingOverlayView.show(in: view, message: "\(bc.bjNick) 방송 연결 중...")
        SOOPAPIClient.shared.fetchStreamInfo(bjId: bc.bjId, broadNo: bc.broadNo) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                overlay.dismiss()
                switch result {
                case .success(let info):
                    RecentWatchStore.shared.save(bc)
                    let player = PlayerViewController()
                    player.streamInfo = info
                    player.posterThumbnailURL = bc.thumbnailURL
                    player.modalPresentationStyle = .fullScreen
                    self.present(player, animated: true)
                case .failure:
                    ToastView.show(in: self.view, message: "재생할 수 없습니다", duration: 1.8)
                }
            }
        }
    }
}

// MARK: - 최근 검색어 칩 버튼

final class RecentChipButton: UIControl {
    private let label = UILabel()
    let query: String
    var onTap: ((String) -> Void)?

    init(query: String) {
        self.query = query
        super.init(frame: .zero)
        backgroundColor = DS.Colors.surface
        layer.cornerRadius = DS.Corner.badge
        translatesAutoresizingMaskIntoConstraints = false

        label.text = query
        label.textColor = DS.Colors.textPrimary
        label.font = DS.Typography.subcaption
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.sm),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.sm),
        ])

        addTarget(self, action: #selector(handleTap), for: .primaryActionTriggered)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() { onTap?(query) }

    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.applyBorder(to: self, focused: self.isFocused)
        }
    }
}
