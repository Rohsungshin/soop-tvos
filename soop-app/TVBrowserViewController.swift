import UIKit
import AuthenticationServices

// MARK: - tvOS 브라우저 (ASWebAuthenticationSession)

class TVBrowserViewController: UIViewController {

    private var loginManager: LoginManager!
    private var statusLabel: UILabel!
    private var urlLabel: UILabel!
    private var currentURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCredentialsAndStart()
    }

    private func setupUI() {
        view.backgroundColor = .black

        // SOOP 로고/타이틀
        let titleLabel = UILabel()
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 36, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.text = "📺 SOOP Live"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // 상태 라벨
        statusLabel = UILabel()
        statusLabel.textColor = .lightGray
        statusLabel.font = UIFont.systemFont(ofSize: 22, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Select 버튼으로 접속"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // URL 표시
        urlLabel = UILabel()
        urlLabel.textColor = .white.withAlphaComponent(0.4)
        urlLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        urlLabel.textAlignment = .center
        urlLabel.numberOfLines = 1
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlLabel)

        // 하단 안내
        let hintLabel = UILabel()
        hintLabel.textColor = .white.withAlphaComponent(0.5)
        hintLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        hintLabel.textAlignment = .center
        hintLabel.text = "Select: 접속  |  Menu: 홈  |  Play/Pause: 새로고침"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 120),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),

            urlLabel.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -20),
            urlLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            urlLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),

            hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
        ])
    }

    private func loadCredentialsAndStart() {
        guard LoginManager.loadCredentials() != nil else {
            statusLabel.text = "⚠️ .env 파일을 확인해주세요"
            return
        }
        loginManager = LoginManager(id: "", password: "", webViewProvider: nil)
        statusLabel.text = "Select 버튼으로 접속"
    }

    /// ASWebAuthenticationSession으로 SOOP 열기
    private func openSoop(_ url: URL) {
        currentURL = url
        urlLabel.text = url.absoluteString.replacingOccurrences(of: "https://", with: "")
        statusLabel.text = "로딩 중..."

        let session = ASWebAuthenticationSession(
            url: url,
            callback: .customScheme("soop"),
            completionHandler: { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == 1 {
                        self?.statusLabel.text = "취소됨\n\nSelect: 다시 접속"
                    } else {
                        self?.statusLabel.text = "오류 발생\n\nSelect: 다시 시도"
                    }
                } else if let callbackURL = callbackURL {
                    self?.urlLabel.text = callbackURL.absoluteString
                    self?.statusLabel.text = "✅ 인증 완료"
                } else {
                    self?.statusLabel.text = "SOOP Live\n\nSelect: 다시 접속"
                }
            }
        })

        session.start()
    }

    // MARK: - 리모컨

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .select:
                let url = URL(string: "https://www.sooplive.com/")!
                openSoop(url)
            case .menu:
                statusLabel.text = "📺 SOOP Live\n\nSelect: 접속"
                urlLabel.text = ""
            case .playPause:
                if let url = currentURL {
                    openSoop(url)
                    statusLabel.text = "🔄 새로고침..."
                }
            default:
                super.pressesBegan(presses, with: event)
            }
        }
    }
}
