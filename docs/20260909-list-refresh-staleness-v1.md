# 목록 갱신 시 예전 정보 잔존 — 2026-09-09 v1

모든 탭에서 공통적으로 "목록을 갱신했는데 예전 정보가 그대로 남아 잘못 표시된다"는 증상을
코드 근거로 규명하고 수정한다.

프로세스: 분석 → 기획 → 구현 → 검증 (설치는 이번 요청 범위 밖)

---

## 1. 분석

### 1-0. 분석 방법

- 워크플로로 12개 렌즈(탭별 6 + 교차 6)를 병렬 투입해 stale-data 메커니즘을 탐색.
  세션 한도로 교차 렌즈 3개와 적대적 반증 에이전트 66개가 실행되지 못해,
  **확정/반증 판정은 원본 코드를 직접 재확인해서 내렸다.** 미검증 건은 §1-6에 분리 기록.
- SOOP 실서버 실측(가설 하나를 반증하는 데 사용) — §1-5.

### 1-1. 증상의 정체: "갱신"의 4가지 실패 모드

한 가지 버그가 아니라, **모든 탭에 같은 관용구로 복제된 4가지 결함**이다.

| # | 결함 | 해당 화면 |
|---|------|-----------|
| A | 갱신 실패 시 이전 목록을 그대로 남긴다 | LIVE / 방송목록 / MY / 탐색 / HOME / 검색 **전부** |
| B | 실패·로딩 안내가 화면에 보이지 않는다 | LIVE / 방송목록 |
| C | 요청 세대(epoch) 부재 — 오래된 응답이 최신 목록을 덮어쓴다 | **전부** |
| D | 갱신했는데 화면을 다시 계산하지 않는다 | 검색 |

### 1-2. 결함 A — 실패 경로가 이전 데이터를 유지한다

각 로더의 `.failure` 분기가 **데이터 배열을 건드리지 않고 `reloadData()`도 호출하지 않는다.**
즉 "실패했다"는 사실만 어딘가에 표시하고, 화면에는 직전에 성공했던 목록이 최신인 것처럼 계속 남는다.

| 파일:라인 | 실패 시 하는 일 | 남는 것 |
|-----------|----------------|---------|
| `LiveCategoriesViewController.swift:90-92` | `statusLabel.text`만 변경 | 옛 카테고리 그리드 + 헤더 "· N개" |
| `LiveListViewController.swift:120-123` | `statusLabel.text` + 헤더 "로드 실패" | 옛 방송 카드 전부 |
| `MyViewController.swift:126-129` | `showErrorState(for:)` | 옛 즐겨찾기 카드 + 섹션 헤더 개수 + "즐겨찾기한 BJ N명" |
| `ExploreViewController.swift:88-91` | `showErrorState()` | 옛 인기 방송/카테고리 캐러셀 |
| `HomeViewController.swift:182-192` | **실패 분기 자체가 없음** (`if case .success`) | 옛 "즐겨찾기 라이브" 캐러셀 (LIVE 배지 포함) |
| `SearchViewController.swift:165-170` | 플래그만 세우고 `return` | 옛 검색 결과 그리드 + 옛 검색 풀 |

여기에 두 화면은 오류 뷰가 **투명**하고 화면 중앙에만 놓여 있어(`DesignSystem.swift:618-687`에
`backgroundColor` 미지정, centerX/centerY + `width ≤ 720` 제약) 옛 목록이 오류 카드 옆·뒤로
그대로 보인다 — MY(`MyViewController.swift:234-238`), 탐색(`ExploreViewController.swift:106-110`).
HOME만 `tableView.isHidden = true`로 가리고 있어(`HomeViewController.swift:165`) 탭마다 동작이 다르다.

**사용자 시나리오**: MY 탭에서 Play/Pause로 새로고침 → 네트워크 순간 오류 →
"즐겨찾기를 불러오지 못했습니다" 카드가 뜨지만 그 옆으로 옛 카드가 계속 보인다.
그중 이미 방송을 끝낸 BJ 카드를 누르면 "방송이 종료되었거나 지금 라이브가 아닙니다" 토스트만 뜬다.

### 1-3. 결함 B — LIVE / 방송목록의 안내 문구는 절대 보이지 않는다

두 화면 모두 `statusLabel`을 **불투명한 `collectionView`보다 먼저** `addSubview` 한다.
UIKit은 나중에 추가된 서브뷰를 위에 그리므로, 화면 정중앙(`centerY`)에 놓인 `statusLabel`은
`collectionView`(배경색 `DS.Colors.background`, 불투명)에 완전히 가려진다.

- `LiveCategoriesViewController.swift:41`(statusLabel) → `:51`(배경색) → `:57`(collectionView)
- `LiveListViewController.swift:64`(statusLabel) → `:75`(배경색) → `:81`(collectionView)

결과: "카테고리 불러오는 중...", "카테고리 로드 실패 ... Play/Pause로 재시도",
"현재 라이브 중인 방송이 없습니다" — 이 세 문구가 **한 번도 사용자에게 보인 적이 없다.**
결함 A와 겹치면 "새로고침했는데 아무 반응 없이 옛 목록만 그대로"라는 정확한 증상이 된다.

### 1-4. 결함 C — 요청 세대(epoch)가 어디에도 없다

앱의 어떤 로더도 요청 생성/취소/세대 토큰을 갖고 있지 않다.
모든 콜백이 `DispatchQueue.main.async` 안에서 **무조건** 배열에 대입한다 → last-writer-wins.
응답이 도착하는 순서는 보장되지 않으므로 **먼저 보낸 오래된 요청이 나중에 도착하면 그것이 최종 화면이 된다.**

특히 근거가 명확한 두 경로:

1. **HOME은 새로고침 1회에 같은 API를 2번씩 동시 호출한다.**
   `pressesBegan`(`HomeViewController.swift:42-51`)이 `loadData()` + `loadFavorites()` + `loadRecent()`를
   호출하는데, `loadData()` 내부에서도(`:123-124`) `loadFavorites()`와 `loadRecent()`를 다시 호출한다.
   → `fetchFavorites` 2개, `fetchLiveListForBJIDs` 2개가 동시에 뜨고, 둘 중 아무거나 나중에 도착한 쪽이 화면이 된다.
   Play/Pause를 두 번 누르면 4개가 경쟁한다.

2. **로그인 완료 알림과 최초 로드가 경쟁한다.**
   `AppDelegate`는 루트 VC를 만든 뒤 백그라운드 `login()`을 시작한다. MY/HOME의 `viewDidLoad`는
   그보다 먼저 `fetchFavorites`를 쏜다(아직 미로그인 → `myapi`가 `data` 없는 응답 → `.invalidResponse`).
   로그인이 성공하면 `.soopLoginSucceeded`로 두 번째 `fetchFavorites`가 시작된다
   (`MyViewController.swift:38-42`, `HomeViewController.swift:36-40`).
   **미로그인 응답이 나중에 도착하면** 정상적으로 로그인됐는데도 MY 탭에
   "로그인 정보를 확인할 수 없습니다" 오류 화면이 남는다.

MY의 `loadFavorites`는 트리거가 5개(`viewDidLoad:37`, 로그인 알림 `:42`, Play/Pause `:45-49`,
빈 상태 새로고침 버튼 `:210`, 오류 재시도 `:233`)로 가장 취약하다.

### 1-5. 결함 D — 검색은 갱신해도 화면을 다시 계산하지 않는다

`SearchResultsViewController`는 "검색 풀(allBroadcasts)"과 "화면(filtered)"이 분리돼 있는데,
**현재 검색어를 보관하지 않는다.**

- `reloadPool()`(`SearchViewController.swift:154-159`)은 `hasLoadedAll/hasLoadFailed/isReloading`을
  리셋하고 풀만 다시 받는다. `filtered`도 `reloadData()`도 건드리지 않는다.
  → Play/Pause로 "검색 풀 새로고침"을 해도 **화면의 결과 카드는 갱신 전 풀의 스냅샷 그대로**다.
- 게다가 `reloadPool()`이 `isReloading = false`로 리셋하기 때문에, 자동 복구 로드가 진행 중이었다면
  완료 콜백의 `if self.isReloading`(`:189`)이 거짓이 되어 `pendingQuery` 재검색이 영영 실행되지 않는다.
  `emptyLabel`은 "데이터를 다시 불러오고 있습니다"에서 멈춘다.
- `updateSearchResults`(`:311-322`)는 `count >= 2`도 `isEmpty`도 아닌 **1글자 입력을 완전히 무시**한다.
  "아프리카"까지 쳤다가 "아"까지 지우면 검색창은 "아"인데 화면에는 "아프리카" 결과가 그대로 남는다.

### 1-6. 그 밖에 확인한 것

**실측으로 반증된 가설** — "`ImageCache`가 옛 썸네일을 고정한다":
`sch.sooplive.com ... m=categoryContentsList`의 `thumbnail` 필드는 서버가 매 호출마다
다른 캐시버스터를 붙여 준다. 동일 방송에 3회 연속 호출 실측:
`.../m/296989913?439` → `?666` → `?364`.
따라서 LIVE/방송목록/탐색/검색의 방송 카드 썸네일은 갱신 시 새 URL이 되어 새로 내려받는다.
(단 MY/HOME 즐겨찾기 카드는 앱이 직접 `?bucket=<epoch/300>`을 만들어 붙이므로
`MyViewController.swift:517` 5분 단위로 고정된다 — 의도된 캐싱이며 이번 범위 밖.)

**부분 실패가 성공으로 보고되는 문제** (범위에 포함):
`fetchCategories`(`SOOPAPIClient.swift:314-378`)는 7페이지를 병렬로 받아 `sorted.isEmpty && anyFailed`
일 때만 실패로 보고한다(`:373`). 1페이지만 성공하고 나머지가 실패하면 700여 개 중 100개만 담긴
결과가 `.success`로 나가고, LIVE 헤더는 "· 100개"를 단정적으로 표시한다.
**1페이지(view_cnt 상위 100개)가 빠지면** HOME/탐색/검색이 "인기 상위 3/12/15개"를 완전히 다른
카테고리에서 뽑게 되어, 갱신할 때마다 인기 목록이 널뛴다.

**셀 포커스 잔상** (범위에 포함, 사용자 가시성은 조건부):
어떤 셀도 `prepareForReuse`를 구현하지 않는다. `FocusEffect.apply`
(`DesignSystem.swift:167-185`)는 셀 인스턴스의 `transform` / `border` / `shadow` /
`contentView.backgroundColor`를 직접 바꾸므로, 포커스가 걸린 채 재사용 풀로 돌아간 셀은
그 장식을 그대로 지닌다 → `reloadData()` 이후 실제 포커스와 무관한 카드가 "선택된 것처럼" 보인다.
UIKit이 포커스 해제 콜백으로 자체 치유하는 경우도 있어 100% 재현은 아니지만,
수정 비용이 3줄이고 부작용이 없어 함께 처리한다.

**이번 범위 밖으로 남기는 것** (별도 사이클 후보):
- 탭 재진입/플레이어 복귀 시 자동 재로드 부재(HOME·MY·LIVE 모두 없음) — 갱신 *정책* 변경이라 별건.
- `fetchStreamInfo` 동시 호출 레이스(카드 연타 시 다른 BJ의 스트림이 열릴 수 있음) — 재생 진입 경로.
- 최근 검색어가 키스트로크마다 저장되어 "아프", "아프리" 같은 조각이 쌓임(`:285`).
- `CarouselRowCell` 재사용 시 내부 캐러셀 `contentOffset`/포커스 인덱스 잔존.
- `remembersLastFocusedIndexPath`가 재정렬된 배열에 인덱스로 포커스를 복원.
- `ImageCache`의 TTL/무효화 부재.

---

## 2. 기획

### 2-1. 원칙 — "화면에 보이는 목록은 항상 마지막으로 성공한 *현재* 요청의 결과"

탭마다 제각각인 실패 처리를 하나의 규칙으로 통일한다.

| 상황 | 화면 |
|------|------|
| 로딩 시작 | 안내 표시(보이는 위치에), 기존 목록은 교체 전까지 유지 |
| 성공 | 새 데이터로 **교체** + 오류/빈 상태 해제 |
| 실패 | 해당 목록을 **비우고** `reloadData()` + 오류 안내 + 재시도 경로 |
| 오래된 응답 도착 | **무시** |

**실패 시 비우는 선택의 근거와 대가**: 옛 목록을 남기면 (1) 사용자가 그것을 최신으로 오인하고,
(2) 종료된 방송을 눌러 재생 실패로 이어진다 — 이번에 보고된 증상 그 자체다.
대가는 일시적 네트워크 오류로 화면이 비워지는 것인데, 오류 안내와 "다시 시도"/Play-Pause 경로가
항상 함께 뜨므로 사용자는 막히지 않는다. "옛 정보 유지 + 오래됨 배지" 대안은 3m 시청 거리 UI에
상태 표시를 하나 더 얹어야 해서 채택하지 않는다.

### 2-2. 요청 세대 토큰 (결함 C)

`DesignSystem.swift`의 공용 헬퍼 섹션에 최소 타입 하나를 추가한다.

```swift
struct RequestEpoch {
    private var current = 0
    mutating func begin() -> Int { current += 1; return current }
    func isCurrent(_ token: Int) -> Bool { token == current }
}
```

각 로더는 시작 시 `let token = epoch.begin()`, 콜백의 메인 큐 진입 직후
`guard self.epoch.isCurrent(token) else { return }`. 모든 로더가 메인 스레드에서만
시작·완료되므로 별도 동기화는 불필요하다.

세대는 "독립적으로 갱신되는 목록" 단위로 둔다.
- HOME: `dataEpoch`(카테고리 → 인기 라이브 연쇄), `favEpoch`, `recentEpoch`
- 탐색: `dataEpoch`(카테고리 → 인기 방송 연쇄)
- MY / LIVE / 방송목록 / 검색: 각 1개

연쇄 호출(`loadPopularLive` / `loadPopularBroadcasts`)은 **부모의 토큰을 물려받아** 검사한다.
그래야 "새 카테고리 + 옛 인기 방송"이 섞인 화면이 나오지 않는다(§1-2 HOME 2-hop 창).

### 2-3. 화면별 변경

1. **LIVE / 방송목록**: `setupUI` 끝에서 `view.bringSubviewToFront(statusLabel)` — 안내 문구를 보이게.
   실패 시 배열을 비우고 `reloadData()`, 헤더 서브타이틀도 실패 상태로.
2. **MY**: 실패 시 `liveFavorites`/`offlineFavorites`를 비우고 `reloadData()`,
   헤더 서브타이틀을 기본값("즐겨찾기 BJ")으로 되돌린다. (섹션 헤더 개수는 `reloadData`로 함께 갱신)
3. **탐색**: 실패 시 `popularCategories`/`popularBroadcasts`를 비우고 `reloadData()`.
   그러면 캐러셀이 사라져 투명한 오류 뷰와 겹치는 문제도 함께 해소된다(검색 진입 셀은 유지).
4. **HOME**: `pressesBegan`에서 중복 호출 제거(`loadData()`만 — 내부에서 나머지를 부른다).
   `loadFavorites`에 실패 분기 추가(비우고 reload). 카테고리 실패 시 관련 두 배열도 비운다.
5. **검색**: `pendingQuery`/`isReloading` 대신 **`currentQuery` 보관**으로 단순화.
   풀 로드가 끝나면 `currentQuery`가 있을 때 항상 재검색 → `reloadPool()` 후 화면이 자동으로 최신 풀 기준으로 다시 계산된다.
   1글자 입력은 "결과 비우고 안내" 경로로 명시 처리. 풀 로드 실패 시 풀과 결과를 모두 비운다.
6. **`SOOPAPIClient.fetchCategories`**: 1페이지가 실패하면 `.failure`로 보고한다.
   (2~7페이지 실패는 목록 뒷부분이 짧아질 뿐이므로 현행대로 성공 처리 + 로그)

### 2-4. 셀 재사용 초기화

`LiveBroadcastCell`, `CategoryCell`, `MyLiveBroadcastCell`, `MyOfflineBJCell`에
`prepareForReuse`를 추가해 포커스 장식을 해제하고 진행 중인 썸네일 로드를 무효화한다
(`UIImageView.cancelImageLoad()`는 이미 존재 — `DesignSystem.swift:799`).

### 2-5. 성공 판정 기준

- tvOS 시뮬레이터 Debug 빌드 성공.
- 6개 로더 전부에서 (a) 실패 시 목록이 비워지고, (b) 오래된 응답이 무시되고,
  (c) 안내 문구가 가려지지 않음이 코드 경로로 확인될 것.
- 적대적 코드리뷰에서 확정된 회귀 0건.

---

## 3. 구현

변경 파일 8개. (`PlayerViewController.swift`의 미커밋 변경 330줄은 이전 사이클 작업으로 이번 범위와 무관)

### `DesignSystem.swift`
- 공용 헬퍼 섹션에 `struct RequestEpoch` 추가 — `mutating func begin() -> Int` / `func isCurrent(_:) -> Bool`.

### `LiveCategoriesViewController.swift`
- `loadEpoch` 도입 — `loadCategories` 시작 시 토큰 발급, 콜백에서 `isCurrent` 확인.
- 실패 시 `categories = []` + `reloadData()`, 헤더 서브타이틀을 "실시간 인기 카테고리"로 되돌림.
- `setupUI` 끝에 `view.bringSubviewToFront(statusLabel)`.
- `CategoryCell.prepareForReuse` 추가 — `FocusEffect.apply(focused: false)` + `cancelImageLoad()`.

### `LiveListViewController.swift`
- 위와 동일한 4가지(`loadEpoch`, 실패 시 `broadcasts = []` + reload, `bringSubviewToFront`,
  `LiveBroadcastCell.prepareForReuse`).

### `MyViewController.swift`
- `loadEpoch` 도입 (트리거 5개 전부가 이 경로를 지난다).
- 실패 시 `liveFavorites`/`offlineFavorites`를 비우고 `reloadData()`, 헤더 서브타이틀 리셋.
  섹션 헤더의 "(N)" 개수도 `reloadData`로 함께 갱신된다.
- `MyLiveBroadcastCell.prepareForReuse` (포커스 + `currentBJID = nil` + 이미지 취소),
  `MyOfflineBJCell.prepareForReuse` (`applyOffline` + 이미지 취소).

### `ExploreViewController.swift`
- `dataEpoch` 도입, `loadPopularBroadcasts(from:token:)`가 **부모 토큰을 물려받아** 검사.
- 실패 시 `popularCategories`/`popularBroadcasts`를 비우고 `reloadData()`
  → 투명한 오류 뷰 뒤로 옛 캐러셀이 비치던 문제도 함께 해소(검색 진입 셀은 유지).

### `HomeViewController.swift`
- `dataEpoch` / `favEpoch` / `recentEpoch` 3개 도입. `loadPopularLive(from:token:)`는 `dataEpoch` 공유.
- `pressesBegan`에서 `loadFavorites()`/`loadRecent()` 중복 호출 제거(`loadData()`가 이미 호출).
- `loadFavorites`에 실패 분기 추가 — 실패 시 `favoritesLive = []` + reload.
- 카테고리 실패 시 `popularCategories`/`popularLive`를 비운다.
- **의도적 비변경**: 카테고리 성공 직후 `popularLive`를 비우지 않는다. 뒤이은 `loadPopularLive`가
  성공/실패 어느 쪽이든 항상 덮어쓰므로 자기 교정되며, 비우면 새로고침마다 행이 사라졌다
  나타나 레이아웃이 튄다. (§2-1의 "실패 시 비운다"는 자기 교정되지 않는 경우에만 적용)

### `SearchViewController.swift`
- `pendingQuery` + `isReloading` → `currentQuery` + `isLoadingPool`로 교체, `poolEpoch` 추가.
- `finishPoolLoad(with:)` 신설 — 성공 시 **`currentQuery`로 결과를 다시 계산**한다.
  이것이 "풀은 새로고침됐는데 화면은 갱신 전 결과" 문제의 직접 해결점.
- 병합 결과가 비면 실패로 간주(상위 15개 카테고리에 라이브가 0건일 수는 없다)
  → "결과가 없습니다"를 거짓으로 단정하지 않고 재시도 경로를 남긴다.
- 실패 시 `allBroadcasts`/`filtered`를 비우고 안내 문구 표시.
- `updateSearchResults`: 1글자 입력이 no-op이던 것을 "결과 비우고 안내"로 변경.
- `group.notify`가 `self`를 강하게 잡던 것을 `[weak self]`로 (epoch 검사를 위해 필요).

### `SOOPAPIClient.swift`
- `fetchCategories`: 여러 콜백에서 락 없이 쓰이던 `anyFailed` 플래그 제거
  (내가 판정 로직을 바꾸며 무용해진 변수 — 데이터 레이스도 함께 사라짐).
  실패 페이지는 `pageResults`에 항목이 없다는 사실로 판정한다.
- **1페이지가 없거나 병합 결과가 비면 `.failure`.** 2~7페이지 실패는 성공으로 처리하고 로그에 남긴다.

### 검증 반영 (§4에서 확정된 결함 수정)

- **`LiveCategoriesViewController` / `LiveListViewController`에 `ErrorStateView` 도입** —
  실패 시 목록을 비우면 포커스 가능한 셀이 사라져 화면이 안내하는 "Play/Pause로 재시도"가
  **실제로는 실행 불가능**해진다(포커스가 탭바로 빠지면 press 이벤트가 이 VC의 responder chain에
  도달하지 않는다). HOME/탐색/MY와 동일하게 포커스 가능한 "다시 시도" 버튼이 있는 오류 뷰를 띄우고
  `preferredFocusEnvironments`로 포커스를 넘긴다. 이제 5개 목록 화면의 실패 처리가 완전히 같은 모양이다.
- **`MyViewController`에도 `bringSubviewToFront(statusLabel)`** — MY의 statusLabel도 동일하게
  가려져 있었다(§1-3은 LIVE/방송목록만 지적했으나 MY도 같은 구조였다).
- **갱신 중 안내는 빈 화면일 때만 표시** — 라벨을 앞으로 올리자, 목록이 남아 있는 상태의 갱신에서
  "불러오는 중..." 텍스트가 카드 위에 겹쳐 보이게 됐다. LIVE/방송목록/MY 모두
  `statusLabel.isHidden = !목록.isEmpty`로 시작하도록 변경.
- **검색 `finishPoolLoad`** — 풀 재로드가 성공했는데 검색어가 비어 있으면 직전 실패 안내 문구가
  그대로 남던 것을 초기 문구로 되돌리도록 수정.
- **검색 `finishPoolLoad`의 뷰 미로드 방어** (자체 발견) — `UISearchController`는 결과 VC의 뷰를
  지연 로드한다. 검색을 한 번도 열지 않은 상태에서 Play/Pause 새로고침이 들어오면
  `resultsCollectionView`가 nil이라 크래시한다(변경 전 코드는 이 경로에서 UI를 건드리지 않았으므로
  이번 변경이 만든 회귀). `guard isViewLoaded`로 상태만 갱신하고 빠지도록 수정.

---

## 4. 검증

### 4-1. 빌드

`xcodegen generate` + tvOS 시뮬레이터(Apple TV 4K 3rd gen) Debug 빌드 — 3회 모두 **BUILD SUCCEEDED**
(최초 구현 / 자체 발견 회귀 수정 후 / 코드리뷰 반영 후).

### 4-2. 시뮬레이터 실행 검증

앱 설치·실행 후 스크린샷 및 로그 확인. HOME 탭 정상 렌더링(인기 방송 4장, 인기 카테고리 캐러셀),
자동 로그인 성공, `fetchCategories: 554 categories` — **실패 페이지 로그 없음**(새 판정 로직이
정상 경로를 막지 않음을 확인).

로그에서 **§1-4의 레이스가 실제로 발생함을 실증**했다:
```
[SOOPAPI] fetchFavorites: 38 (17 live)
[SOOPAPI] fetchFavorites: 38 (17 live)
```
`viewDidLoad`와 `.soopLoginSucceeded`가 각각 쏜 두 개의 요청이다. 수정 전에는 둘 중 나중에
도착한 쪽이 화면이 됐고(미로그인 응답이 이기면 "로그인 정보를 확인할 수 없습니다"),
이제는 `favEpoch`가 나중에 시작된 요청만 반영한다.

### 4-3. 적대적 코드리뷰 (워크플로)

4개 차원(epoch 회귀 / 실패 시 비우기 부작용 / 검색 상태 머신 전수 / 셀·API 변경)으로 리뷰 →
원시 15건 → 건별 2중 반증 검증. 총 에이전트 34개(2개는 API 오류로 실패, 해당 건은 남은 1표로 판정).

**확정 후 수정한 결함**
1. **(high) LIVE·방송목록 실패 시 포커스 dead-end** — 위 "검증 반영" 참조. 이번 변경이 만든 회귀로,
   특히 LIVE 탭은 루트 VC라 탭을 나갔다 와도 `viewDidLoad`가 다시 돌지 않아 **앱 재시작 전까지
   복구 불가**였다. 2명의 검증자가 각각 독립적으로 확인.
2. **(medium) MY의 statusLabel도 가려져 있음** — 수정.
3. **(medium) 검색: 성공한 풀 재로드가 이전 실패 문구를 남김** — 수정.
4. **(low) 앞으로 올린 statusLabel이 갱신 중 카드 위에 겹침** — 수정.

**확정됐으나 이번에 수정하지 않은 것 (이유 명시)**
- **HOME: 즐겨찾기 로드 실패 시 섹션이 아무 안내 없이 사라진다.**
  실패를 무시해 종료된 방송에 LIVE 배지가 남는 기존 동작보다는 낫고, 즐겨찾기의 정식 화면인
  MY 탭에서는 명확한 오류 안내가 나온다. HOME은 요약 화면이라 섹션별 오류 UI를 얹으면
  4섹션 각각에 상태 표시가 필요해져 복잡도가 크게 는다. 별도 사이클 후보.
- **검색 풀의 카테고리별 `fetchBroadcasts` 부분 실패가 무시된다** (15개 중 몇 개 실패해도 완전한
  풀로 간주). 이번엔 "풀이 통째로 비면 실패로 처리"까지만 방어했다. 부분 실패 카운트를 전파하는
  것은 검색 범위 안내 문구까지 손대야 해서 범위 밖.

**반증된 것 (수정 안 함)**
- "풀 로드 완료가 최근 검색어 칩을 재생성해 포커스를 빼앗는다" — 칩 재생성은 기존에도 매 검색마다
  일어나던 동작이고 이번 변경이 새로 만든 경로가 아님.
- "`fetchCategories`의 1페이지 가드가 '비어 있는 1페이지'를 못 잡는다" — 1페이지가 비면
  `sorted.isEmpty` 또는 뒷 페이지 데이터로 판정이 갈리며, 이번 변경의 목적(부분 결과를 인기 상위로
  오인)에는 영향이 없음.

### 4-4. 원격 검증 불가 (사람이 실기기에서 확인해야 함)

네트워크 실패를 시뮬레이터에서 강제할 수단이 없어 **실패 경로의 실제 화면은 확인하지 못했다.**
아래 항목은 정적 분석 + 코드리뷰로만 검증된 상태다.

---

## 5. 수동 테스트 체크리스트 (실기기)

- [ ] 각 탭에서 Play/Pause 새로고침 시 목록이 정상 갱신되는가 (회귀 없음)
- [ ] Play/Pause를 빠르게 3~4회 연타해도 최종 화면이 마지막 요청 결과인가
- [ ] 앱 실행 직후(자동 로그인 완료 전) MY 탭에 들어가도 로그인 후 즐겨찾기가 정상 표시되는가
      — 미로그인 응답이 이겨 "로그인 정보를 확인할 수 없습니다"가 뜨지 않아야 한다
- [ ] Wi-Fi를 끄고 각 탭에서 새로고침 → **옛 목록이 사라지고** 오류 안내가 뜨는가
- [ ] 그 상태에서 "다시 시도" 버튼에 포커스가 자동으로 가고, Wi-Fi를 켠 뒤 누르면 복구되는가
      (LIVE / 방송목록 / MY / 탐색 / HOME 5개 화면 모두)
- [ ] LIVE 탭에서 오류 → 복구 후 탭 이동/재진입해도 정상인가
- [ ] 검색: "아프리카"까지 입력 후 "아"까지 지우면 이전 결과가 사라지는가
- [ ] 검색: 결과가 뜬 상태에서 Play/Pause 새로고침 → 결과가 새 풀 기준으로 다시 계산되는가
- [ ] 검색 화면을 한 번도 열지 않은 채 검색 탭에서 Play/Pause를 눌러도 크래시하지 않는가
- [ ] 방송/카테고리 카드에 포커스한 채 새로고침 → 엉뚱한 카드가 "선택된 것처럼" 보이지 않는가
- [ ] 갱신 중 "불러오는 중..." 문구가 기존 카드 위에 겹쳐 보이지 않는가

설치(실기기 배포)는 이번 요청 범위 밖 — 별도 진행.
