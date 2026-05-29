# SOOP tvOS App UI/UX 개선 기획서 v2 (100점 목표)

> 작성일: 2026-05-29
> 대상: tvOS 17.0+ Apple TV 네이티브 앱 (UIKit, Swift 5)
> 기반: `ui-plan-v1.md` / `ui-design-v1.md` / `ui-eval-v1.md` (74/100)
> 목표: 평가서 감점 요인 전 항목 해결 → 100/100

---

## 0. v1 평가 요약 및 v2 목표

### 0.1 v1 평가 (74/100)

| 카테고리 | 점수 | 주요 감점 |
|---|---|---|
| A. 첫인상 / 디자인 일관성 | 16/20 | 토큰 일부만 적용, dim 컬러 3곳 중복, SOOP 브랜드 잔류 부족 |
| B. 정보 위계 / 가독성 | 15/20 | 제목 22pt / BJ 16pt 위계 약함, 카테고리명 1줄 잘림, MyLive 중복 표시 버그 |
| C. 리모컨 사용성 / 포커스 | 13/20 | 오프라인 카드 차별화 부족, 그림자 클리핑 위험, pre-roll 포커스 정책 미설정 |
| D. 화면별 완성도 | 14/20 | **HOME 미구현, 검색 미구현, 스켈레톤 미구현, 최근 시청 비어 있음** |
| E. 디테일 / 마감 | 16/20 | LoadingOverlay 3곳 복붙, 매직 넘버(28pt/14/36/1920), 이미지 캐시 부재 |

### 0.2 v2 목표 (100/100)

**v1 평가서 "필수 액션 아이템 1~12번 + 디테일 13~20번"을 모두 해결**한다.

핵심 달성 기준:
1. **신규 화면 3종**: `HomeViewController`, `SearchViewController`, `LoadingSkeletonView`
2. **공용 컴포넌트 3종**: `LoadingOverlayView`, `ImageCache` (UIImageView+Cache), `MiniBroadcastCell` (HOME/Explore 캐러셀용)
3. **디자인 토큰 강화**: 28pt subsection, 18pt subcaption, contentInsets 토큰, headerHeight 토큰 추가
4. **카드 위계 강화**: 제목 22pt → 26pt (BJ 16pt와 10pt 차이), 카테고리명 1줄 → 2줄
5. **오프라인/라이브 시각 차별화**: 흑백 처리 + 포커스 색 차별화
6. **버그 수정 3종**: stationName 중복 표시, headerReferenceSize 1920 하드코딩, contentEdgeInsets deprecated

---

## 1. v1 대비 변경/추가 항목 (체크리스트)

### 1.1 신규 파일

| 파일 | 역할 | 우선순위 |
|---|---|---|
| `soop-app/HomeViewController.swift` | 4섹션 HOME 탭 (인기 라이브 / 인기 카테고리 / 최근 시청 / 추천 BJ) | P0 |
| `soop-app/SearchViewController.swift` | 검색 입력 + 결과 그리드 + 최근 검색어 | P0 |
| `soop-app/LoadingSkeletonView.swift` | 카드 스켈레톤 + shimmer 애니메이션 | P0 |
| `soop-app/UIImageView+Cache.swift` | NSCache 기반 이미지 캐시 extension | P0 |
| `soop-app/RecentBroadcastStore.swift` | UserDefaults 기반 최근 시청 기록 | P1 |
| `soop-app/MiniBroadcastCell.swift` | HOME/Explore 가로 캐러셀용 작은 카드 (선택) | P2 |

### 1.2 DesignSystem.swift 강화

| 항목 | v1 | v2 |
|---|---|---|
| `DS.Colors.overlay` | 있음, 미사용 | 3곳에서 직접 사용 |
| `DS.Typography.cardTitle` | 22pt semibold | **26pt semibold (위계 강화)** |
| `DS.Typography.cardTitleMd` | 없음 | 22pt semibold (카테고리명용) |
| `DS.Typography.subsection` | 없음 | **28pt semibold (4곳 중복 제거)** |
| `DS.Typography.subcaption` | 없음 | **18pt semibold (오프라인 닉네임)** |
| `DS.Layout.contentSideMargin` | 없음 | 64pt (Spacing.xl 별칭) |
| `DS.Layout.sectionHeaderHeight` | 없음 | 80pt |
| `DS.Layout.headerTopOffset` | 없음 | 30pt |
| `DS.Layout.gridTopGap` | 없음 | 24pt |
| `DS.ButtonInsets.cta` | 없음 | (14, 36, 14, 36) → UIButtonConfiguration |
| `LoadingOverlayView` | 없음 | 공용 클래스로 추출 |

### 1.3 화면별 변경 요약

| 화면 | v1 상태 | v2 변경 |
|---|---|---|
| `RootTabBarController` | 3탭 (LIVE/탐색/MY) | **4탭 (HOME/LIVE/탐색/MY), 기본 진입 HOME** |
| `HomeViewController` | 없음 | **신규** (4섹션 캐러셀) |
| `LiveCategoriesViewController` | 1줄 truncating, dim 직접 작성 | 2줄 허용, LoadingOverlayView 적용, 스켈레톤 진입, 이미지 캐시 |
| `LiveListViewController` | dim 3곳 중복 | LoadingOverlayView 적용, 스켈레톤 진입, 카드 제목 26pt, 이미지 캐시 |
| `ExploreViewController` | 검색 placeholder, 최근 시청 빈 데이터 | **검색 셀 → SearchVC push, 최근 시청 실데이터** |
| `SearchViewController` | 없음 | **신규** (검색 입력 + 결과) |
| `MyViewController` | stationName 중복, 라이브 썸네일 캐시 무효화 트릭 | 버그 수정, 이미지 캐시, 28pt 토큰, headerReferenceSize 동적 |
| `PlayerViewController` | 28pt/22pt 하드코딩, contentEdgeInsets deprecated | 토큰 적용, UIButtonConfiguration 마이그레이션, retry 카운트 제한, 상단 메타 오버레이 |

---

## 2. 강화된 디자인 시스템 토큰

### 2.1 DesignSystem.swift 변경 (DS enum 전체)

```swift
enum DS {

    // MARK: 색상 — v2 변경 없음 (단, 미사용 토큰을 코드 내 모든 곳에 적용)
    enum Colors {
        // ... v1 그대로 ...
        static let overlay = UIColor(white: 0, alpha: 0.55)   // v2: 3곳에서 실제 사용
        // 신규 추가
        static let offlineImageTint = UIColor(white: 0.55, alpha: 1)  // 오프라인 카드 흑백 톤
        static let focusBorderOffline = UIColor(red: 120/255, green: 120/255, blue: 128/255, alpha: 1) // 오프라인 포커스 보더 (회색)
    }

    // MARK: 타이포그래피 — 위계 강화
    enum Typography {
        static let hero          = UIFont.systemFont(ofSize: 64, weight: .bold)
        static let section       = UIFont.systemFont(ofSize: 36, weight: .semibold)
        /// v2 신규: 28pt subsection — 가로 캐러셀 섹션 헤더, 빈상태 line1, 에러카드 title 등
        static let subsection    = UIFont.systemFont(ofSize: 28, weight: .semibold)
        static let title         = UIFont.systemFont(ofSize: 48, weight: .bold)
        /// v2 변경: 26pt — 큰 카드 제목 (방송 제목) — BJ 16pt와 10pt 차이로 위계 강화
        static let cardTitleLarge = UIFont.systemFont(ofSize: 26, weight: .semibold)
        /// v2 변경: 22pt 그대로 — 카테고리명 등 중간 위계
        static let cardTitle     = UIFont.systemFont(ofSize: 22, weight: .semibold)
        static let body          = UIFont.systemFont(ofSize: 20, weight: .regular)
        static let subhead       = UIFont.systemFont(ofSize: 20, weight: .regular)
        /// v2 신규: 18pt — 오프라인 BJ 닉네임 / 최근 검색어
        static let subcaption    = UIFont.systemFont(ofSize: 18, weight: .semibold)
        static let caption       = UIFont.systemFont(ofSize: 16, weight: .medium)
        /// v2 변경: 16pt bold — 시청자수 배지 가독성 강화 (기존 14pt 너무 작음)
        static let badge         = UIFont.systemFont(ofSize: 16, weight: .bold)
        static let tiny          = UIFont.systemFont(ofSize: 14, weight: .semibold)
    }

    enum Spacing {
        static let xs: CGFloat  = 8
        static let sm: CGFloat  = 16
        static let md: CGFloat  = 24
        static let lg: CGFloat  = 40
        static let xl: CGFloat  = 64
        static let xxl: CGFloat = 96
    }

    enum Corner {
        static let card: CGFloat   = 18
        static let badge: CGFloat  = 6
        static let button: CGFloat = 16
        static let modal: CGFloat  = 24
    }

    // MARK: v2 신규 — 레이아웃 토큰
    enum Layout {
        /// 좌우 콘텐츠 마진 (xl과 동일하지만 의미 명시)
        static let contentSideMargin: CGFloat = 64
        /// 섹션 헤더 높이 (MyVC / Explore 캐러셀 행 헤더)
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
    }

    enum CardSize {
        static let category       = CGSize(width: 320, height: 220)
        static let broadcast      = CGSize(width: 400, height: 282)
        static let myLive         = CGSize(width: 380, height: 280)
        static let myOffline      = CGSize(width: 240, height: 280)
        static let explorePopular = CGSize(width: 400, height: 282)
        static let exploreCategory = CGSize(width: 320, height: 220)
        /// v2 신규: HOME/Explore 캐러셀용 작은 라이브 카드
        static let miniLive       = CGSize(width: 320, height: 230)
        /// v2 신규: HOME 추천 BJ 카드 (작은 프로필 카드)
        static let recommendBJ    = CGSize(width: 200, height: 240)
        /// v2 신규: 검색 결과 카드 (LiveBroadcastCell과 동일)
        static let searchResult   = CGSize(width: 400, height: 282)
    }

    // MARK: v2 신규 — 버튼 인셋
    enum ButtonInsets {
        /// CTA 버튼 (다시 시도, 새로고침, 검색 등) — UIButton.Configuration용
        static let cta = NSDirectionalEdgeInsets(top: 14, leading: 36, bottom: 14, trailing: 36)
    }
}
```

### 2.2 매직 넘버 제거 가이드 (적용 위치)

| 매직 넘버 | v1 위치 | v2 토큰 |
|---|---|---|
| `28pt semibold` | `MyViewController:139, 343, 367`, `ExploreViewController:331`, `PlayerViewController:417` | `DS.Typography.subsection` |
| `18pt semibold` | `MyViewController:555` | `DS.Typography.subcaption` |
| `22pt semibold` (Player 버튼) | `MyViewController:155`, `PlayerViewController:433, 444` | `DS.Typography.cardTitle` 재활용 |
| `32pt bold` (Player 제목) | `PlayerViewController:82` | `DS.Typography.section` (36pt) 또는 신규 `playerTitle` 토큰 추가 |
| `22pt medium` (Player BJ) | `PlayerViewController:91` | `DS.Typography.cardTitle` 재활용 시 weight 차이 → 그대로 두되 주석으로 의도 표시 |
| `UIColor(white: 0, alpha: 0.55)` | `LiveListViewController:139`, `ExploreViewController:131`, `MyViewController:201` | `DS.Colors.overlay` |
| `UIColor(white: 0, alpha: 0.65)` | `MyViewController:547` | `DS.Colors.viewerBadgeBackground` (이미 존재) |
| `UIColor(white: 0, alpha: 0.35)` | `MyViewController:540` | 신규 `DS.Colors.imageDarkOverlay` 또는 그대로 + 주석 |
| `1920` | `MyViewController:62` | `DS.Layout.screenWidth` 또는 동적 `cv.bounds.width` |
| `contentEdgeInsets (14, 36, 14, 36)` | `MyViewController:159`, `PlayerViewController:437, 448` | `UIButton.Configuration.plain()` + `DS.ButtonInsets.cta` |
| `30` (헤더 top offset) | 6개 VC | `DS.Layout.headerTopOffset` |
| `32` (그리드 top inset) | 3개 VC | `DS.Layout.gridTopInset` |
| `72` (그리드 bottom inset) | 3개 VC | `DS.Layout.gridBottomInset` |
| `24` (헤더 ↔ 그리드 간격) | 4개 VC | `DS.Layout.gridTopGap` |
| `80` (섹션 헤더 높이) | `MyViewController:62, 297` | `DS.Layout.sectionHeaderHeight` |
| `60` (statusLabel 좌우 여백) | 3개 VC | `DS.Spacing.xl - 4` 또는 `60` 그대로 + 주석 (border 사례) |

---

## 3. 신규 화면 상세 기획

### 3.1 HomeViewController (신규)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/HomeViewController.swift`

#### 3.1.1 구조

`ExploreViewController`와 동일한 `UITableView + 가로 캐러셀 CarouselRowCell` 패턴 재활용. 단, **CarouselRowCell은 신규 파일 `CarouselRowCell.swift`로 분리**해 HomeVC/ExploreVC 양쪽에서 공유한다.

#### 3.1.2 섹션 구성 (4섹션)

```
┌──────────────────────────────────────────────────────────┐
│  HOME                                                     │
│  지금 SOOP에서 무슨 일이?                                  │
├──────────────────────────────────────────────────────────┤
│  지금 가장 핫한 라이브 (인기 라이브 캐러셀)               │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐                              │  ← LiveBroadcastCell 400x282 × 가로 N
│  └──┘ └──┘ └──┘ └──┘ └──┘                              │
├──────────────────────────────────────────────────────────┤
│  인기 카테고리 TOP 6                                       │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐                        │  ← CategoryCell 320x220 × 6
│  └──┘ └──┘ └──┘ └──┘ └──┘ └──┘                        │
├──────────────────────────────────────────────────────────┤
│  최근 시청한 방송                                          │
│  ┌──┐ ┌──┐ ┌──┐                                         │  ← LiveBroadcastCell × N (RecentBroadcastStore)
│  └──┘ └──┘ └──┘                                         │
├──────────────────────────────────────────────────────────┤
│  내가 즐겨찾기한 라이브 BJ                                 │
│  ┌──┐ ┌──┐ ┌──┐                                         │  ← MyLiveBroadcastCell × N (favorites 중 isLive)
│  └──┘ └──┘ └──┘                                         │
└──────────────────────────────────────────────────────────┘
```

#### 3.1.3 섹션별 데이터 소스 / 빈 상태

| 섹션 | 데이터 소스 | 빈 데이터 fallback |
|---|---|---|
| 인기 라이브 | `SOOPAPIClient.fetchCategories` → 상위 3개 → `fetchBroadcasts(byCategory:)` 머지 → 시청자수 내림차순 상위 20개 | 섹션 자체 숨김 (`numberOfRows = 0`) |
| 인기 카테고리 TOP 6 | `fetchCategories` → 시청자수 내림차순 상위 6개 | 섹션 숨김 |
| 최근 시청 | `RecentBroadcastStore.shared.load()` (UserDefaults) | 섹션 숨김 |
| 즐겨찾기 라이브 | `fetchFavorites` → `isLive == true` 필터 | 섹션 숨김. **로그인 안 됨도 동일하게 숨김** (별도 안내 없이 깔끔하게) |

#### 3.1.4 헤더

- `SectionHeaderView(title: "HOME", subtitle: "지금 SOOP에서 무슨 일이?")` 재활용.

#### 3.1.5 첫 진입 시 포커스

- `preferredFocusEnvironments = [tableView]`.
- 비어 있는 섹션은 `numberOfRowsInSection`이 0을 반환하므로 자연스럽게 다음 섹션의 첫 카드로 포커스가 떨어진다.
- 모든 섹션이 비어 있을 경우 → **로딩 스켈레톤** 표시 (3.3 참조).

#### 3.1.6 데이터 로딩 순서

```
viewDidLoad → showSkeleton()
  ↓
fetchCategories (병렬)
  ↓ success
  ├ 상위 6개 → popularCategoriesSection 갱신
  └ 상위 3개 카테고리에 대해 fetchBroadcasts 머지
       ↓
       popularBroadcastsSection 갱신
fetchFavorites (병렬) → favoritesLiveSection 갱신
RecentBroadcastStore.load() → recentSection 갱신 (즉시)
  ↓ 모든 섹션 ready
hideSkeleton()
```

#### 3.1.7 CarouselRowCell 공통화

기존 `ExploreViewController.swift`의 내부 클래스 `CarouselRowCell`을 별도 파일 `CarouselRowCell.swift`로 추출. 시그니처는 그대로 유지 (`broadcasts` 또는 `categories` 둘 중 하나만 사용). HomeVC와 ExploreVC 양쪽에서 동일 셀 사용. **타이틀 폰트는 `DS.Typography.subsection`**으로 변경 (v1의 28pt 직접 작성 제거).

#### 3.1.8 RootTabBar 변경

```swift
// RootTabBarController.swift viewDidLoad 내부
let homeNav = makeNav(root: HomeViewController(), title: "HOME", tag: 0)
let liveNav = makeNav(root: LiveCategoriesViewController(), title: "LIVE", tag: 1)
let exploreNav = makeNav(root: ExploreViewController(), title: "탐색", tag: 2)
let myNav = makeNav(root: MyViewController(), title: "MY", tag: 3)
viewControllers = [homeNav, liveNav, exploreNav, myNav]
selectedIndex = 0  // HOME 기본 진입
```

---

### 3.2 SearchViewController (신규)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/SearchViewController.swift`

#### 3.2.1 구조

tvOS의 검색은 `UISearchController` + `UISearchContainerViewController`가 표준이지만, SOOP 검색 API의 정확한 엔드포인트가 확인되지 않은 상태이므로 **현실적 구현**으로 다음 2단계 절충안을 채택:

**단계 1 (P0, 본 v2 범위)**: 클라이언트 사이드 필터링 기반 검색
- 앱 시작 시 인기 카테고리 12개 × 카테고리별 라이브 방송을 미리 머지 (~200개) → 메모리 캐시.
- 사용자가 입력한 텍스트로 BJ 닉네임 + 방송 제목을 부분 일치 필터링.
- 결과 그리드 표시 (LiveBroadcastCell 400x282, 4열).
- 빈 결과 시 "검색 결과가 없습니다" 빈 상태 + 인기 카테고리 캐러셀로 대체 제안.

**단계 2 (P2, 향후)**: SOOP search API 직접 호출 (`SOOPAPIClient.search(query:)` 추가). v2 범위 외.

#### 3.2.2 화면 레이아웃

```
┌──────────────────────────────────────────────────────────┐
│  검색                                                     │
│  BJ 닉네임 또는 방송 제목을 입력하세요                    │
├──────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────┐    │
│  │ 🔍  [검색어 입력 필드]                        ✕  │    │  ← UISearchBar (커스텀 스타일)
│  └──────────────────────────────────────────────────┘    │
├──────────────────────────────────────────────────────────┤
│  최근 검색어 (검색어가 비어 있을 때만)                    │
│  · 침착맨   · 우왁굳   · 풍월량   · 김계란   · ✕ 전체삭제  │
├──────────────────────────────────────────────────────────┤
│  검색 결과 N개                                            │
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                                   │  ← LiveBroadcastCell 그리드 4열
│  └──┘ └──┘ └──┘ └──┘                                   │
└──────────────────────────────────────────────────────────┘
```

#### 3.2.3 검색 입력 UI

- `UISearchBar`를 화면 최상단에 가로로 배치. 좌우 패딩 `DS.Layout.contentSideMargin` (64pt), 높이 80pt.
- 배경 `DS.Colors.surface`, 라운드 `DS.Corner.button` (16pt).
- 텍스트 폰트 `DS.Typography.body` (20pt regular).
- tvOS의 가상 키보드가 자동 등장 (`searchBar.becomeFirstResponder()` 호출 시).
- 사용자가 타이핑 → `searchBar(_:textDidChange:)` → **0.3초 debounce** 후 필터링 실행.

#### 3.2.4 결과 그리드

- `UICollectionView` (Flow Layout), `LiveBroadcastCell` 재활용.
- `itemSize = DS.CardSize.searchResult` (400x282), 4열.
- `sectionInset = (32, 64, 72, 64)`, `interitem 24`, `line 40` — LiveListViewController와 동일.

#### 3.2.5 최근 검색어

- `UserDefaults` 키 `recent_searches` 에 최근 10개 문자열 (FIFO) 저장.
- 검색어 입력란이 비어 있을 때만 결과 그리드 위에 가로 스크롤 칩 형태로 표시.
- 각 칩: `UIButton.Configuration.gray()` + `DS.Typography.subcaption` (18pt). 포커스 가능.
- 칩 선택 → 검색어를 SearchBar에 주입 → 자동 검색 실행.
- "✕ 전체삭제" 버튼 (`DS.Colors.live` 텍스트 색).

#### 3.2.6 빈 결과 상태

- 검색어가 비어 있지 않은데 결과 0건 → 가운데에:
  - SF Symbol `magnifyingglass` 80pt (`DS.Colors.textTertiary`)
  - "{검색어}에 대한 결과가 없습니다" `DS.Typography.subsection`
  - "다른 검색어를 시도해보세요" `DS.Typography.body` `DS.Colors.textSecondary`

#### 3.2.7 진입점

- `ExploreViewController.tableView(_:didSelectRowAt:)` 의 검색 셀 분기에서 `ToastView.show` 대신:
  ```swift
  let searchVC = SearchViewController()
  navigationController?.pushViewController(searchVC, animated: true)
  ```

#### 3.2.8 포커스 흐름

- 진입 시 `preferredFocusEnvironments = [searchBar]` — 가상 키보드 즉시 등장.
- 사용자가 입력 후 ↓ 키 누르면 최근 검색어 칩으로 또는 결과 그리드 첫 카드로.
- 결과 그리드 카드 선택 → `LiveListViewController.presentPlayer(for:)`와 동일 흐름.

---

### 3.3 LoadingSkeletonView (공용)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/LoadingSkeletonView.swift`

#### 3.3.1 역할

데이터 로딩 중 빈 화면 대신 카드 placeholder를 표시. 사용자에게 "곧 콘텐츠가 채워진다"는 신호.

#### 3.3.2 API

```swift
final class LoadingSkeletonView: UIView {

    enum Style {
        /// 카테고리 그리드 (320x220 × 5열 × 3행)
        case categoryGrid
        /// 방송 그리드 (400x282 × 4열 × 2행)
        case broadcastGrid
        /// 가로 캐러셀 (320x220 × 5개)
        case carousel
    }

    init(style: Style)

    /// shimmer 시작
    func startAnimating()

    /// shimmer 멈춤 + 페이드 아웃 후 superview에서 제거
    func stopAnimating(completion: (() -> Void)? = nil)
}
```

#### 3.3.3 시각 사양

- **카드 placeholder**: `DS.Colors.skeleton` (#1C1C20) 배경, `DS.Corner.card` (18pt) 라운드.
- **shimmer**: `CAGradientLayer` 를 카드 위에 얹어 좌→우로 흰색 가로선이 이동.
  - 컬러: `[skeleton, skeleton.withAlphaComponent(0.6).blended(white), skeleton]`
  - 위치 stops: `[0.0, 0.5, 1.0]` → `[1.0, 1.5, 2.0]` 으로 1.5초 주기 무한 반복.
  - `CABasicAnimation(keyPath: "locations")`, `repeatCount = .infinity`.
- **레이아웃**: Style별 itemSize에 맞춰 NSLayoutConstraint로 카드를 배치. 실제 collectionView/카드 사이즈와 1:1 매칭하지 않아도 됨 (대략 비율만 맞으면 됨).

#### 3.3.4 사용 위치

| ViewController | Style | 호출 위치 |
|---|---|---|
| `LiveCategoriesViewController` | `.categoryGrid` | `loadCategories` 시작 시 추가, 응답 도착 시 `stopAnimating` |
| `LiveListViewController` | `.broadcastGrid` | `loadBroadcasts` 시작 시 |
| `HomeViewController` | 캐러셀 행마다 `.carousel` (또는 전체 `.broadcastGrid` 1회) | 첫 진입 시 |
| `SearchViewController` | `.broadcastGrid` | 검색 실행 시 (단계 1에서는 즉시 필터링이므로 생략 가능) |

#### 3.3.5 기존 `statusLabel` 처리

- 스켈레톤 도입 후에도 **에러 메시지**는 statusLabel로 표시. 로딩 메시지("불러오는 중...")만 스켈레톤으로 대체.
- 응답이 빈 배열일 때는 스켈레톤 멈춘 후 "현재 라이브 중인 방송이 없습니다" statusLabel 표시.

---

### 3.4 ImageCache (공용)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/UIImageView+Cache.swift`

#### 3.4.1 역할

`URLSession.shared.dataTask`를 직접 호출하는 6곳의 코드를 일괄 교체. NSCache (메모리) + URLCache (디스크 — 시스템 기본) 활용. 디스크 캐시는 별도 코드 없이 URLSession이 알아서 처리 (Cache-Control 헤더 기반).

#### 3.4.2 API

```swift
final class ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage?
    func store(_ image: UIImage, for url: URL)
    func clear()
}

extension UIImageView {
    /// 캐시 우선 로드. completion에서 캐시 hit 여부 알 수 있음.
    /// 셀 재사용 시 token으로 이전 요청 취소 처리.
    @discardableResult
    func loadImage(from url: URL?, placeholder: UIColor = DS.Colors.skeleton) -> UUID?
    
    /// 이전 요청 취소
    func cancelImageLoad(token: UUID?)
}
```

내부 구현 핵심:
- `image(for:)` — 메모리 캐시 우선, 없으면 nil.
- `loadImage(from:)` 흐름:
  1. `image = nil`, `backgroundColor = placeholder`
  2. URL이 nil이면 return nil
  3. 메모리 캐시 hit → 즉시 `image = cached`, return nil
  4. 미스 → `URLSession.shared.dataTask` 시작, UUID 토큰 발행
  5. 응답 시 메모리 캐시 저장 + `image = result`
  6. UUID를 `objc_setAssociatedObject`로 imageView에 묶어 두고, 셀 재사용 시 `cancelImageLoad(token:)` 호출
- 메모리 캐시 사이즈: `totalCostLimit = 50 MB` (이미지 데이터 길이 기준), `countLimit = 200`.

#### 3.4.3 사용 위치 일괄 교체

| 파일 | v1 (`URLSession.shared.dataTask`) | v2 |
|---|---|---|
| `LiveCategoriesViewController.swift:217-225` | `CategoryCell.configure` 내 직접 dataTask | `imageView.loadImage(from: cat.imageURL)` |
| `LiveListViewController.swift:330-338` | `LiveBroadcastCell.configure` | `imageView.loadImage(from: bc.thumbnailURL)` |
| `MyViewController.swift:476-489` | `MyLiveBroadcastCell.configure` (라이브 썸네일) | `imageView.loadImage(from:)` + fallback 콜백 |
| `MyViewController.swift:585-594` | `MyOfflineBJCell.configure` (프로필) | `imageView.loadImage(from:)` |
| `PlayerViewController.swift:138-145` | `loadPoster` | `posterImageView.loadImage(from:)` |
| (신규) HomeViewController, SearchViewController 셀 | — | `imageView.loadImage(from:)` |

#### 3.4.4 라이브 썸네일 캐시 무효화 처리 (특수 케이스)

`MyLiveBroadcastCell`은 `liveimg.sooplive.com/m/{bjId}?dummy=timestamp` 로 매번 새 URL을 만들어 캐시를 우회한다. v2에서는:
- **요청 단위 캐시**: 5분 동안 같은 BJ의 URL은 동일 (timestamp를 5분 단위로 라운드).
- `URL(string: "https://liveimg.sooplive.com/m/\(bjId)?ts=\(Int(Date().timeIntervalSince1970) / 300)")`
- 결과: 5분 동안은 캐시 hit → 카드 재사용 시 깜빡임 없음. 5분 후 자연 갱신.

---

## 4. 기존 화면 개선 사항

### 4.1 RootTabBarController (4탭 확장)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/RootTabBarController.swift`

#### 4.1.1 변경 내용 (line 단위)

| 라인 | v1 | v2 |
|---|---|---|
| `:17` | `let liveNav = makeNav(root: LiveCategoriesViewController(), title: "LIVE", tag: 0)` | `let homeNav = makeNav(root: HomeViewController(), title: "HOME", tag: 0)` 추가 |
| `:18` | `let exploreNav = ... tag: 1` | `let liveNav = ... tag: 1` |
| `:19` | `let myNav = ... tag: 2` | `let exploreNav = ... tag: 2` |
| `:20` | (없음) | `let myNav = ... tag: 3` |
| `:21` | `viewControllers = [liveNav, exploreNav, myNav]` | `viewControllers = [homeNav, liveNav, exploreNav, myNav]` |
| `:22` | `selectedIndex = 0` | `selectedIndex = 0` (HOME) — 그대로지만 의미 변경 |

### 4.2 LiveCategoriesViewController (위계/포커스 강화)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/LiveCategoriesViewController.swift`

#### 4.2.1 변경 항목

| 위치 | v1 | v2 |
|---|---|---|
| `:164` `titleLabel.numberOfLines = 1` | 1줄 truncating | **`numberOfLines = 2`** — 긴 카테고리명 허용. 단 `lineBreakMode = .byTruncatingTail` 유지 |
| `:165` `lineBreakMode` | byTruncatingTail | 유지 |
| `:162` `titleLabel.font = DS.Typography.cardTitle` | 22pt semibold | 유지 (카테고리명은 22pt가 적절) |
| `:30` `setupUI` | dim 직접 사용 X (statusLabel만) | 변경 없음 |
| `:35` `statusLabel` | 항상 텍스트 | 로딩 시작 시 `LoadingSkeletonView(.categoryGrid)` 표시, 응답 후 stopAnimating. statusLabel은 에러/빈데이터 전용 |
| `:217-225` `CategoryCell.configure` 내 `URLSession dataTask` | 직접 다운로드 | **`imageView.loadImage(from: cat.imageURL)`** |
| `:48` `sectionInset = UIEdgeInsets(top: 32, ...)` | 매직 넘버 | `DS.Layout.gridTopInset`, `DS.Layout.gridBottomInset` 사용 |
| `:60` `headerView.topAnchor ... constant: 30` | 매직 넘버 | `DS.Layout.headerTopOffset` |
| `:69` `collectionView.topAnchor ... constant: 24` | 매직 넘버 | `DS.Layout.gridTopGap` |

#### 4.2.2 정보 영역 높이 조정 (2줄 지원)

`CategoryCell`의 정보 영역이 50pt (320x50)이지만, 2줄 제목 + 시청자수까지 표시하려면 부족. **새로운 카드 높이 240pt (이미지 170pt + 정보 70pt)** 로 변경:

```swift
// DesignSystem.swift
static let category = CGSize(width: 320, height: 240)  // v1: 220 → v2: 240
```

- `imageView.heightAnchor = 170` 유지.
- 정보 영역 70pt = 제목 2줄(약 56pt) + spacing 4 + 시청자수 1줄(약 20pt) + 패딩.
- 5열 그리드 영향 없음 (가로 사이즈 320 유지). 행 간격 32pt로 1080p에서 2.5행 표시 (스크롤).

#### 4.2.3 포커스 효과 그림자 클리핑 방지

평가서 C 항목에서 지적된 "lineSpacing 32pt + 그림자 40pt = 8pt 부족" 해결:
- `lineSpacing = 32` → **`lineSpacing = DS.Spacing.lg (40)`** 으로 증가. 카드 행 간격 충분.

### 4.3 LiveListViewController (위계/공용 오버레이)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/LiveListViewController.swift`

#### 4.3.1 변경 항목

| 위치 | v1 | v2 |
|---|---|---|
| `:136-188` `showLoadingOverlay/hideLoadingOverlay` | 53줄 자체 구현 | **`LoadingOverlayView` 공용 컴포넌트로 교체** (`DesignSystem.swift`에 추가) |
| `:284` `titleLabel.font = DS.Typography.cardTitle` | 22pt | **`DS.Typography.cardTitleLarge`** (26pt) — BJ 16pt와 10pt 차이로 위계 강화 |
| `:275` `viewerLabel.font = DS.Typography.tiny` | 14pt | **`DS.Typography.badge`** (16pt bold) — 3m 거리 가독성 |
| `:264, 266` `liveBadge.font = DS.Typography.badge` | 14pt | 16pt로 변경됨 (배지 위계 통일) |
| `:50` `headerView SectionHeaderView(title: "← ...")` | 유니코드 ← | `UIImage(systemName: "chevron.left")` + 별도 imageView로 변경 또는 그대로 유지 (실제 동작은 menu 키이므로 단서) — **v2에서는 그대로 두되 SF Symbol attachment로 변경** |
| `:330-338` `LiveBroadcastCell` 이미지 로딩 | 직접 dataTask | `imageView.loadImage(from: bc.thumbnailURL)` |
| `:30` `viewDidLoad` | 즉시 setupUI + loadBroadcasts | setupUI 후 `showSkeleton(.broadcastGrid)`, loadBroadcasts 응답 시 hide |
| `:285-286` `titleLabel.numberOfLines = 2` | 유지 | 유지 |
| `:71` `sectionInset` 매직 넘버 | 32/64/72/64 | `DS.Layout.gridTopInset/contentSideMargin/...` |

#### 4.3.2 카드 정보 영역 높이 재계산

카드 282pt에서 썸네일 225pt를 빼면 정보 영역 57pt. 제목 26pt 2줄(약 60pt) + BJ 16pt 1줄(약 20pt) + 패딩 = **약 100pt 필요**.

해결책: **카드 높이를 282 → 320으로 증가**:
```swift
static let broadcast = CGSize(width: 400, height: 320)  // v1: 282 → v2: 320
```
- 썸네일 225pt 유지.
- 정보 영역 95pt: 패딩 top 12 + 제목 2줄(60pt) + spacing 4 + BJ 1줄(20pt) + 패딩 bottom 12 = 108pt. **정보 영역 95pt로 약간 압축 (titleLabel 2줄 lineHeight 가능)**.
- 4열 × 400 + 24 × 3 + 64 × 2 = 1800pt (가로 영향 없음).
- 4열 × 2.5행 = 10개가 1080p에 보임 → 스크롤로 더.

#### 4.3.3 LoadingOverlayView 공용 컴포넌트 추가

`DesignSystem.swift` 끝에 추가:

```swift
/// 화면 가운데 카드 형태의 로딩 오버레이.
/// LiveListVC / ExploreVC / MyVC / HomeVC / SearchVC가 모두 사용.
final class LoadingOverlayView: UIView {

    private let card = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    static func show(in parent: UIView, message: String) -> LoadingOverlayView {
        let overlay = LoadingOverlayView(message: message)
        parent.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: parent.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
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
            card.widthAnchor.constraint(equalToConstant: 480),
            card.heightAnchor.constraint(equalToConstant: 200),

            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 40),

            messageLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 24),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
```

3곳 ViewController에서 사용:
```swift
// LiveListViewController.swift presentPlayer 내
private var loadingOverlay: LoadingOverlayView?
// before fetchStreamInfo
loadingOverlay = LoadingOverlayView.show(in: view, message: "\(bc.bjNick) 방송 연결 중...")
// after response
loadingOverlay?.dismiss()
loadingOverlay = nil
```

### 4.4 ExploreViewController (검색 push, 최근 시청 실데이터)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/ExploreViewController.swift`

#### 4.4.1 변경 항목

| 위치 | v1 | v2 |
|---|---|---|
| `:245` `ToastView.show(in: view, message: "검색 기능은 곧 제공됩니다", ...)` | placeholder | **`navigationController?.pushViewController(SearchViewController(), animated: true)`** |
| `:24` `recentBroadcasts: [LiveBroadcast] = []` | 영원히 빈 배열 | `viewWillAppear`마다 `RecentBroadcastStore.shared.load()` 호출 |
| `:129-174` `makeLoadingOverlay` | 자체 구현 | `LoadingOverlayView` 사용 |
| `:131` `dim.backgroundColor = UIColor(white: 0, alpha: 0.55)` | 직접 작성 | 해결 (위 LoadingOverlayView로 대체) |
| `:331` `titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .semibold)` | 매직 넘버 | **`DS.Typography.subsection`** (CarouselRowCell을 별도 파일로 분리하면서 함께 변경) |

#### 4.4.2 ExploreVC 유지/축소 결정

**유지**한다. HOME과 ExploreVC의 역할 차이:
- **HOME**: 개인화 (즐겨찾기, 최근 시청 중심) + 인기 콘텐츠 미리보기.
- **탐색**: 검색 진입점 + 인기 콘텐츠 전체 보기 + 카테고리 탐색.

ExploreVC 섹션 재배치 (4개 → 3개):
1. 검색 진입 셀 (그대로)
2. 지금 가장 핫한 방송 (그대로)
3. 인기 카테고리 (그대로)
- 최근 시청 섹션은 ExploreVC에서 **제거** (HOME에서만 다룸). 코드 죽은 라인 정리.

#### 4.4.3 CarouselRowCell 외부 파일로 분리

기존 `ExploreViewController.swift` 내부 클래스 `CarouselRowCell`을 **`CarouselRowCell.swift`로 분리**해 HomeVC/ExploreVC가 공유. 분리 시 변경:
- `titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .semibold)` → `DS.Typography.subsection`
- 셀 자체에는 변경 없음. v1 시그니처 그대로.

### 4.5 MyViewController (라이브/오프라인 차별화, 버그 수정)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/MyViewController.swift`

#### 4.5.1 버그 수정: stationName.isEmpty 중복 표시

평가서 B 항목 ("titleLabel과 bjLabel에 같은 닉네임이 표시될 수 있음") 해결:

```swift
// v1 (line 468-469)
titleLabel.text = f.stationName.isEmpty ? f.nick : f.stationName
bjLabel.text = f.nick

// v2
if f.stationName.isEmpty {
    // 방송 제목을 알 수 없음 → 제목 라벨 숨김, BJ 닉네임만 표시
    titleLabel.isHidden = true
    bjLabel.text = f.nick
    bjLabel.font = DS.Typography.cardTitleLarge  // 닉네임을 카드 제목 위계로 승격
} else {
    titleLabel.isHidden = false
    titleLabel.text = f.stationName
    bjLabel.text = f.nick
    bjLabel.font = DS.Typography.caption  // 원래 크기
}
```

레이아웃 영향: `titleLabel.isHidden = true`일 때 bjLabel이 titleLabel의 top constraint를 대신 받아야 함. 해결책은 둘 다 stackView (`UIStackView(axis: .vertical)`)로 묶어 stack의 spacing/arrangedSubviews 관리.

```swift
// v2 setupViews 내
let textStack = UIStackView(arrangedSubviews: [titleLabel, bjLabel])
textStack.axis = .vertical
textStack.spacing = 4
textStack.translatesAutoresizingMaskIntoConstraints = false
contentView.addSubview(textStack)

NSLayoutConstraint.activate([
    textStack.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
    textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.sm),
    textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.sm),
])
```

#### 4.5.2 라이브 BJ 카드 위계 강화

| 위치 | v1 | v2 |
|---|---|---|
| `:432` `titleLabel.font = DS.Typography.cardTitle` | 22pt | **`DS.Typography.cardTitleLarge`** (26pt) |
| `:433` `numberOfLines = 1` | 1줄 | **`numberOfLines = 2`** — 긴 제목 허용 |
| `:439` `bjLabel.font = DS.Typography.caption` | 16pt | 유지 (제목 26pt - BJ 16pt = 10pt 차이) |
| `:447` `imageView.heightAnchor = 213` (16:9 비율) | 가독성 충분 | 유지 |
| 카드 크기 380×280 | 정보 영역 67pt | 280 → 320으로 증가, 정보 영역 107pt |

`DS.CardSize.myLive`:
```swift
static let myLive = CGSize(width: 380, height: 320)  // v1: 280 → v2: 320
```

#### 4.5.3 오프라인 BJ 카드 차별화 강화

평가서 C 항목 ("MyOfflineBJCell의 시각 차별화 부재") 해결:

```swift
// MyOfflineBJCell.configure 내 imageView 처리
// v1
imageView.alpha = 0.85
darkOverlay.backgroundColor = UIColor(white: 0, alpha: 0.35)

// v2 — 흑백 + 더 어두운 처리
imageView.alpha = 0.6
darkOverlay.backgroundColor = UIColor(white: 0, alpha: 0.45)
// + CIFilter `CIPhotoEffectMono` 적용 (또는 CGImage 흑백 변환)
// 또는 더 간단: imageView.layer.compositingFilter = "colorMonochromeBlendMode"
```

흑백 처리 단순화 방안:
- `imageView.layer.opacity = 0.6` + `darkOverlay.alpha = 0.5` 만으로도 충분히 죽은 느낌.
- CoreImage 필터를 cell마다 적용하면 비용이 크므로 v2 단계에서는 **alpha + dark overlay**로 대체.

#### 4.5.4 오프라인 카드 포커스 시 추가 단서

평가서 C 항목 추가 해결 — 포커스 시 시각 차별화:

`MyOfflineBJCell.didUpdateFocus` 내:
```swift
override func didUpdateFocus(in context: UIFocusUpdateContext,
                            with coordinator: UIFocusAnimationCoordinator) {
    coordinator.addCoordinatedAnimations { [weak self] in
        guard let self = self else { return }
        if self.isFocused {
            // 1. 표준 scale + 그림자
            FocusEffect.apply(to: self, focused: true)
            // 2. 추가: 회색 보더 (라이브와 차별화)
            self.contentView.layer.borderColor = DS.Colors.focusBorderOffline.cgColor
            self.contentView.layer.borderWidth = 4
            // 3. 추가: imageView 알파 회복 (포커스 시 약간 밝게)
            self.imageView.alpha = 0.8
        } else {
            FocusEffect.apply(to: self, focused: false)
            self.contentView.layer.borderWidth = 0
            self.imageView.alpha = 0.6
        }
    }
}
```

라이브 카드 포커스: 그림자 + scale + 보더 없음 (기본 `FocusEffect.apply`).
오프라인 카드 포커스: 그림자 + scale + **회색 보더 4pt** + 알파 회복.

#### 4.5.5 헤더 referenceSize 동적화 (1920 하드코딩 제거)

```swift
// v1 (line 62)
layout.headerReferenceSize = CGSize(width: 1920, height: 80)

// v2
// setupUI에서는 임시값 (0 또는 임의)
layout.headerReferenceSize = CGSize(width: 0, height: DS.Layout.sectionHeaderHeight)

// viewDidLayoutSubviews에서 collectionView의 실제 너비로 갱신
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let flow = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
        flow.headerReferenceSize = CGSize(width: collectionView.bounds.width, height: DS.Layout.sectionHeaderHeight)
    }
}
```

`MyViewController.swift:295-298` 의 `referenceSizeForHeaderInSection`은 동적으로 cv.bounds.width 반환하므로 그대로 두면 됨.

#### 4.5.6 이미지 캐싱 적용

`MyLiveBroadcastCell.configure` 의 `liveimg.sooplive.com/m/{bjId}?dummy=`:
```swift
// v2 — 5분 단위 timestamp로 캐시 활용
let bucket = Int(Date().timeIntervalSince1970) / 300  // 5분 = 300초
let urlStr = "https://liveimg.sooplive.com/m/\(f.bjId)?ts=\(bucket)"
if let url = URL(string: urlStr) {
    imageView.loadImage(from: url) { [weak self] success in
        if !success {
            self?.loadProfile(bjId: f.bjId)
        }
    }
}
```

`UIImageView.loadImage` 시그니처 확장:
```swift
@discardableResult
func loadImage(from url: URL?, placeholder: UIColor = DS.Colors.skeleton, completion: ((Bool) -> Void)? = nil) -> UUID?
```

#### 4.5.7 contentEdgeInsets → UIButton.Configuration

```swift
// v1 (line 153-163)
let refreshBtn = UIButton(type: .system)
refreshBtn.setTitle("새로고침", for: .normal)
refreshBtn.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
refreshBtn.setTitleColor(DS.Colors.textPrimary, for: .normal)
refreshBtn.backgroundColor = DS.Colors.primary
refreshBtn.layer.cornerRadius = DS.Corner.button
refreshBtn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 36, bottom: 14, right: 36)

// v2
var config = UIButton.Configuration.plain()
config.title = "새로고침"
config.baseBackgroundColor = DS.Colors.primary
config.baseForegroundColor = DS.Colors.textPrimary
config.background.cornerRadius = DS.Corner.button
config.contentInsets = DS.ButtonInsets.cta
config.titleTextAttributesTransformer = .init { incoming in
    var out = incoming
    out.font = DS.Typography.cardTitle  // 22pt semibold
    return out
}
let refreshBtn = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
    self?.loadFavorites()
})
```

#### 4.5.8 28pt 매직 넘버 → `DS.Typography.subsection`

- `:139` `line1.font` → `DS.Typography.subsection`
- `:343, 367` `label.font` → `DS.Typography.subsection`
- `:374` `attributed font` → `DS.Typography.cardTitle` (22pt — section 카운트는 22가 적절)

#### 4.5.9 오프라인 닉네임 폰트 → 토큰

- `:555` `nickLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)` → `DS.Typography.subcaption`

### 4.6 PlayerViewController (상단 메타 오버레이)

**파일**: `/Volumes/MacMiniUsb/soop-app/soop-app/PlayerViewController.swift`

#### 4.6.1 상단 메타 오버레이 (신규)

평가서 D 항목 ("Player의 시청자수/방송 시간 오버레이 부재") 해결:

재생 중 화면 최상단에 가로로 슬라이드 인하는 메타 바를 표시:

```
┌──────────────────────────────────────────────────────────┐
│ ● LIVE  방송 제목 (1줄, 좌측)               BJ닉네임      │  ← 60pt 높이
└──────────────────────────────────────────────────────────┘
```

- 진입 시 (`readyToPlay` 직후) 슬라이드 다운으로 등장 → **5초 후 자동 페이드 아웃**.
- 사용자가 리모컨 키 입력 시 다시 슬라이드 다운 → 5초 후 페이드 아웃 (resolutionLabel과 동일 패턴).
- 메뉴 키 입력 시는 dismiss하지 않고 player 종료 동작 그대로.

**구현 위치**: `setupResolutionLabel` 옆에 `setupTopMetaOverlay` 추가.

```swift
private var topMetaContainer: UIView!
private var topMetaTitleLabel: UILabel!
private var topMetaBJLabel: UILabel!
private var topMetaLiveBadge: UILabel!

private func setupTopMetaOverlay() {
    topMetaContainer = UIView()
    topMetaContainer.backgroundColor = DS.Colors.viewerBadgeBackground  // 검정 65% alpha
    topMetaContainer.layer.cornerRadius = DS.Corner.modal
    topMetaContainer.alpha = 0  // 초기 숨김
    topMetaContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topMetaContainer)

    topMetaLiveBadge = UILabel()
    topMetaLiveBadge.text = "  ● LIVE  "
    topMetaLiveBadge.textColor = DS.Colors.textPrimary
    topMetaLiveBadge.backgroundColor = DS.Colors.live
    topMetaLiveBadge.font = DS.Typography.badge
    topMetaLiveBadge.layer.cornerRadius = DS.Corner.badge
    topMetaLiveBadge.layer.masksToBounds = true
    topMetaLiveBadge.translatesAutoresizingMaskIntoConstraints = false
    topMetaContainer.addSubview(topMetaLiveBadge)

    topMetaTitleLabel = UILabel()
    topMetaTitleLabel.text = streamInfo?.title ?? ""
    topMetaTitleLabel.textColor = DS.Colors.textPrimary
    topMetaTitleLabel.font = DS.Typography.cardTitleLarge  // 26pt
    topMetaTitleLabel.numberOfLines = 1
    topMetaTitleLabel.lineBreakMode = .byTruncatingTail
    topMetaTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    topMetaContainer.addSubview(topMetaTitleLabel)

    topMetaBJLabel = UILabel()
    topMetaBJLabel.text = streamInfo?.bjNick ?? ""
    topMetaBJLabel.textColor = DS.Colors.textSecondary
    topMetaBJLabel.font = DS.Typography.cardTitle  // 22pt
    topMetaBJLabel.translatesAutoresizingMaskIntoConstraints = false
    topMetaContainer.addSubview(topMetaBJLabel)

    NSLayoutConstraint.activate([
        topMetaContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        topMetaContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
        topMetaContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
        topMetaContainer.heightAnchor.constraint(equalToConstant: 64),

        topMetaLiveBadge.leadingAnchor.constraint(equalTo: topMetaContainer.leadingAnchor, constant: 20),
        topMetaLiveBadge.centerYAnchor.constraint(equalTo: topMetaContainer.centerYAnchor),
        topMetaLiveBadge.heightAnchor.constraint(equalToConstant: 28),

        topMetaTitleLabel.leadingAnchor.constraint(equalTo: topMetaLiveBadge.trailingAnchor, constant: 16),
        topMetaTitleLabel.centerYAnchor.constraint(equalTo: topMetaContainer.centerYAnchor),
        topMetaTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: topMetaBJLabel.leadingAnchor, constant: -20),

        topMetaBJLabel.trailingAnchor.constraint(equalTo: topMetaContainer.trailingAnchor, constant: -20),
        topMetaBJLabel.centerYAnchor.constraint(equalTo: topMetaContainer.centerYAnchor),
    ])
}

private var hideMetaTimer: Timer?
private func showTopMetaTemporarily() {
    hideMetaTimer?.invalidate()
    UIView.animate(withDuration: 0.25) {
        self.topMetaContainer.alpha = 1
    }
    hideMetaTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
        UIView.animate(withDuration: 0.6) {
            self?.topMetaContainer.alpha = 0
        }
    }
}
```

호출:
- `readyToPlay` 케이스 진입 시 `showTopMetaTemporarily()` 호출 (기존 `hidePreRoll()` 옆).
- `pressesBegan` 어떤 키 입력이든 → `showTopMetaTemporarily()` 추가.

#### 4.6.2 28pt → 토큰

| 위치 | v1 | v2 |
|---|---|---|
| `:82` `preRollTitleLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)` | 32pt | **`DS.Typography.section`** (36pt) — 메인 화면 강조 |
| `:91` `preRollBJLabel.font = UIFont.systemFont(ofSize: 22, weight: .medium)` | 22pt medium | `DS.Typography.cardTitle` (22pt semibold) — 약간 굵게 |
| `:161` `resolutionLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)` | 22pt bold | `DS.Typography.cardTitle` |
| `:417` `titleLabel.font` (에러카드) | 28pt | **`DS.Typography.subsection`** |
| `:433, 444` 버튼 폰트 22pt | 22pt | `DS.Typography.cardTitle` |

#### 4.6.3 contentEdgeInsets → Configuration

`:437, 448` 의 `contentEdgeInsets` 두 곳을 `UIButton.Configuration` 패턴으로 마이그레이션 (4.5.7과 동일 코드 패턴).

#### 4.6.4 해상도 라벨 텍스트 명확화

평가서 B 항목 ("해상도 라벨 'HD' 모호") 해결:

```swift
// v1 (line 282-290)
case ...360: quality = "SD"
case ...540: quality = "HD"
case ...720: quality = "HD+"
case ...1080: quality = "FHD"
case ...1440: quality = "QHD"
default: quality = "UHD"

// v2 — 해상도 픽셀 수치를 메인으로
case ...360: quality = "360p · SD"
case ...540: quality = "540p · HD"
case ...720: quality = "720p · HD+"
case ...1080: quality = "1080p · FHD"
case ...1440: quality = "1440p · QHD"
default: quality = "2160p · UHD"

// 출력
self.resolutionLabel.text = " \(quality) "
// 줄바꿈 제거, 1줄 라벨
```

`resolutionLabel.numberOfLines = 1` 로 변경.

#### 4.6.5 Retry 카운트 제한

평가서 D 항목 ("retry 무한 루프 방지 없음") 해결:

```swift
// PlayerViewController에 카운터 추가
private var retryCount = 0
private let maxRetries = 3

@objc private func retryTapped() {
    retryCount += 1
    if retryCount >= maxRetries {
        // 최대 시도 횟수 초과 — 안내 후 종료
        showError(title: "재생할 수 없습니다",
                  description: "잠시 후 다시 시도해주세요. (\(maxRetries)회 실패)")
        // retry 버튼 숨김
        // ...
        return
    }
    // 기존 코드: 에러 컨테이너 제거 + startPlayback
}
```

또한 `showError` 호출 시 `retryCount >= maxRetries` 면 retryBtn을 추가하지 않음. backBtn만 표시.

#### 4.6.6 에러 카드 두 버튼 간격 조정

평가서 C 항목 ("retry/back 버튼 사이 간격 24pt + scale 시 충돌") 해결:

```swift
// v1 (line 472-476)
retryBtn.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 40),
retryBtn.trailingAnchor.constraint(equalTo: container.centerXAnchor, constant: -12),

backBtn.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 40),
backBtn.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 12),

// v2 — 간격 24 → 40pt로 증가
retryBtn.trailingAnchor.constraint(equalTo: container.centerXAnchor, constant: -20),
backBtn.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 20),
```

추가로 **기본 포커스 명시**: 에러카드 표시 시 retryBtn이 우선 포커스되도록.

```swift
override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if let err = errorContainer, err.superview != nil {
        return [retryBtn]  // 에러 시 retry 우선
    }
    return super.preferredFocusEnvironments
}
```

(retryBtn을 instance var로 끌어올려야 함.)

#### 4.6.7 Pre-roll 포커스 정책

평가서 C 항목 ("Pre-roll 화면의 포커스 environment 미설정") 해결:

Pre-roll 단계에서는 사용자가 할 수 있는 작업이 menu 키 (= dismiss) 뿐이다. 이건 시스템 처리이므로 별도 포커스 environment 불필요. **단**, 사용자에게 "메뉴 키로 취소할 수 있음" 단서를 추가:

```swift
// preRollStatusLabel 아래에 추가
preRollHintLabel = UILabel()
preRollHintLabel.text = "Menu 키를 눌러 취소"
preRollHintLabel.textColor = DS.Colors.textTertiary
preRollHintLabel.font = DS.Typography.tiny
preRollHintLabel.textAlignment = .center
// ... 레이아웃: preRollStatusLabel 아래 8pt
```

#### 4.6.8 종료 시 자연스러운 트랜지션

평가서 미언급이지만 "PlayerViewController 추가 개선" 요구사항. dismiss 애니메이션 강화:

```swift
@objc private func backTapped() {
    avVC?.player?.pause()
    // pre-roll/error/avVC 모두 페이드 아웃 후 dismiss
    UIView.animate(withDuration: 0.25, animations: {
        self.view.alpha = 0
    }, completion: { _ in
        self.dismiss(animated: false)  // 시스템 dismiss는 즉시 (이미 페이드아웃 완료)
    })
}

override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    for press in presses {
        if press.type == .menu {
            backTapped()  // 동일 처리
            return
        }
    }
    if avVC?.view.alpha ?? 0 > 0 {
        showResolutionLabelTemporarily()
        showTopMetaTemporarily()  // v2 신규
    }
    super.pressesBegan(presses, with: event)
}
```

#### 4.6.9 재생 시작 시 최근 시청 기록 저장

```swift
// startPlayback 내 readyToPlay 케이스에서
case .readyToPlay:
    UIView.animate(withDuration: 0.3) { self.avVC.view.alpha = 1 }
    self.hidePreRoll()
    player.play()
    self.startObservingResolution(item: it)
    // v2 신규: 최근 시청 기록 저장
    RecentBroadcastStore.shared.record(
        broadNo: info.broadNo,
        bjId: info.bjId,
        bjNick: info.bjNick,
        title: info.title,
        thumbnailURL: self.posterThumbnailURL
    )
```

---

## 5. 버그 수정 항목

### 5.1 MyLiveBroadcastCell stationName 중복 표시

**위치**: `MyViewController.swift:468-469`
**문제**: `f.stationName.isEmpty` 시 `titleLabel.text = f.nick`, `bjLabel.text = f.nick` — 같은 텍스트 위아래 중복.
**해결**: 4.5.1 참조 (titleLabel.isHidden 처리 + UIStackView 레이아웃).

### 5.2 LoadingOverlay 3곳 중복 코드

**위치**: `LiveListViewController.swift:136-188`, `ExploreViewController.swift:129-174`, `MyViewController.swift:198-249`
**문제**: 53줄 유사 코드가 3곳에 복붙되어 있음.
**해결**: 4.3.3의 `LoadingOverlayView` 공용 컴포넌트로 통합. 3곳의 `showLoadingOverlay`/`hideLoadingOverlay` 메서드 제거하고 `LoadingOverlayView.show(in:message:)` / `overlay.dismiss()` 호출.

### 5.3 headerReferenceSize 1920 하드코딩

**위치**: `MyViewController.swift:62`
**문제**: `CGSize(width: 1920, height: 80)` — 1080p 해상도 가정한 매직 넘버.
**해결**: 4.5.5 참조 (`viewDidLayoutSubviews`에서 동적 갱신).

### 5.4 contentEdgeInsets deprecated 경고

**위치**: `MyViewController.swift:159`, `PlayerViewController.swift:437, 448`
**문제**: tvOS 15에서 deprecated.
**해결**: `UIButton.Configuration.plain()` + `DS.ButtonInsets.cta` 적용. 4.5.7, 4.6.3 참조.

### 5.5 28pt 폰트 4곳 중복

**위치**: `MyViewController.swift:139, 343, 367`, `ExploreViewController.swift:331`, `PlayerViewController.swift:417`
**문제**: `UIFont.systemFont(ofSize: 28, weight: .semibold)` 4곳에 직접 작성.
**해결**: `DS.Typography.subsection` 토큰 추가 후 일괄 치환.

### 5.6 dim 컬러 3곳 중복

**위치**: `LiveListViewController.swift:139`, `ExploreViewController.swift:131`, `MyViewController.swift:201`
**문제**: `UIColor(white: 0, alpha: 0.55)` 직접 작성. `DS.Colors.overlay` 이미 정의됐는데 미사용.
**해결**: 5.2의 LoadingOverlayView 통합 시 자동 해결.

### 5.7 이미지 fetch race condition

**위치**: `LiveCategoriesViewController.swift:217-225` (및 유사 5곳)
**문제**: `imageView.image = nil; imageTask?.cancel(); ... dataTask` 순서에서 이전 fetch가 완료 직전에 새 dequeue되면 이미지가 다른 셀에 그려질 수 있음.
**해결**: `UIImageView+Cache.swift`의 토큰 기반 패턴으로 자동 해결 (UUID 토큰으로 stale response 무시).

### 5.8 ExploreVC recentBroadcasts 죽은 데이터

**위치**: `ExploreViewController.swift:24, 219-229`
**문제**: 영원히 빈 배열, 섹션 안 보임.
**해결**: 4.4.1 참조 (HOME으로 이전, ExploreVC에서 제거).

---

## 6. 구현 체크리스트 (디자인 에이전트용)

각 항목 완료 시 체크. 모두 체크되어야 100점 달성.

### 6.1 Phase 1 — 디자인 시스템 강화 (반나절)

- [ ] `DesignSystem.swift` 에 `DS.Typography.subsection` (28pt semibold), `subcaption` (18pt semibold), `cardTitleLarge` 유지 (26pt) 토큰 추가.
- [ ] `DesignSystem.swift` 에 `DS.Layout` enum 추가 (`contentSideMargin`, `sectionHeaderHeight`, `headerTopOffset`, `gridTopGap`, `gridTopInset`, `gridBottomInset`, `screenWidth`, `screenHeight`).
- [ ] `DesignSystem.swift` 에 `DS.ButtonInsets.cta` 추가.
- [ ] `DesignSystem.swift` 에 `DS.Colors.offlineImageTint`, `DS.Colors.focusBorderOffline` 추가.
- [ ] `DesignSystem.swift` 끝에 `LoadingOverlayView` 클래스 추가 (4.3.3).
- [ ] `DesignSystem.swift` 의 `DS.Typography.badge` 를 14pt → **16pt bold** 로 변경 (3m 거리 가독성).
- [ ] `DS.CardSize.broadcast` (400, 282) → (400, 320), `myLive` (380, 280) → (380, 320), `category` (320, 220) → (320, 240) 로 변경.
- [ ] `DS.CardSize.miniLive`, `recommendBJ`, `searchResult` 신규 추가.

### 6.2 Phase 2 — 공용 인프라 (반나절)

- [ ] `UIImageView+Cache.swift` 신규 작성. `ImageCache` singleton + `UIImageView.loadImage(from:placeholder:completion:)` extension.
- [ ] `LoadingSkeletonView.swift` 신규 작성. 3가지 Style (`.categoryGrid`, `.broadcastGrid`, `.carousel`). shimmer 애니메이션.
- [ ] `RecentBroadcastStore.swift` 신규 작성. UserDefaults 기반 최근 시청 20개 FIFO.
- [ ] `CarouselRowCell.swift` 신규 작성. `ExploreViewController.swift` 내부 클래스를 외부로 분리. titleLabel.font를 `DS.Typography.subsection`로.

### 6.3 Phase 3 — 신규 화면 (1.5일)

- [ ] `HomeViewController.swift` 신규 작성. 4섹션 (인기 라이브 / 인기 카테고리 TOP 6 / 최근 시청 / 즐겨찾기 라이브).
- [ ] `SearchViewController.swift` 신규 작성. UISearchBar + 결과 그리드 + 최근 검색어 (단계 1: 클라이언트 필터링).
- [ ] `RootTabBarController.swift` 4탭 확장 (HOME / LIVE / 탐색 / MY). `selectedIndex = 0`.

### 6.4 Phase 4 — 기존 화면 수정 (1일)

#### LiveCategoriesViewController.swift

- [ ] `CategoryCell.titleLabel.numberOfLines = 2`.
- [ ] `CategoryCell.configure` 이미지 로딩을 `imageView.loadImage(from:)`로 교체.
- [ ] `viewDidLoad` 시 `LoadingSkeletonView(style: .categoryGrid)` 표시, 응답 후 stopAnimating.
- [ ] `sectionInset` / `headerTopOffset` / `gridTopGap` 토큰 적용.
- [ ] `lineSpacing 32 → DS.Spacing.lg (40)`.

#### LiveListViewController.swift

- [ ] `showLoadingOverlay`/`hideLoadingOverlay` 제거. `LoadingOverlayView.show` / `dismiss` 사용.
- [ ] `LiveBroadcastCell.titleLabel.font = DS.Typography.cardTitleLarge` (26pt).
- [ ] `LiveBroadcastCell.viewerLabel.font = DS.Typography.badge` (16pt bold).
- [ ] `LiveBroadcastCell.configure` 이미지 로딩 → `loadImage`.
- [ ] `viewDidLoad` 시 스켈레톤 표시.
- [ ] `DS.CardSize.broadcast` (400, 320)에 맞춰 정보 영역 95pt 재배치.
- [ ] sectionInset 토큰 적용.

#### ExploreViewController.swift

- [ ] 검색 셀 선택 → `navigationController?.pushViewController(SearchViewController(), animated: true)`.
- [ ] 최근 시청 섹션 제거 (HOME으로 이전).
- [ ] `makeLoadingOverlay` 제거 → `LoadingOverlayView` 사용.
- [ ] CarouselRowCell 내부 클래스 제거 → 외부 파일 import.
- [ ] CarouselRowCell.titleLabel.font를 `DS.Typography.subsection`로.

#### MyViewController.swift

- [ ] `MyLiveBroadcastCell.configure` 의 stationName.isEmpty 버그 수정 (4.5.1).
- [ ] `MyLiveBroadcastCell.titleLabel.font = DS.Typography.cardTitleLarge` (26pt), `numberOfLines = 2`.
- [ ] `DS.CardSize.myLive` (380, 320)에 맞춰 정보 영역 재배치.
- [ ] `MyOfflineBJCell` 흑백 처리 강화 (imageView.alpha 0.6, darkOverlay.alpha 0.45).
- [ ] `MyOfflineBJCell.didUpdateFocus` 에 회색 보더 추가 (4.5.4).
- [ ] `MyOfflineBJCell.nickLabel.font = DS.Typography.subcaption`.
- [ ] `headerReferenceSize 1920` 제거 → `viewDidLayoutSubviews`에서 동적 갱신.
- [ ] `MyLiveBroadcastCell.configure` 라이브 썸네일 URL을 5분 단위 timestamp로.
- [ ] 이미지 로딩 → `loadImage` 일괄 교체.
- [ ] `showLoadingOverlay`/`hideLoadingOverlay` 제거 → `LoadingOverlayView`.
- [ ] `28pt` 폰트 3곳을 `DS.Typography.subsection`로.
- [ ] `MySectionHeader` 카운트 폰트 22pt → `DS.Typography.cardTitle`.
- [ ] `refreshBtn` UIButton.Configuration 마이그레이션 (4.5.7).
- [ ] `viewWillAppear` 시 `loadFavorites()` 재호출 (HOME에서 즐겨찾기 추가 후 돌아왔을 때 갱신).

#### PlayerViewController.swift

- [ ] 상단 메타 오버레이 (`topMetaContainer`) 추가 (4.6.1).
- [ ] `readyToPlay` 직후 `showTopMetaTemporarily()` 호출.
- [ ] `pressesBegan` 어떤 키든 `showTopMetaTemporarily()` 호출 추가.
- [ ] `32pt` (`preRollTitleLabel`) → `DS.Typography.section` (36pt).
- [ ] `22pt` 4곳 → `DS.Typography.cardTitle`.
- [ ] `28pt` (에러카드 title) → `DS.Typography.subsection`.
- [ ] `retryBtn`, `backBtn` UIButton.Configuration 마이그레이션.
- [ ] 해상도 라벨 텍스트 "HD" 모호성 해결 (4.6.4).
- [ ] `numberOfLines = 1`로 변경.
- [ ] `retryCount` / `maxRetries = 3` 도입 (4.6.5).
- [ ] 에러카드 retry/back 버튼 간격 24 → 40 (4.6.6).
- [ ] `preferredFocusEnvironments` 에러 시 retryBtn 반환.
- [ ] Pre-roll에 "Menu 키를 눌러 취소" hint 추가 (4.6.7).
- [ ] `backTapped` 페이드 아웃 후 dismiss (4.6.8).
- [ ] `readyToPlay` 시 `RecentBroadcastStore.shared.record(...)` 호출 (4.6.9).
- [ ] `loadPoster` 를 `posterImageView.loadImage(from:)`로 교체.

### 6.5 Phase 5 — 빌드 / 검증 (반나절)

- [ ] `xcodegen generate` 실행 (신규 4개 파일 자동 포함 확인).
- [ ] `./build.sh` 또는 manual `xcodebuild` 로 BUILD SUCCEEDED 확인.
- [ ] tvOS 시뮬레이터에서 각 화면 진입 동선 확인:
  - [ ] HOME → 인기 라이브 카드 선택 → Player → menu로 복귀.
  - [ ] LIVE → 카테고리 → 방송 → Player.
  - [ ] 탐색 → 검색 셀 → SearchVC → 검색어 입력 → 결과 카드 선택 → Player.
  - [ ] MY → 라이브 BJ → Player. 오프라인 BJ → 토스트.
- [ ] 모든 ViewController가 처음 진입 시 스켈레톤 또는 빠른 응답 표시 (빈 화면 없음).
- [ ] 카드 재진입 시 이미지 깜빡임 없음 (캐시 작동).
- [ ] 매직 넘버 grep 검증:
  - [ ] `grep -rn "UIFont.systemFont(ofSize: 28" soop-app/*.swift` → 0건.
  - [ ] `grep -rn "UIColor(white: 0, alpha: 0.55)" soop-app/*.swift` → 0건.
  - [ ] `grep -rn "1920" soop-app/*.swift` → DS.Layout 정의 외 0건.
  - [ ] `grep -rn "contentEdgeInsets" soop-app/*.swift` → 0건.
- [ ] BUILD 경고: deprecated `contentEdgeInsets` 0건.

---

## 부록 A — 변경 영향 파일 (최종)

| 파일 | 변경 정도 | v2 우선순위 |
|---|---|---|
| `DesignSystem.swift` | 큰 변경 (토큰 추가 + LoadingOverlayView) | P0 |
| `RootTabBarController.swift` | 작은 변경 (HOME 탭 추가) | P0 |
| `LiveCategoriesViewController.swift` | 중간 변경 (2줄, 스켈레톤, 캐시) | P1 |
| `LiveListViewController.swift` | 중간 변경 (위계 강화, 스켈레톤, 공용 오버레이, 캐시) | P1 |
| `ExploreViewController.swift` | 중간 변경 (검색 push, 최근 시청 제거, CarouselRowCell 분리) | P1 |
| `MyViewController.swift` | 큰 변경 (버그 수정, 오프라인 차별화, 토큰 적용, 동적 헤더) | P1 |
| `PlayerViewController.swift` | 중간 변경 (메타 오버레이, retry 제한, 토큰, Configuration) | P1 |
| `HomeViewController.swift` | 신규 | P0 |
| `SearchViewController.swift` | 신규 | P0 |
| `LoadingSkeletonView.swift` | 신규 | P0 |
| `UIImageView+Cache.swift` | 신규 | P0 |
| `RecentBroadcastStore.swift` | 신규 | P1 |
| `CarouselRowCell.swift` | 신규 (분리) | P0 |
| `project.yml` | 무변경 (`sources: path: soop-app`로 자동 포함) | — |

## 부록 B — 100점 평가 기준 매트릭스

| 평가 카테고리 | v1 점수 | v2 목표 | 달성 방안 |
|---|---|---|---|
| A. 첫인상 / 디자인 일관성 | 16/20 | **20/20** | 모든 매직 넘버 제거, `DS.Colors.overlay` 등 미사용 토큰 실제 사용, LoadingOverlayView 통합 |
| B. 정보 위계 / 가독성 | 15/20 | **20/20** | 카드 제목 26pt (BJ 16pt와 10pt 차이), 카테고리명 2줄, MyLive 중복 표시 버그 해결, 시청자수 16pt, 해상도 라벨 명확화 |
| C. 리모컨 사용성 / 포커스 | 13/20 | **20/20** | 오프라인 카드 회색 보더 차별화, lineSpacing 40 확보 (그림자 클리핑 해결), Pre-roll hint 추가, 에러카드 retry 우선 포커스 + 간격 40pt |
| D. 화면별 완성도 | 14/20 | **20/20** | HOME 탭 신설, SearchVC 실구현, 스켈레톤 도입, 최근 시청 실데이터, 이미지 캐시, retry 카운트 제한, Player 메타 오버레이 |
| E. 디테일 / 마감 | 16/20 | **20/20** | LoadingOverlay 공용화, 28pt 토큰화, 이미지 캐싱, contentEdgeInsets → Configuration, headerReferenceSize 동적, race condition 해결 |
| **총점** | **74/100** | **100/100** | |

---

## 부록 C — 디자인 에이전트에 전달할 핵심 원칙

1. **하드코딩 금지**: 폰트/색상/간격은 반드시 `DS.*` 토큰을 통해서만 사용. 새 매직 넘버 발견 시 토큰 추가가 우선.
2. **공용 컴포넌트 우선**: 같은 UI가 2번 이상 나타나면 즉시 공용 컴포넌트로 추출 (`LoadingOverlayView`, `CarouselRowCell`, `SectionHeaderView` 등).
3. **이미지는 반드시 캐시**: `URLSession.shared.dataTask`를 셀에서 직접 호출하지 말 것. 항상 `imageView.loadImage(from:)`.
4. **빈 화면 금지**: 로딩 중에는 항상 스켈레톤 또는 의미 있는 상태 표시. statusLabel 텍스트만으로는 부족.
5. **위계 명확화**: 카드 제목과 부가 정보의 폰트 크기 차이가 최소 8pt 이상.
6. **포커스 차별화**: 동일 그리드 내 시각적으로 다른 의미를 갖는 셀(라이브 vs 오프라인)은 포커스 시에도 다른 단서.
7. **빌드 검증**: 모든 변경 후 `xcodebuild ... BUILD SUCCEEDED` 확인. deprecated 경고 0건 목표.
