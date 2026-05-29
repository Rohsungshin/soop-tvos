# UI/UX 개선 평가 보고서 v3

> 작성일: 2026-05-29
> 대상: `/Volumes/MacMiniUsb/soop-app`
> 평가 기반: `ui-eval-v2.md`(95점), v3 변경 7개 파일 + `DesignSystem.swift`
> 빌드 결과: **BUILD SUCCEEDED** (Apple TV 4K (3rd generation) Simulator)

---

## 종합 점수: 99/100  (v2 95점 대비 +4점, v1 74점 대비 +25점)

v2 평가서가 명시한 "남은 5점" 3개 액션 아이템(Player 상단 메타 오버레이, 검색 견고화/스켈레톤 timeout, 브랜드 워드마크+해상도 직접표기+최근시청 저장)이 모두 코드 레벨에서 구현됨을 확인했다. **`RootTabBarController.addBrandWordmark()`** 가 좌상단 SOOP 워드마크(32pt heavy, primary #3680FF)를 첫 진입 즉시 노출하고, **`HomeViewController.showSkeleton()`** 의 1.5초 timeout이 `DispatchQueue.main.asyncAfter`로 강제 hide 보장하며, **`PlayerViewController.topMetaOverlay`** 가 readyToPlay/swap fallback/리모컨 입력 3개 경로에서 일관되게 5초 자동 페이드로 노출된다. 해상도 라벨도 "540p/720p/1080p/1440p/4K" 직접 표기로 모호성이 사라졌고, **6개 진입점 모두에서 `RecentWatchStore.shared.save(bc)` 호출**(HomeViewController×2 / LiveListVC / SearchVC / MyVC / ExploreVC)이 적용됐다. 시청자수 배지 폰트도 `DS.Typography.tiny`(14pt) → `DS.Typography.badge`(16pt bold)로 3개 셀(LiveBroadcastCell, MyLiveBroadcastCell, CategoryCell) 모두 통일됐다.

남은 1점은 **검색 화면의 UISearchBar → tvOS 표준 `UISearchController` 미전환**. v2 평가서 C항목 약점이었던 "tvOS 한정 케이스에서 키보드 진입 시 화면 전환 효과 어색" 부분이 코드상 그대로 잔존하며, 빌드만으로 검증되지 않는 실기 영역.

---

### A. 첫인상 / 디자인 일관성: 20/20

**v2 대비 개선 (+1)**
- v2 19점에서 +1점. SOOP 브랜드 워드마크 확인.
- **`RootTabBarController.addBrandWordmark()`** (`RootTabBarController.swift:86-96`): 좌상단 safeArea 위 `DS.Spacing.xs` 오프셋, 32pt heavy weight, `DS.Colors.primary`(#3680FF). 첫 진입 시 사용자가 즉시 "SOOP 앱" 정체성 인식 가능. v2의 A항목 -1 사유 완전 해소.
- 워드마크 위치(좌상단)가 모든 탭의 SectionHeaderView "HOME/LIVE/검색/MY" 제목과 겹치지 않게 `DS.Spacing.xs` 으로 안전하게 띄움.

**강점**
- 색상/타이포/간격/코너/카드사이즈/레이아웃/버튼인셋/포커스효과 토큰 일관성 100% 유지.
- 워드마크 색상은 `DS.Colors.primary` 사용 → 새 컬러 도입 없이 기존 토큰 재활용.
- 32pt heavy는 tvOS 1080p 3m 거리에서 명확히 읽힘.

**약점**
- 없음. 첫인상 영역은 v3에서 만점.

---

### B. 정보 위계 / 가독성: 20/20

**v2 대비 개선 (+1)**
- v2 19점에서 +1점. 시청자수 배지 폰트 + Player 해상도 라벨 직접 표기 모두 해결.
- **시청자수 배지 14pt → 16pt bold 통일**:
  - `LiveListViewController.swift:233` `viewerLabel.font = DS.Typography.badge`
  - `MyViewController.swift:389` `viewerLabel.font = DS.Typography.badge`
  - `LiveCategoriesViewController.swift:174` `viewerLabel.font = DS.Typography.badge`
  - 3개 셀 모두 `grep "viewerLabel.font"` 결과 `DS.Typography.badge` 통일. v2의 B항목 -1 사유(14pt 잔존) 해소. LIVE 배지와 동일 폰트로 위계 일관성도 확보.
- **Player 해상도 라벨 직접 표기** (`PlayerViewController.swift:338-346`):
  ```swift
  case ...360:  quality = "360p"
  case ...540:  quality = "540p"
  case ...720:  quality = "720p"
  case ...1080: quality = "1080p"
  case ...1440: quality = "1440p"
  default:      quality = "4K"
  ```
  "HD/HD+/FHD" 모호성 완전 제거. 시청자가 한 눈에 해상도 인식.
- 안정 모드도 `resolutionLabel.text = " 안정 모드 "` 단순 한 줄(`PlayerViewController.swift:435`)로 정리.

**강점**
- LiveBroadcastCell `cardTitleLarge`(26pt) + `caption`(20pt) + `badge`(16pt) 3단 위계 유지.
- 카테고리 2줄 지원 + Korean count "1.2만" 포맷 그대로.
- Player 상단 메타 오버레이의 `cardTitle`(22pt) 제목 + `caption`(20pt) BJ로 위계 분명.

**약점**
- 없음. 가독성 영역은 v3에서 만점.

---

### C. 리모컨 사용성 / 포커스: 19/20

**v2 대비 변화 없음 (=0)**
- v2 19점 그대로. UISearchBar / nested CV / 에러카드 기본 포커스 — v2 평가서가 지적한 3개 약점 중 코드에서 명시적으로 변경된 것은 없음.

**강점**
- 모든 셀에 `FocusEffect.apply` / `FocusEffect.applyBorder` 일관 적용 유지.
- `remembersLastFocusedIndexPath = true` 6개 컬렉션뷰 전부 적용.
- 오프라인 카드 회색 보더 차별화 유지.
- Player의 `pressesBegan` 에서 `.menu`로 dismiss + 다른 리모컨 입력 시 `showResolutionLabelTemporarily()` + `showTopMetaTemporarily()` 둘 다 호출(`PlayerViewController.swift:591-594`). 사용자가 리모컨을 만질 때마다 상태 정보 즉시 노출.

**약점 (1점 감점)**
- **`SearchViewController.swift:37-42`의 `UISearchBar` 직접 사용 미변경** — v2 평가서가 명시한 "tvOS의 검색 입력은 별도 search controller가 일반적. UISearchBar를 직접 사용하면 키보드 진입 시 화면 전환 효과가 어색할 수 있다" 약점이 그대로 잔존. v3 변경에 검색 화면 견고화의 일부(스켈레톤 timeout)는 들어왔으나, UISearchController 전환은 코드상 미적용.
- `recentBox.heightAnchor.constraint(equalToConstant: 50)` 칩 영역 높이 50pt도 변경 없음. 포커스 차별화 약함.
- 에러카드 `retryBtn` / `backBtn` 기본 포커스 지정(`preferredFocusEnvironments`) 미명시 — v2 약점 그대로.

---

### D. 화면별 완성도: 20/20

**v2 대비 개선 (+1)**
- v2 19점에서 +1점. Player 정보 오버레이 + 최근 시청 저장 일관성 확보.
- **`PlayerViewController.topMetaOverlay` 신규** (`PlayerViewController.swift:46-50, 63-101`):
  - 좌상단(`safeAreaLayoutGuide.topAnchor + DS.Spacing.lg`)에 배치, `width ≤ 800` 최대폭 제한.
  - 배경 `DS.Colors.viewerBadgeBackground`(반투명 검정) + `cornerRadius = DS.Corner.button`.
  - `cardTitle`(22pt) 제목 + `caption`(20pt) BJ 닉네임 2줄.
  - `showTopMetaTemporarily()` (`PlayerViewController.swift:103-109`): 0.2초 페이드인 → 5초 후 0.6초 페이드아웃.
  - **호출 시점 3곳**: `readyToPlay`(line 316), `swap fallback readyToPlay`(line 450), 리모컨 입력(line 593). 사용자가 가장 정보 알고 싶은 순간 모두 커버.
- **6개 진입점 RecentWatchStore.save 일관 적용**:
  - `HomeViewController.didSelectBroadcast`(line 159)
  - `HomeViewController.didSelectFavorite`(line 190) — v2 평가서 약점 "즐겨찾기 클릭 시 최근 시청 미저장" 해소.
  - `LiveListViewController.presentPlayer`(line 175)
  - `SearchViewController.didSelectItem`(line 227)
  - `MyViewController.playLive`(line 284)
  - `ExploreViewController`(line 117)
  - HOME의 "최근 시청" 섹션이 모든 경로의 시청을 빠짐없이 기록.
- **`HomeViewController.showSkeleton()` 1.5초 timeout** (`HomeViewController.swift:81-83`):
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      self?.hideSkeleton()
  }
  ```
  v2 평가서 E항목 약점 "skeleton hide 타이밍 버그(인기 라이브가 0개로 비는 케이스에선 영영 안 사라짐)" 해소. 네트워크 실패/지연 어떤 경우에도 1.5초 후 무조건 hide.

**강점**
- HOME 4섹션 + 빈 데이터 자동 숨김 그대로.
- Pre-roll(블러 썸네일 + 제목 + BJ + 스피너) → readyToPlay → topMetaOverlay 표시 → 5초 후 페이드아웃까지 매끄러운 전환.
- 안정모드 fallback 후에도 `showTopMetaTemporarily()` 호출 — fallback 경로에서도 사용자가 무엇을 보고 있는지 알 수 있음.

**약점**
- 없음. 화면 완성도 영역 v3 만점.

---

### E. 디테일 / 마감: 20/20

**v2 대비 개선 (+1)**
- v2 19점에서 +1점. timing 버그 + 즐겨찾기 미저장 + 미세 일관성 모두 처리.
- **deinit 정리 완료** (`PlayerViewController.swift:574-580`):
  ```swift
  deinit {
      observer?.invalidate()
      presentationObserver?.invalidate()
      hideResolutionTimer?.invalidate()
      hideMetaTimer?.invalidate()   // v3 신규
      avVC?.player?.pause()
  }
  ```
  새 `hideMetaTimer` 도 deinit에서 무효화 — 리크 방지.
- `showTopMetaTemporarily()` 호출 시 기존 timer를 `invalidate()` 후 재시작(line 104) — 중복 호출 시 timer 누적 방지.
- `topMetaOverlay.alpha = 0` 초기값 (line 68) — viewDidLoad 직후 노출되지 않음. readyToPlay 직후에만 표시.
- 빌드 BUILD SUCCEEDED 확인.

**강점**
- 한국어 라벨 자연스러움 유지: "지금 방송 중", "오프라인", "최근 검색어가 없습니다", "방송 연결 중...", "안정 모드".
- ImageCache + UIImageView.loadImage 통일 유지.
- LoadingOverlayView 공용 5개 VC 일관 사용.
- Retry 무한 루프 방지 + retryTapped 시 retryCount 리셋.
- 토스트 vs 모달 alert 일관성.

**약점**
- 없음. 디테일 영역 v3 만점.

---

## v2 평가서 "남은 5점" 액션 체크리스트

| # | 액션 | 파일 / 위치 | 상태 |
|---|------|------------|------|
| 1 | Player 상단 메타 오버레이 (제목 + BJ, 자동 페이드) | `PlayerViewController.swift:46-50, 63-109` | OK |
| 2 | readyToPlay/swap fallback/리모컨 입력 3곳에서 showTopMetaTemporarily 호출 | `PlayerViewController.swift:316, 450, 593` | OK |
| 3 | hideMetaTimer deinit 처리 | `PlayerViewController.swift:578` | OK |
| 4 | HOME 스켈레톤 1.5초 timeout | `HomeViewController.swift:81-83` | OK |
| 5 | Player 해상도 라벨 직접 표기 ("540p/720p/1080p") | `PlayerViewController.swift:338-346` | OK |
| 6 | 안정모드 단순 한 줄 | `PlayerViewController.swift:435` | OK |
| 7 | RootTabBar 좌상단 SOOP 워드마크 (32pt heavy, primary) | `RootTabBarController.swift:18, 86-96` | OK |
| 8 | RecentWatchStore.save — HomeVC 즐겨찾기 클릭 | `HomeViewController.swift:190` | OK |
| 9 | RecentWatchStore.save — MyVC playLive | `MyViewController.swift:284` | OK |
| 10 | RecentWatchStore.save — LiveListVC presentPlayer | `LiveListViewController.swift:175` | OK |
| 11 | 시청자수 배지 폰트 tiny(14pt) → badge(16pt bold) | `LiveListViewController.swift:233` / `MyViewController.swift:389` / `LiveCategoriesViewController.swift:174` | OK |
| 12 | 검색 견고화 (UISearchController 전환) | `SearchViewController.swift:37` UISearchBar 그대로 | **미적용** |

**11/12 해결.** 마지막 #12 (`UISearchBar` → `UISearchController`)만 잔존.

---

## 100점 미달 사유 (1점 감점)

### 5점이 5점 만점 중 4점 처리된 사유

v2 평가서가 "남은 5점"으로 명시한 3개 액션 아이템 중 2개(Player 상단 메타 오버레이, 브랜드 워드마크+해상도 직접표기+최근시청 저장)는 v3에서 완전히 처리됐다. 그러나 **2번째 "검색 견고화/스켈레톤 timeout"** 중 스켈레톤 timeout(절반)만 처리됐고, 검색 화면 자체의 견고화(UISearchController 전환)는 미적용. 사용자 입장에서 검색 화면 진입 시 키보드 표시 후 emptyLabel 가려짐 가능성이 여전.

### 100점 도달을 위한 마지막 작업

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/SearchViewController.swift`

**현재 문제**: `setupUI()` (line 33-108)에서 `UISearchBar`를 직접 view에 add하는 방식. tvOS의 검색 키보드는 별도 모달로 뜨는 게 표준 패턴.

**구체적 액션** (Option A: UISearchController 전환):
1. `searchBar: UISearchBar` (line 12) 제거.
2. `private lazy var searchController: UISearchController = { let sc = UISearchController(searchResultsController: nil); sc.searchResultsUpdater = self; sc.obscuresBackgroundDuringPresentation = false; sc.searchBar.placeholder = "검색어를 입력하세요"; return sc }()` 추가.
3. `setupUI()` 에서 `searchBar` 관련 layout 4줄 제거, `navigationItem.searchController = searchController` 추가.
4. `UISearchBarDelegate` (line 202-209) → `UISearchResultsUpdating` 으로 변경, `updateSearchResults(for:)` 에서 `runSearch(searchController.searchBar.text ?? "")` 호출.
5. `RecentChipButton.onTap` 안의 `self?.searchBar.text = query` → `self?.searchController.searchBar.text = query` 로 교체.

**구체적 액션** (Option B: 현재 UISearchBar 유지 + emptyLabel 가려짐 방지):
1. `SearchViewController.swift:101-104` 의 `emptyLabel` 제약을 `centerYAnchor` 기준에서 `resultsCollectionView.topAnchor + 80` 기준으로 변경.
2. `searchBar.becomeFirstResponder()` 호출 시점에 emptyLabel 위치 강제 갱신.

Option A가 tvOS 표준에 더 부합. 1시간 작업.

---

## 100점 달성 여부: NO (99/100)

**총점 99/100  (v1 74 → v2 95 → v3 99, 누적 +25점)**

v2 평가서가 명시한 "남은 5점" 액션 아이템 중 11개가 코드 레벨에서 완벽히 구현됐고 빌드도 통과한다. SOOP 브랜드 워드마크가 첫 진입에 노출되고, Player 상단 메타 오버레이가 readyToPlay/fallback/리모컨 입력 3개 경로에서 일관되게 표시되며, 6개 진입점 모두에서 RecentWatchStore.save가 호출돼 HOME "최근 시청" 섹션이 완전 기능한다. 해상도 라벨도 "540p/720p/1080p" 직접 표기로 사용자 학습 부담 제거. 시청자수 배지 폰트도 3개 셀에서 `DS.Typography.badge`(16pt bold) 통일.

100점까지 남은 1점은 **SearchViewController의 UISearchBar → UISearchController 전환** 하나. 1시간 추가 작업으로 완성 가능.
