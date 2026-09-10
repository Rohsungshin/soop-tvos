import UIKit
import AVKit

// MARK: - MY 탭 (즐겨찾기 BJ)
//
// `https://myapi.sooplive.co.kr/api/favorite` 응답을 그리드로 표시.
// 기획서 3.5:
//   • 라이브 그룹 (큰 카드 380x280) 먼저, 시청자수 내림차순 (시청자수는 모름 → 알파벳 정렬)
//   • 오프라인 그룹 (작은 카드 240x280) 뒤
//   • 빈 상태: SF Symbol + 안내 + 새로고침 버튼
//   • 오프라인 카드 선택 시 alert 대신 토스트
//
// 두 셀 타입을 한 컬렉션뷰에서 2 섹션으로 구분.

final class MyViewController: UIViewController {

    private enum Group: Int {
        case live = 0
        case offline = 1
    }

    private var liveFavorites: [FavoriteBJ] = []
    private var offlineFavorites: [FavoriteBJ] = []

    private var collectionView: UICollectionView!
    private var headerView: SectionHeaderView!
    private var emptyStateView: UIView?
    private var errorStateView: ErrorStateView?
    private var statusLabel: UILabel!
    private var loadingOverlay: LoadingOverlayView?
    /// 트리거가 5개(최초 로드/로그인 알림/Play-Pause/빈 상태 새로고침/오류 재시도)라 요청이 겹치기 쉽다.
    /// 오래된 응답 — 특히 로그인 전에 나간 미인증 응답 — 이 최신 목록을 덮어쓰지 않도록.
    private var loadEpoch = RequestEpoch()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = "MY"
        setupUI()
        loadFavorites()
        NotificationCenter.default.addObserver(self, selector: #selector(onLoginSucceeded),
                                               name: .soopLoginSucceeded, object: nil)
    }

    @objc private func onLoginSucceeded() { loadFavorites() }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .playPause {
            loadFavorites()
            ToastView.show(in: view, message: "새로고침 중...", duration: 1.2)
            return
        }
        super.pressesBegan(presses, with: event)
    }

    private func setupUI() {
        headerView = SectionHeaderView(title: "MY", subtitle: "즐겨찾기 BJ")
        view.addSubview(headerView)

        statusLabel = UILabel()
        statusLabel.text = "즐겨찾기 불러오는 중..."
        statusLabel.textColor = DS.Colors.textSecondary
        statusLabel.font = DS.Typography.body
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 가변 사이즈 (라이브/오프라인 다름) — flow layout으로 셀별 사이즈 반환
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = DS.Spacing.md
        layout.minimumLineSpacing = DS.Spacing.lg
        layout.sectionInset = UIEdgeInsets(top: DS.Spacing.xs, left: DS.Layout.contentSideMargin, bottom: DS.Spacing.lg, right: DS.Layout.contentSideMargin)
        layout.headerReferenceSize = CGSize(width: DS.Layout.screenWidth, height: DS.Layout.sectionHeaderHeight)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = DS.Colors.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MyLiveBroadcastCell.self, forCellWithReuseIdentifier: "live")
        collectionView.register(MyOfflineBJCell.self, forCellWithReuseIdentifier: "offline")
        collectionView.register(MySectionHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: "header")
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Layout.headerTopOffset),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.contentSideMargin),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Layout.contentSideMargin),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Layout.statusSideMargin),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Layout.statusSideMargin),

            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: DS.Spacing.sm),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // statusLabel은 collectionView보다 먼저 addSubview되어 불투명한 그리드 배경에 가려진다.
        // 목록을 비운 뒤 재시도하는 동안 안내가 보이도록 앞으로 올린다.
        view.bringSubviewToFront(statusLabel)
    }

    private func loadFavorites() {
        let token = loadEpoch.begin()
        // 이미 카드가 떠 있으면 갱신 중 안내가 그 위에 겹친다 — 빈 화면일 때만 표시
        statusLabel.isHidden = !(liveFavorites.isEmpty && offlineFavorites.isEmpty)
        statusLabel.text = "즐겨찾기 불러오는 중..."
        hideEmptyState()
        hideErrorState()
        SOOPAPIClient.shared.fetchFavorites { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.loadEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let favs):
                    self.liveFavorites = favs.filter { $0.isLive }.sorted { $0.nick < $1.nick }
                    self.offlineFavorites = favs.filter { !$0.isLive }.sorted { $0.nick < $1.nick }
                    self.statusLabel.isHidden = true
                    if favs.isEmpty {
                        self.headerView.setSubtitle("즐겨찾기 BJ")
                        self.showEmptyState()
                    } else {
                        self.headerView.setSubtitle("즐겨찾기한 BJ \(favs.count)명")
                    }
                    self.collectionView.reloadData()
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                case .failure(let err):
                    // 실패한 갱신이 옛 즐겨찾기 카드를 최신처럼 남기지 않도록 비운다.
                    // (ErrorStateView는 배경이 투명하고 화면 중앙에만 놓여 옛 그리드를 가리지 못한다)
                    self.liveFavorites = []
                    self.offlineFavorites = []
                    self.collectionView.reloadData()
                    self.headerView.setSubtitle("즐겨찾기 BJ")
                    self.statusLabel.isHidden = true
                    self.showErrorState(for: err)
                }
            }
        }
    }

    // MARK: 빈 상태

    private func showEmptyState() {
        hideEmptyState()
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let icon = UIImageView(image: UIImage(systemName: "star.slash"))
        icon.tintColor = DS.Colors.textTertiary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        let line1 = UILabel()
        line1.text = "즐겨찾기한 BJ가 없습니다"
        line1.textColor = DS.Colors.textPrimary
        line1.font = DS.Typography.subsection
        line1.textAlignment = .center
        line1.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line1)

        let line2 = UILabel()
        line2.text = "SOOP 웹/앱에서 BJ를 즐겨찾기에 추가하면\n여기에 표시됩니다"
        line2.textColor = DS.Colors.textSecondary
        line2.font = DS.Typography.body
        line2.textAlignment = .center
        line2.numberOfLines = 2
        line2.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line2)

        var btnConfig = UIButton.Configuration.filled()
        btnConfig.title = "새로고침"
        btnConfig.baseBackgroundColor = DS.Colors.primary
        btnConfig.baseForegroundColor = DS.Colors.textPrimary
        btnConfig.contentInsets = DS.ButtonInsets.cta
        btnConfig.cornerStyle = .fixed
        btnConfig.background.cornerRadius = DS.Corner.button
        btnConfig.attributedTitle = AttributedString("새로고침", attributes: AttributeContainer([
            .font: DS.Typography.cardTitle
        ]))
        let refreshBtn = UIButton(configuration: btnConfig)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.addTarget(self, action: #selector(refreshTapped), for: .primaryActionTriggered)
        container.addSubview(refreshBtn)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 720),

            icon.topAnchor.constraint(equalTo: container.topAnchor),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),

            line1.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: DS.Spacing.md),
            line1.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            line1.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            line2.topAnchor.constraint(equalTo: line1.bottomAnchor, constant: 8),
            line2.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            line2.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            refreshBtn.topAnchor.constraint(equalTo: line2.bottomAnchor, constant: DS.Spacing.lg),
            refreshBtn.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            refreshBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        emptyStateView = container
    }

    private func hideEmptyState() {
        emptyStateView?.removeFromSuperview()
        emptyStateView = nil
    }

    @objc private func refreshTapped() { loadFavorites() }

    // MARK: 오류 상태 (즐겨찾기 로드 실패)

    private func showErrorState(for err: SOOPAPIError) {
        hideErrorState()
        // SOOPAPIError에 인증 전용 케이스가 없어, 로그인 쿠키(AuthTicket) 유무로
        // 인증 오류와 네트워크/서버 오류를 구분한다
        let isLoggedIn = HTTPCookieStorage.shared.cookies?.contains { $0.name == "AuthTicket" } ?? false
        let errorView: ErrorStateView
        if isLoggedIn {
            errorView = ErrorStateView(
                icon: "wifi.exclamationmark",
                title: "즐겨찾기를 불러오지 못했습니다",
                subtitle: "인터넷 연결을 확인하고 다시 시도해 주세요"
            )
        } else {
            errorView = ErrorStateView(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "로그인 정보를 확인할 수 없습니다",
                subtitle: "SOOP 계정으로 로그인되어 있는지 확인해 주세요"
            )
        }
        errorView.onRetry = { [weak self] in self?.loadFavorites() }
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

    // MARK: 인라인 로딩 오버레이 — 공용 LoadingOverlayView 사용

    private func showLoadingOverlay(message: String) {
        hideLoadingOverlay()
        loadingOverlay = LoadingOverlayView.show(in: view, message: message)
    }

    private func hideLoadingOverlay() {
        loadingOverlay?.dismiss()
        loadingOverlay = nil
    }
}

extension MyViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in cv: UICollectionView) -> Int { 2 }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == Group.live.rawValue ? liveFavorites.count : offlineFavorites.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == Group.live.rawValue {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "live", for: indexPath) as! MyLiveBroadcastCell
            cell.configure(with: liveFavorites[indexPath.item])
            return cell
        } else {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "offline", for: indexPath) as! MyOfflineBJCell
            cell.configure(with: offlineFavorites[indexPath.item])
            return cell
        }
    }

    func collectionView(_ cv: UICollectionView,
                       layout collectionViewLayout: UICollectionViewLayout,
                       sizeForItemAt indexPath: IndexPath) -> CGSize {
        return indexPath.section == Group.live.rawValue ? DS.CardSize.myLive : DS.CardSize.myOffline
    }

    func collectionView(_ cv: UICollectionView,
                       viewForSupplementaryElementOfKind kind: String,
                       at indexPath: IndexPath) -> UICollectionReusableView {
        let header = cv.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: "header",
            for: indexPath) as! MySectionHeader
        if indexPath.section == Group.live.rawValue {
            header.configure(text: "지금 방송 중", count: liveFavorites.count, isLive: true)
        } else {
            header.configure(text: "오프라인", count: offlineFavorites.count, isLive: false)
        }
        return header
    }

    func collectionView(_ cv: UICollectionView,
                       layout collectionViewLayout: UICollectionViewLayout,
                       referenceSizeForHeaderInSection section: Int) -> CGSize {
        let count = section == Group.live.rawValue ? liveFavorites.count : offlineFavorites.count
        return count == 0 ? .zero : CGSize(width: cv.bounds.width, height: DS.Layout.sectionHeaderHeight)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == Group.live.rawValue {
            playLive(liveFavorites[indexPath.item])
        } else {
            let bj = offlineFavorites[indexPath.item]
            ToastView.show(in: view, message: "\(bj.nick) 님은 오프라인입니다", duration: 2.0)
        }
    }

    private func playLive(_ f: FavoriteBJ, password: String? = nil) {
        showLoadingOverlay(message: "\(f.nick) 방송 연결 중...")
        SOOPAPIClient.shared.fetchStreamInfo(bjId: f.bjId, broadNo: "0", password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoadingOverlay()
                switch result {
                case .success(let info):
                    // v3: 최근 시청 기록
                    let bc = LiveBroadcast(
                        bjId: info.bjId, broadNo: info.broadNo, title: info.title,
                        bjNick: info.bjNick, thumbnailURL: nil,
                        viewerCount: f.liveViewerCount, category: ""
                    )
                    RecentWatchStore.shared.save(bc)
                    let p = PlayerViewController()
                    p.streamInfo = info
                    p.modalPresentationStyle = .fullScreen
                    self.present(p, animated: true)
                case .failure(let err):
                    if !self.promptPassword(for: err, bjNick: f.nick, retry: { pwd in
                        self.playLive(f, password: pwd)
                    }) {
                        self.showPlaybackError(err)
                    }
                }
            }
        }
    }
}

// MARK: - Section Header

final class MySectionHeader: UICollectionReusableView {

    private let dot = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DS.Colors.background

        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        label.font = DS.Typography.subsection
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.xl),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DS.Spacing.xl),
        ])
        dot.layer.cornerRadius = 6
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, count: Int, isLive: Bool) {
        let textColor = isLive ? DS.Colors.textPrimary : DS.Colors.textSecondary
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: textColor,
                .font: DS.Typography.subsection,
            ]
        )
        attributed.append(NSAttributedString(
            string: " (\(count))",
            attributes: [
                .foregroundColor: DS.Colors.textTertiary,
                .font: DS.Typography.cardTitle,
            ]
        ))
        label.attributedText = attributed
        dot.backgroundColor = isLive ? DS.Colors.live : DS.Colors.textTertiary
    }
}

// MARK: - 라이브 BJ 큰 카드 (380x280)

final class MyLiveBroadcastCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let liveBadge = UILabel()
    private let viewerLabel = UILabel()
    private let titleLabel = UILabel()
    private let bjLabel = UILabel()
    /// v3.2: 셀 재사용 시 fallback closure가 옛 BJ 이미지를 잘못 표시하지 않도록 식별
    private var currentBJID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.backgroundColor = DS.Colors.surface
        contentView.layer.cornerRadius = DS.Corner.card
        contentView.layer.masksToBounds = true
        layer.masksToBounds = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = DS.Colors.skeleton
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        liveBadge.text = "  ● LIVE  "
        liveBadge.textColor = DS.Colors.textPrimary
        liveBadge.backgroundColor = DS.Colors.live
        liveBadge.font = DS.Typography.badge
        liveBadge.textAlignment = .center
        liveBadge.layer.cornerRadius = DS.Corner.badge
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liveBadge)

        viewerLabel.textColor = DS.Colors.textPrimary
        viewerLabel.font = DS.Typography.badge
        viewerLabel.backgroundColor = DS.Colors.viewerBadgeBackground
        viewerLabel.textAlignment = .center
        viewerLabel.layer.cornerRadius = DS.Corner.badge
        viewerLabel.layer.masksToBounds = true
        viewerLabel.isHidden = true
        viewerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(viewerLabel)

        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.cardTitleLarge
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        bjLabel.textColor = DS.Colors.textSecondary
        bjLabel.font = DS.Typography.caption
        bjLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bjLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 213),

            liveBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            liveBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
            liveBadge.heightAnchor.constraint(equalToConstant: 26),

            viewerLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            viewerLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            viewerLabel.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.sm),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.sm),

            bjLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bjLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.sm),
            bjLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.sm),
        ])
    }

    // 포커스 장식(scale/보더/글로우)은 셀 인스턴스에 남으므로, 재사용 시 초기화하지 않으면
    // reloadData 이후 엉뚱한 카드가 "선택된 것처럼" 보인다.
    override func prepareForReuse() {
        super.prepareForReuse()
        FocusEffect.apply(to: self, focused: false)
        currentBJID = nil
        imageView.cancelImageLoad()
    }

    func configure(with f: FavoriteBJ) {
        // v3.2: 셀 재사용 시 fallback이 옛 BJ 이미지를 덮어쓰지 않도록 ID 기록
        currentBJID = f.bjId

        // v2 버그 수정: stationName이 비어 있거나 nick과 동일하면 BJ만 크게 표시
        let hasStation = !f.stationName.isEmpty && f.stationName != f.nick
        if hasStation {
            titleLabel.text = f.stationName
            titleLabel.isHidden = false
            bjLabel.text = f.nick
        } else {
            titleLabel.text = f.nick
            titleLabel.isHidden = false
            bjLabel.text = "라이브 방송 중"
        }
        if f.liveViewerCount > 0 {
            viewerLabel.text = "  \(f.liveViewerCount.koreanCount()) 시청  "
            viewerLabel.isHidden = false
        } else {
            viewerLabel.isHidden = true
        }
        // 방송 썸네일(480x270)이 있으면 그것을, 없거나 실패하면 고해상도 프로필로.
        let bjId = f.bjId
        let profileURL = SOOPAPIClient.profileImageURL(bjId: bjId)
        guard let thumbnailURL = f.thumbnailURL else {
            imageView.loadImage(from: profileURL)
            return
        }
        imageView.loadImage(from: thumbnailURL) { [weak self] success in
            guard let self = self, !success, self.currentBJID == bjId else { return }
            self.imageView.loadImage(from: profileURL)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.apply(to: self, focused: self.isFocused)
        }
    }
}

// MARK: - 오프라인 BJ 작은 카드 (240x280)

final class MyOfflineBJCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let darkOverlay = UIView()
    private let offlineLabel = UILabel()
    private let nickLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.backgroundColor = DS.Colors.surface
        contentView.layer.cornerRadius = DS.Corner.card
        contentView.layer.masksToBounds = true
        layer.masksToBounds = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = DS.Colors.skeleton
        imageView.alpha = 0.85
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        darkOverlay.backgroundColor = UIColor(white: 0, alpha: 0.35)
        darkOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(darkOverlay)

        offlineLabel.text = "  OFFLINE  "
        offlineLabel.textColor = DS.Colors.textOffline
        offlineLabel.font = DS.Typography.badge
        offlineLabel.backgroundColor = UIColor(white: 0, alpha: 0.65)
        offlineLabel.textAlignment = .center
        offlineLabel.layer.cornerRadius = DS.Corner.badge
        offlineLabel.layer.masksToBounds = true
        offlineLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(offlineLabel)

        nickLabel.textColor = DS.Colors.textOffline
        nickLabel.font = DS.Typography.subcaption
        nickLabel.numberOfLines = 1
        nickLabel.lineBreakMode = .byTruncatingTail
        nickLabel.textAlignment = .center
        nickLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nickLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 220),

            darkOverlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            darkOverlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            darkOverlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            darkOverlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            offlineLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            offlineLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
            offlineLabel.heightAnchor.constraint(equalToConstant: 24),

            nickLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            nickLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nickLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }

    // 오프라인 카드도 포커스 장식이 셀에 남으므로 재사용 시 초기화한다.
    override func prepareForReuse() {
        super.prepareForReuse()
        FocusEffect.applyOffline(to: self, focused: false)
        imageView.cancelImageLoad()
    }

    func configure(with f: FavoriteBJ) {
        nickLabel.text = f.nick
        imageView.loadImage(from: SOOPAPIClient.profileImageURL(bjId: f.bjId))
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.applyOffline(to: self, focused: self.isFocused)
        }
    }
}
