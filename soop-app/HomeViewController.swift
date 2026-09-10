import UIKit

// MARK: - HOME 탭 (v2 신규)
//
// 기획서 v2 3.1 — 4섹션 구조:
//   1) 인기 라이브 (가로 캐러셀, mini live 카드 320x230)
//   2) 인기 카테고리 TOP 6 (가로 캐러셀)
//   3) 최근 시청 (UserDefaults 기반)
//   4) 즐겨찾기 라이브 (favorites API에서 라이브 중인 것만)
//
// 비즈니스 로직: SOOPAPIClient 기존 API만 사용.

final class HomeViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case popularLive, popularCategories, recent, favoritesLive
    }

    private var tableView: UITableView!
    private var headerView: SectionHeaderView!
    private var skeletonView: LoadingSkeletonView?
    private var errorStateView: ErrorStateView?

    private var popularLive: [LiveBroadcast] = []
    private var popularCategories: [SOOPCategory] = []
    private var recentBroadcasts: [LiveBroadcast] = []
    private var favoritesLive: [FavoriteBJ] = []

    // 세 목록은 각각 독립적으로 갱신되므로 세대도 따로 관리한다.
    // (카테고리 → 인기 라이브는 하나의 연쇄이므로 dataEpoch를 공유)
    private var dataEpoch = RequestEpoch()
    private var favEpoch = RequestEpoch()
    private var recentEpoch = RequestEpoch()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = "HOME"
        setupUI()
        showSkeleton()
        loadData()
        NotificationCenter.default.addObserver(self, selector: #selector(onLoginSucceeded),
                                               name: .soopLoginSucceeded, object: nil)
    }

    @objc private func onLoginSucceeded() { loadFavorites() }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .playPause {
            // loadData()가 즐겨찾기/최근 시청까지 이어서 부른다.
            // 여기서 또 부르면 같은 API가 2번 동시에 나가 오래된 응답이 이길 수 있다.
            loadData()
            ToastView.show(in: view, message: "새로고침 중...", duration: 1.2)
            return
        }
        super.pressesBegan(presses, with: event)
    }

    private func setupUI() {
        headerView = SectionHeaderView(title: "HOME", subtitle: "오늘 SOOP에서 가장 핫한 콘텐츠")
        view.addSubview(headerView)

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = DS.Colors.background
        tableView.dataSource = self
        tableView.delegate = self
        // v4: 행 자체를 선택/포커스 대상으로 만들지 않는다 — 안쪽 캐러셀 카드가 포커스 타깃
        tableView.allowsSelection = false
        tableView.allowsFocus = false
        // v4.1: 포커스 카드가 행 경계를 살짝 넘어가도 잘리지 않게
        tableView.clipsToBounds = false
        tableView.register(CarouselRowCell.self, forCellReuseIdentifier: "carousel")
        tableView.register(FavoritesCarouselCell.self, forCellReuseIdentifier: "favCarousel")
        tableView.estimatedRowHeight = 360
        tableView.rowHeight = UITableView.automaticDimension
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.contentInset = UIEdgeInsets(top: DS.Spacing.md, left: 0, bottom: DS.Layout.gridBottomInset, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Layout.headerTopOffset),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Layout.contentSideMargin),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: DS.Layout.gridTopGap),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func showSkeleton() {
        let sk = LoadingSkeletonView(style: .carousel)
        view.addSubview(sk)
        NSLayoutConstraint.activate([
            sk.topAnchor.constraint(equalTo: tableView.topAnchor),
            sk.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sk.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sk.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        sk.startAnimating()
        skeletonView = sk
    }

    private func hideSkeleton() {
        skeletonView?.stopAnimating()
        skeletonView = nil
    }

    private func loadData() {
        let token = dataEpoch.begin()
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.dataEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let cats):
                    // 카테고리 도착 즉시 스켈레톤 해제 — 스켈레톤 위 reloadData 방지
                    self.hideSkeleton()
                    self.hideErrorState()
                    self.popularCategories = Array(cats.prefix(6))
                    // 인기 라이브는 아직 이전 갱신의 결과지만, 뒤이은 loadPopularLive가
                    // 성공/실패 어느 쪽이든 항상 덮어쓰므로 여기서 비우지 않는다.
                    // (비우면 새로고침마다 행이 사라졌다 나타나 레이아웃이 튄다)
                    self.tableView.reloadData()
                    self.loadPopularLive(from: Array(cats.prefix(3)), token: token)
                case .failure:
                    // 실패 확정 — 스켈레톤 즉시 해제, 옛 목록을 비우고 오류 상태 뷰 표시
                    self.hideSkeleton()
                    self.popularCategories = []
                    self.popularLive = []
                    self.tableView.reloadData()
                    self.showErrorState()
                }
            }
        }
        loadFavorites()
        loadRecent()
    }

    private func loadPopularLive(from categories: [SOOPCategory], token: Int) {
        let group = DispatchGroup()
        var combined: [LiveBroadcast] = []
        let queue = DispatchQueue(label: "home.merge")
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
            guard let self = self, self.dataEpoch.isCurrent(token) else { return }
            self.popularLive = combined.sorted { $0.viewerCount > $1.viewerCount }.prefix(10).map { $0 }
            self.tableView.reloadData()
        }
    }

    // MARK: 오류 상태 (카테고리 로드 실패)

    private func showErrorState() {
        hideErrorState()
        let errorView = ErrorStateView(icon: "wifi.exclamationmark", title: "콘텐츠를 불러오지 못했습니다")
        errorView.onRetry = { [weak self] in
            guard let self = self else { return }
            self.hideErrorState()
            self.showSkeleton()
            self.loadData()
        }
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        errorStateView = errorView
        // 즐겨찾기/최근 시청 행이 오류 뷰와 겹치지 않게 콘텐츠는 숨긴다
        tableView.isHidden = true
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func hideErrorState() {
        errorStateView?.removeFromSuperview()
        errorStateView = nil
        tableView.isHidden = false
    }

    // 오류 상태 뷰가 떠 있으면 포커스를 "다시 시도" 버튼으로 보낸다
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let errorView = errorStateView { return [errorView] }
        return super.preferredFocusEnvironments
    }

    private func loadFavorites() {
        let token = favEpoch.begin()
        SOOPAPIClient.shared.fetchFavorites { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.favEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let favs):
                    self.favoritesLive = favs.filter { $0.isLive }
                case .failure:
                    // 실패를 무시하면 이미 방송을 끝낸 BJ가 LIVE 배지를 단 채 계속 남는다
                    self.favoritesLive = []
                }
                self.tableView.reloadData()
            }
        }
    }

    private func loadRecent() {
        let token = recentEpoch.begin()
        let saved = RecentWatchStore.shared.load()
        guard !saved.isEmpty else {
            recentBroadcasts = []
            tableView.reloadData()
            return
        }
        // v4.2: 저장된 BJID들을 폴링해서 지금 라이브인 것만 노출.
        // (저장 시점에는 라이브였더라도 시간이 지나면 종료될 수 있어 그대로 보여주면
        // 클릭 시 재생 실패 토스트만 뜨는 식의 deadend가 발생함)
        let bjids = saved.map(\.bjId)
        SOOPAPIClient.shared.fetchLiveListForBJIDs(bjids) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.recentEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let live):
                    // 응답에서 BJID 기반 lookup 만들고, 저장 순서(최신 → 과거)를 유지하며 매핑
                    var liveByBJID: [String: LiveBroadcast] = [:]
                    for bc in live { liveByBJID[bc.bjId] = bc }
                    self.recentBroadcasts = saved.compactMap { liveByBJID[$0.bjId] }
                case .failure:
                    self.recentBroadcasts = []
                }
                self.tableView.reloadData()
            }
        }
    }

    fileprivate func didSelectCategory(_ cat: SOOPCategory) {
        let listVC = LiveListViewController()
        listVC.categoryCode = cat.code
        listVC.categoryTitle = cat.name
        navigationController?.pushViewController(listVC, animated: true)
    }

    fileprivate func didSelectBroadcast(_ bc: LiveBroadcast, password: String? = nil) {
        let overlay = LoadingOverlayView.show(in: view, message: "\(bc.bjNick) 방송 연결 중...")
        SOOPAPIClient.shared.fetchStreamInfo(bjId: bc.bjId, broadNo: bc.broadNo, password: password) { [weak self] result in
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
                    if !self.promptPassword(for: err, bjNick: bc.bjNick, retry: { pwd in
                        self.didSelectBroadcast(bc, password: pwd)
                    }) {
                        self.showPlaybackError(err)
                    }
                }
            }
        }
    }

    fileprivate func didSelectFavorite(_ f: FavoriteBJ, password: String? = nil) {
        let overlay = LoadingOverlayView.show(in: view, message: "\(f.nick) 방송 연결 중...")
        SOOPAPIClient.shared.fetchStreamInfo(bjId: f.bjId, broadNo: "0", password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                overlay.dismiss()
                switch result {
                case .success(let info):
                    // v3: 즐겨찾기 라이브 선택도 최근 시청 기록
                    let bc = LiveBroadcast(
                        bjId: info.bjId,
                        broadNo: info.broadNo,
                        title: info.title,
                        bjNick: info.bjNick,
                        thumbnailURL: nil,
                        viewerCount: f.liveViewerCount,
                        category: ""
                    )
                    RecentWatchStore.shared.save(bc)
                    let player = PlayerViewController()
                    player.streamInfo = info
                    player.modalPresentationStyle = .fullScreen
                    self.present(player, animated: true)
                case .failure(let err):
                    if !self.promptPassword(for: err, bjNick: f.nick, retry: { pwd in
                        self.didSelectFavorite(f, password: pwd)
                    }) {
                        self.showPlaybackError(err)
                    }
                }
            }
        }
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .popularLive:       return popularLive.isEmpty ? 0 : 1
        case .popularCategories: return popularCategories.isEmpty ? 0 : 1
        case .recent:            return recentBroadcasts.isEmpty ? 0 : 1
        case .favoritesLive:     return favoritesLive.isEmpty ? 0 : 1
        }
    }

    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let s = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        switch s {
        case .popularLive:
            let cell = tv.dequeueReusableCell(withIdentifier: "carousel", for: indexPath) as! CarouselRowCell
            cell.configure(
                title: "지금 가장 핫한 방송",
                broadcasts: popularLive,
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
                title: "최근 시청",
                broadcasts: recentBroadcasts,
                categories: [],
                onSelectBroadcast: { [weak self] in self?.didSelectBroadcast($0) },
                onSelectCategory: nil
            )
            return cell
        case .favoritesLive:
            let cell = tv.dequeueReusableCell(withIdentifier: "favCarousel", for: indexPath) as! FavoritesCarouselCell
            cell.configure(
                title: "즐겨찾기 라이브",
                favorites: favoritesLive,
                onSelect: { [weak self] in self?.didSelectFavorite($0) }
            )
            return cell
        }
    }

    func tableView(_ tv: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let s = Section(rawValue: indexPath.section) else { return 0 }
        // v4.3: 카드 높이 320 → 340으로 늘어남에 따라 행 높이 재계산.
        // 헤더 ~32 + 12 gap + 16 padding = 60 + collectionView(card 340 + 36 top + 36 bottom inset) 412 = 472, 8pt 여유 = 480.
        // favoritesLive는 myLive 320 그대로지만 visual 일관성 위해 broadcast와 동일 사용.
        switch s {
        case .popularLive, .recent, .favoritesLive: return 500
        case .popularCategories:                    return 410
        }
    }
}

// MARK: - 즐겨찾기 라이브 캐러셀 (HOME 전용)

final class FavoritesCarouselCell: UITableViewCell {

    private let titleLabel = UILabel()
    private var collectionView: UICollectionView!
    private var favorites: [FavoriteBJ] = []
    private var onSelect: ((FavoriteBJ) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        // v4.1: 포커스 scale + glow가 부모 영역 밖으로 나가도 잘리지 않게 unclip
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
        // v4.1: 위아래 글로우 공간 확보
        layout.sectionInset = UIEdgeInsets(top: 36, left: DS.Layout.contentSideMargin, bottom: 36, right: DS.Layout.contentSideMargin)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.clipsToBounds = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MyLiveBroadcastCell.self, forCellWithReuseIdentifier: "live")
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DS.Spacing.xs),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Layout.contentSideMargin),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Layout.contentSideMargin),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DS.Spacing.sm),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // v4: 행 셀이 포커스를 흡수하지 않도록 — 안쪽 카드가 직접 포커스를 받게 한다
    override var canBecomeFocused: Bool { false }
    override var preferredFocusEnvironments: [UIFocusEnvironment] { [collectionView] }

    func configure(title: String, favorites: [FavoriteBJ], onSelect: ((FavoriteBJ) -> Void)?) {
        titleLabel.text = title
        self.favorites = favorites
        self.onSelect = onSelect
        collectionView.reloadData()
    }
}

extension FavoritesCarouselCell: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { favorites.count }
    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "live", for: indexPath) as! MyLiveBroadcastCell
        cell.configure(with: favorites[indexPath.item])
        return cell
    }
    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return DS.CardSize.myLive
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(favorites[indexPath.item])
    }
}

// MARK: - 최근 시청 저장소

final class RecentWatchStore {
    static let shared = RecentWatchStore()
    private let key = "soop.recent.broadcasts.v1"
    private let maxCount = 10

    private init() {}

    func save(_ bc: LiveBroadcast) {
        var list = load()
        list.removeAll { $0.bjId == bc.bjId }
        list.insert(bc, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        persist(list)
    }

    func load() -> [LiveBroadcast] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([Stored].self, from: data) else {
            return []
        }
        return raw.map { LiveBroadcast(
            bjId: $0.bjId,
            broadNo: $0.broadNo,
            title: $0.title,
            bjNick: $0.bjNick,
            thumbnailURL: $0.thumbnailURL.flatMap { URL(string: $0) },
            viewerCount: $0.viewerCount,
            category: $0.category
        ) }
    }

    private func persist(_ list: [LiveBroadcast]) {
        let stored = list.map { Stored(
            bjId: $0.bjId,
            bjNick: $0.bjNick,
            broadNo: $0.broadNo,
            title: $0.title,
            category: $0.category,
            viewerCount: $0.viewerCount,
            thumbnailURL: $0.thumbnailURL?.absoluteString
        ) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct Stored: Codable {
        let bjId: String
        let bjNick: String
        let broadNo: String
        let title: String
        let category: String
        let viewerCount: Int
        let thumbnailURL: String?
    }
}
