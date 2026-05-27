import UIKit
import AVKit
import AVFoundation

// MARK: - SOOP HLS 재생기
//
// AVPlayerViewController를 풀스크린으로 표시.
// streamInfo.viewURL 을 그대로 AVPlayer 에 넘긴다.
// SOOP의 TS URL은 ?data= 인증 토큰이 URL에 포함돼 있어 별도 헤더 없이도 재생 가능 (이론상).
// Referer 헤더가 필요하면 AVURLAsset 옵션으로 추가한다.

final class PlayerViewController: UIViewController {

    var streamInfo: StreamInfo?

    private var avVC: AVPlayerViewController!
    private var statusLabel: UILabel!
    private var resolutionLabel: UILabel!
    private var observer: NSKeyValueObservation?
    private var presentationObserver: NSKeyValueObservation?
    private var hideResolutionTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        statusLabel = UILabel()
        statusLabel.text = "스트림 연결 중..."
        statusLabel.textColor = .white
        statusLabel.font = UIFont.systemFont(ofSize: 28, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -80),
        ])

        // 해상도 표시 라벨 (우측 상단)
        resolutionLabel = UILabel()
        resolutionLabel.text = "—"
        resolutionLabel.textColor = .white
        resolutionLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        resolutionLabel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        resolutionLabel.textAlignment = .center
        resolutionLabel.layer.cornerRadius = 8
        resolutionLabel.layer.masksToBounds = true
        resolutionLabel.numberOfLines = 2
        resolutionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resolutionLabel)
        NSLayoutConstraint.activate([
            resolutionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            resolutionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -50),
            resolutionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            resolutionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])

        startPlayback()
    }

    private func startPlayback() {
        guard let info = streamInfo else {
            statusLabel.text = "스트림 정보 없음"
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
        addChild(vc)
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
        avVC = vc

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
                    self.statusLabel.isHidden = true
                    player.play()
                    print("[Player] readyToPlay → playing")
                    self.startObservingResolution(item: it)
                case .failed:
                    let err = it.error
                    print("[Player] FAILED: \(String(describing: err))")
                    self.statusLabel.text = "재생 실패\n\(info.bjNick) - \(info.title)\n\n\(err?.localizedDescription ?? "")\n\nMenu 키로 돌아가기"
                    self.tryFallback(info: info)
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
                let quality: String
                switch h {
                case ...360: quality = "SD"
                case ...540: quality = "HD"
                case ...720: quality = "HD+"
                case ...1080: quality = "FHD"
                case ...1440: quality = "QHD"
                default: quality = "UHD"
                }
                self.resolutionLabel.text = " \(quality)\n \(w)×\(h) "
                self.resolutionLabel.alpha = 1
                print("[Player] presentationSize: \(w)x\(h) (\(quality))")
            }
        }
    }

    /// primary viewURL(TS) 실패 시 timeShiftURL(view_url+aid)로 즉시 swap.
    /// 1080p 시도 실패 → 540p로 안정 재생.
    private var didFallback = false
    private func tryFallback(info: StreamInfo) {
        guard !didFallback else {
            print("[Player] fallback already tried — giving up")
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
                case .failure(let err):
                    self.statusLabel.text = "재생 실패 (fallback 실패)\n\(err)\n\nMenu로 돌아가기"
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

        // fallback 라벨 표시
        resolutionLabel.text = " FALLBACK\n — "
        resolutionLabel.alpha = 1
        print("[Player] swapPlayerURL → fallback URL: \(url.absoluteString.prefix(140))")

        // fallback 아이템에도 상태·해상도 KVO 부착
        observer = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch it.status {
                case .readyToPlay:
                    self.statusLabel.isHidden = true
                    self.startObservingResolution(item: it)
                case .failed:
                    print("[Player] Fallback FAILED: \(String(describing: it.error))")
                    self.statusLabel.text = "재생 실패 (fallback 실패)\n\nMenu로 돌아가기"
                    self.statusLabel.isHidden = false
                default:
                    break
                }
            }
        }

        statusLabel.text = "fallback 재생 중..."
        statusLabel.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusLabel.isHidden = true
        }
    }

    deinit {
        observer?.invalidate()
        presentationObserver?.invalidate()
        hideResolutionTimer?.invalidate()
        avVC?.player?.pause()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .menu {
                avVC.player?.pause()
                dismiss(animated: true)
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}
