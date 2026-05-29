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

    private var popularLive: [LiveBroadcast] = []
    private var popularCategories: [SOOPCategory] = []
    private var recentBroadcasts: [LiveBroadcast] = []
    private var favoritesLive: [FavoriteBJ] = []

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
            loadData()
            loadFavorites()
            loadRecent()
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
        // v3: 1.5초 timeout — 네트워크 지연 시에도 스켈레톤이 계속 깜빡이지 않게 강제 종료
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hideSkeleton()
        }
    }

    private func hideSkeleton() {
        skeletonView?.stopAnimating()
        skeletonView = nil
    }

    private func loadData() {
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let cats) = result {
                    self.popularCategories = Array(cats.prefix(6))
                    self.tableView.reloadData()
                    self.loadPopularLive(from: Array(cats.prefix(3)))
                }
            }
        }
        loadFavorites()
        loadRecent()
    }

    private func loadPopularLive(from categories: [SOOPCategory]) {
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
            guard let self = self else { return }
            self.popularLive = combined.sorted { $0.viewerCount > $1.viewerCount }.prefix(10).map { $0 }
            self.hideSkeleton()
            self.tableView.reloadData()
        }
    }

    private func loadFavorites() {
        SOOPAPIClient.shared.fetchFavorites { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let favs) = result {
                    self.favoritesLive = favs.filter { $0.isLive }
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func loadRecent() {
        recentBroadcasts = RecentWatchStore.shared.load()
        tableView.reloadData()
    }

    fileprivate func didSelectCategory(_ cat: SOOPCategory) {
        let listVC = LiveListViewController()
        listVC.categoryCode = cat.code
        listVC.categoryTitle = cat.name
        navigationController?.pushViewController(listVC, animated: true)
    }

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
                case .failure:
                    ToastView.show(in: self.view, message: "재생할 수 없습니다", duration: 1.8)
                }
            }
        }
    }

    fileprivate func didSelectFavorite(_ f: FavoriteBJ) {
        let overlay = LoadingOverlayView.show(in: view, message: "\(f.nick) 방송 연결 중...")
        SOOPAPIClient.shared.fetchStreamInfo(bjId: f.bjId, broadNo: "0") { [weak self] result in
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
                        viewerCount: f.totalViewCount,
                        category: ""
                    )
                    RecentWatchStore.shared.save(bc)
                    let player = PlayerViewController()
                    player.streamInfo = info
                    player.modalPresentationStyle = .fullScreen
                    self.present(player, animated: true)
                case .failure:
                    ToastView.show(in: self.view, message: "재생할 수 없습니다", duration: 1.8)
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
        switch s {
        case .popularLive, .recent, .favoritesLive: return 410
        case .popularCategories:                    return 350
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

        titleLabel.font = DS.Typography.subsection
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = DS.Spacing.md
        layout.minimumInteritemSpacing = DS.Spacing.md
        layout.sectionInset = UIEdgeInsets(top: DS.Spacing.xs, left: DS.Layout.contentSideMargin, bottom: DS.Spacing.xs, right: DS.Layout.contentSideMargin)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
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
