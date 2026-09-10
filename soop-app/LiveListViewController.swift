import UIKit
import AVKit

// MARK: - 실시간 라이브 방송 목록
//
// 카테고리 코드(예: "00040019" LoL)를 받아 `categoryContentsList` API로
// 해당 카테고리의 라이브 방송을 가져온다.
//
// UI v2 — DesignSystem 기반:
//  • 헤더: "← {카테고리명}" + "{n}개 방송 진행 중"
//  • 새로고침 버튼 제거
//  • 카드 400x282, 16:9 썸네일 + 정보 영역 분리
//  • 모달 alert 대신 인라인 로딩 오버레이

final class LiveListViewController: UIViewController {

    /// SOOP 카테고리 코드 (예: "00040019")
    var categoryCode: String = ""
    /// 헤더에 표시할 카테고리 이름
    var categoryTitle: String = ""

    private var broadcasts: [LiveBroadcast] = []
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!
    private var headerView: SectionHeaderView!
    private var loadingOverlay: LoadingOverlayView?
    private var skeletonView: LoadingSkeletonView?
    private var errorStateView: ErrorStateView?
    /// 새로고침 연타 시 오래된 응답이 최신 목록을 덮어쓰지 않도록
    private var loadEpoch = RequestEpoch()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = categoryTitle
        print("[LiveList] viewDidLoad cate=\(categoryCode) title=\(categoryTitle)")
        setupUI()
        loadBroadcasts()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        // 오류 상태에서는 그리드가 비어 포커스 대상이 없다 — "다시 시도" 버튼으로 보낸다
        if let errorView = errorStateView { return [errorView] }
        return [collectionView]
    }

    private func setupUI() {
        // "←" 단서를 포함한 카테고리 헤더 + 진행 중 방송 개수
        headerView = SectionHeaderView(
            title: "← \(categoryTitle)",
            subtitle: "방송 불러오는 중...",
            titleFont: DS.Typography.title
        )
        view.addSubview(headerView)

        statusLabel = UILabel()
        statusLabel.text = "방송 불러오는 중..."
        statusLabel.textColor = DS.Colors.textSecondary
        statusLabel.font = DS.Typography.body
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 카드 400x282, 4열 (400*4 + 24*3 + 64*2 = 1800, 화면 1920에 양옆 60pt 여유)
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.itemSize = DS.CardSize.broadcast
        layout.minimumInteritemSpacing = DS.Spacing.md
        layout.minimumLineSpacing = DS.Spacing.lg
        layout.sectionInset = UIEdgeInsets(top: 32, left: DS.Spacing.xl, bottom: 72, right: DS.Spacing.xl)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = DS.Colors.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LiveBroadcastCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Spacing.xl),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Spacing.xl),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),

            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // statusLabel은 collectionView보다 먼저 addSubview되어 불투명한 그리드 배경에 완전히 가려진다.
        // 로딩/실패/빈 목록 안내가 실제로 보이도록 앞으로 올린다.
        view.bringSubviewToFront(statusLabel)
    }

    private func loadBroadcasts() {
        let token = loadEpoch.begin()
        hideErrorState()
        // 이미 카드가 떠 있으면 갱신 중 안내가 그 위에 겹쳐 읽기 나빠진다 — 빈 화면일 때만 표시
        statusLabel.isHidden = !broadcasts.isEmpty
        statusLabel.text = "방송 불러오는 중..."
        headerView.setSubtitle("방송 불러오는 중...")
        SOOPAPIClient.shared.fetchBroadcasts(byCategory: categoryCode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.loadEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let list):
                    self.broadcasts = list
                    if list.isEmpty {
                        self.statusLabel.text = "현재 라이브 중인 방송이 없습니다.\nPlay/Pause로 새로고침"
                        self.headerView.setSubtitle("방송이 없습니다")
                    } else {
                        self.statusLabel.isHidden = true
                        self.headerView.setSubtitle("\(list.count)개 방송 진행 중")
                    }
                    self.collectionView.reloadData()
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                case .failure(let err):
                    // 실패한 갱신이 옛 방송 카드를 최신처럼 남기지 않도록 비운다.
                    // 비우면 포커스 가능한 셀이 사라져 Play/Pause가 이 VC에 도달하지 못하므로
                    // 포커스 가능한 "다시 시도" 버튼이 있는 오류 뷰를 반드시 함께 띄운다.
                    print("[LiveList] load failed: \(err)")
                    self.broadcasts = []
                    self.collectionView.reloadData()
                    self.statusLabel.isHidden = true
                    self.headerView.setSubtitle("로드 실패")
                    self.showErrorState()
                }
            }
        }
    }

    // MARK: 오류 상태 (방송 목록 로드 실패) — HOME/탐색/MY/LIVE와 동일 패턴

    private func showErrorState() {
        hideErrorState()
        let errorView = ErrorStateView(
            icon: "wifi.exclamationmark",
            title: "방송 목록을 불러오지 못했습니다",
            subtitle: "인터넷 연결을 확인하고 다시 시도해 주세요"
        )
        errorView.onRetry = { [weak self] in self?.loadBroadcasts() }
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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .playPause {
            loadBroadcasts()
            return
        }
        super.pressesBegan(presses, with: event)
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

extension LiveListViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        broadcasts.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LiveBroadcastCell
        cell.configure(with: broadcasts[indexPath.item])
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let bc = broadcasts[indexPath.item]
        presentPlayer(for: bc)
    }

    private func presentPlayer(for bc: LiveBroadcast, password: String? = nil) {
        showLoadingOverlay(message: "\(bc.bjNick) 방송 연결 중...")

        SOOPAPIClient.shared.fetchStreamInfo(bjId: bc.bjId, broadNo: bc.broadNo, password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoadingOverlay()
                switch result {
                case .success(let info):
                    // v3: 최근 시청 기록
                    RecentWatchStore.shared.save(bc)
                    let player = PlayerViewController()
                    player.streamInfo = info
                    player.posterThumbnailURL = bc.thumbnailURL
                    player.modalPresentationStyle = .fullScreen
                    self.present(player, animated: true)
                case .failure(let err):
                    // 비번방이면 비밀번호를 받아 재시도, 아니면 일반 에러 토스트.
                    if !self.promptPassword(for: err, bjNick: bc.bjNick, retry: { pwd in
                        self.presentPlayer(for: bc, password: pwd)
                    }) {
                        self.showPlaybackError(err)
                    }
                }
            }
        }
    }
}

// MARK: - Cell

/// 라이브 방송 카드 — 400x282
///   · 썸네일 400x225 (16:9), 좌상단 LIVE, 우상단 시청자수
///   · 정보 영역 57pt: 제목 22pt(2줄) + BJ 16pt
final class LiveBroadcastCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let bjLabel = UILabel()
    private let viewerLabel = UILabel()
    private let liveBadge = UILabel()

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

        // LIVE 배지 — 좌상단
        liveBadge.text = "  ● LIVE  "
        liveBadge.textColor = DS.Colors.textPrimary
        liveBadge.backgroundColor = DS.Colors.live
        liveBadge.font = DS.Typography.badge
        liveBadge.textAlignment = .center
        liveBadge.layer.cornerRadius = DS.Corner.badge
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liveBadge)

        // 시청자수 — 우상단
        viewerLabel.textColor = DS.Colors.textPrimary
        viewerLabel.font = DS.Typography.badge
        viewerLabel.backgroundColor = DS.Colors.viewerBadgeBackground
        viewerLabel.textAlignment = .center
        viewerLabel.layer.cornerRadius = DS.Corner.badge
        viewerLabel.layer.masksToBounds = true
        viewerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(viewerLabel)

        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.cardTitleLarge
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        // 제목은 잘려도 무방 — BJ 보호를 위해 vertical 압축 허용
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        bjLabel.textColor = DS.Colors.textSecondary
        bjLabel.font = DS.Typography.caption
        bjLabel.numberOfLines = 1
        bjLabel.lineBreakMode = .byTruncatingTail
        // BJ는 절대 잘리지 않도록 보호 — 디자인 우선순위: 콘텐츠 출처 식별
        bjLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        bjLabel.setContentHuggingPriority(.required, for: .vertical)

        // v4.3: 제목 + BJ를 UIStackView로 묶어 자연스러운 수직 정렬.
        // 1줄 제목이면 stack은 위쪽 정렬로 컴팩트하게, 2줄 제목이면 자동으로 BJ가 아래로 밀려나도 잘리지 않는다.
        let infoStack = UIStackView(arrangedSubviews: [titleLabel, bjLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 6
        infoStack.alignment = .leading
        infoStack.distribution = .fill
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoStack)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 225),

            liveBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            liveBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
            liveBadge.heightAnchor.constraint(equalToConstant: 26),

            viewerLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            viewerLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            viewerLabel.heightAnchor.constraint(equalToConstant: 26),
            viewerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            infoStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            infoStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.sm),
            infoStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.sm),
            infoStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    // 포커스 장식(scale/보더/글로우)은 셀 인스턴스에 남으므로, 재사용 시 초기화하지 않으면
    // reloadData 이후 엉뚱한 카드가 "선택된 것처럼" 보인다.
    override func prepareForReuse() {
        super.prepareForReuse()
        FocusEffect.apply(to: self, focused: false)
        imageView.cancelImageLoad()
    }

    func configure(with bc: LiveBroadcast) {
        titleLabel.text = bc.title
        bjLabel.text = bc.bjNick
        if bc.viewerCount > 0 {
            viewerLabel.text = "  \(bc.viewerCount.koreanCount()) 시청  "
            viewerLabel.isHidden = false
        } else {
            viewerLabel.isHidden = true
        }
        imageView.loadImage(from: bc.thumbnailURL)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.apply(to: self, focused: self.isFocused)
        }
    }
}
