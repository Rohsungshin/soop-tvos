import UIKit
import AVKit

// MARK: - MY 탭 (즐겨찾기 BJ)
//
// `https://myapi.sooplive.co.kr/api/favorite` 응답을 그리드로 표시.
// 라이브 중인 BJ는 🔴 LIVE 뱃지 + 클릭 시 즉시 재생.
// 라이브 아닌 BJ는 회색 처리되고 클릭 시 알림.

final class MyViewController: UIViewController {

    private var favorites: [FavoriteBJ] = []
    private var collectionView: UICollectionView!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "MY"
        setupUI()
        loadFavorites()
        NotificationCenter.default.addObserver(self, selector: #selector(onLoginSucceeded),
                                               name: .soopLoginSucceeded, object: nil)
    }

    @objc private func onLoginSucceeded() { loadFavorites() }

    private func setupUI() {
        let header = UILabel()
        header.text = "⭐️ 즐겨찾기"
        header.textColor = .white
        header.font = UIFont.systemFont(ofSize: 56, weight: .bold)
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

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
        statusLabel.text = "즐겨찾기 불러오는 중..."
        statusLabel.textColor = .lightGray
        statusLabel.font = UIFont.systemFont(ofSize: 26)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // 1080p TV — 카드 320x280, 5열
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 280)
        layout.minimumInteritemSpacing = 30
        layout.minimumLineSpacing = 40
        layout.sectionInset = UIEdgeInsets(top: 40, left: 80, bottom: 60, right: 80)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FavoriteCell.self, forCellWithReuseIdentifier: "cell")
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

    @objc private func refreshTapped() { loadFavorites() }

    private func loadFavorites() {
        statusLabel.isHidden = false
        statusLabel.text = "즐겨찾기 불러오는 중..."
        SOOPAPIClient.shared.fetchFavorites { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let favs):
                    self.favorites = favs
                    if favs.isEmpty {
                        self.statusLabel.text = "즐겨찾기한 BJ가 없습니다.\nSOOP 웹/앱에서 즐겨찾기 추가 후\n다시 새로고침 해주세요."
                    } else {
                        self.statusLabel.isHidden = true
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
}

extension MyViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        favorites.count
    }
    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! FavoriteCell
        cell.configure(with: favorites[indexPath.item])
        return cell
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let f = favorites[indexPath.item]
        if !f.isLive {
            let a = UIAlertController(title: "방송 중이 아닙니다",
                message: "\(f.nick) 님은 현재 오프라인입니다.\n방송 시작 후 다시 시도해주세요.",
                preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "확인", style: .default))
            present(a, animated: true)
            return
        }
        // 라이브 중 → 즉시 재생
        let loading = UIAlertController(title: "방송 연결 중...", message: f.nick, preferredStyle: .alert)
        present(loading, animated: false)
        SOOPAPIClient.shared.fetchStreamInfo(bjId: f.bjId, broadNo: "0") { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: false) {
                    switch result {
                    case .success(let info):
                        let p = PlayerViewController()
                        p.streamInfo = info
                        p.modalPresentationStyle = .fullScreen
                        self?.present(p, animated: true)
                    case .failure(let err):
                        let a = UIAlertController(title: "재생 실패", message: "\(err)", preferredStyle: .alert)
                        a.addAction(UIAlertAction(title: "확인", style: .default))
                        self?.present(a, animated: true)
                    }
                }
            }
        }
    }
}

// MARK: - Cell

final class FavoriteCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let nickLabel = UILabel()
    private let bjIdLabel = UILabel()
    private let liveBadge = UILabel()
    private let offlineOverlay = UIView()
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        contentView.layer.cornerRadius = 14
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.18, alpha: 1)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        offlineOverlay.backgroundColor = UIColor(white: 0, alpha: 0.55)
        offlineOverlay.isHidden = true
        offlineOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(offlineOverlay)

        liveBadge.text = " ● LIVE "
        liveBadge.textColor = .white
        liveBadge.backgroundColor = UIColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1)
        liveBadge.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        liveBadge.textAlignment = .center
        liveBadge.layer.cornerRadius = 4
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liveBadge)

        nickLabel.textColor = .white
        nickLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        nickLabel.numberOfLines = 1
        nickLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nickLabel)

        bjIdLabel.textColor = .lightGray
        bjIdLabel.font = UIFont.systemFont(ofSize: 14)
        bjIdLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bjIdLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 200),

            offlineOverlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            offlineOverlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            offlineOverlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            offlineOverlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            liveBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            liveBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 12),
            liveBadge.heightAnchor.constraint(equalToConstant: 24),

            nickLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            nickLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            nickLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            bjIdLabel.topAnchor.constraint(equalTo: nickLabel.bottomAnchor, constant: 4),
            bjIdLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            bjIdLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
        ])
    }

    func configure(with f: FavoriteBJ) {
        nickLabel.text = f.nick
        bjIdLabel.text = "@\(f.bjId)"
        liveBadge.isHidden = !f.isLive
        offlineOverlay.isHidden = f.isLive
        nickLabel.alpha = f.isLive ? 1.0 : 0.7
        bjIdLabel.alpha = f.isLive ? 1.0 : 0.5
        imageView.image = nil
        imageTask?.cancel()
        // 즐겨찾기 BJ 프로필 이미지: stimg.sooplive.com 프로필 패턴
        let prefix = String(f.bjId.prefix(2))
        let urlStr = "https://stimg.sooplive.com/LOGO/\(prefix)/\(f.bjId)/m/\(f.bjId).webp"
        if let url = URL(string: urlStr) {
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.imageView.image = img }
            }
            imageTask?.resume()
        }
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
