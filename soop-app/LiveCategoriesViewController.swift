import UIKit

// MARK: - 카테고리 그리드 (실시간 SOOP API 기반)
//
// `sch.sooplive.com/api.php?m=categoryList`로 모든 카테고리(500+개)를 가져와서
// 시청자수 기준 내림차순으로 표시. 사용자가 카테고리 선택 시 LiveListVC로 push하면서
// 해당 cate_no를 전달.
//
// UI v2 — DesignSystem 기반:
//  • 헤더: 이모지 제거, "LIVE" + 서브타이틀
//  • 새로고침 버튼 제거, Play/Pause 키 안내 푸터
//  • 카드 320x220, 16:8.5 이미지 + 정보 영역 분리
//  • 빨간 시청자 배지 → 흰 텍스트 + 노란 점

final class LiveCategoriesViewController: UIViewController {

    private var categories: [SOOPCategory] = []
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!
    private var headerView: SectionHeaderView!
    private var errorStateView: ErrorStateView?
    /// 새로고침 연타 시 오래된 응답이 최신 목록을 덮어쓰지 않도록
    private var loadEpoch = RequestEpoch()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = "LIVE"
        setupUI()
        loadCategories()
    }

    private func setupUI() {
        headerView = SectionHeaderView(title: "LIVE", subtitle: "실시간 인기 카테고리")
        view.addSubview(headerView)

        statusLabel = UILabel()
        statusLabel.text = "카테고리 불러오는 중..."
        statusLabel.textColor = DS.Colors.textSecondary
        statusLabel.font = DS.Typography.body
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 1080p TV — 카드 320x220, 5열 (320*5 + 24*4 + 64*2 = 1824, 화면 1920에 양옆 48pt 여유)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = DS.CardSize.category
        layout.minimumInteritemSpacing = DS.Spacing.md
        layout.minimumLineSpacing = 32
        layout.sectionInset = UIEdgeInsets(top: 32, left: DS.Spacing.xl, bottom: 72, right: DS.Spacing.xl)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = DS.Colors.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CategoryCell.self, forCellWithReuseIdentifier: "cell")
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
        // 로딩/실패 안내가 실제로 보이도록 앞으로 올린다.
        view.bringSubviewToFront(statusLabel)
    }

    private func loadCategories() {
        let token = loadEpoch.begin()
        hideErrorState()
        // 이미 목록이 떠 있으면 갱신 중 안내가 카드 위에 겹쳐 읽기 나빠진다 — 빈 화면일 때만 표시
        statusLabel.isHidden = !categories.isEmpty
        statusLabel.text = "카테고리 불러오는 중..."
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.loadEpoch.isCurrent(token) else { return }
                switch result {
                case .success(let cats):
                    self.categories = cats
                    self.statusLabel.isHidden = !cats.isEmpty
                    self.headerView.setSubtitle("실시간 인기 카테고리 · \(cats.count)개")
                    self.collectionView.reloadData()
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                case .failure(let err):
                    // 실패한 갱신이 옛 목록을 최신처럼 남기지 않도록 비운다.
                    // 비우면 포커스 가능한 셀이 사라지므로(=Play/Pause가 이 VC에 도달하지 못함)
                    // 포커스 가능한 "다시 시도" 버튼이 있는 오류 뷰를 반드시 함께 띄운다.
                    print("[LiveCategories] load failed: \(err)")
                    self.categories = []
                    self.collectionView.reloadData()
                    self.statusLabel.isHidden = true
                    self.headerView.setSubtitle("실시간 인기 카테고리")
                    self.showErrorState()
                }
            }
        }
    }

    // MARK: 오류 상태 (카테고리 로드 실패) — HOME/탐색/MY와 동일 패턴

    private func showErrorState() {
        hideErrorState()
        let errorView = ErrorStateView(
            icon: "wifi.exclamationmark",
            title: "카테고리를 불러오지 못했습니다",
            subtitle: "인터넷 연결을 확인하고 다시 시도해 주세요"
        )
        errorView.onRetry = { [weak self] in self?.loadCategories() }
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

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .playPause {
            loadCategories()
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

extension LiveCategoriesViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        categories.count
    }
    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! CategoryCell
        cell.configure(with: categories[indexPath.item])
        return cell
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let cat = categories[indexPath.item]
        let listVC = LiveListViewController()
        listVC.categoryCode = cat.code
        listVC.categoryTitle = cat.name
        navigationController?.pushViewController(listVC, animated: true)
    }
}

// MARK: - Cell

/// 카테고리 카드 — 상단 이미지 영역(320x170) + 하단 정보 영역(320x50)
final class CategoryCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let infoContainer = UIView()
    private let titleLabel = UILabel()
    private let viewerStack = UIStackView()
    private let viewerDot = UIView()
    private let viewerLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.layer.cornerRadius = DS.Corner.card
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = DS.Colors.surface

        // 그림자는 contentView 클리핑 밖이라 layer에 직접
        layer.masksToBounds = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = DS.Colors.skeleton
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        infoContainer.backgroundColor = DS.Colors.surface
        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoContainer)

        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.cardTitle
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(titleLabel)

        // 시청자수 스택 — ● 3.2만명 시청
        viewerDot.backgroundColor = DS.Colors.viewerDot
        viewerDot.layer.cornerRadius = 4
        viewerDot.translatesAutoresizingMaskIntoConstraints = false

        viewerLabel.textColor = DS.Colors.textPrimary
        viewerLabel.font = DS.Typography.badge
        viewerLabel.translatesAutoresizingMaskIntoConstraints = false

        viewerStack.axis = .horizontal
        viewerStack.spacing = 6
        viewerStack.alignment = .center
        viewerStack.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(viewerStack)
        viewerStack.addArrangedSubview(viewerDot)
        viewerStack.addArrangedSubview(viewerLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 170),

            infoContainer.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            infoContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            infoContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            infoContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: DS.Spacing.sm),
            titleLabel.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -DS.Spacing.sm),

            viewerStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            viewerStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: DS.Spacing.sm),

            viewerDot.widthAnchor.constraint(equalToConstant: 8),
            viewerDot.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    // 포커스 장식(scale/보더/글로우)은 셀 인스턴스에 남으므로, 재사용 시 초기화하지 않으면
    // reloadData 이후 엉뚱한 카드가 "선택된 것처럼" 보인다.
    override func prepareForReuse() {
        super.prepareForReuse()
        FocusEffect.apply(to: self, focused: false)
        imageView.cancelImageLoad()
    }

    func configure(with cat: SOOPCategory) {
        titleLabel.text = cat.name
        if cat.viewCount > 0 {
            viewerLabel.text = "\(cat.viewCount.koreanCount())명 시청 중"
            viewerStack.isHidden = false
        } else {
            viewerStack.isHidden = true
        }
        imageView.loadImage(from: cat.imageURL)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.apply(to: self, focused: self.isFocused)
        }
    }
}
