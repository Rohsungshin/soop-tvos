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
    private var statusLabel: UILabel!
    private var loadingOverlay: LoadingOverlayView?

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
    }

    private func loadFavorites() {
        statusLabel.isHidden = false
        statusLabel.text = "즐겨찾기 불러오는 중..."
        hideEmptyState()
        SOOPAPIClient.shared.fetchFavorites { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
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
                    self.statusLabel.text = "로드 실패: \(err)\n\n로그인이 안 됐을 수 있습니다.\n(.env의 SOOP_ID/PASSWORD 확인)"
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

    private func playLive(_ f: FavoriteBJ) {
        showLoadingOverlay(message: "\(f.nick) 방송 연결 중...")
        SOOPAPIClient.shared.fetchStreamInfo(bjId: f.bjId, broadNo: "0") { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoadingOverlay()
                switch result {
                case .success(let info):
                    // v3: 최근 시청 기록
                    let bc = LiveBroadcast(
                        bjId: info.bjId, broadNo: info.broadNo, title: info.title,
                        bjNick: info.bjNick, thumbnailURL: nil,
                        viewerCount: f.totalViewCount, category: ""
                    )
                    RecentWatchStore.shared.save(bc)
                    let p = PlayerViewController()
                    p.streamInfo = info
                    p.modalPresentationStyle = .fullScreen
                    self.present(p, animated: true)
                case .failure:
                    ToastView.show(in: self.view, message: "재생할 수 없습니다", duration: 1.8)
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
        if f.totalViewCount > 0 {
            viewerLabel.text = "  \(f.totalViewCount.koreanCount()) 시청  "
            viewerLabel.isHidden = false
        } else {
            viewerLabel.isHidden = true
        }
        // 라이브 썸네일 시도 (BJID 패턴 — 실패하면 프로필로 fallback)
        let urlStr = "https://liveimg.sooplive.com/m/\(f.bjId)?bucket=\(Int(Date().timeIntervalSince1970) / 300)"
        let liveURL = URL(string: urlStr)
        let bjId = f.bjId
        imageView.loadImage(from: liveURL) { [weak self] success in
            guard let self = self, !success, self.currentBJID == bjId else { return }
            // 프로필 이미지로 fallback
            let prefix = String(bjId.prefix(2))
            let fallback = URL(string: "https://stimg.sooplive.com/LOGO/\(prefix)/\(bjId)/m/\(bjId).webp")
            self.imageView.loadImage(from: fallback)
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

    func configure(with f: FavoriteBJ) {
        nickLabel.text = f.nick
        let prefix = String(f.bjId.prefix(2))
        let url = URL(string: "https://stimg.sooplive.com/LOGO/\(prefix)/\(f.bjId)/m/\(f.bjId).webp")
        imageView.loadImage(from: url)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            // v2: 오프라인 카드는 회색 보더로 라이브 카드와 시각 차별화
            if self.isFocused {
                self.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
                self.layer.shadowColor = UIColor.black.cgColor
                self.layer.shadowOpacity = 0.5
                self.layer.shadowOffset = CGSize(width: 0, height: 12)
                self.layer.shadowRadius = 20
                self.contentView.layer.borderColor = DS.Colors.focusBorderOffline.cgColor
                self.contentView.layer.borderWidth = 3
            } else {
                self.transform = .identity
                self.layer.shadowOpacity = 0
                self.contentView.layer.borderWidth = 0
            }
        }
    }
}
