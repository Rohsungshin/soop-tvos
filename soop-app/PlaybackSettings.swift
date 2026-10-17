import Foundation

// MARK: - 재생 설정 (v1)
//
// 설정 탭과 플레이어 트랜스포트 바의 '화질' 메뉴가 **같은 값 하나**를 본다.
// 저장소는 예전부터 플레이어가 쓰던 UserDefaults 키 `soop.player.quality` 그대로다
// (0 = 자동, 그 외 = 짧은 변 등급 360/540/720/1080). 설정 화면을 위해 키를 새로 파면
// 두 화면이 서로 다른 값을 갖게 되므로 키는 늘리지 않고 접근만 이 한곳으로 모은다.
//
// 모드는 저장하지 않는다 — quality 값에서 파생된다(0이면 자동, 아니면 고정).
// 다만 '자동'으로 돌렸다가 다시 '고정'을 고를 때 직전에 고르던 등급으로 돌아가야 하므로
// 마지막 고정 등급만 따로 기억한다(`soop.playback.fixedQuality`).

enum PlaybackMode: Int, CaseIterable {
    case auto = 0
    case fixed = 1
    case native = 2

    var label: String {
        switch self {
        case .auto:   return "자동 (화질 자동 전환)"
        case .fixed:  return "고정 화질"
        case .native: return "네이티브 원본 (1080p)"
        }
    }

    var detail: String {
        switch self {
        case .auto:
            return "망 상태에 따라 화질이 자동으로 바뀝니다. 끊김이 가장 적습니다"
        case .fixed:
            return "고른 화질로 고정합니다. 자동 전환이 없는 대신 망이 느리면 끊길 수 있습니다"
        case .native:
            return "SOOP 미디어 서버에서 원본을 직접 받아 국내에서도 1080p로 봅니다. 비공식 경로라 실패 시 일반 재생으로 전환됩니다"
        }
    }
}

enum PlaybackSettings {

    /// 플레이어가 예전부터 쓰던 키. 설정 탭도 이 값을 읽고 쓴다.
    private static let qualityKey = "soop.player.quality"
    /// '자동'으로 돌려 둔 동안 기억해 두는 직전 고정 등급.
    private static let fixedQualityKey = "soop.playback.fixedQuality"
    /// 재생 방식(auto/fixed/native). 네이티브 추가로 신설.
    private static let modeKey = "soop.playback.mode"

    /// 설정 화면에 노출하는 고정 등급 사다리. 방송이 실제로 주는 등급만 적용되며,
    /// 고른 등급이 없으면 그 이하 중 가장 높은 등급으로 내려간다(QualityLadder.effective).
    static let fixedLadder = [1080, 720, 540, 360]

    /// 0 = 자동, 그 외 = 짧은 변 등급. 플레이어의 화질 메뉴와 공유하는 단일 진실.
    /// 수동 등급을 넣으면 '마지막 고정 등급'도 함께 갱신해, 설정 화면이 플레이어에서 고른 값을 그대로 보여 준다.
    static var quality: Int {
        get { UserDefaults.standard.integer(forKey: qualityKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: qualityKey)
            if newValue != 0 { UserDefaults.standard.set(newValue, forKey: fixedQualityKey) }
        }
    }

    /// 마지막으로 고른 고정 등급(기본 1080 = 방송이 주는 가장 높은 등급으로 고정).
    static var fixedQuality: Int {
        let saved = UserDefaults.standard.integer(forKey: fixedQualityKey)
        return fixedLadder.contains(saved) ? saved : 1080
    }

    /// 재생 방식. 저장값을 그대로 쓴다(네이티브는 quality와 독립).
    /// 예전 버전에는 모드 저장이 없었고 quality에서 파생했으므로, 저장값이 없으면 예전 파생 규칙을 따른다.
    static var mode: PlaybackMode {
        get {
            if UserDefaults.standard.object(forKey: modeKey) != nil {
                let raw = UserDefaults.standard.integer(forKey: modeKey)
                return PlaybackMode(rawValue: raw) ?? (quality == 0 ? .auto : .fixed)
            }
            return quality == 0 ? .auto : .fixed
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            if UserDefaults.standard.object(forKey: qualityKey) == nil {
                quality = (newValue == .auto) ? 0 : fixedQuality
            }
        }
    }
}
