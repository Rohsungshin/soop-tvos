import UIKit
import AVKit
import AVFoundation

// MARK: - SOOP HLS 재생기
//
// AVPlayerViewController를 풀스크린으로 표시.
// streamInfo.viewURL 을 그대로 AVPlayer 에 넘긴다.
// SOOP의 TS URL은 ?data= 인증 토큰이 URL에 포함돼 있어 별도 헤더 없이도 재생 가능 (이론상).
// Referer 헤더가 필요하면 AVURLAsset 옵션으로 추가한다.
//
// UI v2:
//   • Pre-roll: 블러 썸네일 + 방송 제목 + BJ + 스피너
//   • 해상도 라벨 자동 페이드 (4초 후 사라짐)
//   • FALLBACK → "안정 모드" 한글
//   • 실패 시 에러 카드 (다시 시도/돌아가기)

final class PlayerViewController: UIViewController {

    var streamInfo: StreamInfo?
    /// 호출처에서 넘기는 미리보기 썸네일 (pre-roll 화면용)
    var posterThumbnailURL: URL?

    private var avVC: AVPlayerViewController!

    /// 재시도 횟수 제한 — 무한 루프 방지 (v2)
    private var retryCount = 0
    private let maxRetries = 3

    // Pre-roll 컨테이너
    private var preRollContainer: UIView!
    private var posterImageView: UIImageView!
    private var preRollTitleLabel: UILabel!
    private var preRollBJLabel: UILabel!
    private var preRollSpinner: UIActivityIndicatorView!
    private var preRollStatusLabel: UILabel!

    // 에러 카드 컨테이너
    private var errorContainer: UIView?

    private var resolutionLabel: UILabel!
    private var observer: NSKeyValueObservation?
    private var presentationObserver: NSKeyValueObservation?
    private var hideResolutionTimer: Timer?

    // v3: 상단 메타 오버레이 (재생 중)
    private var topMetaOverlay: UIView!
    private var topMetaTitleLabel: UILabel!
    private var topMetaBJLabel: UILabel!
    private var hideMetaTimer: Timer?

    // v5.1: 음량 제어
    //
    // Siri Remote의 물리 음량 버튼은 tvOS 시스템이 소비해 앱에 전달되지 않는다.
    //   • UIPress.PressType에 volume 케이스가 존재하지 않음 (AppleTVOS SDK 확인)
    //   • GameController / AVKit도 Siri Remote 음량 입력을 노출하지 않음
    //   • AVAudioSession.outputVolume은 tvOS에서 readonly (setter 없음)
    // 그 버튼은 HDMI-CEC / IR로 TV·리시버 볼륨을 직접 제어하며,
    // 동작하지 않으면 [설정 > 리모컨과 기기 > 음량 조절]에서 고쳐야 한다 (Apple 지원 108769).
    //
    // 따라서 앱이 제공할 수 있는 음량 기능은 다음 3가지다.
    //   (1) AVPlayer.volume 기반 인앱 음량 — 트랜스포트 바 컨트롤로 리모컨 조작
    //   (2) AVAudioSession.outputVolume KVO — AirPlay/HomePod/BT 출력일 때
    //       물리 음량 버튼이 바꾼 시스템 음량을 HUD로 표시
    //   (3) 외부 HID 키보드/리모컨의 음량 키 처리 (press.key.keyCode)
    private static let volumeStep: Float = 0.1
    private static let volumeSegmentCount = 10
    private static let volumeDefaultsKey = "soop.player.volume"
    // HUD 전용 치수 — DS 토큰 없음
    private static let volumeSegmentSize = CGSize(width: 22, height: 18)
    private static let volumeSegmentGap: CGFloat = 4
    private static let volumeSegmentRadius: CGFloat = 3
    private static let volumeValueWidth: CGFloat = 110
    private static let volumeHintWidth: CGFloat = 560
    private static let volumeIconWidth: CGFloat = 44
    private static let volumeIconPointSize: CGFloat = 30
    private static let volumeColumnSpacing: CGFloat = 6
    private static let volumeHUDDwell: TimeInterval = 2.5
    private static let volumeHintDwell: TimeInterval = 6.0

    private enum VolumeSource { case app, system }

    private var volumeHUD: UIView!
    private var volumeIconView: UIImageView!
    private var volumeSegments: [UIView] = []
    private var volumeValueLabel: UILabel!
    private var volumeSourceLabel: UILabel!
    private var volumeHintLabel: UILabel!
    private var hideVolumeHUDTimer: Timer?
    private var systemVolumeObservation: NSKeyValueObservation?
    private var didShowVolumeHint = false
    /// 다시 시도로 AVPlayer를 새로 만들 때 음소거 상태를 이어 준다 (세션 범위, 저장하지 않음)
    private var pendingMuted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background

        configureAudioSession()
        setupPreRoll()
        setupResolutionLabel()
        setupTopMetaOverlay()
        setupVolumeHUD()
        observeSystemVolume()
        startPlayback()
    }

    // v3: 재생 중 상단 메타 오버레이
    private func setupTopMetaOverlay() {
        topMetaOverlay = UIView()
        topMetaOverlay.backgroundColor = DS.Colors.viewerBadgeBackground
        topMetaOverlay.layer.cornerRadius = DS.Corner.button
        topMetaOverlay.translatesAutoresizingMaskIntoConstraints = false
        topMetaOverlay.alpha = 0
        view.addSubview(topMetaOverlay)

        topMetaTitleLabel = UILabel()
        topMetaTitleLabel.text = streamInfo?.title ?? ""
        topMetaTitleLabel.textColor = DS.Colors.textPrimary
        topMetaTitleLabel.font = DS.Typography.cardTitle
        topMetaTitleLabel.numberOfLines = 1
        topMetaTitleLabel.lineBreakMode = .byTruncatingTail
        topMetaTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        topMetaOverlay.addSubview(topMetaTitleLabel)

        topMetaBJLabel = UILabel()
        topMetaBJLabel.text = streamInfo?.bjNick ?? ""
        topMetaBJLabel.textColor = DS.Colors.textSecondary
        topMetaBJLabel.font = DS.Typography.caption
        topMetaBJLabel.translatesAutoresizingMaskIntoConstraints = false
        topMetaOverlay.addSubview(topMetaBJLabel)

        NSLayoutConstraint.activate([
            topMetaOverlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Spacing.lg),
            topMetaOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Spacing.lg),
            topMetaOverlay.widthAnchor.constraint(lessThanOrEqualToConstant: 800),

            topMetaTitleLabel.topAnchor.constraint(equalTo: topMetaOverlay.topAnchor, constant: DS.Spacing.sm),
            topMetaTitleLabel.leadingAnchor.constraint(equalTo: topMetaOverlay.leadingAnchor, constant: DS.Spacing.md),
            topMetaTitleLabel.trailingAnchor.constraint(equalTo: topMetaOverlay.trailingAnchor, constant: -DS.Spacing.md),

            topMetaBJLabel.topAnchor.constraint(equalTo: topMetaTitleLabel.bottomAnchor, constant: 4),
            topMetaBJLabel.leadingAnchor.constraint(equalTo: topMetaOverlay.leadingAnchor, constant: DS.Spacing.md),
            topMetaBJLabel.trailingAnchor.constraint(equalTo: topMetaOverlay.trailingAnchor, constant: -DS.Spacing.md),
            topMetaBJLabel.bottomAnchor.constraint(equalTo: topMetaOverlay.bottomAnchor, constant: -DS.Spacing.sm),
        ])
    }

    private func showTopMetaTemporarily() {
        hideMetaTimer?.invalidate()
        UIView.animate(withDuration: 0.2) { self.topMetaOverlay.alpha = 1 }
        hideMetaTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.6) { self?.topMetaOverlay.alpha = 0 }
        }
    }

    // MARK: - Pre-roll UI

    private func setupPreRoll() {
        preRollContainer = UIView()
        preRollContainer.backgroundColor = DS.Colors.background
        preRollContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preRollContainer)

        posterImageView = UIImageView()
        posterImageView.contentMode = .scaleAspectFill
        posterImageView.clipsToBounds = true
        posterImageView.backgroundColor = DS.Colors.skeleton
        posterImageView.layer.cornerRadius = DS.Corner.card
        posterImageView.layer.masksToBounds = true
        posterImageView.translatesAutoresizingMaskIntoConstraints = false
        preRollContainer.addSubview(posterImageView)

        // 블러 효과 — tvOS에서 사용 가능한 스타일만 한정
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        posterImageView.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: posterImageView.topAnchor),
            blur.leadingAnchor.constraint(equalTo: posterImageView.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: posterImageView.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: posterImageView.bottomAnchor),
        ])

        preRollTitleLabel = UILabel()
        preRollTitleLabel.text = streamInfo?.title ?? ""
        preRollTitleLabel.textColor = DS.Colors.textPrimary
        preRollTitleLabel.font = DS.Typography.subsection
        preRollTitleLabel.textAlignment = .center
        preRollTitleLabel.numberOfLines = 2
        preRollTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        preRollContainer.addSubview(preRollTitleLabel)

        preRollBJLabel = UILabel()
        preRollBJLabel.text = streamInfo?.bjNick ?? ""
        preRollBJLabel.textColor = DS.Colors.textSecondary
        preRollBJLabel.font = DS.Typography.cardTitle
        preRollBJLabel.textAlignment = .center
        preRollBJLabel.translatesAutoresizingMaskIntoConstraints = false
        preRollContainer.addSubview(preRollBJLabel)

        preRollSpinner = UIActivityIndicatorView(style: .large)
        preRollSpinner.color = DS.Colors.textPrimary
        preRollSpinner.startAnimating()
        preRollSpinner.translatesAutoresizingMaskIntoConstraints = false
        preRollContainer.addSubview(preRollSpinner)

        preRollStatusLabel = UILabel()
        preRollStatusLabel.text = "스트림 연결 중..."
        preRollStatusLabel.textColor = DS.Colors.textSecondary
        preRollStatusLabel.font = DS.Typography.body
        preRollStatusLabel.textAlignment = .center
        preRollStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        preRollContainer.addSubview(preRollStatusLabel)

        NSLayoutConstraint.activate([
            preRollContainer.topAnchor.constraint(equalTo: view.topAnchor),
            preRollContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preRollContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            preRollContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            posterImageView.centerXAnchor.constraint(equalTo: preRollContainer.centerXAnchor),
            posterImageView.centerYAnchor.constraint(equalTo: preRollContainer.centerYAnchor, constant: -100),
            posterImageView.widthAnchor.constraint(equalToConstant: 580),
            posterImageView.heightAnchor.constraint(equalToConstant: 326),

            preRollTitleLabel.topAnchor.constraint(equalTo: posterImageView.bottomAnchor, constant: 32),
            preRollTitleLabel.leadingAnchor.constraint(equalTo: preRollContainer.leadingAnchor, constant: 80),
            preRollTitleLabel.trailingAnchor.constraint(equalTo: preRollContainer.trailingAnchor, constant: -80),

            preRollBJLabel.topAnchor.constraint(equalTo: preRollTitleLabel.bottomAnchor, constant: 8),
            preRollBJLabel.centerXAnchor.constraint(equalTo: preRollContainer.centerXAnchor),

            preRollSpinner.topAnchor.constraint(equalTo: preRollBJLabel.bottomAnchor, constant: 32),
            preRollSpinner.centerXAnchor.constraint(equalTo: preRollContainer.centerXAnchor),

            preRollStatusLabel.topAnchor.constraint(equalTo: preRollSpinner.bottomAnchor, constant: 12),
            preRollStatusLabel.centerXAnchor.constraint(equalTo: preRollContainer.centerXAnchor),
        ])

        loadPoster()
    }

    private func loadPoster() {
        posterImageView.loadImage(from: posterThumbnailURL)
    }

    private func hidePreRoll() {
        UIView.animate(withDuration: 0.3) {
            self.preRollContainer.alpha = 0
        } completion: { _ in
            self.preRollContainer.isHidden = true
        }
    }

    // MARK: - 해상도 라벨

    private func setupResolutionLabel() {
        resolutionLabel = UILabel()
        resolutionLabel.text = "—"
        resolutionLabel.textColor = DS.Colors.textPrimary
        resolutionLabel.font = DS.Typography.cardTitle
        resolutionLabel.backgroundColor = DS.Colors.viewerBadgeBackground
        resolutionLabel.textAlignment = .center
        resolutionLabel.layer.cornerRadius = DS.Corner.badge
        resolutionLabel.layer.masksToBounds = true
        resolutionLabel.numberOfLines = 2
        resolutionLabel.alpha = 0
        resolutionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resolutionLabel)
        NSLayoutConstraint.activate([
            resolutionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            resolutionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -50),
            resolutionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            resolutionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    private func showResolutionLabelTemporarily() {
        hideResolutionTimer?.invalidate()
        UIView.animate(withDuration: 0.2) {
            self.resolutionLabel.alpha = 1
        }
        // 3초 후 페이드 아웃
        hideResolutionTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.6) {
                self?.resolutionLabel.alpha = 0
            }
        }
    }

    // MARK: - 오디오 세션

    /// tvOS 프로세스 기본 카테고리는 soloAmbient다. 동영상 재생 앱은 .playback + .moviePlayback이 맞다.
    /// 세션을 명시적으로 활성화해야 AVPlayer 오디오가 정상 출력 경로(TV·리시버·AirPlay)로 나간다.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            print("[Player] audioSession .playback/.moviePlayback active — outputVolume=\(session.outputVolume)")
        } catch {
            print("[Player] audioSession setup FAILED: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[Player] audioSession deactivate FAILED: \(error)")
        }
    }

    /// 시스템 출력 음량은 tvOS에서 읽기 전용이지만 KVO는 가능하다.
    /// AirPlay·HomePod·블루투스 출력일 때는 물리 음량 버튼이 이 값을 바꾸므로 HUD로 보여 준다
    /// (HDMI-CEC / IR 출력이면 값이 변하지 않는다 — 상단 주석 참고).
    private func observeSystemVolume() {
        systemVolumeObservation = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
                DispatchQueue.main.async {
                    guard let self = self,
                          self.isViewLoaded, self.view.window != nil,
                          (self.avVC?.view.alpha ?? 0) > 0 else { return }
                    print("[Player] system outputVolume → \(session.outputVolume)")
                    self.showVolumeHUD(source: .system)
                }
            }
    }

    // MARK: - 인앱 음량

    private static func savedVolume() -> Float {
        guard UserDefaults.standard.object(forKey: volumeDefaultsKey) != nil else { return 1.0 }
        return min(max(UserDefaults.standard.float(forKey: volumeDefaultsKey), 0), 1)
    }

    /// 트랜스포트 바에 음량 컨트롤을 붙인다 (AVPlayerViewController.transportBarCustomMenuItems, tvOS 15+).
    /// 재생 중 리모컨을 아래로 스와이프 → 트랜스포트 바 → 좌우 이동으로 선택한다.
    /// 항목 제목은 고정이다 — 상태에 따라 배열을 다시 할당하면 사용자가 누르고 있는
    /// 항목의 포커스가 초기화될 수 있어, 음소거 상태는 HUD로만 보여 준다.
    private func makeTransportBarItems() -> [UIMenuElement] {
        let down = UIAction(title: "음량 낮추기",
                            image: UIImage(systemName: "speaker.wave.1.fill")) { [weak self] _ in
            self?.stepVolume(by: -Self.volumeStep)
        }
        let up = UIAction(title: "음량 높이기",
                          image: UIImage(systemName: "speaker.wave.3.fill")) { [weak self] _ in
            self?.stepVolume(by: Self.volumeStep)
        }
        let mute = UIAction(title: "음소거 전환",
                            image: UIImage(systemName: "speaker.slash.fill")) { [weak self] _ in
            self?.toggleMute()
        }
        return [down, up, mute]
    }

    private func stepVolume(by delta: Float) {
        guard let player = avVC?.player else { return }
        // 음소거 중 어느 방향이든 음량을 조작하면 음소거를 푼다 (숨은 상태로 값만 바뀌는 일 방지)
        player.isMuted = false
        player.volume = min(max(player.volume + delta, 0), 1)
        UserDefaults.standard.set(player.volume, forKey: Self.volumeDefaultsKey)
        print("[Player] app volume → \(player.volume)")
        showVolumeHUD(source: .app)
    }

    private func toggleMute() {
        guard let player = avVC?.player else { return }
        player.isMuted.toggle()
        print("[Player] muted → \(player.isMuted)")
        showVolumeHUD(source: .app)
    }

    // MARK: - 음량 HUD

    private func setupVolumeHUD() {
        volumeHUD = UIView()
        volumeHUD.backgroundColor = DS.Colors.viewerBadgeBackground
        volumeHUD.layer.cornerRadius = DS.Corner.button
        volumeHUD.alpha = 0
        volumeHUD.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(volumeHUD)

        // 스택 뷰의 arrangedSubview는 translatesAutoresizingMaskIntoConstraints를 스택이 직접 관리한다
        volumeIconView = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
        volumeIconView.tintColor = DS.Colors.textPrimary
        volumeIconView.contentMode = .center
        // 심볼 3종(speaker / wave.2 / slash)의 폭이 달라도 베이스라인·캡 높이가 같도록 고정 포인트 크기
        volumeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Self.volumeIconPointSize, weight: .semibold)
        volumeIconView.widthAnchor.constraint(equalToConstant: Self.volumeIconWidth).isActive = true

        let segmentBar = UIStackView()
        segmentBar.axis = .horizontal
        segmentBar.spacing = Self.volumeSegmentGap
        volumeSegments = (0..<Self.volumeSegmentCount).map { _ in
            let seg = UIView()
            seg.backgroundColor = DS.Colors.volumeSegmentEmpty
            seg.layer.cornerRadius = Self.volumeSegmentRadius
            seg.widthAnchor.constraint(equalToConstant: Self.volumeSegmentSize.width).isActive = true
            seg.heightAnchor.constraint(equalToConstant: Self.volumeSegmentSize.height).isActive = true
            segmentBar.addArrangedSubview(seg)
            return seg
        }

        volumeValueLabel = UILabel()
        volumeValueLabel.textColor = DS.Colors.textPrimary
        volumeValueLabel.font = DS.Typography.cardTitle
        volumeValueLabel.textAlignment = .right
        volumeValueLabel.widthAnchor.constraint(equalToConstant: Self.volumeValueWidth).isActive = true

        let row = UIStackView(arrangedSubviews: [volumeIconView, segmentBar, volumeValueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DS.Spacing.sm

        volumeSourceLabel = UILabel()
        volumeSourceLabel.textColor = DS.Colors.textSecondary
        volumeSourceLabel.font = DS.Typography.caption

        // 메뉴 명칭은 Apple 한국어 지원 문서(108769) 표기를 따른다
        volumeHintLabel = UILabel()
        volumeHintLabel.text = "리모컨의 음량 버튼은 TV·리시버 음량을 조절합니다\n반응이 없으면 설정 > 리모컨과 기기 > 음량 조절에서 바꿔 보세요"
        volumeHintLabel.textColor = DS.Colors.textSecondary
        volumeHintLabel.font = DS.Typography.caption
        volumeHintLabel.numberOfLines = 2
        volumeHintLabel.textAlignment = .center
        volumeHintLabel.isHidden = true
        volumeHintLabel.widthAnchor.constraint(equalToConstant: Self.volumeHintWidth).isActive = true

        // 힌트가 보일 때/숨을 때 필의 폭이 달라져도 게이지 행이 항상 가운데 오도록 center 정렬
        let column = UIStackView(arrangedSubviews: [row, volumeSourceLabel, volumeHintLabel])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = Self.volumeColumnSpacing
        column.translatesAutoresizingMaskIntoConstraints = false
        volumeHUD.addSubview(column)

        NSLayoutConstraint.activate([
            // 상단 메타 오버레이(좌측, 최대 폭 800)·해상도 라벨(우측)과 같은 밴드에 두면 겹치므로
            // 메타 오버레이 바로 아래 밴드에 건다.
            volumeHUD.topAnchor.constraint(equalTo: topMetaOverlay.bottomAnchor, constant: DS.Spacing.md),
            volumeHUD.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            column.topAnchor.constraint(equalTo: volumeHUD.topAnchor, constant: DS.Spacing.sm),
            column.bottomAnchor.constraint(equalTo: volumeHUD.bottomAnchor, constant: -DS.Spacing.sm),
            column.leadingAnchor.constraint(equalTo: volumeHUD.leadingAnchor, constant: DS.Spacing.md),
            column.trailingAnchor.constraint(equalTo: volumeHUD.trailingAnchor, constant: -DS.Spacing.md),
        ])
    }

    private func showVolumeHUD(source: VolumeSource) {
        // 에러 카드 위로 HUD가 떠오르지 않도록
        guard errorContainer == nil else { return }

        let level: Float
        let muted: Bool

        switch source {
        case .app:
            muted = avVC?.player?.isMuted ?? false
            level = muted ? 0 : (avVC?.player?.volume ?? 0)
            volumeSourceLabel.text = "앱 음량"
            // 물리 음량 버튼과 인앱 음량이 다른 것이라는 안내는 재생 세션당 한 번만.
            volumeHintLabel.isHidden = didShowVolumeHint
            didShowVolumeHint = true
        case .system:
            muted = false
            level = AVAudioSession.sharedInstance().outputVolume
            volumeSourceLabel.text = "시스템 음량"
            volumeHintLabel.isHidden = true
        }

        let filled = Int((level * Float(Self.volumeSegmentCount)).rounded())
        for (index, segment) in volumeSegments.enumerated() {
            segment.backgroundColor = index < filled ? DS.Colors.textPrimary : DS.Colors.volumeSegmentEmpty
        }
        // 시스템 음량은 10% 단위가 아니므로 라벨은 실제 값으로, 게이지만 세그먼트로 양자화
        volumeValueLabel.text = muted ? "음소거" : "\(Int((level * 100).rounded()))%"
        let iconName = muted ? "speaker.slash.fill" : (filled == 0 ? "speaker.fill" : "speaker.wave.2.fill")
        volumeIconView.image = UIImage(systemName: iconName)

        hideVolumeHUDTimer?.invalidate()
        UIView.animate(withDuration: 0.15) { self.volumeHUD.alpha = 1 }
        // 한 번만 뜨는 안내문은 읽을 시간을 더 준다
        let dwell = volumeHintLabel.isHidden ? Self.volumeHUDDwell : Self.volumeHintDwell
        hideVolumeHUDTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.4) { self?.volumeHUD.alpha = 0 }
        }
    }

    // MARK: - 재생 시작

    private func startPlayback() {
        guard let info = streamInfo else {
            showError(title: "스트림 정보 없음", description: "재생할 정보가 비어 있습니다.")
            return
        }
        print("[Player] URL: \(info.viewURL)")

        // 공유 쿠키 저장소(URLSession에서 player_live_api로 받은 쿠키)를
        // Cookie 헤더로 직접 합쳐 AVPlayer가 동일 세션으로 보이게 한다
        var cookieHeader = ""
        if let cookies = HTTPCookieStorage.shared.cookies(for: info.viewURL) {
            cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        // sooplive.com 도메인 쿠키들도 함께 (CDN 도메인엔 직접 안 매칭될 수 있음)
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let soopCookies = allCookies.filter { $0.domain.contains("sooplive") }
        let extra = soopCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !extra.isEmpty {
            cookieHeader = cookieHeader.isEmpty ? extra : "\(cookieHeader); \(extra)"
        }
        print("[Player] cookies: \(cookieHeader.prefix(120))...")

        var headers: [String: String] = [
            "Referer": "https://play.sooplive.com/",
            "Origin": "https://play.sooplive.com",
            "User-Agent": "AppleCoreMedia/1.0.0 (Apple TV; U; CPU OS 17_4 like Mac OS X)"
        ]
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: info.viewURL, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        let vc = AVPlayerViewController()
        vc.player = player
        vc.videoGravity = .resizeAspect
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // pre-roll 위에 안 보이도록 처음엔 숨김
        vc.view.alpha = 0
        addChild(vc)
        view.insertSubview(vc.view, belowSubview: preRollContainer)
        vc.didMove(toParent: self)
        avVC = vc

        // 해상도 라벨 / 음량 HUD를 가장 위로
        view.bringSubviewToFront(resolutionLabel)
        view.bringSubviewToFront(volumeHUD)

        // 지난 재생에서 쓰던 인앱 음량 복원(+ 다시 시도 시 음소거 유지) + 트랜스포트 바 음량 컨트롤 부착
        player.volume = Self.savedVolume()
        player.isMuted = pendingMuted
        vc.transportBarCustomMenuItems = makeTransportBarItems()

        // 최고 변종 선택 강제 — SD(360p) 대신 HD(540p) 골라지도록
        // SOOP는 비구독자에게 master playlist에 HD(540p) + SD(360p) 변종만 제공함
        item.preferredPeakBitRate = 0  // 0 = 무제한 (최고 변종 자동 선택)
        if #available(tvOS 11.0, *) {
            item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        }

        // 플레이어 상태 관찰 — 실패 시 fallback
        observer = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch it.status {
                case .readyToPlay:
                    UIView.animate(withDuration: 0.3) { self.avVC.view.alpha = 1 } completion: { _ in
                        self.handOffFocusToPlayer()
                    }
                    self.hidePreRoll()
                    player.play()
                    print("[Player] readyToPlay → playing")
                    self.startObservingResolution(item: it)
                    self.showTopMetaTemporarily()
                    // 복원된 인앱 음량이 100%가 아니거나 음소거면 이유 없이 조용하지 않도록 한 번 보여 준다
                    if player.volume < 1 || player.isMuted {
                        self.showVolumeHUD(source: .app)
                    }
                case .failed:
                    let err = it.error
                    print("[Player] FAILED: \(String(describing: err))")
                    self.tryFallback(info: info, originalError: err)
                default:
                    break
                }
            }
        }
    }

    /// presentationSize KVO — 실제 디코딩되는 비디오 해상도를 라벨에 표시
    private func startObservingResolution(item: AVPlayerItem) {
        presentationObserver = item.observe(\.presentationSize, options: [.new, .initial]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let size = it.presentationSize
                guard size.width > 0, size.height > 0 else { return }
                let w = Int(size.width)
                let h = Int(size.height)
                // v3: 시청자가 즉시 이해 가능한 직접 표기
                let quality: String
                switch h {
                case ...360:  quality = "360p"
                case ...540:  quality = "540p"
                case ...720:  quality = "720p"
                case ...1080: quality = "1080p"
                case ...1440: quality = "1440p"
                default:      quality = "4K"
                }
                self.resolutionLabel.text = " \(quality) "
                self.showResolutionLabelTemporarily()
                print("[Player] presentationSize: \(w)x\(h) (\(quality))")
            }
        }
    }

    /// primary viewURL(TS) 실패 시 timeShiftURL(view_url+aid)로 즉시 swap.
    /// 1080p 시도 실패 → 540p로 안정 재생.
    /// v2: maxRetries 초과 시 즉시 에러 카드.
    private var didFallback = false
    private func tryFallback(info: StreamInfo, originalError: Error? = nil) {
        retryCount += 1
        guard retryCount <= maxRetries else {
            print("[Player] retry budget exhausted (\(retryCount)/\(maxRetries))")
            showError(title: "재생할 수 없습니다",
                      description: "여러 번 시도했지만 연결되지 않습니다. 잠시 후 다시 시도해 주세요")
            return
        }
        guard !didFallback else {
            print("[Player] fallback already tried — giving up")
            showError(
                title: "재생할 수 없습니다",
                description: "네트워크 또는 방송 상태를 확인하세요"
            )
            return
        }
        didFallback = true
        // 1순위: streamInfo 안에 미리 받아둔 fallback URL 사용 (timeShiftURL = view_url+aid)
        if let fb = info.timeShiftURL, fb != info.viewURL {
            print("[Player] Fallback to view_url+aid: \(fb.absoluteString.prefix(140))")
            swapPlayerURL(fb)
            return
        }
        // 2순위: 다시 view_url 받아오기
        print("[Player] Re-fetching view_url for fallback")
        SOOPAPIClient.shared.fetchViewURL(broadNo: info.broadNo, bjId: info.bjId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let viewURL):
                    var url = viewURL
                    if let aid = info.aid, !aid.isEmpty {
                        if let composed = URL(string: viewURL.absoluteString + "?aid=" + aid) {
                            url = composed
                        }
                    }
                    self.swapPlayerURL(url)
                case .failure:
                    self.showError(
                        title: "재생할 수 없습니다",
                        description: "네트워크 또는 방송 상태를 확인하세요"
                    )
                }
            }
        }
    }

    private func swapPlayerURL(_ url: URL) {
        // sooplive 쿠키 + Referer/Origin 헤더
        var cookieHeader = ""
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let soopCookies = allCookies.filter { $0.domain.contains("sooplive") }
        cookieHeader = soopCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        var headers: [String: String] = [
            "Referer": "https://play.sooplive.com/",
            "Origin": "https://play.sooplive.com",
            "User-Agent": "AppleCoreMedia/1.0.0 (Apple TV; U; CPU OS 17_4 like Mac OS X)"
        ]
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = 0
        if #available(tvOS 11.0, *) {
            item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        }

        // 이전 observer 교체 (NSKeyValueObservation 재할당 시 자동 해제되지만 명시적 처리)
        observer?.invalidate()
        presentationObserver?.invalidate()

        avVC.player?.replaceCurrentItem(with: item)
        avVC.player?.play()

        // 안정 모드 라벨
        resolutionLabel.text = " 안정 모드 "
        showResolutionLabelTemporarily()
        print("[Player] swapPlayerURL → fallback URL: \(url.absoluteString.prefix(140))")

        preRollStatusLabel.text = "안정 모드로 재시도 중..."

        // fallback 아이템에도 상태·해상도 KVO 부착
        observer = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch it.status {
                case .readyToPlay:
                    UIView.animate(withDuration: 0.3) { self.avVC.view.alpha = 1 } completion: { _ in
                        self.handOffFocusToPlayer()
                    }
                    self.hidePreRoll()
                    self.startObservingResolution(item: it)
                    self.showTopMetaTemporarily()
                    if let player = self.avVC?.player, player.volume < 1 || player.isMuted {
                        self.showVolumeHUD(source: .app)
                    }
                case .failed:
                    print("[Player] Fallback FAILED: \(String(describing: it.error))")
                    self.showError(
                        title: "재생할 수 없습니다",
                        description: "네트워크 또는 방송 상태를 확인하세요"
                    )
                default:
                    break
                }
            }
        }
    }

    // MARK: - 에러 카드

    private func showError(title: String, description: String) {
        errorContainer?.removeFromSuperview()

        let container = UIView()
        container.backgroundColor = DS.Colors.background.withAlphaComponent(0.92)
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.tintColor = DS.Colors.live
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.subsection
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.textColor = DS.Colors.textSecondary
        descLabel.font = DS.Typography.body
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(descLabel)

        var retryConfig = UIButton.Configuration.filled()
        retryConfig.baseBackgroundColor = DS.Colors.primary
        retryConfig.baseForegroundColor = DS.Colors.textPrimary
        retryConfig.contentInsets = DS.ButtonInsets.cta
        retryConfig.cornerStyle = .fixed
        retryConfig.background.cornerRadius = DS.Corner.button
        retryConfig.attributedTitle = AttributedString("다시 시도", attributes: AttributeContainer([
            .font: DS.Typography.cardTitle
        ]))
        let retryBtn = UIButton(configuration: retryConfig)
        retryBtn.translatesAutoresizingMaskIntoConstraints = false
        retryBtn.addTarget(self, action: #selector(retryTapped), for: .primaryActionTriggered)
        container.addSubview(retryBtn)

        var backConfig = UIButton.Configuration.filled()
        backConfig.baseBackgroundColor = DS.Colors.surfaceElevated
        backConfig.baseForegroundColor = DS.Colors.textPrimary
        backConfig.contentInsets = DS.ButtonInsets.cta
        backConfig.cornerStyle = .fixed
        backConfig.background.cornerRadius = DS.Corner.button
        backConfig.attributedTitle = AttributedString("돌아가기", attributes: AttributeContainer([
            .font: DS.Typography.cardTitle
        ]))
        let backBtn = UIButton(configuration: backConfig)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.addTarget(self, action: #selector(backTapped), for: .primaryActionTriggered)
        container.addSubview(backBtn)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -160),
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 80),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -80),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 80),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -80),

            retryBtn.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 40),
            retryBtn.trailingAnchor.constraint(equalTo: container.centerXAnchor, constant: -12),

            backBtn.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 40),
            backBtn.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 12),
        ])

        errorContainer = container
        preRollSpinner.stopAnimating()
        preRollSpinner.isHidden = true
        // 카드 뒤의 플레이어가 방향 이동으로 포커스를 가져가지 않도록 숨기고, 카드로 포커스 이동
        avVC?.view.alpha = 0
        requestFocus(on: container)
    }

    @objc private func retryTapped() {
        errorContainer?.removeFromSuperview()
        errorContainer = nil
        didFallback = false
        retryCount = 0
        // v3.2 [버그 수정]: 이전 AVPlayerViewController 정리 (누수 방지)
        tearDownAVPlayer()
        preRollContainer.alpha = 1
        preRollContainer.isHidden = false
        preRollSpinner.isHidden = false
        preRollSpinner.startAnimating()
        preRollStatusLabel.text = "스트림 연결 중..."
        startPlayback()
    }

    /// v3.2: 현재 AVPlayer/AVPlayerViewController/observer를 모두 정리
    private func tearDownAVPlayer() {
        pendingMuted = avVC?.player?.isMuted ?? false
        observer?.invalidate()
        observer = nil
        presentationObserver?.invalidate()
        presentationObserver = nil
        avVC?.player?.pause()
        avVC?.player?.replaceCurrentItem(with: nil)
        avVC?.willMove(toParent: nil)
        avVC?.view.removeFromSuperview()
        avVC?.removeFromParent()
        avVC = nil
    }

    @objc private func backTapped() {
        avVC?.player?.pause()
        dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            deactivateAudioSession()
        }
    }

    // MARK: - 포커스

    /// AVPlayerViewController는 alpha 0으로 삽입되므로 초기 포커스 대상이 될 수 없다.
    /// 페이드인 후 명시적으로 포커스를 넘겨야 트랜스포트 바(= 음량 컨트롤)를 열 수 있다.
    private func handOffFocusToPlayer() {
        guard let avVC = avVC else { return }
        requestFocus(on: avVC)
    }

    /// setNeedsFocusUpdate()는 "이 환경이 현재 포커스 항목을 포함하지 않으면 아무 효과가 없다"
    /// (UIFocus.h). 프리롤 단계에는 포커스 가능한 뷰가 없어 그 전제가 깨지므로,
    /// 전제 조건이 없는 UIFocusSystem.requestFocusUpdate(to:)를 쓴다.
    private func requestFocus(on environment: UIFocusEnvironment) {
        guard let focusSystem = UIFocusSystem.focusSystem(for: self) else { return }
        focusSystem.requestFocusUpdate(to: environment)
        focusSystem.updateFocusIfNeeded()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let errorContainer = errorContainer {
            return [errorContainer]
        }
        if let avVC = avVC, avVC.view.alpha > 0 {
            return [avVC]
        }
        return super.preferredFocusEnvironments
    }

    deinit {
        observer?.invalidate()
        presentationObserver?.invalidate()
        systemVolumeObservation?.invalidate()
        hideResolutionTimer?.invalidate()
        hideMetaTimer?.invalidate()
        hideVolumeHUDTimer?.invalidate()
        avVC?.player?.pause()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                // avVC는 startPlayback이 조기 반환하면 nil일 수 있다 (강제 언래핑 크래시 방지).
                backTapped()
                return
            }
            // 외부 HID 키보드·리모컨의 음량 키 (Siri Remote 버튼은 오지 않음 — 상단 주석 참고)
            if let keyCode = press.key?.keyCode {
                switch keyCode {
                case .keyboardVolumeUp:
                    stepVolume(by: Self.volumeStep)
                    return
                case .keyboardVolumeDown:
                    stepVolume(by: -Self.volumeStep)
                    return
                case .keyboardMute:
                    toggleMute()
                    return
                default:
                    break
                }
            }
        }
        // 사용자가 리모컨을 만지면 해상도 라벨 + 상단 메타 잠시 표시
        if avVC?.view.alpha ?? 0 > 0 {
            showResolutionLabelTemporarily()
            showTopMetaTemporarily()
        }
        super.pressesBegan(presses, with: event)
    }
}
