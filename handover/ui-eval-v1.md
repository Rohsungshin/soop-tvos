# UI/UX 개선 평가 보고서 v1

> 작성일: 2026-05-29
> 대상: `/Volumes/MacMiniUsb/soop-app`
> 평가 기반: `ui-plan-v1.md`, `ui-design-v1.md`, 실구현 Swift 파일 6종 + `DesignSystem.swift`
> 빌드 결과: BUILD SUCCEEDED (Apple TV 4K (3rd generation) Simulator)

---

## 종합 점수: 74/100

전체적으로 v0 대비 큰 폭의 시각·구조 개선이 확인된다. 다만 기획서에서 명시한 일부 항목(HOME 탭, 스켈레톤, 이미지 캐시, 검색 화면, 최근 시청)이 v2로 미뤄졌고, 또 코드 레벨에서 토큰 미적용/포커스 효과 누락/매직 넘버가 다수 남아 있어 100점 평가는 불가능하다. 실제 사용자가 3m 거리의 Apple TV 화면에서 처음 켰을 때 "꽤 깔끔하지만 어딘가 미완"이라고 느낄 수준이다.

---

### A. 첫인상 / 디자인 일관성: 16/20

**강점**
- `DesignSystem.swift`로 색상/타이포/간격/코너/카드사이즈/포커스를 한 곳에 모았다 (`DesignSystem.swift:9-103`). 토큰 자체의 디자인(다크 #0A0A0C, 카드 #141418, 빨강 #F23C3C, 파랑 #3680FF, 노란 점 #FFC300)은 일관되고 모던하다.
- 모든 ViewController가 `view.backgroundColor = DS.Colors.background`를 적용해 다크 톤이 통일된다 (`LiveCategoriesViewController.swift:24`, `LiveListViewController.swift:30`, `MyViewController.swift:33`, `ExploreViewController.swift:28`, `PlayerViewController.swift:44`).
- 이모지가 헤더에서 제거되었고, "LIVE / 탐색 / MY" 텍스트 탭이 tvOS 네이티브 톤과 맞다.

**약점**
- **토큰을 만들었지만 절반만 적용**된다. 예: `MyViewController.swift:139, 343, 367, 374`는 28pt/22pt 폰트를 `UIFont.systemFont(ofSize:weight:)`로 하드코딩한다 — `DS.Typography`에 `section`(36pt), `cardTitle`(22pt) 등 이미 있는데도 직접 만든다. `nickLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)` (`MyViewController.swift:555`)는 토큰에 없는 18pt를 새로 만든다.
- `PlayerViewController.swift:82, 91, 161, 417, 433, 444`는 32pt / 22pt / 28pt를 하드코딩 — Player 전용이라고 하지만 `DS.Typography` 토큰에서 가장 가까운 값을 재활용해야 일관성이 유지된다.
- 로딩 오버레이의 dim 컬러 `UIColor(white: 0, alpha: 0.55)`가 `LiveListViewController.swift:139`, `ExploreViewController.swift:131`, `MyViewController.swift:201`에 세 번 중복 작성됨. `DS.Colors.overlay`(이미 존재, `DesignSystem.swift:20`)를 쓰지 않았다. 한 번 토큰화한 색을 동일 상황에 안 쓰는 건 일관성 점수 깎임.
- "SOOP 브랜드 톤"이 빨강 LIVE 배지에만 묶여 있고 SOOP 로고/워드마크는 어디에도 없다. 사용자는 "다크한 라이브 스트리밍 앱"으로만 인식할 수 있다.

---

### B. 정보 위계 / 가독성: 15/20

**강점**
- LiveBroadcast 카드: 16:9 썸네일(400x225) + 정보 영역(57pt) 명확히 분리. LIVE 배지(좌상단, 빨강 #F23C3C) + 시청자수 배지(우상단, 검정 반투명)의 보색 대비로 핵심 정보가 즉시 인식된다 (`LiveListViewController.swift:262-309`).
- CategoryCell: 노란 점 + 흰 텍스트로 "● 시청자수 시청 중" 패턴은 SOOP 톤이 잘 살아 있다 (`LiveCategoriesViewController.swift:170-185`).
- `Int.koreanCount()` 헬퍼로 "12345 → 1.2만" 자동 포맷 (`DesignSystem.swift:147-153`). 1080p TV 3m 거리에서 핵심 숫자가 짧게 보인다.

**약점**
- **카드 제목과 BJ 닉네임의 폰트 위계가 약하다**. LiveBroadcastCell에서 제목 22pt semibold (`DS.Typography.cardTitle`)와 BJ 16pt medium (`DS.Typography.caption`)의 차이가 6pt밖에 안 됨. 기획서 3.3에서 "제목 22pt 2줄 + BJ 16pt"는 명시했지만, 실제 3m 거리에서 두 줄이 비슷한 무게로 보일 가능성이 높다. 제목을 26pt(`DS.Typography.cardTitleLarge`)로 키우거나, BJ를 14pt로 줄여 차를 8pt 이상 확보해야 한다.
- **MyLiveBroadcastCell의 제목과 BJ 라벨이 동일 텍스트가 될 가능성**. `MyViewController.swift:468-469`:
  ```swift
  titleLabel.text = f.stationName.isEmpty ? f.nick : f.stationName
  bjLabel.text = f.nick
  ```
  `stationName`이 비어 있으면 두 라벨에 모두 닉네임이 표시되어 같은 글자가 위·아래에 나란히 나온다. 사용자에게 정보 가치 0.
- **LiveBroadcast 셀의 viewerLabel 폰트가 14pt(`DS.Typography.tiny`)** (`LiveListViewController.swift:275`). LIVE 배지(14pt bold)와 동일 크기인데, 3m 거리에서 시청자수가 너무 작게 보일 수 있다. 기획서 3.3은 "14pt `.semibold`"로 명시했으나 안전선은 16pt 이상이 적절.
- CategoryCell의 카테고리명이 1줄 truncating (`LiveCategoriesViewController.swift:164`). 기획서 1.2의 L4("긴 이름 잘림")를 그대로 답습한다. 2줄 허용이 옳다.
- Player의 해상도 라벨 텍스트 " HD\n 1280×720 " 가 가독성 측면에서 단위 표기 없이 곤란 (`PlayerViewController.swift:290`). 사용자에게 720p가 "HD"인지 "HD+"인지 헷갈리는데, 둘 다 라벨에 등장한다.

---

### C. 리모컨 사용성 / 포커스: 13/20

**강점**
- `FocusEffect.apply(to:focused:)` 유틸이 잘 만들어졌다 — 보더 없이 scale 1.06 + 그림자(opacity 0.7, offset y=16, radius 24). 실제 모든 그리드 셀이 같은 패턴(`coordinator.addCoordinatedAnimations` 블록 안에서 호출)을 따라 일관성 확보.
- `collectionView.remembersLastFocusedIndexPath = true`가 모든 컬렉션뷰에 적용됨 — 깊이 진입 후 돌아왔을 때 포커스 복원.
- LiveListViewController의 `preferredFocusEnvironments`가 collectionView를 반환해 진입 시 즉시 카드에 포커스가 떨어진다 (`LiveListViewController.swift:43-45`).

**약점**
- **`MyOfflineBJCell`에 포커스 시 시각적 차별화 부재**. 라이브 카드와 오프라인 카드가 동일한 `FocusEffect.apply` 처리를 받는데, 오프라인 카드는 그림자/scale 효과만 있고 추가 단서가 없다 (`MyViewController.swift:598-604`). 기획서 1.5의 M2("라이브/오프라인 차별화가 약함")가 일부만 해소됨. 포커스 시 "방송이 없습니다" 같은 보조 라벨 표시가 누락.
- **ExploreViewController의 tableView 자체에 포커스 정책 미설정**. tableView는 가로 캐러셀 안에 collectionView를 품고 있어 포커스가 다음과 같이 흐른다: 헤더(포커스 불가) → 검색 셀(포커스) → 인기방송 캐러셀(컬렉션뷰 셀) → 인기카테고리 캐러셀(컬렉션뷰 셀). 그러나 `CarouselRowCell`의 컬렉션뷰가 tableView cell 안에 nested된 구조라, 위→아래 방향 키 입력 시 캐러셀 내 가장 왼쪽 카드로 떨어지는지 모호하다. 코드만으로는 검증 불가하지만, tableView/collectionView nested 환경에서 자주 발생하는 포커스 트랩 위험이 있다.
- **포커스 진입 시 카드 그림자가 contentView 클리핑으로 잘릴 위험**. CategoryCell이 `contentView.layer.masksToBounds = true`, `layer.masksToBounds = false`로 잘 분리되었으나 (`LiveCategoriesViewController.swift:144-149`), 그림자 offset y=16 + radius 24 = 40pt가 흐려진다. 카드 간 lineSpacing이 32pt(`LiveCategoriesViewController.swift:47`)밖에 안 되어, 아래쪽 카드 그림자가 위쪽 카드 영역 위에 살짝 깔리거나 다음 셀에 가려질 수 있다.
- **Pre-roll 화면의 포커스 environment 미설정**. PlayerViewController 진입 시 pre-roll만 보이는데, `errorContainer`의 retry/back 버튼이 나타나기 전엔 포커스 대상이 없다. 사용자가 메뉴 키 외엔 아무 동작도 못 함 — 대안 UX 없음.
- **에러 카드의 retry/back 버튼 사이 간격 24pt**(`PlayerViewController.swift:473-476`). 두 버튼이 화면 중심에서 12pt씩 떨어져 있는데, 포커스 시 scale 1.03이면 충돌할 수 있다. 또한 어느 쪽이 기본 포커스인지 명시되지 않음.
- **LiveListViewController의 헤더 "← 카테고리명"**가 텍스트로만 표시됨 (`LiveListViewController.swift:50`). 메뉴 키로 돌아간다는 단서이지만, 시각적 단서일 뿐 ←를 포커스해 누를 수는 없다 — 발견성↓.

---

### D. 화면별 완성도: 14/20

**강점**
- ExploreViewController가 placeholder에서 벗어났다: 검색 진입 셀 + 인기방송 캐러셀(상위 3개 카테고리 머지) + 인기카테고리 캐러셀의 3섹션 (`ExploreViewController.swift:15-17`). 사용자에게 첫 진입 시 보여줄 콘텐츠가 분명히 있다.
- MyViewController가 라이브/오프라인 2섹션으로 분리되었다 — 헤더 점 색(라이브 빨강 / 오프라인 회색)으로 명확 구분 (`MyViewController.swift:361-379`). 라이브 BJ가 위에 정렬됨.
- PlayerViewController의 pre-roll(블러 썸네일 + 제목 + BJ + 스피너)이 빈 검정 화면 문제를 해결한다 (`PlayerViewController.swift:53-145`).
- 빈 상태(즐겨찾기 0명) — SF Symbol `star.slash` + 안내 + 파란 새로고침 CTA (`MyViewController.swift:124-187`). 기획서 3.5 그대로 구현.

**약점**
- **검색 화면이 placeholder**. 사용자가 검색 셀을 선택해도 `ToastView.show(in: view, message: "검색 기능은 곧 제공됩니다")`로 끝남 (`ExploreViewController.swift:245`). Explore 탭의 핵심인 검색이 사실상 미구현 — 디자인 보고서에서 인정하지만 100점 평가에선 결격.
- **HOME 탭이 신설되지 않음**. 기획서 3.1·4.1에서 "기본 진입 탭"으로 명시했으나 RootTabBarController는 여전히 3탭 (`RootTabBarController.swift:17-22`). 기획서 핵심 신규 기능이 빠짐.
- **최근 시청 섹션이 빈 데이터**. `ExploreViewController.swift:24, 219-229`에서 섹션은 정의됐지만 `recentBroadcasts: []`이 영원히 비어 있어 `numberOfRowsInSection`이 0 반환 → 섹션 자체 안 보임 (`ExploreViewController.swift:189`). 코드는 죽은 코드, UI는 비어 있음.
- **로딩 스켈레톤 미구현**. 기획서 4.2 명시. 데이터 로딩 중 빈 그리드 + 중앙에 "카테고리 불러오는 중..." 텍스트만 나옴 (`LiveCategoriesViewController.swift:35`). 사용자는 여전히 앱이 멈춘 느낌을 받을 가능성.
- **MyLiveBroadcastCell의 라이브 썸네일 fetch 패턴이 매번 실행**. `liveimg.sooplive.com/m/{bjId}?dummy=timestamp`를 매번 fetch (`MyViewController.swift:479`). 캐시 없음 — 즐겨찾기 12명이면 12회 fetch, 화면 진입마다 반복. 사용자 체감 깜빡임.
- **에러 카드의 retry가 처음부터 다시**. `retryTapped`에서 `startPlayback()` 직접 호출 (`PlayerViewController.swift:484-494`). pre-roll spinner를 다시 켜고 시도하지만, 만약 동일 에러가 재현되면 사용자는 같은 카드를 반복 보게 된다 — 무한 루프 방지 없음.
- **Player의 시청자수/방송 시간 오버레이 부재**. 기획서 1.6의 P4("채팅, 방송 정보 부재")가 여전. v2 항목이라 하지만 디자인 완성도 측면에선 감점.

---

### E. 디테일 / 마감: 16/20

**강점**
- **모달 alert → 토스트 전환**이 일관되게 적용. `ToastView.show(in: view, message:)` 호출이 5곳에서 사용됨 (`LiveListViewController.swift:223`, `ExploreViewController.swift:123, 245`, `MyViewController.swift:305, 322`). 화면 끊김 없는 사용자 경험.
- **한국어 라벨이 자연스럽다**. "방송 불러오는 중...", "재생할 수 없습니다", "{n}개 방송 진행 중", "지금 방송 중", "안정 모드". 직역체 없음.
- **빌드 가능**. 최신 `xcodebuild` 결과 BUILD SUCCEEDED 확인 (`xcodebuild ... -destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)"`).
- `Int.koreanCount()` 같은 작은 헬퍼가 코드 중복을 줄임.

**약점**
- **매직 넘버가 여전히 다수**. `DS.Spacing.xs/sm/md/lg/xl/xxl`이 정의됐지만 `contentEdgeInsets = UIEdgeInsets(top: 14, left: 36, bottom: 14, right: 36)`가 두 곳에 직접 작성 (`MyViewController.swift:159`, `PlayerViewController.swift:437, 448`). 14/36은 토큰에 없는 값.
- **`UIColor(white: 0, alpha: 0.55)`가 3곳 중복** (위 A 항목 참조). `DS.Colors.overlay`를 안 씀.
- **`UIFont.systemFont(ofSize: 28, weight: .semibold)`가 4곳 중복** (`MyViewController.swift:139, 343, 367`, `ExploreViewController.swift:331`, `PlayerViewController.swift:417`). `DS.Typography.section`(36pt)과 `cardTitle`(22pt) 사이의 토큰이 없어 직접 만들고 있다 — 28pt 토큰 추가가 누락.
- **이미지 캐싱 미구현** (`grep -n "NSCache\|URLCache" *.swift` 결과 없음). 기획서 4.3 명시. 카드 재사용 시 같은 이미지가 매번 다시 fetch되어 깜빡임.
- **이미지 task cancel 패턴이 살짝 위험**. `imageView.image = nil; imageTask?.cancel(); ... imageTask = URLSession.shared.dataTask(...)` 순서 (`LiveCategoriesViewController.swift:217-225`)인데, 이전 fetch 완료 직전에 새로 dequeue되면 race condition. 큰 문제는 아니지만 동시성 안전성 미흡.
- **MyLiveBroadcastCell의 라이브 썸네일 URL `?dummy=timestamp`** (`MyViewController.swift:479`)가 캐시 무효화 트릭이지만, 결과적으로 매번 다시 다운로드 → 토큰화된 디자인의 일관성과 별개로 자원 낭비.
- `contentEdgeInsets`가 tvOS 15에서 deprecated인데 그대로 사용 (`MyViewController.swift:159`, `PlayerViewController.swift:437, 448`). 빌드 경고로 남음.
- **`headerReferenceSize = CGSize(width: 1920, height: 80)`** 하드코딩 (`MyViewController.swift:62`) — 1920은 1080p에 한정된 매직 넘버, `referenceSizeForHeaderInSection`에서 동적 계산하지만 layout 단계에서 한번 1920을 박아둠.
- **각 화면별 로딩 오버레이 코드가 3곳에 거의 동일하게 복붙**되어 있음 (`LiveListViewController.swift:136-188`, `ExploreViewController.swift:129-174`, `MyViewController.swift:198-249`). DRY 원칙 위배 — `DesignSystem.swift`에 `LoadingOverlay` 컴포넌트로 분리되어야 함.
- **HEAD 줄에 사용된 ←** (`LiveListViewController.swift:50`): "← {카테고리명}" — 진짜 백 화살표 SF Symbol이 아니라 유니코드 문자. 폰트에 따라 표시 차이가 날 수 있다.

---

## 100점이 되기 위한 부족한 점 (구체적 액션 아이템)

### 필수 (90→95점)

1. **HOME 탭 신설** — 기획서 3.1 / 4.1. `HomeViewController` 작성 + `RootTabBarController.swift:17-22`의 viewControllers 배열에 추가. 첫 진입 탭(`selectedIndex = 0`)을 HOME으로. 섹션: 즐겨찾기 라이브 / 최근 시청 / 인기 카테고리 TOP 6.
2. **검색 화면(`SearchViewController`) 실구현** — 기획서 3.4 / 4.7. `SOOPAPIClient`에 `search(query:)` 메서드 추가. 검색 셀(`ExploreViewController.swift:245`)의 토스트 대신 push.
3. **이미지 캐싱(`ImageLoader`) 도입** — 기획서 4.3. `NSCache<NSURL, UIImage>` + `URLCache.shared` 활용. CategoryCell / LiveBroadcastCell / MyLiveBroadcastCell / MyOfflineBJCell의 `URLSession.shared.dataTask`를 일괄 교체.
4. **로딩 스켈레톤** — 기획서 4.2. statusLabel 텍스트 대신 카드 모양 placeholder N개 + shimmer 애니메이션.
5. **최근 시청 기록 저장 + Explore 섹션 실데이터** — `UserDefaults` 기반. PlayerViewController에서 재생 시작 시 broadNo/bjId/title/thumbnail/timestamp 저장. ExploreViewController.recentBroadcasts에 주입.

### 중요 (95→98점)

6. **로딩 오버레이를 `LoadingOverlayView` 공용 컴포넌트로 분리** — 3곳 중복 제거. `DesignSystem.swift`에 추가.
7. **MyLiveBroadcastCell의 `stationName.isEmpty` 시 BJ 이름 중복 표시 버그 수정** — 라이브 방송 제목을 알 수 없을 땐 `bjLabel`만 표시하고 `titleLabel`은 `isHidden = true`.
8. **카테고리명 1줄 truncating → 2줄 허용** — `LiveCategoriesViewController.swift:164`의 `numberOfLines = 1`을 2로. "리그 오브 레전드" 등 긴 이름 잘림 해결.
9. **타이포 토큰에 28pt `.semibold` 추가** — 코드 4곳 중복(`MyViewController.swift:139, 343`, `ExploreViewController.swift:331`, `PlayerViewController.swift:417`)을 `DS.Typography.subsection`(가칭)으로 일괄 치환.
10. **dim 오버레이 컬러를 `DS.Colors.overlay`로 치환** — `LiveListViewController.swift:139`, `ExploreViewController.swift:131`, `MyViewController.swift:201`.
11. **`contentEdgeInsets` → `UIButton.Configuration`로 마이그레이션** — `MyViewController.swift:159`, `PlayerViewController.swift:437, 448`. deprecated 경고 제거.
12. **에러 카드의 retry 카운트 제한** — 3회 이상 실패 시 "잠시 후 다시 시도하세요" 안내 + 자동 dismiss. 무한 루프 방지.

### 디테일 (98→100점)

13. **MyOfflineBJCell 포커스 시 시각 단서 추가** — 포커스 시 카드 위에 "OFFLINE — 알림 받기" 같은 액션 hint를 띄우거나, 포커스 색을 회색 계열로 차별화.
14. **시청자수 배지 폰트 14pt → 16pt** — 3m 거리 가독성 확보.
15. **LiveBroadcast 카드의 제목/BJ 폰트 위계 강화** — 제목 26pt(`cardTitleLarge`) + BJ 14pt(`tiny`) 조합으로 12pt 차이 확보.
16. **Player 해상도 라벨의 "HD" 표기 모호성 해결** — "540p", "720p", "1080p"처럼 픽셀 높이만 표시. 또는 "HD 540p" 명시.
17. **SOOP 로고/워드마크를 RootTabBar 좌측에 작게 표시** — 첫 진입 시 브랜드 인지.
18. **`headerReferenceSize` 1920 하드코딩 제거** — `viewDidLayoutSubviews`에서 동적 갱신.
19. **Explore에 빈 데이터 fallback** — `loadData` 실패 시 토스트 또는 빈 상태 UI.
20. **30초 시청자수 자동 갱신** — 기획서 4.5. `Timer`로 화면 표시 중인 셀의 viewerCount만 patch.

---

## 100점 달성 여부: NO

**총점 74/100**

100점이 되려면 위 액션 아이템 20개 중 최소 1~12번(필수+중요)이 모두 처리되어야 한다. 현재 코드는 v1 기획서의 디자인 시스템·시각 토대를 잘 잡았지만, 기획서가 명시한 **신규 화면(HOME, 검색)·인프라(이미지 캐시, 스켈레톤)·데이터 흐름(최근 시청)**의 절반 이상이 v2로 미뤄졌다. 또한 만들어진 디자인 토큰이 코드 곳곳에서 안 쓰이거나(28pt, dim 컬러), 매직 넘버가 새로 생겨났다(14/36/1920).

특히 사용자 입장에서 가장 크게 느낄 결격 사유는:
1. **Explore의 검색을 누르면 토스트만 뜨고 끝남** — 핵심 가치 미실현
2. **앱 첫 진입 시 LIVE 카테고리 그리드만 보임** — HOME 탭 부재
3. **카드 그리드 로딩 중 빈 화면** — 스켈레톤 부재로 체감 성능 저하

이 3가지가 처리되면 90점대로 도약 가능하다.
