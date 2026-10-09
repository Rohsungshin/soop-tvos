import UIKit

// MARK: - 서버 기반 로그인 화면 (요청 중 / 대기 중 / 실패·만료·취소)
//
// LoginServerClient 로 로그인 서버(soop-login-svr)에 창을 요청하고, 사용자가 PC 에서 SOOP 로그인을
// 완료할 때까지 폴링한다. 쿠키 수신 시 SOOPAPIClient.applyServerCookies 로 주입·검증한 뒤 dismiss 하고
// onLoginSuccess(nickname) 콜백을 호출한다(성공 화면 없이 즉시 dismiss).
//
// 상태/문구/포커스 앵커는 chzzk-app ServerLoginViewController 와 같고, 스타일만 DS 토큰을 따른다.

final class ServerLoginViewController: UIViewController {

    /// 로그인 성공 시 검증된 닉네임을 전달한다 (dismiss 완료 후 호출).
    var onLoginSuccess: ((String?) -> Void)?

    private enum State {
        case requesting                       // 요청 중
        case pending(isBusy: Bool)            // 대기 중 (isBusy = 409 busy 재사용)
        case failed(ServerLoginFailReason)    // 실패/만료/취소
    }
    private var currentState: State = .requesting

    // MARK: UI
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let statusLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .large)
    private let primaryBtn = ServerLoginButton(title: "다시 요청", isPrimary: true)
    private let cancelBtn = ServerLoginButton(title: "취소", isPrimary: false)

    // MARK: 라이프사이클

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        setupUI()
        // 진입 즉시 서버에 로그인 요청 전송
        startRequest()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        switch currentState {
        case .requesting, .pending: return [cancelBtn]
        case .failed:               return [primaryBtn]
        }
    }

    // MARK: 레이아웃 (MyViewController 빈 상태와 같은 720pt 중앙 구성)

    private func setupUI() {
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        for (label, font, color) in [(titleLabel, DS.Typography.section, DS.Colors.textPrimary),
                                     (messageLabel, DS.Typography.body, DS.Colors.textSecondary),
                                     (statusLabel, DS.Typography.caption, DS.Colors.textTertiary)] {
            label.font = font
            label.textColor = color
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }

        activity.hidesWhenStopped = true
        activity.color = DS.Colors.primary
        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)

        primaryBtn.addTarget(self, action: #selector(primaryTapped), for: .primaryActionTriggered)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .primaryActionTriggered)
        // primaryBtn 을 숨기면 스택이 cancelBtn 만 가운데에 놓는다
        let buttons = UIStackView(arrangedSubviews: [primaryBtn, cancelBtn])
        buttons.axis = .horizontal
        buttons.spacing = DS.Spacing.md
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        let formWidth: CGFloat = 720
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 160),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: DS.Spacing.md),
            titleLabel.widthAnchor.constraint(equalToConstant: formWidth),

            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DS.Spacing.sm),
            messageLabel.widthAnchor.constraint(equalToConstant: formWidth),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: DS.Spacing.md),
            statusLabel.widthAnchor.constraint(equalToConstant: formWidth),

            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: DS.Spacing.md),

            buttons.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: activity.bottomAnchor, constant: DS.Spacing.lg),
        ])
    }

    // MARK: 상태 적용

    private func apply(_ state: State) {
        currentState = state
        switch state {
        case .requesting:
            show(symbol: "arrow.up.forward.app", tint: DS.Colors.textSecondary,
                 title: "로그인 요청 중", message: "서버에 로그인 창을 요청하는 중이에요.", status: "")
            activity.startAnimating()
            primaryBtn.isHidden = true
            // 요청 중에도 취소 허용 — 요청이 지연될 때 화면을 빠져나갈 수 있게. cancel() 은 requestId nil 을 안전 처리한다.
            cancelBtn.setTitle("취소")

        case .pending(let isBusy):
            show(symbol: "desktopcomputer", tint: DS.Colors.primary,
                 title: "PC에서 로그인해 주세요",
                 message: isBusy
                    ? "PC에서 이미 로그인 창이 열려 있어요.\n로그인을 완료하면 자동으로 연결돼요."
                    : "PC에 SOOP 로그인 창이 열렸어요.\n로그인을 완료하면 자동으로 연결돼요.",
                 status: "대기 중... (최대 5분)")
            activity.startAnimating()
            primaryBtn.isHidden = true
            cancelBtn.setTitle("취소")

        case .failed(let reason):
            let copy = Self.failCopy(for: reason)
            showFailure(symbol: copy.symbol, title: copy.title, message: copy.message, status: copy.status)
            return
        }
        cancelBtn.isEnabled = true
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func show(symbol: String, tint: UIColor, title: String, message: String, status: String) {
        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = tint
        titleLabel.text = title
        messageLabel.text = message
        statusLabel.text = status
        statusLabel.isAccessibilityElement = !status.isEmpty
    }

    /// 실패 화면 공통 — "다시 요청"(포커스) + "닫기".
    private func showFailure(symbol: String, title: String, message: String, status: String) {
        activity.stopAnimating()
        show(symbol: symbol, tint: DS.Colors.live, title: title, message: message, status: status)
        primaryBtn.isHidden = false
        primaryBtn.isEnabled = true
        cancelBtn.isEnabled = true
        cancelBtn.setTitle("닫기")
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    /// 실패 사유별 화면 문구.
    private static func failCopy(for reason: ServerLoginFailReason)
        -> (symbol: String, title: String, message: String, status: String) {
        switch reason {
        case .windowClosed:
            return ("xmark.circle", "로그인 창이 닫혔어요",
                    "PC에서 로그인 창이 닫혔어요.\n다시 요청하면 새 창이 열려요.", "")
        case .expired:
            return ("clock.badge.exclamationmark", "로그인 시간이 초과됐어요",
                    "5분 안에 로그인을 완료하지 못했어요.\n다시 요청해 주세요.", "")
        case .loginError:
            return ("exclamationmark.triangle", "로그인에 실패했어요",
                    "PC에서 SOOP 로그인 중 오류가 발생했어요.\n다시 요청해 주세요.", "")
        case .verificationFailed:
            return ("person.crop.circle.badge.exclamationmark", "로그인 확인에 실패했어요",
                    "로그인이 완료됐지만 인증을 확인할 수 없어요.\n잠시 후 다시 요청해 주세요.", "")
        case .cancelled:
            return ("minus.circle", "로그인 요청이 취소됐어요",
                    "로그인 요청이 취소됐어요.\n다시 요청하면 새 창이 열려요.", "")
        case .serverUnreachable:
            return ("wifi.exclamationmark", "서버에 연결할 수 없어요",
                    "로그인 서버에 연결할 수 없어요.\n서버가 실행 중인지 확인해 주세요.",
                    "LOGIN_SERVER_URL 설정과 PC의 soop-login-svr 실행 여부를 확인해 주세요.")
        case .unauthorized:
            return ("lock.trianglebadge.exclamationmark", "서버 인증에 실패했어요",
                    "로그인 서버 토큰이 일치하지 않아요.\n서버 설정을 확인해 주세요.",
                    "LOGIN_SERVER_TOKEN 과 서버의 AUTH_TOKEN 이 같아야 해요.")
        }
    }

    // MARK: 서버 로그인 흐름

    private func startRequest() {
        apply(.requesting)
        LoginServerClient.shared.requestLogin(
            clientId: UIDevice.current.name,
            onPending: { [weak self] isBusy in
                DispatchQueue.main.async { self?.apply(.pending(isBusy: isBusy)) }
            },
            onOutcome: { [weak self] outcome in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch outcome {
                    case .completed(let cookies, let nickname):
                        self.handleCompleted(cookies: cookies, nickname: nickname)
                    case .failed(let reason):
                        self.apply(.failed(reason))
                    }
                }
            }
        )
    }

    /// 쿠키 수신 완료 → 주입/검증. 성공 시 dismiss 후 콜백, 실패 시 저장 실패 화면.
    private func handleCompleted(cookies: String, nickname: String?) {
        SOOPAPIClient.shared.applyServerCookies(cookies) { [weak self] ok, verifiedNickname in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    let name = verifiedNickname ?? nickname
                    let callback = self.onLoginSuccess
                    self.dismiss(animated: true) { callback?(name) }
                } else {
                    self.currentState = .failed(.verificationFailed)
                    self.showFailure(symbol: "key.slash", title: "인증 정보를 저장할 수 없어요",
                                     message: "로그인은 됐지만 세션을 확인하지 못했어요.\n잠시 후 다시 시도해 주세요.",
                                     status: "")
                }
            }
        }
    }

    // MARK: 액션

    @objc private func primaryTapped() {
        startRequest()
    }

    @objc private func cancelTapped() {
        switch currentState {
        case .pending:
            // 대기 중 취소 → /login/cancel + 폴링 중단 → 취소 화면 (dismiss 안 함)
            LoginServerClient.shared.cancel()
            apply(.failed(.cancelled))
        case .requesting:
            LoginServerClient.shared.cancel()
            dismiss(animated: true)
        case .failed:
            dismiss(animated: true)
        }
    }
}

/// 서버 로그인 화면/MY 헤더 공용 버튼 — 포커스 시 FocusEffect.applyBorder (ErrorRetryButton 과 같은 스타일).
final class ServerLoginButton: UIButton {

    init(title: String, isPrimary: Bool) {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = isPrimary ? DS.Colors.primary : DS.Colors.surfaceElevated
        config.baseForegroundColor = DS.Colors.textPrimary
        config.contentInsets = DS.ButtonInsets.cta
        config.cornerStyle = .fixed
        config.background.cornerRadius = DS.Corner.button
        configuration = config
        layer.cornerRadius = DS.Corner.button
        setTitle(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ title: String) {
        configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: DS.Typography.cardTitle
        ]))
        accessibilityLabel = title
    }

    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { [weak self] in
            guard let self = self else { return }
            FocusEffect.applyBorder(to: self, focused: self.isFocused)
        }
    }
}
