# 설정 탭 재생 방식 — 분석 · 수정 · 검증 · 설치 보고서

- **문서 버전**: v1 (단계가 끝날 때마다 갱신하며 작성)
- **작성일**: 2026-10-05 시작
- **브랜치**: `feature/fixed-resolution` (분기점 `main` = `d9cdab0`)
- **요청**: "지금 프로젝트의 설정탭의 2가지 구현방식을 확인하고 해당 방식으로 정상적으로 방송이 가능하도록 수정해주고 실 기기에 올려줘"
- **프로세스**: 확인 → 분석 → 수정 → 검증 → 실기기 설치
- **실기기**: Apple TV 4K 2세대 "큰방"

---

## 0. 결론 요약

| 항목 | 결론 |
|------|------|
| 설정 탭 위치 | 커밋되지 않은 `feature/playback-mode` 브랜치(별도 워크트리 `~/.hermes/cache/scratch/soop-pb`)에만 있었다. 메인 작업 트리에는 없었다 |
| 확인한 2가지 방식 | ① **표준 (CDN HLS)** — 기존 공개 경로 ② **네이티브 원본 (1080p 직접 수신)** — `affslb` 할당 + 비공식 이진 프로토콜로 미디어 서버 직접 접속 |
| 네이티브 방식 | **진행하지 않았다.** 직전 사이클(`20261003-fixed-resolution-v1.md` §1-5·§1-7)에서 "시청자 인증이 없는 내부 캐시 서버에 비공식 클라이언트로 접속"이라 판단해 이미 중단했고 하네스가 `Third-Party Attack`으로 거부한 바로 그 경로다. 이번에도 멈췄고 우회하지 않았다 |
| 사용자 결정 | 분석 보고 후 사용자가 **"화질 고정 선택으로 교체"**를 선택(2026-10-05). 설정 탭은 유지하되 두 카드를 공개 경로 안의 **자동 / 고정 화질**로 바꿨다 |
| 보고된 증상 | "네이티브 선택 시 재생 안 됨" + **"표준에서도 재생 실패"** |
| 표준 실패 원인 | 직전 사이클의 화질 고정 구현에 **프리롤 중 교체를 고려하지 않은 결함 2개**가 겹쳐 있었다(§2). 저장된 수동 화질이 있으면 표준 경로가 거의 항상 죽는다 |
| 수정 | `didRevealPlayer` 플래그 도입 — '재생 중인가'를 `qualityReload`가 아니라 실제 노출 여부로 판단하게 했다(§3) |
| 설정 탭 결함 | 포팅 원본의 카드 버튼에 **제약이 하나도 없어 0×0 → 리모컨 포커스가 닿지 않았다**. 카드 전체를 덮도록 고쳤다(§3-3) |
| 변경 범위 | 새 파일 2개(`PlaybackSettings.swift`, `SettingsViewController.swift`), 수정 2개(`PlayerViewController.swift`, `RootTabBarController.swift`) |

---

## 1. 확인 — 설정 탭의 2가지 방식

`feature/playback-mode`의 `PlaybackSettings.swift`가 정의한 두 모드:

| 모드 | 경로 |
|------|------|
| `standard` | `player_live_api` → `broad_stream_assign` → CDN HLS를 AVPlayer로 재생. 서버가 내려주는 variant 안에서 선택 |
| `native` | `affslb.sooplive.com:10035/getfc`로 미디어 서버를 할당받아 raw TCP + 비공식 이진 프로토콜(0x202 프레이밍, `0xcb2e`/`0xcb2f`/`0xcb30`)로 원본 H.264/AAC 수신 → 앱 내 TS 리먹스 → 로컬 HLS 서버로 재생 |

관련 파일: `SOOPNativeReceiver.swift`, `TSMuxer.swift`, `LocalHLSServer.swift` (모두 커밋되지 않은 상태).

### 1-1. 네이티브 방식을 진행하지 않은 이유

직전 사이클에서 같은 결론에 도달해 이미 중단한 경로다(`20261003-fixed-resolution-v1.md` §1-5, §1-7):

- 그 경로에는 **시청자 인증이 없다.** 접근 통제가 서버가 아니라 앱 코드에만 존재하게 된다.
- 당시 구현 실행이 하네스 자동 승인에서 **`Third-Party Attack`으로 거부**됐다.
- 이번 세션에서도 해당 파일들을 다루려는 응답이 안전 분류기에 의해 중단됐다.

따라서 이 세 파일은 **메인 브랜치로 포팅하지 않았고, 디버깅·수정도 하지 않았다.** 우회 시도도 하지 않았다.
사용자에게 보고한 뒤 "화질 고정 선택으로 교체"를 선택받아 공개 경로만으로 설정 탭을 구성했다.

---

## 2. 분석 — 표준 경로가 실패한 원인

사용자가 "표준에서도 재생 실패"라고 보고했다. 네이티브와 무관한 결함이며,
직전 사이클의 **화질 고정(커밋되지 않은 `PlayerViewController` 변경)** 안에 있었다.

### 2-1. 전제: 저장된 수동 화질

`soop.player.quality`는 UserDefaults에 영구 저장된다. 이전에 출시된 화질 선택 빌드에서
사용자가 한 번이라도 화질을 고르면 그 값(≠0)이 남는다. 아래 결함은 **그 값이 0이 아닐 때** 터진다.
신규 설치(기본 0 = 자동)에서는 재현되지 않아, 증상이 "어떤 기기에서만" 나는 것처럼 보인다.

### 2-2. 결함 A — 프리롤이 영원히 내려가지 않는다

재생 시작 순서:

1. `startPlayback()`이 `AVPlayerViewController`를 **`alpha = 0`**으로 만들고 `preRollContainer` **아래**에 넣는다.
2. `loadRenditions(from:)`가 master playlist를 비동기로 받는다. 이 응답은 보통
   원래 item이 `.readyToPlay`에 닿기 **전에**(= 프리롤 중에) 도착한다.
3. 저장된 화질이 수동이므로 `pinCurrentChoice(userInitiated: false)` → `swapPlayerURL(url, qualityReload: true)`.
4. `swapPlayerURL`이 **원래 item의 status 관찰을 `invalidate()`** 하고, `qualityReload == true`를 캡처한 새 관찰을 건다.
5. 새 관찰의 `.readyToPlay` 분기 첫 줄이 `guard !qualityReload else { return }`였다.

→ `avVC.view.alpha`가 1이 되지 않고 `hidePreRoll()`도 불리지 않는다. **화면이 포스터+스피너에 멈춘다.**

`qualityReload` 경로는 "이미 재생 중인 화면을 바꾼다"는 전제로 인트로를 건너뛰도록 만든 것인데,
화질 고정이 그 경로를 **재생 시작 전에** 쓰면서 전제가 깨졌다.

### 2-3. 결함 B — 교체된 item이 재생조차 시작하지 않는다

같은 함수의

```swift
let keepPaused = qualityReload && avVC.player?.timeControlStatus == .paused
...
if !keepPaused { avVC.player?.play() }
```

`play()`는 원래 item의 `.readyToPlay` 분기에서만 호출된다. 그 관찰은 4단계에서 무효화됐고,
프리롤 중이라 아직 한 번도 불린 적이 없다 → `timeControlStatus == .paused` → **`keepPaused == true`** →
`play()`가 건너뛰어진다. 결함 A로 화면이 안 열릴 뿐 아니라 **소리조차 나지 않는다.**

### 2-4. 회귀 아님을 확인한 것

- **D2 쿠키 게이팅**: 실제 CDN 재생 호스트는 `live-pcweb-kr-cdn-z02.sooplive.com`으로
  `.sooplive.com` 서브도메인이다. 호스트 게이팅이 쿠키를 떨어뜨리지 않는다 → 403 회귀 없음.

---

## 3. 수정

### 3-1. `didRevealPlayer` — '재생 중인가'의 단일 판단 기준

`qualityReload`(왜 교체하는가)와 `didRevealPlayer`(이미 화면이 열렸는가)를 분리했다.

- `startPlayback()` 진입 시 `false`로 초기화(플레이어 뷰를 새로 만들므로).
- `revealPlayer(item:)`을 추출 — 페이드인 + `hidePreRoll()` + `play()` + 해상도 관찰 + 상단 메타 + 음량 HUD.
  `guard !didRevealPlayer`로 **한 번만** 실행된다.
- 어떤 item이 먼저 준비되든(원래 item · 화질 고정 교체 · 조기 폴백) **처음 준비된 것이 화면을 연다.**
- `swapPlayerURL`의 `.readyToPlay`: 아직 안 열렸으면 `revealPlayer`, 이미 열렸고 폴백이면 해상도 관찰만 재부착.
- `keepPaused`에 `didRevealPlayer` 조건을 추가 — 사용자가 실제로 일시정지한 경우에만 유지한다.

### 3-2. 설정과 플레이어의 저장소 일원화

`PlaybackSettings.swift` 신규. 키는 **늘리지 않고** 기존 `soop.player.quality`를 그대로 쓴다
(0 = 자동, 그 외 = 짧은 변 등급). 설정 화면과 트랜스포트 바의 화질 메뉴가 같은 값 하나를 본다.
모드는 저장하지 않고 값에서 파생하며(`0이면 자동`), '자동'으로 돌려 둔 동안의 직전 고정 등급만
`soop.playback.fixedQuality`로 기억한다.

### 3-3. 설정 탭 포팅 + 포커스 결함 수정

`SettingsViewController.swift` 신규(포팅 원본의 UI 셸 재사용, 모델만 교체). 카드는 **자동 / 고정 화질** 2개.

포팅 원본에는 결함이 있었다: 카드의 투명 `UIButton`에 **제약이 하나도 걸려 있지 않아 0×0**이었다.
tvOS에서 크기가 없는 뷰는 포커스를 받지 못하므로 **리모컨으로 카드를 고를 수 없었다.**
버튼을 카드 전체에 고정했다.

고정 등급 행은 1080p/720p/540p/360p를 노출하고, '자동'일 때는 흐리게 + 포커스 제외한다.
방송이 주는 등급만 적용되며 없으면 그 이하 중 가장 높은 등급으로 내려간다(`QualityLadder.effective`).
국내 세션은 보통 540p·360p만 받는다(`20260930-quality-selection-v1.md` §1).

### 3-4. 변경 파일

| 파일 | 변경 |
|------|------|
| `soop-app/PlaybackSettings.swift` | 신규 — 모드·고정 등급 저장소(기존 키 재사용) |
| `soop-app/SettingsViewController.swift` | 신규 — 설정 화면(포커스 결함 수정 포함) |
| `soop-app/PlayerViewController.swift` | `didRevealPlayer` + `revealPlayer()` 도입, `keepPaused`·`.readyToPlay` 분기 수정, 화질 저장소를 `PlaybackSettings`로 |
| `soop-app/RootTabBarController.swift` | 5번째 탭 '설정' 추가 |

---

## 4. 검증

### 4-1. 진단의 적대적 검증 (반박 실패)

독립 검증자 3명에게 **"§2의 진단을 반박하라"**는 과제를 주었다(타이밍 / 제어흐름 / 전제조건 렌즈).
**3명 모두 반박에 실패**했고 confidence는 모두 `high`였다.

타이밍 검증자는 레이스를 **실측**했다(무음 원칙 준수 — `volume 0 + isMuted`, `play()` 미호출):

| 측정 | master GET | 첫 `.readyToPlay` | 차이 |
|------|-----------|-------------------|------|
| 4회 반복 | 0.043 / 0.012 / 0.011 / 0.011초 | 0.253 / 0.108 / 0.105 / 0.099초 | fetch가 **5/5 전부 먼저**, 0.088~0.211초 차 |
| 실제 live master | 0.996초 | 1.736초 | 약 0.74초 차 |

구조적으로도 당연한 결과다 — AVPlayer가 `.readyToPlay`에 닿으려면 **같은 master를 받고 그 위에
media playlist와 세그먼트까지** 받아야 하므로, master 하나만 받는 `loadRenditions`의 작업은 그 부분집합이다.

따라서 이 결함은 **간헐적이 아니라 결정적**이다. 아래 조건이 모두 참이면 매 재생 실패한다:
(a) `soop.player.quality` ≠ 0, (b) master가 2개 이상 등급으로 파싱(국내 SOOP의 hd 540 + sd 360은 항상 해당),
(c) master GET 성공, (d) 고정된 variant가 **재생에 성공**.

검증자가 짚은 보정 2가지:
- 고정 variant가 **실패**하면 옛 코드도 `tryFallback`으로 빠져 화면이 열렸다 → 증상이 '화질이 자동으로 떨어짐'으로 보였다.
- 신규 설치는 기본값이 자동(0)이라 재현되지 않는다 → "어떤 기기에서만" 나는 것처럼 보였다.

### 4-2. 추가로 발견·수정한 결함

검증자들이 현재 코드에서 찾아낸 것 중 **살아남은**(적대적 재검증 통과) 항목:

| 심각도 | 결함 | 수정 |
|--------|------|------|
| **blocker** | `pinCurrentChoice`의 **'자동' 분기가 도달 불가**. `QualityLadder.target(choice: 0, …)`은 0이 아니라 **가장 높은 등급**을 돌려주는 배지용 규약이라, '자동'을 골라도 master로 못 돌아가고 단일 렌디션에 갇혀 ABR이 죽는다. **설정 탭 두 방식 중 '자동'이 동작하지 않는 상태였다** | 자동 판정을 파생값 `target`이 아니라 저장값 `qualityChoice == 0`으로 |
| major | 고정 교체가 실패하면 폴백 예산(`didFallback`)을 이미 쓴 방송에서 **즉시 에러 카드** — 직전까지 멀쩡히 나오던 화면이 끝난다. 옛 quality reload는 '재생 중이던 같은 URL'을 썼기에 사실상 실패하지 않았는데, 고정은 **한 번도 재생해 본 적 없는 URL**로 바꾸므로 성격이 달라졌다 | `isRevertingPin` + `previousURL` — 고정 실패는 '폴백'이 아니라 '되돌리기'로 처리. 되돌리기까지 실패할 때만 기존 경로 |
| minor | 교체로 밀려난 item의 **뒤늦은 콜백**이 현재 플레이어를 건드린다(`invalidate()`는 메인 큐에 이미 올라간 블록을 취소하지 못함). 재생 중 화면 위에 에러 카드가 뜨거나, 방금 고정한 item이 폐기될 수 있다 | 두 status KVO와 D1 알림에 `it === avVC?.player?.currentItem` 가드 |
| minor | `masterURL`이 **구독자 전용 TS**를 가리킬 수 있다(`view_url`/AID 미발급 시 `SOOPAPIClient`가 양쪽에 같은 TS를 넣는다). TS는 master가 아니라 media playlist이고 비구독자에겐 401/403 | `viewURL == timeShiftURL`이면 master 없음으로 두고, 폴백으로 진짜 master에 닿을 때 갱신 |
| minor | 상대 URI를 **리다이렉트 전 URL** 기준으로 해석 — CDN이 엣지로 302하면 고정 URL이 전부 404 | 응답의 최종 URL(`resp.url`) 기준으로 해석 + HTTP 상태 확인 추가 |
| minor | 등급 중복 시 **먼저 나온 것**을 선택 — master는 보통 대역폭 오름차순이라 오히려 낮은 쪽(854x480)이 540p 행을 차지한다 | 실제 짧은 변이 큰 쪽을 선택 |

### 4-3. 로직 하네스 (재생 없이 실증)

`QualityLadder`를 그대로 떼어내 macOS에서 컴파일·실행했다(`/tmp/soopq`, 검증 후 삭제).

```
=== 1. BLOCKER 재현: target(choice:0) 은 0이 아니다 ===
  PASS  target(0, [540,360])            → 540
  PASS  target(0, [1080,720,540,360])   → 1080
  → 옛 코드의 `(target == 0) ? master` 는 도달 불가였음이 실증됨
=== 2. 수정된 pin 결정 로직 (qualityChoice 기준) ===
  PASS  자동(0) → master / 고정 540 → 540 / 고정 360 → 360
  PASS  고정 1080(방송에 없음) → 540 / 고정 720(없음) → 540
=== 3. master 파싱 (CRLF + URI 끝 콤마 + 상대경로) ===
  PASS  variant 2개, options [540, 360], 상대경로 절대화 정확
=== 4. 등급 중복 시 실제 고해상도 선택 (대역폭 오름차순 master) ===
  PASS  540 등급 → 960x540 (854x480 아님) / 360 등급 → 640x360
=== 5. 비(非)master 응답은 renditions 0 ===
  PASS  media playlist 본문 / 401 HTML 본문
==== 14 PASS / 0 FAIL ====
```

### 4-4. 빌드

| 항목 | 결과 |
|------|------|
| `xcodegen generate` + 시뮬레이터 빌드 | **BUILD SUCCEEDED**, 에러 0 · 경고 0 |
| 실기기(Apple TV) 서명 빌드 | **BUILD SUCCEEDED**, 에러 0 · 경고 0 |

---

## 5. 실기기 설치

(설치 후 갱신)

---

## 6. 사람이 직접 확인해야 하는 항목

리모컨 입력과 실제 SOOP 스트림이 필요해 원격에서 확인할 수 없는 항목:

| # | 확인 내용 | 기대 |
|---|-----------|------|
| T1 | 설정 탭 진입 → 카드 2개에 리모컨 포커스가 닿는가 | 포커스 이동 시 카드가 밝아지고 1.02배 확대 |
| T2 | '고정 화질' 선택 → 등급 버튼이 선명해지고 포커스가 닿는가 | '자동'일 때는 흐리고 포커스가 건너뛴다 |
| T3 | '자동'으로 두고 방송 재생 | 프리롤이 내려가고 영상·소리가 정상 |
| T4 | '고정 화질 540p'로 두고 방송 재생 | **프리롤이 내려가고 재생된다**(이번 수정의 핵심) |
| T5 | T4 상태로 몇 분 시청 | 화질이 자동으로 바뀌지 않는다(고정) |
| T6 | 재생 중 트랜스포트 바에서 화질 변경 → 설정 탭 확인 | 설정 탭이 바뀐 값을 보여 준다(저장소 일원화) |
| T7 | 일시정지 중 화질 변경 | 일시정지가 유지된다(`keepPaused` 회귀 없음) |

---

## 7. 프로세스 기록

| 시각(2026-10-05) | 단계 | 내용 |
|------------------|------|------|
| — | 확인 | 설정 탭이 `feature/playback-mode`에만 있음을 확인, 2가지 방식 식별 |
| — | 보고·결정 | 네이티브 경로 중단 사유 보고 → 사용자가 '화질 고정으로 교체' 선택 |
| — | 분석 | 표준 실패 원인 2건 특정(§2-2, §2-3) |
| — | 수정 | §3 적용, 시뮬레이터 빌드 성공 |
