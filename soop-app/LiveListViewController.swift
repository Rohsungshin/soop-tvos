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
    }

    private func loadBroadcasts() {
        statusLabel.isHidden = false
        statusLabel.text = "방송 불러오는 중..."
        headerView.setSubtitle("방송 불러오는 중...")
        SOOPAPIClient.shared.fetchBroadcasts(byCategory: categoryCode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
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
                    self.statusLabel.text = "오류: \(err)\n\nPlay/Pause로 재시도"
                    self.headerView.setSubtitle("로드 실패")
                }
            }
        }
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

    private func presentPlayer(for bc: LiveBroadcast) {
        showLoadingOverlay(message: "\(bc.bjNick) 방송 연결 중...")

        SOOPAPIClient.shared.fetchStreamInfo(bjId: bc.bjId, broadNo: bc.broadNo) { [weak self] result in
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
                case .failure:
                    ToastView.show(in: self.view, message: "재생할 수 없습니다", duration: 1.8)
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
