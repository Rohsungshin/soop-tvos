# Apple TV 리모컨 음량 버튼 — 분석·기획·구현·검수·설치 보고서

- **문서 버전**: v1
- **작성일**: 2026-09-06
- **기준 커밋**: b5e5211 (main) + 미커밋 작업 트리 변경분 (`soop-app/PlayerViewController.swift`, `soop-app/DesignSystem.swift`)
- **요청**: "애플티비 리모트의 음량 버튼이 동작 안 하고 있어. 해당 버튼이 동작되도록 기능 구현을 해줘."
- **설치 대상**: Apple TV 4K 2세대 "큰방" (tvOS 26.6)

---

## 0. 결론 요약

| 항목 | 결론 |
|------|------|
| Siri Remote 물리 음량 버튼을 앱이 받을 수 있는가 | **불가능.** tvOS SDK에 해당 입력이 존재하지 않는다 (§1.1 증거). 그 버튼은 HDMI-CEC/IR로 TV·리시버를 직접 제어하며, 앱과 무관하게 **설정 > 리모컨과 기기 > 음량 조절**에서 고쳐야 한다. |
| 그러면 앱에서 무엇을 했는가 | 앱에는 오디오 세션 설정도, 음량 조절 수단도 전혀 없었다. **리모컨으로 조작 가능한 인앱 음량 제어**(트랜스포트 바 3개 항목 + HUD), **시스템 음량 변화 표시**(AirPlay/HomePod/BT 출력 시 물리 버튼 반응이 화면에 보임), **오디오 세션 정식 설정**, 그리고 트랜스포트 바를 열 수 없게 만들던 **포커스 결함 수정**을 구현했다. |
| 검수 | 1차 5차원 리뷰 27건 → 적대적 검증 → 13건 반영, 5건 보류(사유 명시). 2차: regression **ship**, cleanliness 반영, focus는 실기기 수동 확인(T1·T2 PASS)으로 대체 (§4.3). |
| 설치 | 실기기 "큰방"에 설치·실행 완료 (최종본 PID 10587). 사용자가 트랜스포트 바 음량 항목·HUD 노출을 직접 확인. 나머지 §6 체크리스트(T3~T10)는 미확인. |

---

## 1. 분석

### 1.1 근본 원인 — 플랫폼 제약 (SDK 헤더로 확정)

AppleTVOS 26.5 SDK(`xcrun --sdk appletvos --show-sdk-path`)를 직접 grep·타입체크한 결과:

| 확인 항목 | 증거 | 의미 |
|----------|------|------|
| `UIPress.PressType`에 볼륨 케이스 | `UIKit/UIPress.h`에서 `volume` 0건. 케이스는 upArrow·downArrow·leftArrow·rightArrow·select·menu·playPause·pageUp/Down(14.3)·tvRemoteOneTwoThree/FourColors(18.1)뿐. `swiftc -typecheck -target arm64-apple-tvos17.0`에서 `.volumeUp` → `has no member` 오류 | `pressesBegan`으로는 절대 받을 수 없음 |
| GameController | `GameController.framework/Headers` 전체 `volume` 0건. `GCMicroGamepad`(Siri Remote 프로파일)는 dpad·buttonA·buttonX·buttonMenu만 노출 | 컨트롤러 API로도 불가 |
| AVKit | `AVKit.framework/Headers` 전체 `volume` 0건 | 플레이어 UI에 시스템 음량 훅 없음 |
| `AVAudioSession.outputVolume` | `@property (readonly) float outputVolume API_AVAILABLE(... tvos(9.0))` — **읽기 전용, KVO 가능**. `setOutputMuted:`는 `API_UNAVAILABLE(tvos)` | 시스템 음량을 **바꿀 수는 없고, 관측만** 가능 |
| `MPVolumeSettings*` | `MP_UNAVAILABLE_BEGIN(tvos, ...)` | 시스템 볼륨 UI 호출 불가 |
| `AVAudioSessionCategory.playback` / `.moviePlayback` | 둘 다 `tvos(9.0)` 가용 | 앱이 세션 설정은 할 수 있음 |
| `AVPlayerViewController.transportBarCustomMenuItems` | `API_AVAILABLE(tvos(15.0))`, UIMenu/UIAction만 지원, 중첩 메뉴 무시 | 인앱 컨트롤을 붙일 공식 지점 |
| `AVPlayer.volume` / `isMuted` | `tvos(9.0)` 가용, 플레이어 단위 게인 0.0–1.0 | 인앱 음량의 실체 |
| `UIKeyboardHIDUsage.keyboardVolumeUp/Down/Mute` | `UIKeyConstants.h`, `tvos(13.4)`, `UIPress.key.keyCode`로 도달 | **외부 HID 키보드**의 음량 키만 앱에 옴 (Siri Remote 아님) |

### 1.2 Apple 공식 동작 (지원 문서)

- Siri Remote 음량 버튼은 HDMI-CEC 또는 학습된 IR로 TV/리시버 볼륨을 제어한다. 옵션: **자동 / HDMI(CEC) / IR을 통해 TV / 끔 / 새로운 기기 학습**. 광케이블 연결 사운드바는 CEC 불가 → "IR을 통해 TV"로 전환.
- 버튼이 안 될 때 Apple 지침: ① 리모컨 재시작(TV/제어센터 + 음량 낮추기 5초) ② **설정 > 리모컨과 기기 > 음량 조절**에서 다른 옵션 선택.
- 문서 어디에도 "특정 앱에서만 안 된다"는 원인은 없다. 이 동작은 홈 화면·모든 앱에서 동일하다.
- 출처: [If the volume buttons on your Apple TV remote aren't working (108769, ko-KR)](https://support.apple.com/ko-kr/108769), [Control your TV and volume with the Siri Remote](https://support.apple.com/en-ie/guide/tv/atvbbe2477c9/17.0/tvos/17.0), [If you can't control your TV or receiver (HT205225)](https://support.apple.com/en-mide/HT205225)

### 1.3 코드 감사 (변경 전)

| 발견 | 위치 | 영향 |
|------|------|------|
| `AVAudioSession` 사용 **전무** — 카테고리/모드/활성화 없음 | 빌드 타깃 전체 grep 0건 | 프로세스 기본 `soloAmbient`로 재생. 동영상 앱 권장 설정(`.playback`/`.moviePlayback`) 미적용 |
| `AVPlayer.volume`/`isMuted` 미사용, 음량 UI 없음 | `PlayerViewController.swift` | 앱 안에 음량을 바꿀 수단이 전혀 없음 |
| `AVPlayerViewController`를 **alpha 0** 자식 VC로 삽입, 페이드인 후 포커스 갱신 요청 없음, `preferredFocusEnvironments` 미구현 | 구 289–292행 | alpha 0 뷰는 포커스 불가 → 프리롤 단계에 포커스 대상이 없음 → 재생 후에도 플레이어가 포커스를 못 받으면 **트랜스포트 바가 열리지 않아** "리모컨이 플레이어에서 안 먹는다"로 체감될 수 있음 |
| 7개 `pressesBegan` 오버라이드 | 각 VC | 볼륨 케이스가 없어 음량과 무관. 플레이어의 `.menu` 분기가 `avVC.player?.pause()`로 IUO 강제 언래핑 → `streamInfo == nil` 조기 반환 시 Menu 누르면 크래시(잠재) |
| Info.plist / entitlements | — | 오디오 관련 키 없음. tvOS에 필요한 오디오 권한 없음 |

### 1.4 결론

"물리 버튼이 앱에서 동작하게" 만드는 코드는 존재할 수 없다. 사용자가 실제로 원하는 것 — **이 앱에서 시청 중 리모컨으로 음량을 조절하고, 버튼을 눌렀을 때 화면에 반응이 보이는 것** — 은 구현 가능하며, 현재 앱은 그 어느 것도 갖고 있지 않았다.

---

## 2. 기획

### 2.1 구현 항목

| # | 항목 | 근거 |
|---|------|------|
| F1 | `AVAudioSession` `.playback` + `.moviePlayback` + `setActive(true)`, dismiss 시 `setActive(false, .notifyOthersOnDeactivation)` | 동영상 앱의 정식 세션. 완전히 빠져 있던 결함 |
| F2 | **인앱 음량**: 트랜스포트 바 커스텀 항목 3개(음량 낮추기 / 음량 높이기 / 음소거 전환) → `AVPlayer.volume` 10% 스텝, `isMuted` 토글. UserDefaults에 음량 저장·복원 | 리모컨으로 조작 가능한 유일한 공식 경로(`transportBarCustomMenuItems`) |
| F3 | **음량 HUD**: 아이콘 + 10칸 게이지 + 퍼센트 + "앱 음량/시스템 음량" 라벨. 2.5초 후 자동 숨김 | 피드백 없는 음량 컨트롤은 사용 불가 |
| F4 | **시스템 음량 관측**: `AVAudioSession.outputVolume` KVO → HUD "시스템 음량" | AirPlay/HomePod/BT 출력일 때 물리 버튼이 바꾼 값이 화면에 보임. HDMI-CEC/IR 출력이면 값이 안 변함 = 진단 신호 |
| F5 | **안내문**(재생 세션당 1회, 6초): "리모컨의 음량 버튼은 TV·리시버 음량을 조절합니다 / 반응이 없으면 설정 > 리모컨과 기기 > 음량 조절에서 바꿔 보세요" | 사용자의 혼란("왜 안 되지")에 직접 답함. Apple ko-KR 메뉴 명칭 그대로 사용 |
| F6 | **포커스 수정**: `preferredFocusEnvironments` 오버라이드 + 페이드인 완료 후 `UIFocusSystem.requestFocusUpdate(to:)` | F2의 전제. 포커스 없이는 트랜스포트 바 자체를 못 연다 |
| F7 | **HID 음량 키 처리**: `press.key?.keyCode` ∈ {volumeUp, volumeDown, mute} | 물리 음량 키가 앱에 도달하는 유일한 경로(외부 키보드/HID 리모컨). 요청의 문자 그대로에 해당 |
| F8 | Menu 분기 `backTapped()` 경유 (IUO 강제 언래핑 제거) | `pressesBegan`을 수정하면서 같은 줄의 잠재 크래시를 1글자 수준으로 제거. §4.2에 명시 |

### 2.2 검토 후 채택하지 않은 대안

| 대안 | 기각 사유 |
|------|----------|
| D-pad 상/하로 음량 조절 | `AVPlayerViewController`가 상/하 스와이프를 정보 패널·자막 패널에 이미 씀. 표준 동작을 깨뜨림 |
| `MPVolumeView` | 헤더상 tvOS 미제외지만 시스템 볼륨 setter가 없어 실효 없음. `AVPlayer.h` 주석도 iOS 전용 안내 |
| 트랜스포트 바 UIMenu(단계 선택형) | 매번 메뉴를 다시 열어야 해 반복 조작이 불편. 직접 UIAction 3개가 연타에 유리 |
| 음소거 상태에 따라 항목 제목 변경("음소거"↔"해제") | 항목 배열 재할당이 누르고 있는 항목의 포커스를 초기화할 수 있음(검수 지적). 제목 고정 + HUD로 상태 표시 |
| 음소거 UserDefaults 영속화 | 한 번 음소거하면 이후 모든 방송이 무음으로 시작하는 제품 결정 문제. 세션 범위(다시 시도 간 유지)만 채택 |

---

## 3. 구현

변경 파일: `soop-app/PlayerViewController.swift` (+328/−5), `soop-app/DesignSystem.swift` (+3). 빌드: 시뮬레이터·실기기 모두 `BUILD SUCCEEDED`, 경고 0.

| 항목 | 위치 (`PlayerViewController.swift`) | 내용 |
|------|------|------|
| 헤더 주석·상수 | 52–94행 | 플랫폼 제약 근거, `volumeStep=0.1`, 세그먼트 10칸, HUD 치수 상수, `pendingMuted` |
| F1 오디오 세션 | `configureAudioSession()` 296행, `deactivateAudioSession()` 307행, `viewDidDisappear` 857행 | `viewDidLoad` 첫 줄에서 설정·활성화, `isBeingDismissed`일 때만 비활성화 |
| F4 시스템 음량 KVO | `observeSystemVolume()` 318행 | `.new` 옵션, 메인 큐, `isViewLoaded && window != nil && avVC.alpha > 0` 가드 |
| F2 인앱 음량 | `savedVolume()` 333행, `makeTransportBarItems()` 342행, `stepVolume` 358행, `toggleMute` 368행 | 어느 방향이든 스텝하면 음소거 해제(숨은 값 변경 방지). 음량은 UserDefaults `soop.player.volume` |
| F3 HUD | `setupVolumeHUD()` 377행, `showVolumeHUD(source:)` 452행 | `topMetaOverlay.bottomAnchor + md`에 중앙 정렬(상단 밴드 충돌 회피). 에러 카드 표시 중 무시. 라벨은 실제 % (시스템 음량은 10% 단위가 아님) |
| 재생 시작 시 적용 | 546–548행 | `player.volume = savedVolume()`, `player.isMuted = pendingMuted`, `transportBarCustomMenuItems` 부착 |
| 복원값 공개 | 573행(primary), 712행(fallback) | 복원 음량 < 100% 또는 음소거면 readyToPlay에 HUD 1회 표시 — "이유 없는 무음" 방지 |
| F6 포커스 | `handOffFocusToPlayer()` 868행, `requestFocus(on:)` 876행, `preferredFocusEnvironments` 882행, `showError` 818행 | `UIFocusSystem.focusSystem(for:)?.requestFocusUpdate(to:)` 사용. `setNeedsFocusUpdate()`는 "현재 포커스 항목을 포함하지 않으면 효과 없음"(`UIFocus.h:72`)이라 프리롤 단계에서 무효. 에러 카드가 뜨면 플레이어 alpha 0 + 카드로 포커스 |
| F7·F8 presses | `pressesBegan` 902행 | `.menu` → `backTapped()`; `keyboardVolumeUp/Down/Mute` → 인앱 음량 |
| DS 토큰 | `DesignSystem.swift:52` | `DS.Colors.volumeSegmentEmpty` (white 22%) |

### 3.1 사용 방법 (사용자 관점)

1. 방송 재생 중 리모컨 터치 표면을 **아래로 스와이프**(또는 클릭)하면 트랜스포트 바가 열린다.
2. 좌/우로 이동해 **음량 낮추기 / 음량 높이기 / 음소거 전환**을 선택한다. 항목에 포커스를 둔 채 Select를 반복하면 10%씩 바뀐다.
3. 화면 상단 중앙 HUD에 **앱 음량 n%**(또는 음소거)가 2.5초간 표시된다. 처음 한 번은 물리 음량 버튼 안내가 6초간 함께 보인다.
4. Apple TV 출력이 AirPlay/HomePod/블루투스이면 **리모컨 물리 음량 버튼**을 눌렀을 때 HUD에 **시스템 음량 n%**가 뜬다. HDMI(TV 스피커/리시버)면 TV가 직접 볼륨을 바꾸므로 HUD는 뜨지 않는다 — 그 경우 TV 자체 OSD가 뜨는 것이 정상이며, 아무 반응이 없으면 **설정 > 리모컨과 기기 > 음량 조절**을 바꿔야 한다.

---

## 4. 검수

### 4.1 1차 — 5차원 병렬 리뷰 → 적대적 검증

- 리뷰 차원: correctness / focus-uikit / audio-session / ux-design-system / scope-simplicity → **원 findings 27건**
- 검증: 건당 2명(반박자 + 실무 관점). 세션 한도로 12건만 판정 완료, 나머지는 §4.2의 제 판단으로 대체.
- 판정 결과: 10건 유지, 2건 반박(그중 "포커스 API 반박"은 `UIFocusSystem.h:33–35` 원문으로 재확인해 **반박이 틀렸음**을 확정 — `requestFocusUpdate(to:)`에는 포함 전제가 없음).

### 4.2 반영 / 보류

**반영(13건)**

| # | 지적 | 조치 |
|---|------|------|
| 1 | `setNeedsFocusUpdate()`는 포커스 미포함 환경에서 무효 (2명 독립 지적, 헤더 원문) | `UIFocusSystem.requestFocusUpdate(to:)`로 교체, `showError`에도 적용 |
| 2 | 음소거 중 "낮추기"가 값만 바꾸고 표시는 음소거 | 어느 방향이든 스텝 시 음소거 해제 |
| 3 | 저장된 0%(또는 낮은 값)로 다음 방송이 이유 없이 무음 | readyToPlay에서 복원값 < 100% 또는 음소거면 HUD 1회 표시 (클램프로 사용자 의도를 덮어쓰지 않음) |
| 4 | 다시 시도 시 음소거만 유실 | `pendingMuted`로 세션 내 이월 |
| 5 | HUD 퍼센트가 10% 단위로 양자화 → 시스템 음량 오표시 | 라벨은 실제 값, 게이지만 양자화 |
| 6 | HUD가 에러 카드 위로 떠오름 | `errorContainer != nil`이면 무시 |
| 7 | 항목 배열 재할당이 조작 중 포커스를 훔칠 수 있음 | 제목 고정("음소거 전환"), 재할당 코드 제거 |
| 8 | 힌트 표시/숨김 간 필 폭 변화로 게이지가 61pt 밀림 | `column.alignment = .center` |
| 9 | HUD 위치가 다른 뷰 높이(160)로 하드코딩 | `topMetaOverlay.bottomAnchor`에 앵커 |
| 10 | 심볼 3종 폭 차이로 아이콘이 튐 | `SymbolConfiguration(pointSize: 30)` + `.center` |
| 11 | 힌트 2.5초는 36음절을 읽기엔 짧고 `textTertiary`는 흐림 | 힌트 있을 때 6초, `textSecondary`, 2줄 중앙 정렬 |
| 12 | 설정 경로 한국어가 Apple 표기와 다를 수 있음 | Apple ko-KR 108769 확인: **"리모컨과 기기 > 음량 조절"**로 교정 |
| 13 | 에러 카드 뒤 플레이어가 방향 이동으로 포커스를 가져갈 수 있음(제 변경으로 생긴 회귀) | `showError`에서 `avVC.view.alpha = 0` |
| + | 중복 할당(`refreshTransportBarItems` vs 직접 대입), HUD 매직 넘버 | #7로 함께 해소 / 이름 붙인 private 상수로 승격 |

**보류(5건) — 사유**

| 지적 | 사유 |
|------|------|
| 오디오 세션 인터럽션/백그라운드 후 재활성화 옵서버 추가 | 카테고리는 세션에 고정되고 `AVPlayer.play()`가 암묵적으로 재활성화한다. 변경 전에도 명시적 활성화가 없었으므로 회귀 아님. 검증 없이 옵서버를 추가하는 위험이 더 큼 |
| `setActive(true)`가 `viewDidLoad` 메인 스레드에서 present 애니메이션을 지연시킬 수 있음 | HDMI 경로에서는 즉시 반환. Apple 샘플도 동일 위치. 실기기에서 체감 지연 보고 시 readyToPlay로 이동 |
| outputVolume KVO가 경로 변경에도 반응 | 기존 가드(`avVC.alpha > 0`)가 활성화 직후 잡음은 이미 차단. 재생 중 경로 변경 시 시스템 음량 HUD가 뜨는 것은 오히려 정보 제공 |
| 범위 축소 제안: KVO·영속화·힌트·HID 처리 삭제 | KVO는 물리 버튼이 화면에 보이는 유일한 경로, 힌트는 사용자 질문에 대한 직접 답, HID는 물리 음량 키가 앱에 도달하는 유일한 경로, 영속화 없이는 매 방송 100%로 리셋되어 기능이 고장 난 것처럼 보임. 모두 요청("음량 버튼이 동작되도록")에 직결됨 |
| Menu 분기 크래시 수정을 별도 커밋으로 분리 | 커밋은 이번 요청 범위 밖(사용자 지시 없음). 본 문서 F8에 명시해 추적 가능하게 함 |

### 4.3 2차 — 수정본 회귀 리뷰 (regression / focus / cleanliness 3렌즈)

| 렌즈 | 판정 | 요지 |
|------|------|------|
| regression | **ship** | 1차 반영 12건에서 회귀 없음. 검증 방식: `pendingMuted` 수명(6개 present 지점 모두 새 인스턴스 생성 확인), `showError` alpha 0 ↔ `preferredFocusEnvironments`·KVO 가드 상호작용, HUD 앵커 시점(`setupTopMetaOverlay`가 먼저 실행), **힌트 2줄 폭 Core Text 실측**(16pt: 322pt / 411pt < 560pt, 정확히 2줄), **음량 ±0.1 누적 오차 전수 검사**(1.0에서 도달 가능한 23개 Float 상태 중 (0.99, 1.0) 구간 없음 → "< 1" 공개 조건이 100%에서 오발동하지 않음) |
| cleanliness | fix-first → **반영 완료** | 기능 지적 없음. "(v4)" 버전 태그가 기존 v4 릴리스와 충돌 → `v5.1`; 사용자 노출 문구 "음량 조절 에서" 띄어쓰기 → "음량 조절에서"; 새 주석의 조사 띄어쓰기를 파일 관례(붙여쓰기)로 통일; `showVolumeHUD`의 중복 `bringSubviewToFront` 제거; HUD 치수 상수 정리(6/44/30 승격) 및 스택 arrangedSubview의 `translatesAutoresizingMaskIntoConstraints` 일관화; DS 토큰 주석에 alpha 표기. 1차 잔재(`refreshTransportBarItems` 참조 등) 없음 확인 |
| focus | **중단 → 실기기 수동 확인으로 대체** | 리뷰어가 tvOS 시뮬레이터에 프로브 앱을 만들어 포커스 핸드오프를 실측하던 중, 프로브가 재생한 Apple 샘플 스트림(bipbop) 소리가 Mac mini에서 나 사용자 요청으로 중단. 대신 **사용자가 실기기에서 트랜스포트 바가 열리고 음량 항목·HUD가 보이는 것을 직접 확인**(§6 T1·T2 PASS) — 이 렌즈가 검증하려던 핵심(포커스가 플레이어에 도달하는가)이 실물로 확인됨 |

반영 후 시뮬레이터·실기기 재빌드 `BUILD SUCCEEDED`, 경고 0 → 실기기 재설치(§5).

---

## 5. 설치

| 단계 | 명령 / 결과 |
|------|------------|
| 기기 | `xcrun devicectl device info details --device ED4F9D49-…` → 큰방, AppleTV11,1, tvOS 26.6 (23L773), developerMode enabled, tunnelState connected |
| 빌드 | `xcodebuild -project soop-app.xcodeproj -scheme soop-app -destination id=ED4F9D49-0D1F-5E57-8342-859E42F8590B -configuration Debug -derivedDataPath /tmp/soop-build-device -allowProvisioningUpdates build` → **BUILD SUCCEEDED**, 서명 "Apple Development: asukarr@gmail.com", 프로파일 "tvOS Team Provisioning Profile: com.ssroh.soop-app" |
| 설치 | `xcrun devicectl device install app --device ED4F9D49-… /tmp/soop-build-device/Build/Products/Debug-appletvos/soop-app.app` → **App installed** (최종본 `…/B1ACD246-…/soop-app.app`; 1차 설치 `…/F436B7AB-…`는 2차 검수 반영본으로 교체) |
| 실행 | `xcrun devicectl device process launch --device ED4F9D49-… com.ssroh.soop-app` → **Launched**, 6초 후 프로세스 확인 **PID 10587** (시작 크래시 없음) |

---

## 6. 수동 테스트 체크리스트 (실기기에서 사람이 확인해야 하는 항목)

원격 도구로는 물리 리모컨을 누를 수 없어 T1·T2 외에는 확인되지 않았다.

| ID | 절차 | 기대 결과 |
|----|------|----------|
| T1 | LIVE → 카테고리 → 방송 선택, 재생 시작 후 **아래로 스와이프** | 트랜스포트 바가 열리고 오른쪽에 **음량 낮추기 / 음량 높이기 / 음소거 전환**이 보인다 (F6 포커스 수정의 핵심 검증) — **✅ 사용자 확인(2026-09-06)** |
| T2 | "음량 낮추기"에 포커스 두고 Select 3회 | HUD "앱 음량 70%", 게이지 7칸, 소리가 실제로 작아진다. 첫 표시에는 2줄 안내문이 6초간 보인다 — **✅ HUD 노출 사용자 확인** (수치·청감은 미확인) |
| T3 | "음소거 전환" Select → 다시 Select | HUD "음소거" ↔ "앱 음량 n%"; 소리 on/off |
| T4 | 음소거 상태에서 "음량 높이기" | 음소거가 풀리며 값 +10% |
| T5 | Menu로 나갔다가 다른 방송 재생 | T2에서 맞춘 음량(70%)으로 시작하고 readyToPlay 직후 HUD가 1회 뜬다 |
| T6 | 리모컨 **물리 음량 버튼** (출력이 TV/HDMI일 때) | TV 자체 볼륨 OSD가 바뀐다. 앱 HUD는 뜨지 않는 것이 정상. 아무 반응 없으면 **설정 > 리모컨과 기기 > 음량 조절**에서 "IR을 통해 TV" 등으로 변경 후 재확인 |
| T7 | 출력을 HomePod/AirPlay/블루투스로 바꾸고 물리 음량 버튼 | 앱 HUD에 **"시스템 음량 n%"**가 뜬다 (F4) |
| T8 | 스트림을 끊어 에러 카드 유도 → "다시 시도" | 재시도 버튼에 포커스가 있고, 카드 뒤로 포커스가 빠지지 않는다. 재생 복구 후 음소거 상태가 유지된다(T3 후라면) |
| T9 | Menu 버튼 (트랜스포트 바 닫힘/열림 각각) | 열림: 바가 닫힘 → 한 번 더 Menu: 플레이어 종료. 닫힘: 즉시 종료 |
| T10 | (선택) 블루투스 키보드 연결 후 음량 키 | 인앱 음량이 바뀌고 HUD 표시 (F7) |

---

## 7. 프로세스 기록

| 단계 | 방식 | 결과 |
|------|------|------|
| 분석 | 워크플로 30 에이전트(코드 감사·SDK 헤더·문서/커뮤니티 리서치·기기 파이프라인·8개 주장 × 3렌즈 검증·비평) | 세션 한도로 27개 실패. 완료된 **SDK 헤더 감사·코드 감사·기기 파이프라인**이 결정적 증거를 제공했고, 리서치·검증은 본인이 헤더 재grep + Apple 문서 WebFetch로 직접 대체 |
| 기획 | 본인 | §2 |
| 구현 | 본인 | §3 |
| 검수 1차 | 워크플로 62 에이전트(5 리뷰 + 27×2 검증 + 비평) | 리뷰 5/5 완료, 검증 12/54 완료, 나머지 세션 한도 실패 → §4.2 |
| 검수 2차 | 워크플로 3 에이전트 | regression·cleanliness 완료, focus 중단(§4.3). 테스트에 쓰인 시뮬레이터 프로브 앱 4종(`com.probe.*`, `local.volprobe`)과 `/tmp` 스크래치(FocusProbe·fpadv·focustest·volprobe·*.swift)는 사용자 요청으로 모두 종료·삭제, 시뮬레이터 종료. 실기기에는 테스트 앱 미설치 확인 |
| 설치 | devicectl | §5 |
