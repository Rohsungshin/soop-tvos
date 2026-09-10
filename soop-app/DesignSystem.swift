import UIKit

// MARK: - SOOP tvOS Design System
//
// 기획서 v2 기반 디자인 토큰 모음.
// 색상 / 타이포그래피 / 간격 / 코너 / 카드 사이즈 / 레이아웃 / 버튼 인셋 / 포커스 효과 등
// 매직 넘버 / 하드코딩 컬러 대신 이 파일의 토큰을 사용한다.

enum DS {

    // MARK: 색상 (다크 모드 전용)
    enum Colors {
        /// 메인 배경 #0A0A0C — 순 검정 대신 살짝 따뜻한 흑
        static let background = UIColor(red: 10/255,  green: 10/255,  blue: 12/255,  alpha: 1)
        /// 카드 기본 배경 #141418
        static let surface = UIColor(red: 20/255,  green: 20/255,  blue: 24/255,  alpha: 1)
        /// 포커스/elevated 카드 #202026
        static let surfaceElevated = UIColor(red: 32/255,  green: 32/255,  blue: 38/255,  alpha: 1)
        /// 썸네일 위 오버레이 (55% 어둠) — 로딩 dim에서 사용
        static let overlay = UIColor(white: 0, alpha: 0.55)
        /// 스켈레톤 placeholder #1C1C20
        static let skeleton = UIColor(red: 28/255,  green: 28/255,  blue: 32/255,  alpha: 1)

        /// LIVE 배지 빨강 #F23C3C
        static let live = UIColor(red: 242/255, green: 60/255,  blue: 60/255,  alpha: 1)
        /// SOOP 푸른 액센트 #3680FF (포커스 보더 / CTA)
        static let primary = UIColor(red: 54/255,  green: 128/255, blue: 255/255, alpha: 1)
        /// 시청자수 점 강조 #FFC300
        static let viewerDot = UIColor(red: 255/255, green: 195/255, blue: 0/255,   alpha: 1)

        /// 본문/제목 흰색
        static let textPrimary = UIColor.white
        /// 보조 텍스트 #B4B4BC
        static let textSecondary = UIColor(red: 180/255, green: 180/255, blue: 188/255, alpha: 1)
        /// 오프라인/disabled 텍스트 #787880
        static let textTertiary = UIColor(red: 120/255, green: 120/255, blue: 128/255, alpha: 1)
        /// 오프라인 BJ 이름 #8C8C94
        static let textOffline = UIColor(red: 140/255, green: 140/255, blue: 148/255, alpha: 1)

        /// 구분선 (white 8% alpha)
        static let divider = UIColor(white: 1, alpha: 0.08)

        /// 시청자수 배지 배경
        static let viewerBadgeBackground = UIColor(white: 0, alpha: 0.65)

        /// 오프라인 카드 흑백 톤
        static let offlineImageTint = UIColor(white: 0.55, alpha: 1)
        /// 오프라인 포커스 보더 (회색)
        static let focusBorderOffline = UIColor(red: 120/255, green: 120/255, blue: 128/255, alpha: 1)

        /// 음량 HUD의 빈 세그먼트 (white 22% alpha)
        static let volumeSegmentEmpty = UIColor(white: 1, alpha: 0.22)
    }

    // MARK: 타이포그래피
    enum Typography {
        /// 화면 최상단 메인 헤더 ("LIVE", "MY")
        static let hero = UIFont.systemFont(ofSize: 64, weight: .bold)
        /// 섹션 헤더 (Explore "인기 카테고리" 등)
        static let section = UIFont.systemFont(ofSize: 36, weight: .semibold)
        /// 28pt subsection — 가로 캐러셀 섹션 헤더, 빈상태 line1, 에러카드 title 등
        static let subsection = UIFont.systemFont(ofSize: 28, weight: .semibold)
        /// 카테고리/이전 헤더 (← 카테고리명)
        static let title = UIFont.systemFont(ofSize: 48, weight: .bold)
        /// 큰 카드 제목 (방송 제목) — BJ 16pt와 10pt 차이로 위계 강화
        static let cardTitleLarge = UIFont.systemFont(ofSize: 26, weight: .semibold)
        /// 중간 카드 제목 (카테고리명, 방송 제목)
        static let cardTitle = UIFont.systemFont(ofSize: 22, weight: .semibold)
        /// 일반 본문
        static let body = UIFont.systemFont(ofSize: 20, weight: .regular)
        /// 헤더 보조 (실시간 인기 카테고리 등)
        static let subhead = UIFont.systemFont(ofSize: 20, weight: .regular)
        /// 18pt subcaption — 오프라인 BJ 닉네임 / 최근 검색어
        static let subcaption = UIFont.systemFont(ofSize: 18, weight: .semibold)
        /// 캡션 (BJ 닉네임 등)
        static let caption = UIFont.systemFont(ofSize: 16, weight: .medium)
        /// 배지 (LIVE / 시청자수) — 16pt bold, 3m 거리 가독성 강화
        static let badge = UIFont.systemFont(ofSize: 16, weight: .bold)
        /// 작은 메타정보 (Pre-roll hint 등)
        static let tiny = UIFont.systemFont(ofSize: 14, weight: .semibold)
    }

    // MARK: 간격 (8pt 기반)
    enum Spacing {
        static let xs: CGFloat  = 8
        static let sm: CGFloat  = 16
        static let md: CGFloat  = 24
        static let lg: CGFloat  = 40
        static let xl: CGFloat  = 64
        static let xxl: CGFloat = 96
    }

    // MARK: 코너 반경
    enum Corner {
        static let card: CGFloat    = 18
        static let badge: CGFloat   = 6
        static let button: CGFloat  = 16
        static let modal: CGFloat   = 24
    }

    // MARK: 레이아웃 토큰 (v2 신규)
    enum Layout {
        /// 좌우 콘텐츠 마진 (Spacing.xl과 동일하지만 의미 명시)
        static let contentSideMargin: CGFloat = 64
        /// 섹션 헤더 높이 (MyVC 등)
        static let sectionHeaderHeight: CGFloat = 80
        /// safeArea 위 헤더 시작 offset
        static let headerTopOffset: CGFloat = 30
        /// 헤더 ↔ 그리드 사이 여백
        static let gridTopGap: CGFloat = 24
        /// 그리드 상단 inset
        static let gridTopInset: CGFloat = 32
        /// 그리드 하단 inset
        static let gridBottomInset: CGFloat = 72
        /// 1080p 화면 너비 (참조용)
        static let screenWidth: CGFloat = 1920
        /// 1080p 화면 높이
        static let screenHeight: CGFloat = 1080
        /// 메시지 카드 너비 (LoadingOverlayView 등)
        static let messageCardWidth: CGFloat = 480
        /// 메시지 카드 높이
        static let messageCardHeight: CGFloat = 200
        /// statusLabel 좌우 여백 (헤더와 동일선)
        static let statusSideMargin: CGFloat = 60
    }

    // MARK: 카드 사이즈 (1080p 기준)
    enum CardSize {
        /// 카테고리 카드 — 가로 강조, 2줄 제목 지원
        static let category   = CGSize(width: 320, height: 240)
        /// 라이브 방송 카드 (제목 26pt 2줄 + BJ 16pt) — 정보 영역 ~115pt 확보
        static let broadcast  = CGSize(width: 400, height: 340)
        /// MY 탭 라이브 방송 카드 — broadcast와 동일 위계
        static let myLive     = CGSize(width: 380, height: 320)
        /// MY 탭 오프라인 BJ 카드
        static let myOffline  = CGSize(width: 240, height: 280)
        /// Explore 인기 캐러셀 카드 — broadcast 카드와 동일
        static let explorePopular = CGSize(width: 400, height: 340)
        /// Explore 인기 카테고리 캐러셀 카드 — 일반 카테고리와 동일
        static let exploreCategory = CGSize(width: 320, height: 240)
        /// HOME/Explore 캐러셀용 작은 라이브 카드
        static let miniLive       = CGSize(width: 320, height: 230)
        /// HOME 추천 BJ 카드 (작은 프로필 카드)
        static let recommendBJ    = CGSize(width: 200, height: 240)
        /// 검색 결과 카드 (LiveBroadcastCell과 동일)
        static let searchResult   = CGSize(width: 400, height: 340)
    }

    // MARK: 버튼 인셋 (v2 신규)
    enum ButtonInsets {
        /// CTA 버튼 (다시 시도, 새로고침, 검색 등) — UIButton.Configuration용
        static let cta = NSDirectionalEdgeInsets(top: 14, leading: 36, bottom: 14, trailing: 36)
    }
}

// MARK: - 포커스 효과 유틸
//
// 다크 배경(#0A0A0C)에서 검은 그림자는 사실상 안 보인다 — 3m 시청 거리에서
// 포커스가 한눈에 들어오도록 다음 3가지를 결합:
//   1. 큰 스케일 (1.10) — 인접 카드와 명확한 차이
//   2. SOOP 브랜드 블루 보더 (4pt) — 카드 외곽 윤곽선
//   3. 블루 글로우 (centered shadow, radius 36) — 다크 배경 위 발광 효과
//   4. 카드 배경 surfaceElevated 승격 — 미세한 밝기 전환

enum FocusEffect {
    /// 카드 표준 포커스 — scale + 블루 글로우 + 블루 보더
    static func apply(to cell: UICollectionViewCell, focused: Bool) {
        if focused {
            cell.transform = CGAffineTransform(scaleX: 1.10, y: 1.10)
            cell.contentView.backgroundColor = DS.Colors.surfaceElevated
            cell.contentView.layer.borderColor = DS.Colors.primary.cgColor
            cell.contentView.layer.borderWidth = 4
            // 블루 글로우 (centered shadow = halo effect)
            cell.layer.shadowColor   = DS.Colors.primary.cgColor
            cell.layer.shadowOpacity = 0.85
            cell.layer.shadowOffset  = .zero
            cell.layer.shadowRadius  = 36
            cell.layer.shouldRasterize = false
        } else {
            cell.transform = .identity
            cell.contentView.backgroundColor = DS.Colors.surface
            cell.contentView.layer.borderWidth = 0
            cell.layer.shadowOpacity = 0
        }
    }

    /// 오프라인/비활성 카드 포커스 — 회색 글로우 (라이브와 시각 차별화)
    static func applyOffline(to cell: UICollectionViewCell, focused: Bool) {
        if focused {
            cell.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            cell.contentView.layer.borderColor = DS.Colors.focusBorderOffline.cgColor
            cell.contentView.layer.borderWidth = 4
            cell.layer.shadowColor   = DS.Colors.focusBorderOffline.cgColor
            cell.layer.shadowOpacity = 0.6
            cell.layer.shadowOffset  = .zero
            cell.layer.shadowRadius  = 28
        } else {
            cell.transform = .identity
            cell.contentView.layer.borderWidth = 0
            cell.layer.shadowOpacity = 0
        }
    }

    /// 보더 포커스 — 검색 진입 / 최근 검색어 칩 같은 비-카드 요소용
    static func applyBorder(to view: UIView, focused: Bool) {
        if focused {
            view.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            view.layer.borderColor = DS.Colors.primary.cgColor
            view.layer.borderWidth = 3
            view.layer.shadowColor = DS.Colors.primary.cgColor
            view.layer.shadowOpacity = 0.6
            view.layer.shadowOffset = .zero
            view.layer.shadowRadius = 20
        } else {
            view.transform = .identity
            view.layer.borderWidth = 0
            view.layer.shadowOpacity = 0
        }
    }
}

// MARK: - 공용 헬퍼

extension Int {
    /// 시청자수 한국식 포맷: 12345 → "1.2만", 980 → "980"
    func koreanCount() -> String {
        if self >= 10000 {
            return String(format: "%.1f만", Double(self) / 10000)
        }
        return "\(self)"
    }
}

/// 목록 갱신 경쟁 방지용 요청 세대 토큰.
///
/// 앱의 모든 목록 로더는 취소가 없는 fire-and-forget 호출이라, 새로고침을 연달아 하거나
/// 로그인 알림 같은 자동 트리거가 겹치면 **먼저 보낸 오래된 요청이 나중에 도착해** 최신 목록을
/// 덮어쓸 수 있다. 로드 시작 시 `begin()`으로 세대를 올려 토큰을 받고, 응답을 반영하기 직전에
/// `isCurrent(_:)`로 그 사이 더 새로운 로드가 시작되지 않았는지 확인한다.
///
/// 모든 로더는 메인 스레드에서 시작하고 콜백도 메인 큐로 넘어온 뒤에 검사하므로 별도 동기화는 없다.
struct RequestEpoch {
    private var current = 0

    /// 새 로드 시작 — 이후 이 토큰보다 오래된 응답은 모두 무효가 된다.
    mutating func begin() -> Int {
        current += 1
        return current
    }

    /// 이 토큰이 아직 가장 최신 로드의 것인가.
    func isCurrent(_ token: Int) -> Bool { token == current }
}

// MARK: - 헤더 컨테이너 (재사용 가능)

/// 화면 최상단 헤더 — 큰 타이틀 + 작은 서브타이틀.
/// LIVE / MY / 탐색 화면에서 공통으로 사용.
final class SectionHeaderView: UIView {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String, titleFont: UIFont = DS.Typography.hero) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = titleFont
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.text = subtitle
        subtitleLabel.textColor = DS.Colors.textSecondary
        subtitleLabel.font = DS.Typography.subhead
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSubtitle(_ text: String) {
        subtitleLabel.text = text
    }
}

// MARK: - 토스트 (하단 슬라이드 인)

/// 화면 하단에 짧게 나타났다 사라지는 메시지.
/// 모달 alert를 대체. 사용처: 오프라인 BJ 선택, 재생 실패 등.
final class ToastView: UIView {

    private let label = UILabel()

    static func show(in parent: UIView, message: String, duration: TimeInterval = 2.0) {
        let toast = ToastView(message: message)
        parent.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.bottomAnchor, constant: -60),
        ])

        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 30)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            toast.alpha = 1
            toast.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: duration, options: .curveEaseIn) {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 30)
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }

    private init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = DS.Colors.surfaceElevated
        layer.cornerRadius = DS.Corner.button
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 16

        label.text = message
        label.textColor = DS.Colors.textPrimary
        label.font = DS.Typography.body
        label.textAlignment = .center
        // v4.4: 19+ 인증 안내 같은 멀티라인 메시지 지원
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 재생 에러 → 사용자 메시지 매핑 (v4.4)

extension UIViewController {
    /// fetchStreamInfo 실패 시 호출. SOOPAPIError를 구체 토스트 메시지로 변환한다.
    func showPlaybackError(_ err: SOOPAPIError) {
        let message: String
        switch err {
        case .adultVerificationRequired:
            message = "성인 인증이 필요한 방송입니다\nSOOP 웹에서 본인인증 + 성인 콘텐츠 보기 설정 후 다시 시도하세요"
        case .notLive:
            message = "방송이 종료되었거나 지금 라이브가 아닙니다"
        case .streamUnavailable(let why):
            message = "재생할 수 없습니다 (\(why))"
        default:
            message = "재생할 수 없습니다"
        }
        ToastView.show(in: view, message: message, duration: 3.5)
    }

    /// 비밀번호 방송(BPWD=Y) 에러면 tvOS 비밀번호 입력 알림을 띄우고 입력값으로 `retry`를 호출한다.
    /// 비번 관련 에러가 아니면 아무 것도 안 하고 false를 반환 → 호출부가 showPlaybackError로 폴백.
    /// - returns: 이 에러를 비밀번호 흐름으로 처리했으면 true.
    @discardableResult
    func promptPassword(for err: SOOPAPIError, bjNick: String,
                        retry: @escaping (String) -> Void) -> Bool {
        let message: String
        switch err {
        case .passwordRequired:  message = "\(bjNick) 님의 방송은 비밀번호가 필요합니다"
        case .passwordIncorrect: message = "비밀번호가 올바르지 않습니다. 다시 입력하세요"
        default:                 return false
        }
        let alert = UIAlertController(title: "비밀번호 방송", message: message, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.isSecureTextEntry = true
            tf.placeholder = "비밀번호"
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "입장", style: .default) { [weak self, weak alert] _ in
            let pwd = alert?.textFields?.first?.text ?? ""
            guard !pwd.isEmpty else {
                // 빈 값으로 입장하면 UIAlertController는 이미 닫히는 중이라 조용한 dead-end가 된다.
                // 사용자가 흐름에서 이탈하지 않도록 프롬프트를 다시 띄운다. (취소로만 빠져나갈 수 있음)
                DispatchQueue.main.async {
                    self?.promptPassword(for: err, bjNick: bjNick, retry: retry)
                }
                return
            }
            retry(pwd)
        })
        present(alert, animated: true)
        return true
    }
}

// MARK: - 공용 로딩 오버레이 (v2 신규)

/// 화면 가운데 카드 형태의 로딩 오버레이.
/// LiveListVC / ExploreVC / MyVC / HomeVC / SearchVC 등이 모두 사용.
final class LoadingOverlayView: UIView {

    private let card = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    @discardableResult
    static func show(in parent: UIView, message: String) -> LoadingOverlayView {
        let overlay = LoadingOverlayView(message: message)
        parent.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: parent.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
        overlay.alpha = 0
        UIView.animate(withDuration: 0.15) { overlay.alpha = 1 }
        return overlay
    }

    func dismiss() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }

    private init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DS.Colors.overlay

        card.backgroundColor = DS.Colors.surfaceElevated
        card.layer.cornerRadius = DS.Corner.modal
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        spinner.color = DS.Colors.textPrimary
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(spinner)

        messageLabel.text = message
        messageLabel.textColor = DS.Colors.textPrimary
        messageLabel.font = DS.Typography.body
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: DS.Layout.messageCardWidth),
            card.heightAnchor.constraint(equalToConstant: DS.Layout.messageCardHeight),

            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: DS.Spacing.lg),

            messageLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: DS.Spacing.md),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: DS.Spacing.md),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -DS.Spacing.md),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 공용 로딩 스켈레톤 (v2 신규)

/// 데이터 로딩 중 빈 화면 대신 카드 placeholder를 표시.
/// shimmer 애니메이션으로 "곧 콘텐츠가 채워진다"는 신호를 준다.
final class LoadingSkeletonView: UIView {

    enum Style {
        /// 카테고리 그리드 (320x240 × 5열 × 2행)
        case categoryGrid
        /// 방송 그리드 (400x320 × 4열 × 2행)
        case broadcastGrid
        /// 가로 캐러셀 (320x230 × 5개)
        case carousel
    }

    private let style: Style
    private var cardLayers: [CALayer] = []
    private var shimmerLayers: [CAGradientLayer] = []

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DS.Colors.background
        isUserInteractionEnabled = false
        buildCards()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildCards() {
        let cardSize: CGSize
        let columns: Int
        let rows: Int
        switch style {
        case .categoryGrid:
            cardSize = DS.CardSize.category
            columns = 5
            rows = 2
        case .broadcastGrid:
            cardSize = DS.CardSize.broadcast
            columns = 4
            rows = 2
        case .carousel:
            cardSize = DS.CardSize.miniLive
            columns = 5
            rows = 1
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = DS.Spacing.lg
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Layout.gridTopInset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Layout.contentSideMargin),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DS.Layout.contentSideMargin),
        ])

        for _ in 0..<rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = DS.Spacing.md
            row.alignment = .top
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)

            for _ in 0..<columns {
                let card = UIView()
                card.backgroundColor = DS.Colors.skeleton
                card.layer.cornerRadius = DS.Corner.card
                card.translatesAutoresizingMaskIntoConstraints = false
                card.clipsToBounds = true
                row.addArrangedSubview(card)
                NSLayoutConstraint.activate([
                    card.widthAnchor.constraint(equalToConstant: cardSize.width),
                    card.heightAnchor.constraint(equalToConstant: cardSize.height),
                ])
                cardLayers.append(card.layer)
            }
        }
    }

    func startAnimating() {
        layoutIfNeeded()
        // 카드별 shimmer gradient 추가
        for layer in cardLayers {
            let gradient = CAGradientLayer()
            gradient.frame = layer.bounds
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            let base = DS.Colors.skeleton.cgColor
            let highlight = UIColor(white: 0.25, alpha: 1).cgColor
            gradient.colors = [base, highlight, base]
            gradient.locations = [0.0, 0.5, 1.0]
            layer.addSublayer(gradient)
            shimmerLayers.append(gradient)

            let anim = CABasicAnimation(keyPath: "locations")
            anim.fromValue = [-1.0, -0.5, 0.0]
            anim.toValue = [1.0, 1.5, 2.0]
            anim.duration = 1.5
            anim.repeatCount = .infinity
            gradient.add(anim, forKey: "shimmer")
        }
    }

    func stopAnimating(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        }, completion: { _ in
            for g in self.shimmerLayers {
                g.removeAllAnimations()
                g.removeFromSuperlayer()
            }
            self.shimmerLayers.removeAll()
            self.removeFromSuperview()
            completion?()
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, layer) in cardLayers.enumerated() where i < shimmerLayers.count {
            shimmerLayers[i].frame = layer.bounds
        }
    }
}

// MARK: - 공용 오류 상태 뷰 (v5 신규)

/// 데이터 로드 실패 시 화면 중앙에 표시 — 아이콘 + 안내 문구(+ 보조 문구) + 포커스 가능한 "다시 시도" 버튼.
/// HOME / 탐색 / MY 탭에서 공통 사용. 레이아웃은 MyViewController.showEmptyState()와 동일 구조.
/// VC에서 centerX/centerY로 배치하고, preferredFocusEnvironments로 버튼에 포커스를 보낸다.
final class ErrorStateView: UIView {

    /// "다시 시도" 선택 시 호출. 연타 방지를 위해 첫 선택 시 버튼이 비활성화된다.
    var onRetry: (() -> Void)?

    private let retryButton: ErrorRetryButton

    // MyViewController.showEmptyState()와 동일 확정값 — DS 토큰 없음 (디자인 명세 §4-4)
    private static let errorIconSize: CGFloat = 80
    private static let errorContainerMaxWidth: CGFloat = 720
    private static let errorTitleSubtitleGap: CGFloat = 8

    init(icon: String, title: String, subtitle: String? = nil) {
        var btnConfig = UIButton.Configuration.filled()
        btnConfig.baseBackgroundColor = DS.Colors.primary
        btnConfig.baseForegroundColor = DS.Colors.textPrimary
        btnConfig.contentInsets = DS.ButtonInsets.cta
        btnConfig.cornerStyle = .fixed
        btnConfig.background.cornerRadius = DS.Corner.button
        btnConfig.attributedTitle = AttributedString("다시 시도", attributes: AttributeContainer([
            .font: DS.Typography.cardTitle
        ]))
        retryButton = ErrorRetryButton(configuration: btnConfig)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = DS.Colors.textTertiary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = DS.Colors.textPrimary
        titleLabel.font = DS.Typography.subsection
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // 포커스 보더가 버튼의 둥근 배경을 따라가도록
        retryButton.layer.cornerRadius = DS.Corner.button
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryTapped), for: .primaryActionTriggered)
        addSubview(retryButton)

        // 서브타이틀은 MY 탭처럼 조치 안내가 필요한 화면만 사용
        var buttonTopAnchor = titleLabel.bottomAnchor
        if let subtitle = subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.textColor = DS.Colors.textSecondary
            subtitleLabel.font = DS.Typography.body
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 2
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subtitleLabel)
            NSLayoutConstraint.activate([
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Self.errorTitleSubtitleGap),
                subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            buttonTopAnchor = subtitleLabel.bottomAnchor
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.errorContainerMaxWidth),

            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.errorIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.errorIconSize),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: DS.Spacing.md),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            retryButton.topAnchor.constraint(equalTo: buttonTopAnchor, constant: DS.Spacing.lg),
            retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            retryButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 오류 뷰 표시 직후 포커스가 "다시 시도" 버튼으로 가도록
    override var preferredFocusEnvironments: [UIFocusEnvironment] { [retryButton] }

    @objc private func retryTapped() {
        // 연타 방지 — 재시도 시 뷰 자체가 제거/재표시되므로 재활성화는 불필요
        retryButton.isEnabled = false
        onRetry?()
    }
}

/// ErrorStateView 전용 "다시 시도" 버튼 — 포커스 시 FocusEffect.applyBorder 적용
private final class ErrorRetryButton: UIButton {
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

// MARK: - 이미지 캐시 + UIImageView extension (v2 신규)

/// 메모리 + URLCache 기반 간단한 이미지 캐시.
/// 6곳에서 사용되던 URLSession.shared.dataTask 직접 호출을 일괄 교체.
final class ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSURL, UIImage>()

    private init() {
        memory.totalCostLimit = 50 * 1024 * 1024  // 50MB
        memory.countLimit = 200
    }

    func image(for url: URL) -> UIImage? {
        return memory.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func clear() {
        memory.removeAllObjects()
    }
}

/// 토큰 보관용 associated key
private var kImageLoadTokenKey: UInt8 = 0

extension UIImageView {

    /// 현재 진행 중인 로드 요청의 토큰. 셀 재사용 시 stale response 무시용.
    private var currentLoadToken: UUID? {
        get { objc_getAssociatedObject(self, &kImageLoadTokenKey) as? UUID }
        set { objc_setAssociatedObject(self, &kImageLoadTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 캐시 우선 로드.
    /// - placeholder: 이미지가 없을 동안 보여줄 배경색
    /// - completion: success 여부 (디스크/메모리 hit 포함). main 큐에서 호출됨.
    @discardableResult
    func loadImage(from url: URL?,
                   placeholder: UIColor = DS.Colors.skeleton,
                   completion: ((Bool) -> Void)? = nil) -> UUID? {
        // 셀 재사용 케이스: 이전 토큰 무효화
        let token = UUID()
        currentLoadToken = token

        self.image = nil
        self.backgroundColor = placeholder

        guard let url = url else {
            completion?(false)
            return nil
        }

        // 메모리 캐시 hit → 즉시 적용
        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            completion?(true)
            return nil
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else {
                DispatchQueue.main.async {
                    guard let self = self, self.currentLoadToken == token else { return }
                    completion?(false)
                }
                return
            }
            ImageCache.shared.store(img, for: url)
            DispatchQueue.main.async {
                guard let self = self, self.currentLoadToken == token else { return }
                self.image = img
                completion?(true)
            }
        }.resume()

        return token
    }

    /// 진행 중인 요청 취소 (강제 무효화). 별도 cancel은 불필요하지만 명시적 호출용.
    func cancelImageLoad() {
        currentLoadToken = nil
        self.image = nil
    }
}
