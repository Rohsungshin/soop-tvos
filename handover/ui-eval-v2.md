# UI/UX 개선 평가 보고서 v2

> 작성일: 2026-05-29
> 대상: `/Volumes/MacMiniUsb/soop-app`
> 평가 기반: `ui-plan-v2.md`, `ui-eval-v1.md`(74점), 실구현 Swift 파일 8종 + `DesignSystem.swift`
> 빌드 결과: **BUILD SUCCEEDED** (Apple TV 4K (3rd generation) Simulator)

---

## 종합 점수: 95/100  (v1 74점 대비 +21점)

v1 평가서의 **모든 필수·중요 액션 아이템(1~12번)이 코드 레벨에서 해결**되었음을 확인했다. HOME 탭이 첫 진입 4섹션으로 신설되었고, SearchViewController가 클라이언트 사이드 필터링 + 최근 검색어 칩으로 실구현되었으며, LoadingSkeletonView · ImageCache · RecentWatchStore · LoadingOverlayView가 모두 한 곳에 모여 있다. 매직 넘버 / 하드코딩 컬러 / `contentEdgeInsets` deprecated 경고 모두 토큰화되었고, MyLiveBroadcastCell의 닉네임 중복 버그 · MyOfflineBJCell 포커스 무차별화 · Player 무한 retry 모두 코드에 반영되었다.

다만 **(1) Player 화면의 시청자수/방송시간 오버레이 부재** (v1 D항목 마지막 약점), **(2) 30초 자동 시청자수 갱신 부재**, **(3) SOOP 워드마크/브랜드 식별 요소 부재** 등 v1의 "디테일(98→100점)" 영역 일부가 여전하다. 사용자 입장에선 "거의 완벽하지만 마지막 5%"의 미완.

---

### A. 첫인상 / 디자인 일관성: 19/20

**v1 대비 개선**
- v1 16점에서 +3점. 토큰 적용률이 사실상 100%에 도달.
- `DS.Typography.subsection` (28pt) / `subcaption` (18pt) 토큰 추가로 v1에서 4곳 중복되던 28pt 하드코딩 완전 제거. `grep "UIFont.systemFont(ofSize: 28"` 결과 `DesignSystem.swift` 1곳(정의)만 매칭.
- `DS.Layout.screenWidth` / `messageCardWidth` / `headerTopOffset` / `gridTopGap` 등 레이아웃 토큰 신설로 `1920` / `60` / `30` / `24` 등 매직 넘버가 사실상 사라짐.
- `DS.ButtonInsets.cta`(`NSDirectionalEdgeInsets(top:14,leading:36,bottom:14,trailing:36)`) 토큰으로 `MyViewController.swift:157` · `PlayerViewController.swift:441,455`이 일관되게 사용. `UIButton.Configuration` 마이그레이션 완료, deprecated 경고 제거.
- `DS.Colors.overlay` 사용 + `LoadingOverlayView` 단일 클래스화로 v1의 "dim 컬러 3곳 중복" 해소.

**강점**
- 색상/타이포/간격/코너/카드사이즈/레이아웃/버튼인셋/포커스효과를 한 enum(`DS`)에 깔끔하게 모은 구조. 9개 화면이 모두 동일 토큰 사용.
- 탭바도 다크 톤(`DS.Colors.background`) + 선택/비선택 컬러 일관 적용. SF Symbol 아이콘(`house`/`dot.radiowaves.left.and.right`/`magnifyingglass`/`person.circle`)으로 시각 깊이 추가.
- `LoadingSkeletonView`의 shimmer 그라데이션이 다크 모드 톤(#1C1C20 → 25% white → #1C1C20)에 잘 맞춤.

**약점 (1점 감점)**
- **SOOP 브랜드 워드마크 부재** — RootTabBarController의 좌측 상단이나 HOME 헤더 어디에도 "SOOP" 텍스트 로고가 없다. v1 평가서 디테일 #17 미구현. 첫 진입 시 사용자가 "SOOP 앱"임을 알 단서는 빨강 LIVE 배지(#F23C3C)뿐.
- `MyViewController.swift:495, 502`의 `UIColor(white: 0, alpha: 0.35)` · `UIColor(white: 0, alpha: 0.65)`는 오프라인 다크 오버레이용으로 의도된 값이지만 `DS.Colors.viewerBadgeBackground`(0.65)와 동일한 값을 토큰화 안 함. 사소한 일관성 흠.

---

### B. 정보 위계 / 가독성: 19/20

**v1 대비 개선**
- v1 15점에서 +4점. 핵심 카드 위계 + 버그 모두 해결.
- **`LiveBroadcastCell.titleLabel.font = DS.Typography.cardTitleLarge` (26pt)** 적용 (`LiveListViewController.swift:240`). BJ는 16pt → 10pt 차이로 위계 확보, 3m 거리 가독성 개선.
- **`MyLiveBroadcastCell`의 닉네임 중복 버그 수정** (`MyViewController.swift:427-438`):
  ```swift
  let hasStation = !f.stationName.isEmpty && f.stationName != f.nick
  if hasStation { titleLabel.text = f.stationName; bjLabel.text = f.nick }
  else { titleLabel.text = f.nick; bjLabel.text = "라이브 방송 중" }
  ```
  v1에서 stationName이 비면 같은 글자가 위·아래에 표시되던 문제 해결.
- **`CategoryCell.titleLabel.numberOfLines = 2`** (`LiveCategoriesViewController.swift:163`). "리그 오브 레전드" 등 긴 카테고리명 잘림 해소.
- 시청자수 배지 폰트는 여전히 14pt(`DS.Typography.tiny`)인데, LIVE 배지(`badge` 16pt)가 더 굵어 위계 자체는 분명.

**강점**
- `Int.koreanCount()`로 "1.2만" 자동 포맷 유지. 1080p 3m 거리에서 짧고 명확.
- CategoryCell의 ●(노란 점) + "시청 중" 패턴, LIVE 배지(빨강) + 시청자수(반투명 검정)의 보색 대비 효과적.
- 빈 상태(`MyViewController.showEmptyState`)에서 `subsection` 28pt → `body` 20pt → `cardTitle` 22pt 버튼 위계가 명확.

**약점 (1점 감점)**
- 시청자수 배지 폰트 14pt → 16pt 미적용 (v1 디테일 #14). `DS.Typography.tiny`(14pt)를 그대로 쓰는데, `badge`(16pt) 토큰이 LIVE 배지에만 적용되고 시청자수에는 안 씀. 일관성·가독성 둘 다 살짝 미흡.
- Player의 해상도 라벨 "HD\n720×720" 표기 모호성(v1 #16) 여전. `case ...540: "HD"`, `case ...720: "HD+"`로 분리되었으나 "HD"가 540p인지 720p인지 사용자 학습 필요. "540p / 720p / 1080p" 직접 표기가 더 명확.

---

### C. 리모컨 사용성 / 포커스: 19/20

**v1 대비 개선**
- v1 13점에서 +6점. 모든 셀에 일관된 포커스 효과 + 오프라인 카드 차별화.
- **`MyOfflineBJCell`에 회색 보더(`DS.Colors.focusBorderOffline`) 포커스 차별화** 적용 (`MyViewController.swift:549-563`). v1 약점 M2 해소.
- `FocusEffect.applyBorder(to: container, focused:)`가 `ExploreViewController.SearchEntryCell` + `SearchViewController.RecentChipButton`에 일관 적용. 비-카드 요소도 포커스 시각 단서.
- 모든 컬렉션뷰에 `remembersLastFocusedIndexPath = true` 유지.

**강점**
- `LiveListViewController.preferredFocusEnvironments`로 진입 시 즉시 카드에 포커스.
- HOME / Explore / MY / Search 각 화면에서 헤더는 포커스 불가, 카드/칩만 포커스 — 흐름이 명확.
- `RecentChipButton`의 `canBecomeFocused = true` + `applyBorder` 조합으로 칩 자체가 포커스 가능.

**약점 (1점 감점)**
- **Search 화면의 UISearchBar 포커스 흐름이 tvOS 한정 케이스에서 모호** — `searchBar.searchBarStyle = .minimal`은 작동하지만, tvOS의 검색 입력은 별도 search controller가 일반적. UISearchBar를 직접 사용하면 키보드 진입 시 화면 전환 효과가 어색할 수 있다(코드만으론 확정 불가, 시뮬레이터 실행 테스트 필요).
- HOME의 nested UITableView → CarouselRowCell.collectionView 구조에서 위→아래 키 누를 때 캐러셀 내부 셀로 포커스 이동이 가능한지 모호 (v1 약점 그대로). 검증되진 않았으나 위험 영역.
- Player 에러카드의 "다시 시도/돌아가기" 사이 간격 24pt(`-12, +12`) — 두 버튼이 화면 중심에서 12pt씩 떨어져 있는데 기본 포커스 어느 쪽인지 명시 안 됨(v1 약점 잔존).

---

### D. 화면별 완성도: 19/20

**v1 대비 개선**
- v1 14점에서 +5점. HOME / Search 신규 화면 모두 실제로 동작.
- **HOME 탭 신설** (`HomeViewController.swift`): 4섹션(인기 라이브 / 인기 카테고리 / 최근 시청 / 즐겨찾기 라이브) 모두 실데이터 연동. 첫 진입 탭(`selectedIndex = 0`)이 HOME.
- **SearchViewController 실구현** (`SearchViewController.swift:177-199`): 상위 5개 카테고리 머지 → `bjNick`/`title` 필터링 → 결과 그리드. `addRecent` + UserDefaults 영속화로 최근 검색어 칩 동작. 빈 결과 시 `"\"\(query)\"에 대한 결과가 없습니다"` 인라인 표시.
- **LoadingSkeletonView** (`DesignSystem.swift:387-512`): `carousel` / `categoryGrid` / `broadcastGrid` 3종 스타일 + shimmer 애니메이션. HomeViewController가 `.carousel`로 실제 사용.
- **RecentWatchStore** (`HomeViewController.swift:330-385`): UserDefaults Codable 영속화로 PlayerViewController 진입 시 자동 저장 (`LiveListViewController` `ExploreViewController` `SearchViewController` `HomeViewController` 4곳에서 `RecentWatchStore.shared.save(bc)` 호출 — 실제로는 HOME/Search/Explore 3곳).
- ExploreViewController 검색 셀 → SearchViewController push (`ExploreViewController.swift:196-202`). v1의 placeholder 토스트 제거.

**강점**
- HOME의 4섹션을 빈 데이터 시 자동 숨김(`numberOfRowsInSection` 0 반환) 처리로 첫 진입 시 잡음 최소화.
- PlayerViewController의 pre-roll(블러 썸네일 + 제목 + BJ + 스피너) 그대로 유지 — 빈 검정 화면 문제 해결.
- 빈 상태 + `UIButton.Configuration` 기반 새로고침 CTA(`MyViewController.showEmptyState`) 깔끔.

**약점 (1점 감점)**
- **Player 화면의 시청자수/방송시간 오버레이 부재** (v1 #19, P4): 재생 중 사용자가 채팅·시청자수·방송 시작 시간을 알 수 없음. 디테일 영역이지만 "완성도"엔 영향.
- 30초 시청자수 자동 갱신(v1 #20) 미적용. HOME/Explore의 인기 방송 시청자수가 화면 진입 시점에 고정됨. `Timer.scheduledTimer` 한 줄로 해결 가능.
- HOME의 `loadPopularLive`가 항상 상위 3개 카테고리 머지로 고정 — "추천" 알고리즘이 없어 매번 같은 결과(예: 핫이슈/스타크래프트/리그오브레전드)만 나옴. 사용자가 새로 볼 콘텐츠 없음.

---

### E. 디테일 / 마감: 19/20

**v1 대비 개선**
- v1 16점에서 +3점. 코드 중복 / 매직 넘버 / deprecated 경고 모두 해결.
- **LoadingOverlay 공용화 완료** (`DesignSystem.swift:313-381`): `LiveListViewController` · `ExploreViewController` · `MyViewController` · `HomeViewController` · `SearchViewController` 5곳 모두 `LoadingOverlayView.show(in:message:)` 호출. v1의 "3곳 복붙" 완전 제거.
- **ImageCache 도입** (`DesignSystem.swift:518-602`): `NSCache<NSURL, UIImage>` 기반, `totalCostLimit = 50MB` / `countLimit = 200`. `UIImageView.loadImage(from:placeholder:completion:)` extension으로 6개 셀(`CategoryCell` `LiveBroadcastCell` `MyLiveBroadcastCell` `MyOfflineBJCell` `posterImageView` 등)에서 일관 사용. `currentLoadToken: UUID`로 셀 재사용 시 stale response 방지.
- **Player retry 무한 루프 방지** (`PlayerViewController.swift:299-307`): `retryCount` / `maxRetries = 3` / 초과 시 "여러 번 시도했지만 연결되지 않습니다. 잠시 후 다시 시도해 주세요" 카드. `retryTapped`에서 `retryCount = 0`으로 리셋 — 사용자 명시적 재시도는 항상 허용.
- **`contentEdgeInsets` → `UIButton.Configuration`** 완료 (`MyViewController.swift:153-164`, `PlayerViewController.swift:438-464`): `var btnConfig = UIButton.Configuration.filled()` 패턴, `contentInsets = DS.ButtonInsets.cta` 토큰 사용. deprecated 경고 제거.
- **빌드 통과 확인**: `xcodebuild ... BUILD SUCCEEDED` (Apple TV 4K 3세대 시뮬레이터).

**강점**
- 한국어 라벨 자연스러움 유지: "지금 방송 중", "오프라인", "최근 검색어가 없습니다", "방송 연결 중...", "안정 모드".
- 토스트 일관성: 오프라인 BJ 선택, 재생 실패, 데이터 준비 중 등 모달 alert 없이 인라인 토스트.
- `MyLiveBroadcastCell`의 라이브 썸네일 캐시 키 `?bucket=\(Int(Date().timeIntervalSince1970) / 300)` — 5분 단위 캐시 키로 v1의 "매번 다시 fetch" 해소.

**약점 (1점 감점)**
- HOME의 `loadFavorites`에서 `RecentWatchStore.shared.save`는 호출되지 않음 — `didSelectFavorite`에서 즉시 재생 진입 시 즐겨찾기 라이브 클릭은 최근 시청 기록에 안 남음. 의도일 수도 있으나 "최근 시청" 섹션과의 일관성 미흡.
- `RecentChipButton`의 포커스 시 scale 1.03이지만 chip 자체가 작아(높이 50pt) 포커스 차별화가 약간 약함. 색상 또는 보더 굵기 강화 가능.
- 검색 결과 빈 상태 메시지 `"\"\(query)\"에 대한 결과가 없습니다"`가 화면 정중앙에 표시되는데 (collectionView 위에 emptyLabel 표시 + collectionView 비움), `emptyLabel`의 `centerYAnchor` 가 view 중앙 기준이라 키보드 표시 시 가려질 수 있음.
- `HomeViewController.skeletonView`가 `loadPopularLive` 완료 후에만 hide 됨 — `loadFavorites`/`loadRecent`가 먼저 끝나도 스켈레톤이 계속 보임. 보통은 문제 없으나 인기 라이브가 0개로 비는 케이스에선 스켈레톤이 영영 안 사라질 수 있음.

---

## v1 감점 요인 해결 체크리스트

- [x] HOME 탭 신설 — `HomeViewController` + `RootTabBarController.swift:46-47` `selectedIndex = 0`
- [x] SearchViewController 실구현 — `SearchViewController.swift`, 클라이언트 사이드 필터 + 최근 검색어 칩 + UserDefaults
- [x] LoadingSkeleton 도입 — `DesignSystem.swift:387-512` 3종 스타일, HomeViewController에서 실사용
- [x] LoadingOverlay 공용화 (3곳 복붙 제거) — `DesignSystem.swift:313-381` `LoadingOverlayView.show(in:message:)`, 5개 VC에서 일관 사용
- [x] 이미지 캐시 도입 — `DesignSystem.swift:518-602` `ImageCache.shared` + `UIImageView.loadImage` extension, 6개 셀에서 사용
- [x] cardTitleLarge 26pt 적용 — `LiveListViewController.swift:240`, `MyViewController.swift:392`
- [x] 카테고리 2줄 지원 — `LiveCategoriesViewController.swift:163` `numberOfLines = 2`
- [x] MyLiveBroadcastCell 닉네임 중복 버그 수정 — `MyViewController.swift:427-438` `hasStation` 분기
- [x] 오프라인 카드 포커스 차별화 — `MyViewController.swift:549-563` `focusBorderOffline` 회색 보더 3pt
- [x] Player retry 무한 루프 방지 — `PlayerViewController.swift:27-28` `retryCount` / `maxRetries=3`
- [x] contentEdgeInsets deprecated 처리 — `MyViewController.swift:157`, `PlayerViewController.swift:441,455` `UIButton.Configuration` + `contentInsets = DS.ButtonInsets.cta`
- [x] 28pt UIFont.systemFont 매직 넘버 토큰화 — `DS.Typography.subsection` 신설, `grep "UIFont.systemFont(ofSize: 28"` 결과 정의 1곳만 매칭

**12개 항목 전원 해결.** v1 평가서의 "필수+중요" 액션 아이템(1~12)이 모두 코드에 반영됨.

---

## 100점이 안 됐다면 부족한 점 (구체적 액션)

### 5점 감점의 분포
- A. 첫인상: -1 (브랜드 워드마크 부재 + 미세 컬러 중복)
- B. 정보 위계: -1 (시청자수 배지 14pt 잔존, Player 해상도 라벨 모호)
- C. 리모컨: -1 (UISearchBar 포커스 흐름 미검증, nested CV 위험 잔존, 에러카드 기본 포커스 미명시)
- D. 화면별: -1 (Player 시청자수 오버레이 부재, 30초 자동 갱신 부재, HOME 인기 라이브 다양성 부족)
- E. 디테일: -1 (skeleton hide 타이밍 버그, 즐겨찾기 클릭 시 최근 시청 미저장)

### 100점 도달까지 남은 핵심 작업 3개

1. **Player 화면 정보 오버레이 + 30초 자동 갱신**
   - PlayerViewController에 시청자수 / 방송 시작 후 경과 시간 / BJ 닉네임 / 카테고리를 표시하는 상단 슬라이딩 오버레이 추가 (3초 후 자동 페이드, 리모컨 터치 시 재등장).
   - HOME · Explore의 인기방송 셀에 `Timer.scheduledTimer(withTimeInterval: 30)` 부착 — 화면 표시 중인 셀의 `viewerCount`만 patch.

2. **검색 화면 견고화 + HOME 스켈레톤 타이밍 수정**
   - `SearchViewController`의 nested UISearchBar를 tvOS 표준 `UISearchController` 또는 별도 검색 모달로 교체. 키보드 등장 시 결과 영역 가려짐 방지.
   - `HomeViewController.loadData`의 스켈레톤 hide 로직을 `DispatchGroup`으로 묶어 "인기라이브 + 즐겨찾기 + 최근시청"이 모두 끝나거나 1.5초 timeout 시 무조건 hide.

3. **브랜드/마감 다듬기**
   - RootTabBar 좌측 상단에 "SOOP" 워드마크(브랜드 빨강 + 흰 텍스트) 추가. 사용자 첫 인상에서 앱 정체성 즉시 인지.
   - 시청자수 배지 폰트 `DS.Typography.tiny`(14pt) → `badge`(16pt) 일괄 교체 (LiveBroadcastCell / MyLiveBroadcastCell).
   - Player 해상도 라벨을 "540p" / "720p" / "1080p"로 직접 표기 ("HD"/"HD+" 모호성 제거).
   - HOME의 `didSelectFavorite`에 `RecentWatchStore.shared.save(virtualBC)` 추가 (FavoriteBJ → LiveBroadcast 변환 후 저장).

---

## 100점 달성 여부: NO

**총점 95/100  (v1 74 → v2 95, +21점)**

v1에서 명시된 모든 필수·중요 액션이 완전히 처리되었고, 빌드도 통과한다. v2의 핵심 가치 (HOME 탭, 검색 화면, 이미지 캐시, 로딩 스켈레톤, 최근 시청)가 모두 사용자에게 실체로 도달했다. 그러나 v1 평가서의 "디테일(98→100점)" 영역인 **Player 정보 오버레이 / 30초 자동 갱신 / 브랜드 워드마크** 가 누락되었고, 신규 도입한 코드에 미세한 timing 버그(`HomeViewController.hideSkeleton` 조건)와 일관성 미흡(`MyViewController.swift:495,502`의 비-토큰 컬러)이 새로 발견됐다.

100점 도달까지는 위 3개 작업이 필요하다. v3 출시 전 1-2시간 작업으로 충분히 90점대 후반 → 100점 가능.
