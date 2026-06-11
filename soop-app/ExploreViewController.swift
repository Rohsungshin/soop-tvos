import UIKit

// MARK: - 탐색 탭
//
// 기획서 3.4 — 수직 스크롤 + 섹션별 가로 캐러셀 구조.
//   섹션 1: 검색 진입 셀 (큰 입력형 CTA, 검색 화면 미구현 시 placeholder)
//   섹션 2: 지금 가장 핫한 방송 — 인기 카테고리 상위의 라이브 머지 (가로 캐러셀)
//   섹션 3: 인기 카테고리 (가로 캐러셀)
//   섹션 4: 최근 시청한 방송 — UserDefaults 기반 (현재는 비활성)
//
// 기존 비즈니스 로직 변경 없음. SOOPAPIClient의 기존 API만 활용.

final class ExploreViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case search, popularBroadcasts, popularCategories, recent
    }

    private var tableView: UITableView!
    private var headerView: SectionHeaderView!
    private var errorStateView: ErrorStateView?

    private var popularCategories: [SOOPCategory] = []
    private var popularBroadcasts: [LiveBroadcast] = []
    private var recentBroadcasts: [LiveBroadcast] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = "탐색"
        setupUI()
        loadData()
    }

    private func setupUI() {
        headerView = SectionHeaderView(title: "탐색", subtitle: "무엇을 보고 싶으세요?")
        view.addSubview(headerView)

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = DS.Colors.background
        // tvOS의 UITableView는 기본적으로 separator 없음 — separatorStyle 속성 미지원
        tableView.dataSource = self
        tableView.delegate = self
        // v4.1: 포커스 카드 glow가 행 경계를 넘어가도 잘리지 않게
        tableView.clipsToBounds = false
        tableView.register(SearchEntryCell.self, forCellReuseIdentifier: "search")
        tableView.register(CarouselRowCell.self, forCellReuseIdentifier: "carousel")
        tableView.estimatedRowHeight = 320
        tableView.rowHeight = UITableView.automaticDimension
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.contentInset = UIEdgeInsets(top: 24, left: 0, bottom: 64, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Spacing.xl),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Spacing.xl),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .playPause {
            loadData()
            ToastView.show(in: view, message: "새로고침 중...", duration: 1.2)
            return
        }
        super.pressesBegan(presses, with: event)
    }

    private func loadData() {
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let cats):
                    self.hideErrorState()
                    let top12 = Array(cats.prefix(12))
                    self.popularCategories = top12
                    self.tableView.reloadData()
                    // 인기 방송 — 상위 3개 카테고리 머지
                    let topForBroadcasts = Array(cats.prefix(3))
                    self.loadPopularBroadcasts(from: topForBroadcasts)
                case .failure:
                    // 로드 실패 — 오류 상태 뷰 + 재시도 (검색 진입 셀은 그대로 유지)
                    self.showErrorState()
                }
            }
        }
    }

    // MARK: 오류 상태 (카테고리 로드 실패)

    private func showErrorState() {
        hideErrorState()
        let errorView = ErrorStateView(icon: "wifi.exclamationmark", title: "콘텐츠를 불러오지 못했습니다")
        errorView.onRetry = { [weak self] in
            guard let self = self else { return }
            self.hideErrorState()
            self.loadData()
        }
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        errorStateView = errorView
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func hideErrorState() {
        errorStateView?.removeFromSuperview()
        errorStateView = nil
    }

    // 오류 상태 뷰가 떠 있으면 포커스를 "다시 시도" 버튼으로 보낸다
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let errorView = errorStateView { return [errorView] }
        return super.preferredFocusEnvironments
    }

    private func loadPopularBroadcasts(from categories: [SOOPCategory]) {
        let group = DispatchGroup()
        var combined: [LiveBroadcast] = []
        let queue = DispatchQueue(label: "explore.merge")
        for cat in categories {
            group.enter()
            SOOPAPIClient.shared.fetchBroadcasts(byCategory: cat.code) { result in
                if case .success(let list) = result {
                    queue.sync { combined.append(contentsOf: list) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // 시청자수 내림차순 정렬 후 상위 20개
            self.popularBroadcasts = combined.sorted { $0.viewerCount > $1.viewerCount }.prefix(20).map { $0 }
            self.tableView.reloadData()
        }
    }

    // 셀에서 콜백으로 호출 — 카테고리 선택
    fileprivate func didSelectCategory(_ cat: SOOPCategory) {
        let listVC = LiveListViewController()
        listVC.categoryCode = cat.code
        listVC.categoryTitle = cat.name
        navigationController?.pushViewController(listVC, animated: true)
    }

    // 셀에서 콜백으로 호출 — 방송 선택
    fileprivate func didSelectBroadcast(_ bc: LiveBroadcast) {
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

// MARK: - TableView Data

extension ExploreViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .search:             return 1
        case .popularBroadcasts:  return popularBroadcasts.isEmpty ? 0 : 1
        case .popularCategories:  return popularCategories.isEmpty ? 0 : 1
        case .recent:             return recentBroadcasts.isEmpty ? 0 : 1
        }
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let s = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        switch s {
        case .search:
            let cell = tv.dequeueReusableCell(withIdentifier: "search", for: indexPath) as! SearchEntryCell
            return cell
        case .popularBroadcasts:
            let cell = tv.dequeueReusableCell(withIdentifier: "carousel", for: indexPath) as! CarouselRowCell
            cell.configure(
                title: "지금 가장 핫한 방송",
                broadcasts: popularBroadcasts,
                categories: [],
                onSelectBroadcast: { [weak self] in self?.didSelectBroadcast($0) },
                onSelectCategory: nil
            )
            return cell
        case .popularCategories:
            let cell = tv.dequeueReusableCell(withIdentifier: "carousel", for: indexPath) as! CarouselRowCell
            cell.configure(
                title: "인기 카테고리",
                broadcasts: [],
                categories: popularCategories,
                onSelectBroadcast: nil,
                onSelectCategory: { [weak self] in self?.didSelectCategory($0) }
            )
            return cell
        case .recent:
            let cell = tv.dequeueReusableCell(withIdentifier: "carousel", for: indexPath) as! CarouselRowCell
            cell.configure(
                title: "최근 시청한 방송",
                broadcasts: recentBroadcasts,
                categories: [],
                onSelectBroadcast: { [weak self] in self?.didSelectBroadcast($0) },
                onSelectCategory: nil
            )
            return cell
        }
    }

    func tableView(_ tv: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let s = Section(rawValue: indexPath.section) else { return 0 }
        // v4.3: broadcast 카드 높이 320 → 340으로 늘어남에 따라 행 높이 재계산
        switch s {
        case .search:             return 200
        case .popularBroadcasts:  return 500
        case .popularCategories:  return 410
        case .recent:             return 500
        }
    }

    func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        // v2: 검색 셀 → SearchViewController로 push
        if indexPath.section == Section.search.rawValue {
            let searchVC = SearchViewController()
            navigationController?.pushViewController(searchVC, animated: true)
        }
    }
}

// MARK: - 검색 진입 셀

final class SearchEntryCell: UITableViewCell {

    private let container = UIView()
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        container.backgroundColor = DS.Colors.surface
        container.layer.cornerRadius = DS.Corner.card
        container.layer.masksToBounds = false
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        iconView.image = UIImage(systemName: "magnifyingglass")
        iconView.tintColor = DS.Colors.textPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        label.text = "검색하기 — BJ 닉네임/방송 제목"
        label.textColor = DS.Colors.textSecondary
        label.font = DS.Typography.body
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.xl),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.xl),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DS.Spacing.lg),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: DS.Spacing.md),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DS.Spacing.lg),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.applyBorder(to: self.container, focused: self.isFocused)
        }
    }
}

// MARK: - 가로 캐러셀 행

/// 단일 가로 캐러셀 행 — 섹션 제목 + UICollectionView (방송 or 카테고리)
final class CarouselRowCell: UITableViewCell {

    private let titleLabel = UILabel()
    private var collectionView: UICollectionView!
    private var broadcasts: [LiveBroadcast] = []
    private var categories: [SOOPCategory] = []
    private var onSelectBroadcast: ((LiveBroadcast) -> Void)?
    private var onSelectCategory: ((SOOPCategory) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        // v4.1: 포커스된 카드가 scale + glow로 부모 영역을 넘어가도 잘리지 않게 unclip
        clipsToBounds = false
        contentView.clipsToBounds = false

        titleLabel.font = DS.Typography.subsection
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = DS.Spacing.md
        layout.minimumInteritemSpacing = DS.Spacing.md
        // v4.1: 좌우 글로우 잘림 방지 — sectionInset 좌우는 그대로 두고
        // 상하 inset을 늘려 위아래로도 글로우 공간 확보
        layout.sectionInset = UIEdgeInsets(top: 36, left: DS.Spacing.xl, bottom: 36, right: DS.Spacing.xl)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.clipsToBounds = false   // 안쪽 카드 glow 살리기
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LiveBroadcastCell.self, forCellWithReuseIdentifier: "broadcast")
        collectionView.register(CategoryCell.self, forCellWithReuseIdentifier: "category")
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.xl),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.xl),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // v4: 행 자체가 포커스를 받으면 내부 컬렉션뷰의 카드까지 포커스가 도달하지 않는다.
    // 셀을 포커스 불가로 만들어 포커스가 안쪽 카드로 흘러 들어가게 한다.
    override var canBecomeFocused: Bool { false }
    override var preferredFocusEnvironments: [UIFocusEnvironment] { [collectionView] }

    func configure(title: String,
                   broadcasts: [LiveBroadcast],
                   categories: [SOOPCategory],
                   onSelectBroadcast: ((LiveBroadcast) -> Void)?,
                   onSelectCategory: ((SOOPCategory) -> Void)?) {
        titleLabel.text = title
        self.broadcasts = broadcasts
        self.categories = categories
        self.onSelectBroadcast = onSelectBroadcast
        self.onSelectCategory = onSelectCategory
        collectionView.reloadData()
    }
}

extension CarouselRowCell: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return broadcasts.isEmpty ? categories.count : broadcasts.count
    }
    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if !broadcasts.isEmpty {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "broadcast", for: indexPath) as! LiveBroadcastCell
            cell.configure(with: broadcasts[indexPath.item])
            return cell
        } else {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "category", for: indexPath) as! CategoryCell
            cell.configure(with: categories[indexPath.item])
            return cell
        }
    }
    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return broadcasts.isEmpty ? DS.CardSize.exploreCategory : DS.CardSize.explorePopular
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if !broadcasts.isEmpty {
            onSelectBroadcast?(broadcasts[indexPath.item])
        } else {
            onSelectCategory?(categories[indexPath.item])
        }
    }
}
