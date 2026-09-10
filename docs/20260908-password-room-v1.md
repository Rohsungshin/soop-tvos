# 비밀번호 방송(비번방) 입장 기능 — 2026-09-08 v1

온라인 방 진입 시 비번방(`is_password=1` / `BPWD=Y`)은 현재 아예 접속이 불가능하다.
사용자가 비밀번호를 입력하면 입장할 수 있도록 구현한다.

프로세스: 분석 → 기획 → 구현 → 검수 (설치는 이번 요청 범위 밖, 별도 진행)

---

## 1. 분석 (실측 기반)

SOOP 실서버에 직접 요청을 보내 비번방의 동작을 리버스 엔지니어링했다. (로그인 세션은
`.env`의 `SOOP_ID/SOOP_PASSWORD`로 `login.sooplive.co.kr/app/LoginAction.php` 성공, RESULT=1)

### 1-1. 비번방 식별
- 카테고리 리스트(`sch.sooplive.com ... m=categoryContentsList`) 응답의 각 방송에
  `is_password` 필드가 있다 (`0`/`1`). 실측 시점 상위 120개 카테고리에서 72개 비번방 관측.
- 스트림 메타(`live.sooplive.com/afreeca/player_live_api.php`, `type=live`) 응답 `CHANNEL`에
  `BPWD` 필드가 있다. 비번방이면 `"Y"`, 아니면 `"N"`.

### 1-2. 비번방의 스트림 해석 흐름 (핵심)
`player_live_api.php`는 요청 `type`에 따라 역할이 다르다.

| 요청 | 정상방 | 비번방 (빈 비번 / 틀린 비번) |
|------|--------|------------------------------|
| `type=live` | `RESULT=1`, `BSTATUS=BROADING`, **`TS` URL 포함** | `RESULT=1`, `BSTATUS=BROADING`, `BPWD=Y`, **`TS` 없음** |
| `type=aid`  | `RESULT=1` + **`AID` 토큰** | **`RESULT=0`, AID 없음** |

- **비밀번호 검증은 `type=aid` 호출에서 일어난다.** `type=live`는 비번을 검증하지 않는다
  (틀린 비번 `''`/`0000`/`1234`/`asdf` 모두 `RESULT=1 BPWD=Y`, TS 없음으로 동일).
- `type=aid`에 `pwd=<정답>`을 실으면 `RESULT=1` + `AID`가 발급된다. 틀리면 `RESULT=0`.
  (정상방은 비번이 없으니 빈 `pwd`로도 `RESULT=1`+`AID`가 나온다 — 실측 확인)
- 스트림 배정 엔드포인트 `livestream-manager.sooplive.com/broad_stream_assign.html`는
  비번방에 대해서도 `view_url`(`auth_master_playlist.m3u8`)을 반환한다. 실제 인가는
  이 `view_url`에 붙이는 `?aid=<토큰>`으로 이뤄진다.

### 1-3. 현재 앱이 실패하는 지점
`SOOPAPIClient._fetchStreamInfo` → `fetchAID`가 항상 `pwd=`(빈값)로 `type=aid`를 호출한다.
비번방에서는 `RESULT=0`으로 AID를 못 받고, 비번방은 `TS`도 없으므로
`streamUnavailable("no auth available")`로 떨어진다 → "아예 접속 불가".

### 1-4. 결론: 구현 가능
클라이언트에서 사용자가 입력한 비밀번호를 `type=aid`(및 `type=live`)의 `pwd`로 전달하면
AID를 받아 `view_url+aid`로 재생할 수 있다. yt-dlp의 `--video-password` 동작과 동일하며,
서버측 우회가 아니라 정규 비밀번호 입력 경로다.

---

## 2. 기획

### 2-1. 데이터 계층 (`SOOPAPIClient`)
1. `SOOPAPIError`에 두 케이스 추가:
   - `.passwordRequired` — 비번방인데 비밀번호 미입력 (첫 진입 시 UI에 프롬프트 지시)
   - `.passwordIncorrect` — 비밀번호 틀림 (AID 미발급 → 재입력 유도)
2. `fetchStreamInfo(bjId:broadNo:password:completion:)` — `password: String? = nil` 추가.
   기존 호출부는 기본값으로 무변경 컴파일.
3. `_fetchStreamInfo`:
   - `type=live` 본문의 `pwd`에 입력 비번을 실어 보낸다(정답이면 TS를 바로 줄 수도 있어 고화질 우선).
   - `CHANNEL.BPWD == "Y"` 이고 `password`가 비어있으면 즉시 `.passwordRequired` 반환(1차 진입).
   - `fetchAID`에 비번 전달. 비번방인데 AID를 못 받으면 `.passwordIncorrect`로 매핑.
4. `fetchAID(bjId:broadNo:password:completion:)` — `pwd`에 비번(퍼센트 인코딩) 실어 전달.
5. 비밀번호 값은 `&`,`=`,공백,한글 등을 포함할 수 있어 form 본문에 넣기 전 퍼센트 인코딩.

### 2-2. UI 계층
- `UIViewController` 확장에 공용 헬퍼 `promptPassword(for:bjNick:retry:) -> Bool` 추가
  (`DesignSystem.swift`의 `showPlaybackError` 옆). tvOS 보안 텍스트필드 알림으로 비번 입력받아
  `retry(pwd)` 호출. 비번 에러가 아니면 `false` 반환 → 호출부가 기존 `showPlaybackError`로 폴백.
- 6개 재생 진입부(LiveList / Explore / Home 방송·즐겨찾기 / My / Search)에 동일 패턴 적용:
  - 진입 함수에 `password: String? = nil` 파라미터 추가, `fetchStreamInfo`에 전달.
  - `.failure` 처리에서 `promptPassword`가 처리하면 재입력 시 같은 함수를 비번과 함께 재호출,
    아니면 `showPlaybackError`.
  - Search는 인라인 블록을 `playBroadcast(_:password:)`로 최소 추출(재시도를 위해 필요).

### 2-3. 범위 밖 (의도적 비구현)
- 비번방 표시 배지(리스트에서 자물쇠 아이콘 등) — 이번엔 진입/재생만. (별도 개선 후보)
- 비밀번호 기억/자동입력 — 미구현.

---

## 3. 구현

변경 파일(비번방 기능 관련 7개. `PlayerViewController.swift`의 330줄 변경은 이전 사이클의 미커밋
작업으로 이번 범위와 무관):

### `SOOPAPIClient.swift`
- `SOOPAPIError`에 `.passwordRequired`, `.passwordIncorrect` 추가.
- `fetchStreamInfo(..., password: String? = nil, ...)` → `_fetchStreamInfo`로 전달.
- `_fetchStreamInfo`:
  - `type=live` 본문 `pwd`에 `formEncode(password ?? "")` 적용.
  - `CHANNEL.BPWD == "Y"` 이고 비번이 비어있으면 즉시 `.passwordRequired` 반환.
  - `fetchAID(..., password:)`로 비번 전달.
  - AID 미획득 + 비번방일 때, **AID 응답이 정상 파싱됐으나 발급 거부(RESULT=0)된 경우에만**
    `.passwordIncorrect`로 매핑. 네트워크/파싱 실패는 일반 `.streamUnavailable`로 유지
    (정답인데 일시 오류가 났을 때 "비번 틀림" 오표기 방지 — 검수 반영).
- `fetchAID(..., password: String? = nil, ...)` → `type=aid` 본문에 `pwd` 실음.
- `formEncode(_:)` 헬퍼 추가(영숫자 외 전부 퍼센트 인코딩).

### `DesignSystem.swift`
- `UIViewController.promptPassword(for:bjNick:retry:) -> Bool` 추가:
  `.passwordRequired`/`.passwordIncorrect`면 tvOS 보안 텍스트필드 알림 → `retry(pwd)`.
  그 외 에러면 `false` 반환(호출부가 `showPlaybackError`로 폴백).
  빈 값으로 "입장" 시 알림이 조용히 닫히지 않도록 프롬프트를 다시 띄움(검수 반영).

### 재생 진입부 6곳
`LiveListViewController`, `ExploreViewController`, `HomeViewController`(방송/즐겨찾기),
`MyViewController`, `SearchViewController`(인라인 블록을 `playBroadcast(_:password:)`로 최소 추출).
각 진입 함수에 `password: String? = nil` 추가 → `fetchStreamInfo`에 전달,
`.failure` 처리에서 `promptPassword`로 비번 흐름 처리 후 같은 함수를 비번과 함께 재호출.

---

## 4. 검수

### 컴파일
- `xcodegen generate` + tvOS 시뮬레이터(Apple TV 4K 3rd gen) Debug 빌드 → **BUILD SUCCEEDED**.

### 실서버 실측(분석과 동일 세션)
- 정상방: `type=aid` 빈 비번 → `RESULT=1`+AID (기존 경로 무변경 확인).
- 비번방: `type=live`는 어떤 비번이든 `RESULT=1 BPWD=Y`, TS 없음. `type=aid` 틀린 비번 → `RESULT=0`.
  `broad_stream_assign`는 비번방에도 `view_url` 반환. → 정답 비번 시 `view_url+aid`로 재생 성립.

### 적대적 코드리뷰(워크플로: 4개 차원 리뷰 → 발견 건별 반증 검증, 에이전트 16개)
확정된 결함 2건, 모두 수정 완료:
1. **(medium) 빈 비밀번호 dead-end** — 빈 값으로 "입장" 클릭 시 알림이 조용히 닫히고 아무 피드백
   없이 그리드로 복귀. → 빈 값이면 프롬프트를 다시 띄우도록 수정.
2. **(low) AID 실패 원인 혼동** — 비번방에서 네트워크/파싱 실패까지 "비밀번호 틀림"으로 표기될 수
   있음. → 서버가 정상 응답으로 발급을 거부한 경우(RESULT=0)에만 `.passwordIncorrect`로 매핑,
   일시적 오류는 일반 오류로 분리.

수정 후 재빌드 → **BUILD SUCCEEDED**.

### 원격 검증 불가(사람이 실기기에서 확인해야 함)
- 실제 비번방에 대한 올바른 비밀번호 입력 → 재생 성공은 유효한 비밀번호가 있어야 확인 가능하여
  이 세션에서 end-to-end 재생까지는 검증하지 못함. 메커니즘은 실측 + yt-dlp 동작으로 확정.
- tvOS 리모컨으로의 알림/키보드 상호작용은 아래 체크리스트로 실기기 확인 필요.

---

## 5. 수동 테스트 체크리스트 (실기기)

물리 Apple TV에서 리모컨으로 확인 필요(원격 검증 불가 항목):
- [ ] 일반(비번 없는) 방송 진입이 기존과 동일하게 즉시 재생되는가 (회귀 없음)
- [ ] 비번방 진입 시 비밀번호 입력 알림이 뜨는가
- [ ] 올바른 비밀번호 입력 시 재생되는가
- [ ] 틀린 비밀번호 입력 시 "올바르지 않습니다" 안내 후 재입력 알림이 다시 뜨는가
- [ ] 알림에서 "취소" 시 조용히 닫히고 앱이 정상 상태로 돌아가는가
- [ ] 즐겨찾기(broadNo=0) 경로의 비번방도 동일하게 동작하는가
