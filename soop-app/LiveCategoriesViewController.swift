import UIKit

// MARK: - 카테고리 그리드 (실시간 SOOP API 기반)
//
// `sch.sooplive.com/api.php?m=categoryList`로 모든 카테고리(500+개)를 가져와서
// 시청자수 기준 내림차순으로 표시. 사용자가 카테고리 선택 시 LiveListVC로 push하면서
// 해당 cate_no를 전달.

final class LiveCategoriesViewController: UIViewController {

    private var categories: [SOOPCategory] = []
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "LIVE"
        setupUI()
        loadCategories()
    }

    private func setupUI() {
        let header = UILabel()
        header.text = "📺 LIVE"
        header.textColor = .white
        header.font = UIFont.systemFont(ofSize: 56, weight: .bold)
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        // 새로고침 버튼 (우측 상단)
        let refreshBtn = UIButton(type: .system)
        refreshBtn.setTitle("🔄 새로고침", for: .normal)
        refreshBtn.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        refreshBtn.setTitleColor(.white, for: .normal)
        refreshBtn.backgroundColor = UIColor(white: 0.15, alpha: 1)
        refreshBtn.layer.cornerRadius = 16
        refreshBtn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 28, bottom: 14, right: 28)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.addTarget(self, action: #selector(refreshTapped), for: .primaryActionTriggered)
        view.addSubview(refreshBtn)

        statusLabel = UILabel()
        statusLabel.text = "카테고리 불러오는 중..."
        statusLabel.textColor = .lightGray
        statusLabel.font = UIFont.systemFont(ofSize: 26)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 1080p TV 기준 — 화면 1920x1080, 행당 5장 ≈ 카드 320 + 간격
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 240)
        layout.minimumInteritemSpacing = 30
        layout.minimumLineSpacing = 40
        layout.sectionInset = UIEdgeInsets(top: 40, left: 80, bottom: 80, right: 80)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CategoryCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),

            refreshBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -80),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func refreshTapped() {
        loadCategories()
    }

    private func loadCategories() {
        statusLabel.isHidden = false
        statusLabel.text = "카테고리 불러오는 중..."
        SOOPAPIClient.shared.fetchCategories { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let cats):
                    self.categories = cats
                    self.statusLabel.isHidden = !cats.isEmpty
                    self.collectionView.reloadData()
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                case .failure(let err):
                    self.statusLabel.text = "카테고리 로드 실패\n\(err)\n\nPlay/Pause로 재시도"
                }
            }
        }
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

final class CategoryCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let viewerLabel = UILabel()
    private let overlay = UIView()
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = UIColor(white: 0.1, alpha: 1)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        overlay.backgroundColor = UIColor(white: 0, alpha: 0.55)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(overlay)

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        viewerLabel.textColor = .white
        viewerLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        viewerLabel.textAlignment = .center
        viewerLabel.backgroundColor = UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 0.9)
        viewerLabel.layer.cornerRadius = 4
        viewerLabel.layer.masksToBounds = true
        viewerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(viewerLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            overlay.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            viewerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            viewerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            viewerLabel.heightAnchor.constraint(equalToConstant: 26),
            viewerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    func configure(with cat: SOOPCategory) {
        titleLabel.text = cat.name
        viewerLabel.text = " ● \(formatViewers(cat.viewCount)) "
        viewerLabel.isHidden = cat.viewCount == 0
        imageView.image = nil
        imageTask?.cancel()
        if let url = cat.imageURL {
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.imageView.image = img }
            }
            imageTask?.resume()
        }
    }

    private func formatViewers(_ n: Int) -> String {
        if n >= 10000 { return String(format: "%.1f만", Double(n)/10000) }
        return "\(n)"
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            if self.isFocused {
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.contentView.layer.borderColor = UIColor.white.cgColor
                self.contentView.layer.borderWidth = 5
            } else {
                self.transform = .identity
                self.contentView.layer.borderWidth = 0
            }
        }
    }
}
