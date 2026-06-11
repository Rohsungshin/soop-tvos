import UIKit

// MARK: - 검색 화면 (v4 — tvOS 네이티브 패턴)
//
// tvOS에서 UISearchBar를 view에 직접 add하면 키보드가 뜨지 않는다.
// 표준 패턴: `UISearchContainerViewController` + `UISearchController` 조합.
//   - UISearchContainerViewController가 큰 검색 입력 영역 + tvOS 키보드를 제공
//   - UISearchController의 searchResultsController로 결과 VC를 연결
//   - 결과 VC는 UISearchResultsUpdating을 구현하여 입력에 따라 필터링
//
// 비즈니스 로직 (allBroadcasts 풀, recentQueries, 셀 선택 → 재생)은 SearchResultsViewController로 이동.

final class SearchViewController: UIViewController {

    private let resultsVC = SearchResultsViewController()
    private var searchController: UISearchController!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = "검색"

        searchController = UISearchController(searchResultsController: resultsVC)
        searchController.searchResultsUpdater = resultsVC
        searchController.searchBar.placeholder = "BJ 닉네임 또는 방송 제목"
        searchController.obscuresBackgroundDuringPresentation = false
        // 결과 VC가 칩 탭 시 검색바 텍스트를 갱신할 수 있도록 콜백 연결
        resultsVC.onRequestQuery = { [weak self] q in
            self?.searchController.searchBar.text = q
            self?.searchController.isActive = true
        }

        let containerVC = UISearchContainerViewController(searchController: searchController)
        containerVC.title = "검색"

        addChild(containerVC)
        view.addSubview(containerVC.view)
        containerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerVC.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        containerVC.didMove(toParent: self)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .playPause {
            resultsVC.reloadPool()
            ToastView.show(in: view, message: "검색 풀 새로고침 중...", duration: 1.2)
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

// MARK: - 검색 결과 VC

final class SearchResultsViewController: UIViewController {

    /// 칩 탭 시 부모(SearchViewController)에 검색바 텍스트 갱신을 요청하는 콜백
    var onRequestQuery: ((String) -> Void)?

    private var recentBox: UIStackView!
    private var resultsCollectionView: UICollectionView!
    private var emptyLabel: UILabel!

    private var allBroadcasts: [LiveBroadcast] = []
    private var filtered: [LiveBroadcast] = []
    private var recentQueries: [String] = []
    private var hasLoadedAll = false
    /// 풀 로드 실패 기록 — 다음 검색 시도 시 자동 재로드 트리거
    private var hasLoadFailed = false
    /// 자동 재로드 진행 중 — 중복 재로드 방지
    private var isReloading = false
    /// 재로드 완료 후 이어서 실행할 검색어
    private var pendingQuery: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        loadRecentQueries()
        setupUI()
        loadAllBroadcasts()
    }

    private func setupUI() {
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
            recentBox.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Spacing.md),
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
        setEmptyStateVisible(true)
    }

    /// emptyLabel ↔ resultsCollectionView 상호 배타 표시 — 두 isHidden을 항상 함께 설정
    private func setEmptyStateVisible(_ visible: Bool) {
        emptyLabel.isHidden = !visible
        resultsCollectionView.isHidden = visible
    }

    /// 외부에서 호출 — Play/Pause 새로고침
    func reloadPool() {
        hasLoadedAll = false
        hasLoadFailed = false
        isReloading = false
        loadAllBroadcasts()
    }

    private func loadAllBroadcasts() {
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard case .success(let cats) = result else {
                    // 실패 기록 — 다음 검색 시도 시 runSearch가 자동 재로드한다
                    self.hasLoadFailed = true
                    self.isReloading = false
                    return
                }
                let group = DispatchGroup()
                var combined: [LiveBroadcast] = []
                let queue = DispatchQueue(label: "search.merge")
                // 상위 15개 카테고리의 라이브를 머지하여 검색 풀로 사용
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
                    self.hasLoadFailed = false
                    // 자동 재로드 성공 — 마지막으로 시도한 검색어로 이어서 검색
                    if self.isReloading {
                        self.isReloading = false
                        if let q = self.pendingQuery {
                            self.pendingQuery = nil
                            self.runSearch(q)
                        }
                    }
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
                    self?.onRequestQuery?(query)
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
            emptyLabel.text = "검색어를 입력해 보세요"
            setEmptyStateVisible(true)
            resultsCollectionView.reloadData()
            return
        }
        if !hasLoadedAll {
            // 아직 검색 가능한 풀이 없음 — 이전 결과 그리드를 비우고 빈 상태로 전환 (design §2-3)
            filtered = []
            resultsCollectionView.reloadData()
            if isReloading {
                // 재로드 진행 중 — 중복 재로드 없이 검색어만 갱신
                pendingQuery = query
                emptyLabel.text = "데이터를 다시 불러오고 있습니다"
                ToastView.show(in: view, message: "데이터를 다시 불러오고 있습니다", duration: 2.0)
            } else if hasLoadFailed {
                // 풀 로드 실패 상태 — 검색 시도를 트리거로 자동 재로드
                pendingQuery = query
                isReloading = true
                emptyLabel.text = "검색 데이터를 다시 불러옵니다"
                ToastView.show(in: view, message: "검색 데이터를 다시 불러옵니다", duration: 2.0)
                loadAllBroadcasts()
            } else {
                emptyLabel.text = "데이터 준비 중입니다. 잠시 후 다시 시도해 주세요"
                ToastView.show(in: view, message: "데이터 준비 중입니다. 잠시 후 다시 시도해 주세요", duration: 2.0)
            }
            setEmptyStateVisible(true)
            return
        }
        filtered = allBroadcasts.filter {
            $0.bjNick.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
        if filtered.isEmpty {
            // 결과 0건 — 검색 범위(상위 15개 카테고리) 안내를 함께 표시
            emptyLabel.attributedText = noResultsText(for: query)
        }
        setEmptyStateVisible(filtered.isEmpty)
        resultsCollectionView.reloadData()
        // 2글자 이상의 명시적 검색만 최근 검색어로 저장
        if query.count >= 2 { addRecent(query) }
    }

    /// 결과 0건 안내 — 1줄: 결과 없음 / 2줄: 검색 범위 안내
    private func noResultsText(for query: String) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\"\(query)\"에 대한 결과가 없습니다\n",
            attributes: [
                .font: DS.Typography.subsection,
                .foregroundColor: DS.Colors.textSecondary,
            ]
        )
        text.append(NSAttributedString(
            string: "인기 카테고리 상위 15개의 라이브 방송에서 검색한 결과입니다",
            attributes: [
                .font: DS.Typography.body,
                .foregroundColor: DS.Colors.textTertiary,
            ]
        ))
        return text
    }
}

// MARK: - UISearchResultsUpdating

extension SearchResultsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        // tvOS 검색 키보드는 한 글자씩 들어옴 — 1글자는 너무 광범위하므로 2글자 이상에서 필터링
        if text.count >= 2 {
            runSearch(text)
        } else if text.isEmpty {
            filtered = []
            emptyLabel.text = "검색어를 입력해 보세요"
            setEmptyStateVisible(true)
            resultsCollectionView.reloadData()
        }
    }
}

// MARK: - Collection View

extension SearchResultsViewController: UICollectionViewDataSource, UICollectionViewDelegate {
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
                case .failure(let err):
                    self.showPlaybackError(err)
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
