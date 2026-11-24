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
//   • FALLBACK(view_url+aid) 스왑은 화면에 드러내지 않는다 — 배지는 실제 화질만 (v6)
//   • 실패 시 에러 카드 (다시 시도/돌아가기)
//   • 트랜스포트 바 '화질' 메뉴 + 우상단 화질 배지 (v6)

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

    /// 플레이어 뷰를 한 번이라도 드러냈는지(프리롤을 내렸는지). startPlayback마다 false로 돌아간다.
    /// 화질 고정은 프리롤 중에 item을 교체할 수 있는데, 그 경로(qualityReload)는 '재생 중 교체'를 전제로
    /// 인트로(페이드인·프리롤 내리기·재생 시작)를 건너뛴다. 아직 드러나기 전이라면 건너뛰면 안 되므로
    /// '재생 중인가'를 qualityReload가 아니라 이 플래그로 판단한다.
    private var didRevealPlayer = false

    /// 화질 고정 교체가 실패해 직전 URL로 되돌리는 중인지. 고정은 '한 번도 재생해 본 적 없는' media URL로 바꾸는 일이라
    /// 실패할 수 있는데, 그때 폴백 예산(didFallback)을 써 버리면 멀쩡히 나오던 화면이 에러 카드로 끝난다.
    /// 되돌리기까지 실패할 때만 기존 폴백·에러 경로로 간다.
    private var isRevertingPin = false

    /// D1: 재생 중 소스가 죽을 때(라이브 끊김) 오는 AVPlayerItemFailedToPlayToEndTime 알림 토큰.
    /// status KVO는 시작 실패에서만 .failed를 주고 재생 중 사망은 못 잡는다
    /// (docs/20261003-fixed-resolution-v1.md §1-6 D1). 이 알림으로 폴백/에러 카드를 띄운다.
    private var failedToEndObserver: NSObjectProtocol?

    // v6: 화질 선택 — 0 = 자동, 그 외 = 짧은 변 등급(360/540/720/1080). 방송이 바뀌어도 유지한다(음량과 같은 방식).
    // v8: 설정 탭과 같은 값을 보도록 저장소를 PlaybackSettings로 모았다(키는 `soop.player.quality` 그대로).
    private var qualityChoice: Int {
        get { PlaybackSettings.quality }
        set { PlaybackSettings.quality = newValue }
    }
    /// 화질 메뉴 행 — 재생 중 master에 실제로 있는 등급(높은 것부터). 등급이 2개 미만이면 비어 있고 메뉴는 '자동'만.
    private var qualityOptions: [Int] = []
    /// 화질 고정: master를 파싱해 얻은 등급→media playlist URL(높은 등급 우선). 수동 N을 고르면 이 URL을 직접 재생해
    /// 렌디션을 하나로 고정한다(ABR 전환 불가 = 고정). docs/20261003-fixed-resolution-v1.md §2-3.
    private var renditions: [(bucket: Int, url: URL)] = []
    /// 이 방송의 master(= view_url+aid) URL. '자동'으로 돌아갈 때의 대상이자 renditions 파싱 대상이다.
    /// TS(구독자 타임머신) 방송은 timeShiftURL이 공개 master라 그쪽을 쓴다.
    private var masterURL: URL?
    /// 지금 AVPlayer에 올라가 있는 URL. 같은 URL로 불필요하게 교체하지 않으려고 추적한다.
    private var currentPlayURL: URL?
    /// 화질 메뉴 행 인스턴스(키 0 = 자동). 체크·부제는 이 인스턴스를 제자리에서 바꾼다.
    private var qualityActions: [Int: UIAction] = [:]
    /// 트랜스포트 바 음량 항목 — AVPlayerViewController마다 한 번 만들어 화질 메뉴를 바꿀 때도 같은 인스턴스를 쓴다.
    private var volumeMenuItems: [UIMenuElement] = []

    /// 네이티브 재생 세션(모드가 native일 때만 존재). 폴백 시 nil이 되고 CDN 경로로 이어진다.
    private var nativeController: SOOPNativePlayerController?
    /// 네이티브 폴백으로 CDN 자동 재생에 이미 넘어갔는지(토스트·재폴백 방지).
    private var didFallbackFromNative = false
    /// 재생 중 끊긴 네이티브 세션을 원본으로 다시 연결한 횟수(플레이어 화면당). 다 쓰면 CDN으로 넘어간다.
    private var nativeReconnects = 0
    private static let maxNativeReconnects = 3

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
        // 화질을 올리려고 item을 바꾼 직후처럼 첫 프레임 전이면 직전 item의 글자가 보이므로 띄우지 않는다
        guard currentQualityBucket() > 0 else { return }
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

    /// 트랜스포트 바 '화질' 메뉴 — '자동' + 재생 중 master에 실제로 있는 화질만.
    /// 최상위 UIMenu는 image가 없으면 버튼이 생기지 않는다. 행 제목은 고정이고 체크·부제는 syncQualityMenu가 맞춘다.
    private func makeQualityMenu() -> UIMenu {
        qualityActions = [:]
        let actions = ([0] + qualityOptions).map { q -> UIAction in
            let action = UIAction(title: q == 0 ? "자동" : QualityLadder.label(q)) { [weak self] _ in
                self?.selectQuality(q)
            }
            qualityActions[q] = action
            return action
        }
        syncQualityMenu()
        return UIMenu(title: "화질", image: UIImage(systemName: "gearshape"), options: .singleSelection, children: actions)
    }

    /// 체크(적용 중인 행)와 체크 행의 부제('현재 X')를 보관한 인스턴스에서 제자리로 맞춘다(다음에 열 때 반영).
    /// .singleSelection의 체크 자동 이동에는 기대지 않는다(tvOS 17~25에서 확인하지 못함).
    private func syncQualityMenu() {
        let checked = QualityLadder.effective(choice: qualityChoice, options: qualityOptions)
        let actual = currentQualityBucket()
        for (q, action) in qualityActions {
            action.state = q == checked ? .on : .off
            action.subtitle = q == checked ? QualityLadder.rowSubtitle(row: q, actual: actual) : nil
        }
    }

    /// 고른 화질을 저장하고 고정한다. 수동 N이면 그 등급 variant의 media playlist URL을 직접 재생해(단일 렌디션)
    /// ABR 전환 자체를 막는다 = 진짜 고정. 자동이면 master로 돌려 ABR을 되살린다.
    /// 상한(preferredMaximumResolution)으로 내리던 예전 방식은 망이 흔들리면 더 낮은 화질로 떠내려가 다시 오르지 않았다
    /// (docs/20260930-quality-selection-v1.md §2-7). 고정은 그 문제가 없다.
    private func selectQuality(_ q: Int) {
        // 체크가 옮겨 갈 때만 저장한다 — 체크된 행을 다시 고르는 복구가 대체 중인 선호(예: 1080p)를 지우지 않게
        qualityChoice = QualityLadder.choice(afterPicking: q, saved: qualityChoice, options: qualityOptions)
        pinCurrentChoice(userInitiated: true)
    }

    /// 저장된 화질을 실제 재생에 적용한다. 수동 N → N 등급 media URL로 교체(고정), 자동 → master로 교체(ABR).
    /// renditions가 없으면(파싱 실패·단일 화질 방송) 메뉴가 '자동'뿐이라 할 일이 없다.
    private func pinCurrentChoice(userInitiated: Bool) {
        func refreshLabel() { if userInitiated { updateQualityLabel(show: true) } }
        guard !renditions.isEmpty, let master = masterURL, avVC?.player?.currentItem != nil else {
            refreshLabel(); return
        }
        // '자동'은 저장값으로 판단한다. target(choice:options:)는 자동일 때 0이 아니라 '기대 등급'(= 가장 높은 행)을
        // 돌려주는 배지용 규약이라, 그것으로 자동을 판정하면 master 분기가 영영 선택되지 않아
        // '자동'을 골라도 단일 렌디션에 갇힌 채 ABR이 돌아오지 않는다.
        let desired: URL?
        if qualityChoice == 0 {
            desired = master
        } else {
            let target = QualityLadder.target(choice: qualityChoice, options: qualityOptions)
            desired = renditions.first(where: { $0.bucket == target })?.url
        }
        guard let url = desired, currentPlayURL != url else { refreshLabel(); return }
        // 메뉴 핸들러 안에서 item을 바꾸다 포커스 갱신 중 크래시한 보고가 있어 다음 런루프로 미룬다(기존 규칙).
        DispatchQueue.main.async { [weak self] in self?.swapPlayerURL(url, qualityReload: true) }
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

    // MARK: - 재생 헤더 / 끊김 감지

    /// AVPlayer에 넘길 공통 요청 헤더.
    /// Referer·Origin·UA는 SOOP CDN이 요구하므로 항상 싣지만, 로그인 쿠키(AuthTicket/UserTicket 등)는
    /// 요청 호스트가 SOOP 도메인일 때만 싣는다. 예전 코드는 호스트와 무관하게 쿠키를 실어,
    /// SOOP이 아닌 호스트(루프백 등)로 가는 순간 로그인 세션이 샜다
    /// (docs/20261003-fixed-resolution-v1.md §1-6 D2). SOOP 재생 URL은 모두 *.sooplive 서브도메인이라 회귀가 없다.
    private static func playbackHeaders(for url: URL) -> [String: String] {
        var headers: [String: String] = [
            "Referer": "https://play.sooplive.com/",
            "Origin": "https://play.sooplive.com",
            "User-Agent": "AppleCoreMedia/1.0.0 (Apple TV; U; CPU OS 17_4 like Mac OS X)"
        ]
        if let host = url.host?.lowercased(),
           host == "sooplive.com" || host.hasSuffix(".sooplive.com")
             || host == "sooplive.co.kr" || host.hasSuffix(".sooplive.co.kr") {
            let soopCookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.contains("sooplive") }
            if !soopCookies.isEmpty {
                headers["Cookie"] = soopCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
        }
        return headers
    }

    /// D1: 지금 재생 중인 item에 '재생 중 실패' 알림 관찰을 건다. 이전 관찰은 먼저 해제한다.
    private func observePlaybackFailure(for item: AVPlayerItem, info: StreamInfo) {
        removePlaybackFailureObserver()
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            guard let self = self, self.avVC != nil, !self.isBeingDismissed else { return }
            // 교체로 밀려난 item의 뒤늦은 알림으로 재생 중인 화면을 건드리지 않는다
            guard (note.object as AnyObject?) === self.avVC?.player?.currentItem else { return }
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            print("[Player] playback failed mid-stream → fallback/error")
            // 이미 에러 카드가 떠 있으면 중복 처리하지 않는다. 그 밖에는 기존 폴백 로직을 그대로 탄다
            // (폴백 전이면 대체 URL, 폴백했으면 에러 카드).
            guard self.errorContainer == nil else { return }
            // 네이티브(루프백) 재생이 끊긴 경우는 네이티브 복구로 — tryFallback은 CDN URL로 조용히 바꿔
            // 수신기를 뒤에 남겨 둔 채 화질 메뉴만 540p/360p로 바꿔 놓았다.
            if let native = self.nativeController {
                native.stop()
                self.nativeController = nil
                self.recoverFromNativeFailure(info: info, reason: .protocolError("loopback playback failed mid-stream"))
                return
            }
            self.tryFallback(info: info, originalError: err)
        }
    }

    private func removePlaybackFailureObserver() {
        if let token = failedToEndObserver {
            NotificationCenter.default.removeObserver(token)
            failedToEndObserver = nil
        }
    }

    // MARK: - 재생 시작

    private func startPlayback() {
        guard let info = streamInfo else {
            showError(title: "스트림 정보 없음", description: "재생할 정보가 비어 있습니다.")
            return
        }
        // 네이티브 모드: 공개 방송으로 확인된 방송만 원본 수신을 시도한다(docs/20261010 §2-3 게이트).
        // 19+·비번방·실패 이력이 있으면 게이트가 닫혀 있으므로 그냥 CDN 경로로 진행한다.
        if PlaybackSettings.mode == .native, Self.nativeGatePasses(info) {
            startNativePlayback(info: info)
            return
        }
        startCDNPlayback(info: info)
    }

    /// 네이티브 경로 게이트 — 공개(grade<19)·비번방 아님·라이브 방송만.
    private static func nativeGatePasses(_ info: StreamInfo) -> Bool {
        guard info.isLive, info.grade < 19, !info.isPasswordRoom else { return false }
        return true
    }

    /// 네이티브 재생 — 원본 수신 → 루프백 HLS를 AVPlayer에 넘긴다. 실패하면 CDN 자동으로.
    private func startNativePlayback(info: StreamInfo) {
        let controller = SOOPNativePlayerController(quality: .p1080)
        nativeController = controller
        didFallbackFromNative = false

        // 프리롤 문구 — 무엇을 기다리는지 알려준다.
        preRollStatusLabel?.text = "원본 연결 중…"

        controller.onPlaylistReady = { [weak self] in
            guard let self = self, self.nativeController === controller,
                  let url = controller.playlistURL else { return }
            print("[Player] native playlist ready: \(url.absoluteString)")
            self.playLoopbackHLS(url)
        }
        controller.onFallback = { [weak self] error in
            guard let self = self, self.nativeController === controller else { return }
            print("[Player] native failed: \(error.localizedDescription)")
            self.nativeController = nil
            self.recoverFromNativeFailure(info: info, reason: error)
        }
        controller.start(bjId: info.bjId, broadNo: info.broadNo)
    }

    /// 네이티브 세션이 끊겼을 때. 재생까지 갔던 세션이면 원본으로 다시 연결하고(일시적 끊김 한 번으로 그 방송을
    /// 끝까지 540p로 보게 되지 않게), 재생 전에 실패했거나 재연결을 다 썼으면 CDN으로 넘어간다.
    private func recoverFromNativeFailure(info: StreamInfo, reason: SOOPNativeError) {
        guard didRevealPlayer, nativeReconnects < Self.maxNativeReconnects else {
            fallbackToCDN(info: info, reason: reason)
            return
        }
        nativeReconnects += 1
        print("[Player] native reconnect \(nativeReconnects)/\(Self.maxNativeReconnects) (\(reason.localizedDescription))")
        tearDownAVPlayer()
        didRevealPlayer = false   // 재연결이 재생 전에 또 실패하면 위 가드로 CDN에 넘어가게
        showPreRoll(status: "원본 다시 연결 중…")
        startNativePlayback(info: info)
    }

    /// 재생 중 다시 연결할 때 프리롤을 다시 띄운다(내려간 프리롤 위로 빈 화면이 보이지 않게).
    private func showPreRoll(status: String) {
        preRollContainer.alpha = 1
        preRollContainer.isHidden = false
        preRollSpinner.isHidden = false
        preRollSpinner.startAnimating()
        preRollStatusLabel.text = status
    }

    /// 루프백 HLS URL로 AVPlayer를 띄운다(헤더·쿠키 불필요 — 127.0.0.1).
    private func playLoopbackHLS(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        didRevealPlayer = false     // startCDNPlayback과 같다 — 재연결·다시 시도로 들어온 새 플레이어도 드러나야 한다
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = self
        vc.videoGravity = .resizeAspect
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.alpha = 0
        addChild(vc)
        view.insertSubview(vc.view, belowSubview: preRollContainer)
        vc.didMove(toParent: self)
        avVC = vc

        view.bringSubviewToFront(resolutionLabel)
        view.bringSubviewToFront(volumeHUD)

        player.volume = Self.savedVolume()
        player.isMuted = pendingMuted
        // 네이티브는 CDN 등급 사다리와 무관 — 메뉴는 안내 행 하나.
        volumeMenuItems = makeTransportBarItems()
        vc.transportBarCustomMenuItems = volumeMenuItems + [makeNativeQualityMenu()]
        resolutionLabel.text = "원본 1080p"

        observer = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self, it === self.avVC?.player?.currentItem else { return }
                if it.status == .readyToPlay {
                    self.revealPlayer(item: it)
                    self.observeNativeResolution()
                } else if it.status == .failed {
                    // 루프백 재생 실패 — 재연결 또는 CDN으로.
                    guard let info = self.streamInfo else { return }
                    print("[Player] loopback FAILED: \(String(describing: it.error))")
                    self.nativeController?.stop()
                    self.nativeController = nil
                    self.recoverFromNativeFailure(info: info, reason: .protocolError("loopback playback failed"))
                }
            }
        }
        observePlaybackFailure(for: item, info: streamInfo ?? info0())
    }

    /// StreamInfo가 nil일 일은 없지만 컴파일러를 위한 도우미.
    private func info0() -> StreamInfo {
        StreamInfo(bjId: "", broadNo: "", title: "", bjNick: "",
                   viewURL: URL(string: "about:blank")!, timeShiftURL: nil, aid: nil,
                   resolution: "", isLive: false, grade: 99, isPasswordRoom: false)
    }

    /// 네이티브 재생 중 실제 해상도 배지 갱신 — 기존 관찰 로직을 그대로 쓰고 문구만 원본으로.
    private func observeNativeResolution() {
        startObservingResolution(item: avVC?.player?.currentItem ?? AVPlayerItem(url: URL(string: "about:blank")!))
    }

    /// 네이티브 재생 중 화질 메뉴 — CDN 사다리와 무관한 안내 행.
    private func makeNativeQualityMenu() -> UIMenu {
        let action = UIAction(title: "네이티브 원본 (1080p 직접 수신)") { _ in }
        action.subtitle = "설정에서 재생 방식을 바꿀 수 있습니다"
        return UIMenu(title: "화질", image: UIImage(systemName: "gearshape"), children: [action])
    }

    /// 네이티브 실패 → CDN 자동 재생 + 토스트 1회.
    private func fallbackToCDN(info: StreamInfo, reason: SOOPNativeError) {
        guard !didFallbackFromNative else { return }
        didFallbackFromNative = true
        // 루프백 플레이어가 남아 있으면(재생 중 끊김) 정리하고 프리롤을 다시 띄운다. 예전엔 그대로 둔 채
        // CDN 플레이어를 하나 더 얹어 AVPlayer 두 개가 겹쳐 있었다.
        if avVC != nil {
            tearDownAVPlayer()
            showPreRoll(status: "스트림 연결 중...")
        } else {
            preRollStatusLabel?.text = "스트림 연결 중..."
        }
        // 기존 실패/폴백 상태를 리셋하고 CDN 경로로 처음부터.
        didFallback = false
        startCDNPlayback(info: info)
        showToast("네이티브 재생 실패 — 일반 재생으로 전환했습니다\n(\(reason.localizedDescription))")
    }

    private func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = DS.Colors.textPrimary
        label.font = DS.Typography.caption
        label.numberOfLines = 3
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0, alpha: 0.75)
        label.layer.cornerRadius = DS.Corner.button
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
        ])
        label.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        UIView.animate(withDuration: 0.25, animations: { label.alpha = 1 }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                UIView.animate(withDuration: 0.4, animations: { label.alpha = 0 }) { _ in
                    label.removeFromSuperview()
                }
            }
        }
    }

    /// CDN(기존) 재생 — 원래 startPlayback의 본문.
    private func startCDNPlayback(info: StreamInfo) {
        // AVPlayer에 넘길 요청 헤더. 로그인 쿠키는 SOOP 도메인에만 싣는다(playbackHeaders, D2).
        // 전체 URL에는 aid 토큰이 들어 있어 호스트만 찍는다(토큰 노출 방지).
        let headers = Self.playbackHeaders(for: info.viewURL)
        print("[Player] URL host: \(info.viewURL.host ?? "?") (cookies: \(headers["Cookie"] != nil ? "on" : "off"))")

        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: info.viewURL, options: options)
        let item = AVPlayerItem(asset: asset)
        didRevealPlayer = false     // 새 플레이어 뷰는 alpha 0 + 프리롤 위 — 아직 아무것도 드러나지 않았다
        applyQualityCap(to: item)   // 자동일 때 1080p 초과(1440p·4K) variant를 배제한다. 고정 재생엔 영향 없음
        let player = AVPlayer(playerItem: item)
        currentPlayURL = info.viewURL
        // master(= 자동 대상, renditions 파싱 대상). TS 방송은 viewURL이 TS라 공개 master인 timeShiftURL을 쓴다.
        // 다만 view_url이나 AID를 못 받으면 SOOPAPIClient가 양쪽에 같은 TS를 넣는다. TS는 master가 아니라
        // media playlist이고 비구독자에겐 401/403이라 파싱 대상이 못 되므로, 그때는 master가 없는 것으로 둔다
        // (폴백으로 진짜 master에 닿으면 swapPlayerURL에서 채운다).
        masterURL = (info.timeShiftURL == info.viewURL) ? nil : (info.timeShiftURL ?? info.viewURL)

        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = self   // Menu로 플레이어를 닫을 때를 AVKit이 알려 준다(playerViewControllerShouldDismiss)
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

        // 지난 재생에서 쓰던 인앱 음량 복원(+ 다시 시도 시 음소거 유지) + 트랜스포트 바 음량·화질 컨트롤 부착
        player.volume = Self.savedVolume()
        player.isMuted = pendingMuted
        // 화질 메뉴는 '자동'만으로 먼저 붙이고, master를 파싱하면 목록을 채운다(보통 프리롤 중에 끝남).
        // 저장된 화질이 수동이면 파싱이 끝나는 대로 그 등급 media URL로 조용히 고정 전환한다(loadRenditions).
        qualityOptions = []
        renditions = []
        volumeMenuItems = makeTransportBarItems()
        vc.transportBarCustomMenuItems = volumeMenuItems + [makeQualityMenu()]
        if let master = masterURL { loadRenditions(from: master) }

        // 플레이어 상태 관찰 — 실패 시 fallback
        observer = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 화질 고정 교체로 item이 이미 바뀐 뒤 도착한 콜백은 버린다(swapPlayerURL의 가드와 같은 이유)
                guard it === self.avVC?.player?.currentItem else { return }
                switch it.status {
                case .readyToPlay:
                    self.revealPlayer(item: it)
                case .failed:
                    let err = it.error
                    print("[Player] FAILED: \(String(describing: err))")
                    self.tryFallback(info: info, originalError: err)
                default:
                    break
                }
            }
        }
        observePlaybackFailure(for: item, info: info)   // D1: 재생 중 끊김 감지
    }

    /// 첫 readyToPlay에서 한 번만 — 플레이어를 드러내고 프리롤을 내리고 재생을 시작한다.
    /// 어떤 item에서 오든(원래 item·화질 고정 교체·폴백) 처음 준비된 것이 화면을 연다.
    private func revealPlayer(item: AVPlayerItem) {
        guard !didRevealPlayer, let player = avVC?.player else { return }
        didRevealPlayer = true
        UIView.animate(withDuration: 0.3) { self.avVC.view.alpha = 1 } completion: { _ in
            self.handOffFocusToPlayer()
        }
        hidePreRoll()
        player.play()
        print("[Player] readyToPlay → playing")
        startObservingResolution(item: item)
        showTopMetaTemporarily()
        // 복원된 인앱 음량이 100%가 아니거나 음소거면 이유 없이 조용하지 않도록 한 번 보여 준다
        if player.volume < 1 || player.isMuted {
            showVolumeHUD(source: .app)
        }
    }

    /// presentationSize KVO — 실제 디코딩되는 비디오 해상도를 라벨에 표시
    private func startObservingResolution(item: AVPlayerItem) {
        presentationObserver = item.observe(\.presentationSize, options: [.new, .initial]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let size = it.presentationSize
                guard size.width > 0, size.height > 0 else { return }
                self.updateQualityLabel(show: true)
                print("[Player] presentationSize: \(Int(size.width))x\(Int(size.height)) (\(QualityLadder.label(QualityLadder.bucket(for: size))))")
            }
        }
    }

    /// 지금 디코딩 중인 화질의 짧은 변 등급. 첫 프레임 전이면 0.
    private func currentQualityBucket() -> Int {
        guard let size = avVC?.player?.currentItem?.presentationSize, size.width > 0, size.height > 0 else { return 0 }
        return QualityLadder.bucket(for: size)
    }

    /// 화질 배지 — 1줄째는 실제 화질, 2줄째는 체크된 수동 행(대체 행 포함)과 실제가 다를 때만. 메뉴의 체크·부제도 함께 맞춘다.
    private func updateQualityLabel(show: Bool) {
        syncQualityMenu()
        let actual = currentQualityBucket()
        guard actual > 0 else { return }
        let lines = QualityLadder.badgeLines(actual: actual, choice: qualityChoice, options: qualityOptions)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let text = NSMutableAttributedString(string: " \(lines.first) ", attributes: [
            .font: DS.Typography.cardTitle, .foregroundColor: DS.Colors.textPrimary, .paragraphStyle: centered,
        ])
        if let second = lines.second {
            text.append(NSAttributedString(string: "\n \(second) ", attributes: [
                .font: DS.Typography.caption, .foregroundColor: DS.Colors.textSecondary, .paragraphStyle: centered,
            ]))
        }
        resolutionLabel.attributedText = text
        if show { showResolutionLabelTemporarily() }
    }

    /// 저장한 화질을 item의 해상도 상한으로 건다. 상한일 뿐이라 망이 느리면 AVPlayer가 더 낮은 화질로 내려간다.
    private func applyQualityCap(to item: AVPlayerItem) {
        item.preferredPeakBitRate = 0
        item.preferredMaximumResolution = QualityLadder.cap(for: qualityChoice)
        print("[Player] quality \(qualityChoice == 0 ? "auto" : "\(qualityChoice)p") → cap \(Int(item.preferredMaximumResolution.width))")
    }

    /// master playlist 본문을 직접 받아 파싱해 등급→media URL 지도(renditions)와 메뉴 목록을 만든다.
    /// tvOS 17에는 AVAssetVariant.url이 없어 load(.variants) 대신 본문을 파싱한다(URL이 있어야 화질을 고정할 수 있다).
    /// 방송당 한 번(startPlayback) 부른다. 목록이 바뀔 때만 메뉴를 재할당한다(포커스 초기화 방지).
    private func loadRenditions(from master: URL) {
        var req = URLRequest(url: master)
        for (k, v) in Self.playbackHeaders(for: master) { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data, let text = String(data: data, encoding: .utf8), (200..<300).contains(status) else {
                // TS·만료 토큰은 401/403 본문(playlist가 아님)을 준다. 메뉴는 '자동'인 채로 둔다.
                print("[Player] renditions: fetch failed (http \(status), err \((err as NSError?)?.code ?? 0)) — menu kept")
                return
            }
            // 상대 URI는 AVPlayer와 같게 '리다이렉트 후 최종 URL' 기준으로 풀어야 한다.
            // 요청 URL로 풀면 CDN이 엣지로 302할 때 교체 URL이 전부 리다이렉트 전 호스트를 가리켜 404가 난다.
            let base = (resp as? HTTPURLResponse)?.url ?? master
            let parsed = QualityLadder.renditions(fromPlaylist: text, baseURL: base)
            let sizes = parsed.map { $0.size }
            let options = QualityLadder.options(from: sizes)
            // 등급이 겹치면(예: 854x480과 960x540이 모두 540 등급) 실제 해상도가 높은 쪽을 쓴다.
            // master의 나열 순서는 대역폭 오름차순인 경우가 많아 '먼저 나온 것'은 오히려 낮은 쪽이다.
            var map: [Int: (side: CGFloat, url: URL)] = [:]
            for r in parsed {
                let b = QualityLadder.bucket(for: r.size)
                let side = min(r.size.width, r.size.height)
                if map[b] == nil || side > map[b]!.side { map[b] = (side, r.url) }
            }
            DispatchQueue.main.async {
                guard let self = self, let avVC = self.avVC else { return }
                self.renditions = options.compactMap { b in map[b].map { (b, $0.url) } }
                print("[Player] renditions: \(options) (parsed \(parsed.count))")
                if options != self.qualityOptions {
                    self.qualityOptions = options
                    avVC.transportBarCustomMenuItems = self.volumeMenuItems + [self.makeQualityMenu()]
                }
                self.updateQualityLabel(show: false)
                // 저장된 화질이 수동이면 그 등급 media URL로 고정 전환한다(프리롤 중에 조용히).
                if self.qualityChoice != 0 { self.pinCurrentChoice(userInitiated: false) }
            }
        }.resume()
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

    /// - parameter qualityReload: 화질을 올리려고 같은 URL로 item만 새로 만드는 경우. 재생 중 교체라 프리롤 숨기기·페이드인·
    ///   상단 메타·음량 HUD·포커스 넘기기를 하지 않고, 일시정지 중이었으면 그대로 둔다. 실패하면 아직 폴백 전이면 폴백, 아니면 에러 카드.
    private func swapPlayerURL(_ url: URL, qualityReload: Bool = false) {
        // 로그인 쿠키는 SOOP 도메인에만 싣는다(playbackHeaders, D2).
        let headers = Self.playbackHeaders(for: url)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        applyQualityCap(to: item)

        // 이전 observer 교체 (NSKeyValueObservation 재할당 시 자동 해제되지만 명시적 처리)
        observer?.invalidate()
        presentationObserver?.invalidate()

        // 화면이 새 item으로 넘어가는 동안 직전 item의 배지가 남지 않게 바로 숨긴다(첫 프레임에서 다시 뜬다)
        hideResolutionTimer?.invalidate()
        resolutionLabel.alpha = 0

        // 사용자가 일시정지해 둔 상태를 화질 교체가 깨지 않게 하는 장치다. 아직 드러나기 전(프리롤 중)에는
        // 재생을 시작한 적이 없어 항상 .paused라, didRevealPlayer를 함께 보지 않으면 교체된 item이 영영 재생되지 않는다.
        let previousURL = currentPlayURL   // 고정 교체가 실패하면 여기로 되돌린다
        let keepPaused = qualityReload && didRevealPlayer && avVC.player?.timeControlStatus == .paused
        avVC.player?.replaceCurrentItem(with: item)
        currentPlayURL = url
        if !keepPaused { avVC.player?.play() }
        syncQualityMenu()   // 실제를 모르는 동안은 체크 행의 '현재 X' 부제를 비운다
        // renditions는 startPlayback에서 한 번 파싱한다. 다만 그때(TS 등으로) 비어 있었고 지금 폴백으로 master에 닿았으면
        // 이 URL이 진짜 master이므로 '자동'의 대상도 여기로 옮기고 다시 파싱한다(masterURL이 죽은 TS로 남지 않게).
        if renditions.isEmpty, !qualityReload {
            masterURL = url
            loadRenditions(from: url)
        }

        if qualityReload {
            startObservingResolution(item: item)   // 첫 프레임이 readyToPlay보다 먼저 올 수 있다
            print("[Player] quality reload — same URL, new item")
        } else {
            print("[Player] swapPlayerURL → fallback host: \(url.host ?? "?")")   // 토큰이 든 전체 URL은 찍지 않는다
        }

        // fallback 아이템에도 상태·해상도 KVO 부착
        observer = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 이미 다른 item으로 교체된 뒤 뒤늦게 도착한 콜백은 버린다. invalidate()는 메인 큐에
                // 이미 올라간 블록을 취소하지 못해, 화질 고정 교체와 직전 item의 실패가 겹치면
                // 재생 중인 화면 위에 에러 카드가 뜨거나 방금 고정한 item이 폐기된다.
                guard it === self.avVC?.player?.currentItem else { return }
                switch it.status {
                case .readyToPlay:
                    self.isRevertingPin = false
                    if !self.didRevealPlayer {
                        // 프리롤 중에 교체된 경우(화질 고정 또는 조기 폴백) — 이 item이 화면을 연다
                        self.revealPlayer(item: it)
                    } else if !qualityReload {
                        // 이미 재생 중이던 화면을 폴백으로 바꾼 경우 — 인트로는 다시 하지 않고 해상도 관찰만 새 item에 건다
                        self.startObservingResolution(item: it)
                    }
                case .failed:
                    print("[Player] \(qualityReload ? "Quality reload" : "Fallback") FAILED: \(String(describing: it.error))")
                    // 화질 고정 교체 실패 — 직전까지 재생되던 URL로 되돌린다. 폴백 예산을 쓰지 않는다.
                    if qualityReload, !self.isRevertingPin, let back = previousURL, back != url {
                        print("[Player] quality pin failed → reverting to previous URL")
                        self.isRevertingPin = true
                        self.swapPlayerURL(back, qualityReload: true)
                        return
                    }
                    // primary를 같은 URL로 바꾼 것뿐이면 primary 실패와 같이 한 번 폴백한다(기존 자동 복구 유지)
                    if qualityReload, !self.didFallback, let info = self.streamInfo {
                        self.tryFallback(info: info, originalError: it.error)
                        return
                    }
                    self.showError(
                        title: "재생할 수 없습니다",
                        description: "네트워크 또는 방송 상태를 확인하세요"
                    )
                default:
                    break
                }
            }
        }
        if let info = streamInfo { observePlaybackFailure(for: item, info: info) }   // D1: 새 item에도 끊김 감지
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
        removePlaybackFailureObserver()   // D1
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 프리롤·에러 카드의 Menu는 UIKit 모달 닫기로 끝나 backTapped()를 거치지 않는다. 어느 경로로 닫혀도 소리가 남지 않게 멈춘다.
        if isBeingDismissed { avVC?.player?.pause() }
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
        nativeController?.stop()
        observer?.invalidate()
        presentationObserver?.invalidate()
        removePlaybackFailureObserver()   // D1
        systemVolumeObservation?.invalidate()
        hideResolutionTimer?.invalidate()
        hideMetaTimer?.invalidate()
        hideVolumeHUDTimer?.invalidate()
        avVC?.player?.pause()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                // 누르는 순간 닫지 않는다 — 재생 화면에서는 AVKit이 팝업·바를 한 단계씩 닫고 마지막에
                // playerViewControllerShouldDismiss로 요청한다. 프리롤·에러 카드에서는 UIKit 모달 닫기가 처리한다(둘 다 누름은 취소로 끝남).
                // 아무도 쓰지 않은 누름만 pressesEnded에서 닫는다(tvOS 26.5에서는 관측되지 않은 대비 경로).
                menuPressBeganHere = true
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

    /// Menu를 여기서 누르기 시작했는지. AVKit이 팝업·바를 닫는 데 쓴 누름은 pressesCancelled로 끝나 종료로 이어지지 않는다.
    private var menuPressBeganHere = false

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            if menuPressBeganHere {
                menuPressBeganHere = false
                // avVC는 startPlayback이 조기 반환하면 nil일 수 있다 (강제 언래핑 크래시 방지).
                backTapped()
            }
            return
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            menuPressBeganHere = false
            return
        }
        super.pressesCancelled(presses, with: event)
    }
}

extension PlayerViewController: AVPlayerViewControllerDelegate {
    /// 화질 팝업 → 트랜스포트 바를 닫고 난 뒤의 Menu는 AVKit이 '플레이어 닫기'로 판단해 여기로 묻는다.
    /// 우리 AVPlayerViewController는 자식으로 끼워 넣은 것이라 스스로 닫히지 못하므로
    /// (AVPlayerViewController.h의 playerViewControllerShouldDismiss 설명) 플레이어 화면을 직접 닫는다.
    func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
        print("[Player] AVKit asks to dismiss (Menu with nothing to close)")
        backTapped()
        return false
    }
}

// MARK: - 화질 규칙 (순수 로직 — UIKit·AVFoundation 없이 macOS에서도 컴파일된다. 규칙 검증은 이 MARK부터 파일 끝까지 잘라 쓰므로
// 파일 끝에 둔다 — docs/20260930-quality-selection-v1.md §5-2)

/// 0 = 자동, 그 외 = 짧은 변 등급(360/540/720/1080).
enum QualityLadder {
    /// 짧은 변 기준 등급 — 기존 해상도 라벨의 경계값을 그대로 쓴다(세로 1080x1920도 1080p).
    static func bucket(for size: CGSize) -> Int {
        switch Int(min(size.width, size.height)) {
        case ...360:  return 360
        case ...540:  return 540
        case ...720:  return 720
        case ...1080: return 1080
        case ...1440: return 1440
        default:      return 2160
        }
    }

    static func label(_ bucket: Int) -> String { bucket == 2160 ? "4K" : "\(bucket)p" }

    /// 메뉴 행: master에 실제로 있는 1080p 이하 등급, 높은 것부터(중복 제거).
    /// 2개 미만이면 고를 것이 없으므로 비운다 — 효과 없는 선택이 전역 저장값이 되지 않게(메뉴는 '자동'만).
    static func options(from sizes: [CGSize]) -> [Int] {
        let buckets = Set(sizes.filter { $0.width > 0 && $0.height > 0 }.map(bucket(for:)).filter { $0 <= 1080 }).sorted(by: >)
        return buckets.count >= 2 ? buckets : []
    }

    /// 체크할 행: 고른 화질이 이 방송에 없으면 그 이하 중 가장 높은 것, 그것도 없으면 가장 낮은 것
    /// (= AVPlayer가 cap(for: choice)에서 실제로 고르는 것). 행이 없으면 '자동'. 저장값은 바꾸지 않는다.
    static func effective(choice: Int, options: [Int]) -> Int {
        guard choice != 0, let lowest = options.last else { return 0 }
        return options.first { $0 <= choice } ?? lowest
    }

    /// 선택을 적용했을 때 기대하는 등급: 수동이면 체크 행, 자동이면 가장 높은 행(행이 없으면 0).
    static func target(choice: Int, options: [Int]) -> Int {
        choice == 0 ? (options.first ?? 0) : effective(choice: choice, options: options)
    }

    /// 행을 고른 뒤 저장할 값: 체크가 옮겨 갈 때만 그 행, 이미 체크된 행을 다시 고르면 저장값 그대로.
    static func choice(afterPicking row: Int, saved: Int, options: [Int]) -> Int {
        row == effective(choice: saved, options: options) ? saved : row
    }

    /// preferredMaximumResolution은 가로·세로를 각각 비교하므로 정사각형으로 건다(가로·세로 방송 공통).
    /// SOOP 사다리는 16:9(세로 방송은 9:16)라는 실측을 전제로 한다 — 4:3 사다리라면 한 등급 위까지 통과한다.
    /// 자동은 1080p 등급까지 — 가로 방송은 기존 1920x1080 상한과 같은 variant만 허용한다.
    static func cap(for choice: Int) -> CGSize {
        let side = CGFloat((choice == 0 ? 1080 : choice) * 16 / 9)
        return CGSize(width: side, height: side)
    }

    /// 배지 문구 — 팝업의 체크 행을 줄인 것. 1줄 = 실제 화질(자동이면 '자동(X)'),
    /// 2줄 = 수동 행이 체크돼 있는데 실제가 다를 때만 '{체크 행} 선택됨'(팝업의 '✓ 행 / 현재 X'와 같은 내용).
    static func badgeLines(actual: Int, choice: Int, options: [Int]) -> (first: String, second: String?) {
        let checked = effective(choice: choice, options: options)
        if checked == 0 { return ("자동(\(label(actual)))", nil) }
        if actual != checked { return (label(actual), "\(label(checked)) 선택됨") }
        return (label(actual), nil)
    }

    /// 체크 행의 부제: '자동'이면 늘 '현재 X', 수동 행이면 실제가 다를 때만. 실제를 모르면 없음.
    static func rowSubtitle(row: Int, actual: Int) -> String? {
        guard actual > 0, row == 0 || row != actual else { return nil }
        return "현재 \(label(actual))"
    }

    // MARK: master playlist 파싱 (화질 고정용)

    /// master playlist 본문에서 (해상도, media playlist 절대 URL)을 뽑는다.
    /// tvOS 17에는 AVAssetVariant.url이 없어 직접 파싱한다. SOOP master의 특징(docs/20260930-quality-selection-v1.md §1-4):
    /// CRLF 줄바꿈, `#EXT-X-STREAM-INF:` 다음 줄이 상대 URI(줄 끝에 ','가 붙기도 함), 속성은 RESOLUTION·BANDWIDTH·NAME.
    static func renditions(fromPlaylist text: String, baseURL: URL) -> [(size: CGSize, url: URL)] {
        // Character.isNewline은 CR·LF·CRLF(단일 grapheme)·기타 유니코드 줄바꿈을 모두 처리한다.
        // SOOP master는 CRLF라 "\n"/"\r" 비교로는 한 줄도 나뉘지 않는다.
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var result: [(size: CGSize, url: URL)] = []
        var i = 0
        while i < lines.count {
            guard lines[i].hasPrefix("#EXT-X-STREAM-INF:"), let size = resolution(inStreamInf: lines[i]) else {
                i += 1; continue
            }
            // 다음 비(非)주석·비어있지 않은 줄이 URI
            var j = i + 1
            while j < lines.count, lines[j].isEmpty || lines[j].hasPrefix("#") { j += 1 }
            if j < lines.count {
                var uri = lines[j]
                if uri.hasSuffix(",") { uri = String(uri.dropLast()) }          // SOOP은 URI 줄 끝에 ','를 붙인다
                uri = uri.trimmingCharacters(in: .whitespaces)
                if let url = URL(string: uri, relativeTo: baseURL)?.absoluteURL {
                    result.append((size, url))
                }
            }
            i = j + 1
        }
        return result
    }

    private static func resolution(inStreamInf line: String) -> CGSize? {
        guard let value = attribute("RESOLUTION", in: line) else { return nil }
        let parts = value.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// `KEY=value` 추출. value가 따옴표로 묶여 있으면(예: NAME="hd") 그 안을, 아니면 콤마 또는 줄 끝까지.
    private static func attribute(_ key: String, in line: String) -> String? {
        guard let range = line.range(of: key + "=") else { return nil }
        let rest = line[range.upperBound...]
        if rest.first == "\"" {
            let body = rest.dropFirst()
            guard let end = body.firstIndex(of: "\"") else { return nil }
            return String(body[..<end])
        }
        if let end = rest.firstIndex(of: ",") { return String(rest[..<end]) }
        return String(rest)
    }
}
