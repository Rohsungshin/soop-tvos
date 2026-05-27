import UIKit
import AVKit

// MARK: - 실시간 라이브 방송 목록
//
// 카테고리 코드(예: "00040019" LoL)를 받아 `categoryContentsList` API로
// 해당 카테고리의 라이브 방송을 가져온다.

final class LiveListViewController: UIViewController {

    /// SOOP 카테고리 코드 (예: "00040019")
    var categoryCode: String = ""
    /// 헤더에 표시할 카테고리 이름
    var categoryTitle: String = ""

    private var broadcasts: [LiveBroadcast] = []
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
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
        let header = UILabel()
        header.text = "📺 \(categoryTitle)"
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
        statusLabel.text = "방송 불러오는 중..."
        statusLabel.textColor = .lightGray
        statusLabel.font = UIFont.systemFont(ofSize: 26)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 1080p TV — 카드 380x290, 행당 4장 (380*4 + 30*3 + 80*2 = 1770)
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.itemSize = CGSize(width: 380, height: 290)
        layout.minimumInteritemSpacing = 30
        layout.minimumLineSpacing = 40
        layout.sectionInset = UIEdgeInsets(top: 40, left: 80, bottom: 80, right: 80)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LiveBroadcastCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),

            refreshBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -80),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),

            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func refreshTapped() {
        loadBroadcasts()
    }

    private func loadBroadcasts() {
        statusLabel.isHidden = false
        statusLabel.text = "방송 불러오는 중..."
        SOOPAPIClient.shared.fetchBroadcasts(byCategory: categoryCode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let list):
                    self.broadcasts = list
                    if list.isEmpty {
                        self.statusLabel.text = "현재 라이브 중인 방송이 없습니다.\n\nPlay/Pause로 새로고침"
                    } else {
                        self.statusLabel.isHidden = true
                    }
                    self.collectionView.reloadData()
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                case .failure(let err):
                    self.statusLabel.text = "오류: \(err)\n\nPlay/Pause로 재시도"
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
        let loading = UIAlertController(title: "방송 연결 중...", message: bc.bjNick, preferredStyle: .alert)
        present(loading, animated: false)

        SOOPAPIClient.shared.fetchStreamInfo(bjId: bc.bjId, broadNo: bc.broadNo) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: false) {
                    switch result {
                    case .success(let info):
                        let player = PlayerViewController()
                        player.streamInfo = info
                        player.modalPresentationStyle = .fullScreen
                        self?.present(player, animated: true)
                    case .failure(let err):
                        let alert = UIAlertController(
                            title: "재생 실패",
                            message: "\(err)",
                            preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "확인", style: .default))
                        self?.present(alert, animated: true)
                    }
                }
            }
        }
    }
}

// MARK: - Cell

final class LiveBroadcastCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let bjLabel = UILabel()
    private let viewerLabel = UILabel()
    private let liveBadge = UILabel()
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        contentView.layer.cornerRadius = 14
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        liveBadge.text = " ● LIVE "
        liveBadge.textColor = .white
        liveBadge.backgroundColor = UIColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1)
        liveBadge.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        liveBadge.textAlignment = .center
        liveBadge.layer.cornerRadius = 4
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liveBadge)

        viewerLabel.textColor = .white
        viewerLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        viewerLabel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        viewerLabel.textAlignment = .center
        viewerLabel.layer.cornerRadius = 4
        viewerLabel.layer.masksToBounds = true
        viewerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(viewerLabel)

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        bjLabel.textColor = .lightGray
        bjLabel.font = UIFont.systemFont(ofSize: 14)
        bjLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bjLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 213),

            liveBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            liveBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
            liveBadge.heightAnchor.constraint(equalToConstant: 24),

            viewerLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            viewerLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            viewerLabel.heightAnchor.constraint(equalToConstant: 24),
            viewerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            bjLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bjLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        ])
    }

    func configure(with bc: LiveBroadcast) {
        titleLabel.text = bc.title
        bjLabel.text = bc.bjNick
        viewerLabel.text = bc.viewerCount > 0 ? " \(formatViewers(bc.viewerCount)) " : ""
        viewerLabel.isHidden = bc.viewerCount == 0
        imageView.image = nil
        imageTask?.cancel()
        if let url = bc.thumbnailURL {
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
                self.contentView.layer.borderWidth = 4
            } else {
                self.transform = .identity
                self.contentView.layer.borderWidth = 0
            }
        }
    }
}
