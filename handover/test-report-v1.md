# v3.1 버그 검토 보고서

## 검토 요약
- 검토 파일: 9개 (DesignSystem, RootTabBar, Home, Search, Explore, LiveCategories, LiveList, My, Player + AppDelegate/SOOPAPIClient 참고)
- 발견된 버그: 12개 (Critical: 0, High: 2, Medium: 5, Low: 5)
- 검토 방식: 코드 정적 분석 + 런타임 시나리오 시뮬레이션 (셀 재사용, retry, 비동기 콜백 순서, 포커스, 메모리 누수)

## Critical (즉시 크래시 가능)
없음. 빌드 통과, force unwrap 위험한 IBOutlet 없음, 모든 `as!` 캐스트는 등록된 셀에 대해 안전, 배열 인덱스는 dataSource 카운트 기반.

## High (오작동/데이터 손실)

### Bug #H1: PlayerViewController retry 시 AVPlayerViewController 누적 (메모리 누수 + 다중 재생)
- 파일: /Volumes/MacMiniUsb/soop-app/soop-app/PlayerViewController.swift:556-567 (`retryTapped`) → 248 (`startPlayback`)
- 현상: `retryTapped`가 `startPlayback()`을 다시 호출하면 line 283에서 새 `AVPlayerViewController vc = AVPlayerViewController()`를 만들어 `addChild(vc)` + `view.insertSubview(vc.view, ...)` 후 `avVC = vc`로 덮어쓴다. **이전 `avVC`는 그 자리에 남고 player가 살아있다.** 두 개의 AVPlayer가 동시에 살아있으며, 한쪽이 보이지 않아도 디코딩/네트워크 자원을 점유한다. retry를 N번 누르면 N개의 AVPlayer가 동시에 존재.
- 재현 시나리오:
  1) 재생 실패하여 에러카드 노출
  2) "다시 시도" 버튼 누름 → 새 AVPlayer 생성 (이전 것은 free되지 않음)
  3) 또 실패 → 또 "다시 시도" → 누적
  4) 한 채널에서 음성이 두 번 나거나 메모리 압박
- 수정 방향: `retryTapped()` 첫 줄에서 기존 child VC 정리:
  ```swift
  avVC?.player?.replaceCurrentItem(with: nil)
  avVC?.willMove(toParent: nil)
  avVC?.view.removeFromSuperview()
  avVC?.removeFromParent()
  avVC = nil
  observer?.invalidate(); observer = nil
  presentationObserver?.invalidate(); presentationObserver = nil
  ```

### Bug #H2: MyLiveBroadcastCell 썸네일 fallback이 셀 재사용 시 잘못된 BJ 이미지로 덮어씀
- 파일: /Volumes/MacMiniUsb/soop-app/soop-app/MyViewController.swift:453-462 (`MyLiveBroadcastCell.configure`)
- 현상: `imageView.loadImage(from: liveURL) { [weak self] success in ... self.imageView.loadImage(from: fallback) }` — 외부 콜백에는 토큰 가드가 있지만, **콜백이 도착할 시점에 셀이 다른 BJ로 재사용**됐다면 closure가 캡처한 `bjId`는 옛 BJ의 것이라 `fallback` URL도 옛 BJ의 프로필이 로드된다. 그 시점 `self.imageView.loadImage(from: fallback)`는 토큰을 새로 할당하여 **방금 적용된 새 BJ의 라이브 이미지를 nil로 wipe**하고 옛 BJ 프로필을 깔게 된다.
- 재현 시나리오:
  1) 즐겨찾기 라이브 BJ 30명 빠르게 스크롤
  2) 셀 A가 BJ X로 표시되면서 liveURL_X 시작
  3) 스크롤 후 셀 A 재사용 → BJ Y, liveURL_Y 시작 → imageView가 Y의 이미지를 표시
  4) 그러나 직후 liveURL_X 응답이 실패로 도착 → closure가 fallback_X 로드 시작 → imageView.image = nil + Y 이미지 token 무효화
  5) Y 이미지 자리에 X의 프로필이 표시되는 시각적 깜빡임 / 잘못된 표시
- 수정 방향:
  - configure 시작 시 토큰을 저장하고 fallback 직전에 검증
  - 또는 외부 콜백에서 `guard self.imageView.currentLoadToken == originalToken else { return }` 확인
  - 가장 단순한 방법: configure 진입 시 캡처한 `bjId`와 현재 cell의 `bjId`(별도 property로 저장)를 비교

## Medium (사용성 저하)

### Bug #M1: RootTabBarController brandLabel 표시 순서 문제 (TV 좌상단 SOOP 워드마크가 안 보일 수 있음)
- 파일: /Volumes/MacMiniUsb/soop-app/soop-app/RootTabBarController.swift:13-51 (`viewDidLoad`)
- 현상: `addBrandWordmark()`로 `view.addSubview(brandLabel)` 후 `viewControllers = [...]`이 실행되면, UIKit이 selected child VC의 view를 tab controller view에 삽입한다. 일반적으로 **child VC view가 brandLabel보다 위 z-order에 올라간다** → brandLabel이 가려진다. 탭바 아래쪽이라 child VC가 안 닿을 수도 있지만 contentView/safeArea 처리에 따라 보이지 않을 수 있음.
- 재현 시나리오: HOME 탭에서 좌상단 "SOOP" 워드마크 확인. 자식 VC의 `view.backgroundColor = DS.Colors.background`로 깔려 있다면 brandLabel이 그 아래 묻혀 안 보일 수 있음.
- 수정 방향: `viewControllers = [...]` 다음 줄에 `view.bringSubviewToFront(brandLabel)` 또는 `viewDidLayoutSubviews`에서 매번 bringSubviewToFront.

### Bug #M2: HomeViewController 즐겨찾기 도착 시 스켈레톤 위 reloadData (시각 불일치)
- 파일: /Volumes/MacMiniUsb/soop-app/soop-app/HomeViewController.swift:91-103, 127-137
- 현상: `loadData()`는 fetchCategories → fetchPopularLive(group.notify에서 hideSkeleton + reloadData) 흐름이지만, 동시에 `loadFavorites`/`loadRecent`도 즉시 시작되어 응답 도착 시 `tableView.reloadData()`를 호출한다. fetchFavorites가 fetchPopularLive보다 먼저 끝나면 **스켈레톤이 여전히 화면을 덮고 있는데 그 아래에서 reloadData가 일어남** → 사용자에게 보이지 않지만, 1.5초 timeout 직후 갑자기 4개 섹션 일부만 채워진 어색한 상태가 노출될 수 있음.
- 재현 시나리오: 네트워크가 느린 환경에서 fetchCategories는 1.4초, fetchFavorites는 0.3초에 도착. 스켈레톤이 1.5초에 사라지고 즐겨찾기만 보이는 잠깐의 상태.
- 수정 방향: 스켈레톤 보이는 동안 reloadData를 미루거나, 데이터 도착 후 hideSkeleton과 동시에 reloadData.

### Bug #M3: SearchViewController는 상위 5개 카테고리에서만 검색 (대다수 BJ는 검색 결과에 안 잡힘)
- 파일: /Volumes/MacMiniUsb/soop-app/soop-app/SearchViewController.swift:112-135 (`loadAllBroadcasts`)
- 현상: `for cat in cats.prefix(5)` — SOOP 카테고리는 500+개인데 상위 5개만 머지함. 사용자가 LoL/스타크래프트/배그 외 카테고리 BJ를 검색하면 "결과 없음"으로 표시되는데, **실제로는 SOOP에 라이브 중**. 사용자는 검색이 망가졌다고 오해할 수 있음.
- 재현 시나리오: 11번째로 인기있는 카테고리의 BJ 닉네임을 검색 → 결과 없음.
- 수정 방향: 더 많은 카테고리(예: 30개) 머지, 또는 SOOP에 검색 API가 있다면 그 API로 변경. 빈 결과 시 "상위 5개 카테고리 범위 내에서 검색 중"을 사용자에게 안내.

### Bug #M4: SearchViewController 빈 검색 결과 화면이 가려질 수 있음 (레이아웃 겹침)
- 파일: /Volumes/MacMiniUsb/soop-app/soop-app/SearchViewController.swift:103-107
- 현상: `emptyLabel`이 `view.centerXAnchor / centerYAnchor`로 중앙에 배치되는데, `resultsCollectionView`도 같은 영역을 덮고 있다. `emptyLabel.isHidden = false` 시 collectionView 위에 있긴 하지만 (addSubview 순서) — 만약 후속 reloadData로 collectionView가 깜빡이면 사용자에게 잠깐 겹침이 보일 수 있음. `emptyLabel` 보이는 동안 `resultsCollectionView.isHidden = true`로 분기하는 게 안전.
- 재현 시나리오: 검색어 입력 → "결과 없음" 표시 후 다른 검색어 입력 → 잠깐 두 UI 겹침.
- 수정 방향: `emptyLabel.isHidden`와 `resultsCollectionView.isHidden`을 동시에 토글.

### Bug #M5: HomeViewController/SearchViewController/ExploreViewController에서 fetchCategories/fetchBroadcasts 실패 시 침묵
- 파일: 각 VC의 `loadData()` / `loadAllBroadcasts()` / `loadPopularLive()`
- 현상: `if case .success(let cats) = result` 패턴만 처리하고 `.failure`는 무시. 사용자에게 "로드 실패" 신호가 전혀 없음 → 빈 화면을 보고 "앱이 망가졌다"고 인식할 가능성.
- 재현 시나리오: 네트워크 끊긴 상태로 앱 실행 → HOME 탭은 1.5초 스켈레톤 후 완전히 빈 화면.
- 수정 방향: `.failure` 케이스에서 toast 또는 statusLabel로 사용자 알림. LiveCategoriesViewController는 이미 처리하고 있으므로 그 패턴 따르기.

## Low (코드 품질)

### Bug #L1: HomeViewController 스켈레톤 1.5초 timeout이 데이터 도착보다 늦으면 "유령" 호출
- 파일: HomeViewController.swift:81-84
- 현상: `loadPopularLive`의 group.notify에서 이미 `hideSkeleton`을 호출했고 timeout이 그 후 발화하면 `skeletonView?` 가 nil이라 no-op이다. 안전하지만 의미상 불필요한 호출. Low로 분류.

### Bug #L2: RecentWatchStore thumbnailURL 직렬화 — 즐겨찾기에서 시청 시 thumbnailURL을 nil로 저장
- 파일: HomeViewController.swift:181-189, MyViewController.swift:279-283
- 현상: `didSelectFavorite`/`playLive`에서 LiveBroadcast를 만들 때 `thumbnailURL: nil`을 넣음. 그 결과 "최근 시청" 캐러셀에서 해당 항목은 썸네일 없이 placeholder 색만 표시됨. 영구적 UX 손실은 아니지만 일관성 부족.
- 수정 방향: 즐겨찾기 BJ의 라이브 이미지 URL (`https://liveimg.sooplive.com/m/\(bjId)?bucket=...`)을 RecentWatchStore에 함께 저장.

### Bug #L3: MyLiveBroadcastCell 닉네임 중복 fix가 stationName이 nil이 아닌 빈 문자열일 때만 동작
- 파일: MyViewController.swift:436-445
- 현상: `let hasStation = !f.stationName.isEmpty && f.stationName != f.nick` — SOOP API가 stationName에 whitespace나 "BJ 닉네임 " 같은 trailing space를 넣으면 비교가 어긋남. 실제 API 응답이 무결하면 OK.
- 수정 방향: `f.stationName.trimmingCharacters(in: .whitespacesAndNewlines)` 으로 비교 안정성 향상.

### Bug #L4: PlayerViewController hideMetaTimer / hideResolutionTimer 동시 invalidate 누락 가능성 (사실상 안전)
- 파일: PlayerViewController.swift:574-580
- 현상: `deinit`에서 `hideResolutionTimer?.invalidate()`, `hideMetaTimer?.invalidate()`를 호출. 그러나 `showResolutionLabelTemporarily`/`showTopMetaTemporarily`가 호출될 때마다 이전 timer를 invalidate하므로 누적은 없음. 정상 동작.
- 비고: retry 시에는 timer가 살아있는 채로 startPlayback → 새 KVO observer가 또 showResolutionLabelTemporarily 호출 → 새 timer 할당, 옛 timer는 invalidate. 정상.

### Bug #L5: ExploreViewController "recent" 섹션은 항상 비어 있는데 카테고리 카드 셀의 dataSource는 조건 분기에 양쪽이 있음 (cosmetic)
- 파일: ExploreViewController.swift:336-360
- 현상: `CarouselRowCell.collectionView` dataSource가 `broadcasts.isEmpty ? categories : broadcasts` 분기를 한다. recentBroadcasts.isEmpty면 섹션이 표시되지 않으므로 (`numberOfRowsInSection`이 0 반환) 문제 없으나, 가독성을 위해 enum-based section types로 명시하면 더 좋음.

## 안전 확인 (버그 아님)

- **Force unwrap**: 모든 IBOutlet은 lazy initializer 또는 viewDidLoad의 setupUI()에서 할당 후 사용. 강제 언래핑 없음.
- **`as!` 캐스트**: 모두 등록된 셀 클래스에 대한 dequeue 결과. 안전.
- **weak self**: 모든 비동기 콜백(URLSession completion, DispatchQueue.main.async, Timer, NotificationCenter selector)에 적절히 적용.
- **메모리 누수**:
  - Timer: 모두 invalidate가 보장됨 (이전 timer 교체 시 invalidate, deinit에 정리)
  - KVO Observer (`NSKeyValueObservation`): 재할당 시 자동 invalidate + deinit에서 명시적 invalidate
  - NotificationCenter selector observer: iOS 9+에서 자동 제거됨
  - URLSession dataTask: 토큰 무효화로 stale 응답 무시
- **메인 스레드 위반**: 모든 UI 업데이트는 `DispatchQueue.main.async` 안에서 실행.
- **셀 재사용**:
  - `LiveBroadcastCell.configure`, `CategoryCell.configure`, `MyOfflineBJCell.configure`은 모든 라벨/이미지를 재설정 → stale data 없음
  - `MyLiveBroadcastCell` 단독 예외 (Bug #H2 참고)
- **pressesBegan에서 super 호출**: LiveCategories/LiveList/Player 모두 적절히 super 호출 (PlayPause 처리 시 return 후 super 안 부르는 건 의도된 동작)
- **remembersLastFocusedIndexPath**: 모든 grid/carousel collectionView에 true 설정
- **AVPlayer 자원 해제**: deinit에서 `player.pause()` (다만 #H1처럼 retry 케이스에서는 누수)
- **`fetchStreamInfo` 호출 패턴**: 새로 추가된 화면(Home/Search)도 기존과 동일한 시그니처 사용. 비즈니스 로직 침해 없음.
- **데이터 모델**: LiveBroadcast / FavoriteBJ / SOOPCategory / StreamInfo 변경 없음 — UI 레이어가 기존 모델만 소비.
- **네비게이션 흐름**: 카테고리 → LiveList → Player 흐름 유지. Home/Search도 동일 PlayerViewController 사용. 침해 없음.
- **NSCache (ImageCache)**: 동시 접근 안전 (NSCache 자체가 thread-safe). 토큰 race는 main thread 일원화로 회피.
- **LoadingOverlayView 중첩**: `LiveListViewController.showLoadingOverlay`/`MyViewController.showLoadingOverlay`은 호출 시 `hideLoadingOverlay()`로 이전 것을 정리. HomeVC/SearchVC/ExploreVC는 local 변수 `overlay`만 사용하므로 중첩 위험 없음.
- **contentEdgeInsets deprecated → UIButton.Configuration**: MyViewController(refreshBtn), PlayerViewController(retryBtn/backBtn) 모두 `UIButton.Configuration` 채택. 정상.
- **매직 넘버 토큰화**: DS.Spacing/DS.CardSize/DS.Layout/DS.ButtonInsets 활용. 일부 inline 값(LiveCategories의 sectionInset top=32, LiveList의 카드 imageView 높이 225 등)이 남아있지만 거의 토큰 또는 명시적 값으로 정리됨.
