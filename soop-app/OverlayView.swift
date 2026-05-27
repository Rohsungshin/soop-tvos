import UIKit

protocol OverlayViewDelegate: AnyObject {
    func overlayDidRequestGoBack()
    func overlayDidRequestGoForward()
    func overlayDidRequestReload()
    func overlayDidRequestHome()
    func overlayDidRequestLogin()
}

/// tvOS 리모컨용 오버레이 UI
class OverlayView: UIView {

    weak var delegate: OverlayViewDelegate?

    private let urlLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.alpha = 0.0
        return label
    }()

    private let controlHintLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white.withAlphaComponent(0.6)
        label.font = UIFont.systemFont(ofSize: 13, weight: .light)
        label.textAlignment = .center
        label.text = "◀ 뒤로  ▶ 앞으로  ⏯ 새로고침  Menu: 홈"
        label.numberOfLines = 1
        return label
    }()

    private var hideTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(urlLabel)
        addSubview(statusLabel)
        addSubview(controlHintLabel)

        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        controlHintLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            urlLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            urlLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            urlLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),

            controlHintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            controlHintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            controlHintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])

        isUserInteractionEnabled = true
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        addGestureRecognizer(tap)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        swipeLeft.direction = .left
        addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
        swipeRight.direction = .right
        addGestureRecognizer(swipeRight)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        addGestureRecognizer(longPress)
    }

    func updateURL(_ urlString: String) {
        let display = urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "?").first ?? urlString
        urlLabel.text = display
    }

    func showStatus(_ text: String, duration: TimeInterval = 1.5) {
        statusLabel.text = text
        UIView.animate(withDuration: 0.3) { self.statusLabel.alpha = 1.0 }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.statusLabel.alpha = 0.0 }
        }
    }

    @objc private func handleTap(_: UITapGestureRecognizer) {
        showStatus("◀ 뒤로  ▶ 앞으로  ⏯ 새로고침")
    }

    @objc private func handleSwipeLeft() {
        showStatus("◀ 뒤로 가기")
        delegate?.overlayDidRequestGoBack()
    }

    @objc private func handleSwipeRight() {
        showStatus("▶ 앞으로 가기")
        delegate?.overlayDidRequestGoForward()
    }

    @objc private func handleLongPress() {
        showStatus("🏠 홈으로 이동")
        delegate?.overlayDidRequestHome()
    }
}
