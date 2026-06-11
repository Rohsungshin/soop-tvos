# SOOP tvOS 앱 오류·빈 상태 UX 개선 검수 보고서

- **문서 버전**: v1.0
- **검수일**: 2026-06-11
- **대상**: git 작업 트리 미커밋 변경분 (DesignSystem / Explore / Home / My / RootTabBar / Search ViewController)
- **기준 문서**: consulting-v1.0 §4 배점표, plan-v1.0, design-v1.0
- **검수자**: 검수 에이전트

---

## 1. 점수표

| 체크 포인트 | 배점 | 획득 | 판정 |
|------------|------|------|------|
| C1. 홈/탐색 오류 상태 + 재시도 (I-1) | 25 | 25 | 합격 |
| C2. 검색 데드락 해소 (I-2) | 15 | 15 | 합격 |
| C3. MY 탭 메시지 친화화 + 재시도 (I-3) | 15 | 15 | 합격 |
| C4. 워드마크 z-order (I-4) | 5 | 5 | 합격 |
| C5. 스켈레톤 타이밍 (I-5) | 10 | 10 | 합격 |
| C6. 검색 범위 안내 (I-6) | 5 | 5 | 합격 |
| C7. emptyLabel 겹침 방지 (I-7) | 5 | 3 | 감점 |
| C8. 빌드 성공 | 10 | 10 | 합격 |
| C9. 디자인 시스템 일관성 | 5 | 5 | 합격 |
| C10. Surgical change 원칙 | 5 | 5 | 합격 |
| **총점** | **100** | **98** | **불합격(미달)** |

---

## 2. 항목별 검증 근거

### C1. 홈/탐색 오류 상태 + 재시도 (25/25)

- **공용 오류 뷰**: `DesignSystem.swift:569-676` `ErrorStateView` 신설. 아이콘(`wifi.exclamationmark`) + 타이틀 + (옵션)서브타이틀 + 포커스 가능한 "다시 시도" 버튼.
- **확정 문구 글자 단위 대조**: 홈/탐색 모두 `"콘텐츠를 불러오지 못했습니다"` (`HomeViewController.swift:151`, `ExploreViewController.swift:100`) — plan §1-4 / design §1-4 표와 정확히 일치. 버튼 문구 `"다시 시도"` (`DesignSystem.swift:588`) 일치.
- **포커스 가능**: `ErrorRetryButton.canBecomeFocused = true` (`DesignSystem.swift:666`), `ErrorStateView.preferredFocusEnvironments → [retryButton]` (`:655`), VC가 다시 `preferredFocusEnvironments`에서 errorView 반환(`HomeViewController.swift:177-180`, `ExploreViewController.swift:122-125`). 표시 직후 `setNeedsFocusUpdate()+updateFocusIfNeeded()` 호출(`HomeViewController.swift:166-167`, `Explore:112-113`). 포커스 체인 정상.
- **포커스 효과**: `FocusEffect.applyBorder` (`DesignSystem.swift:673`) — design §1-6 명세대로.
- **성공 복구**: 재시도 → `hideErrorState()` → 홈은 `showSkeleton()` 후 `loadData()`(`Home:152-157`), 탐색은 `loadData()`(`Explore:101-105`). `.success` 분기에서 `hideErrorState()` 호출(`Home:112`, `Explore:81`)로 정상 복구.
- **부분 실패 처리**: 카테고리 성공·인기 라이브 전부 실패 시 오류 뷰 미표시(`loadPopularLive`는 오류 뷰를 띄우지 않음) — plan §1-5 엣지 케이스 준수.
- **재시도 연타**: `retryTapped`에서 `retryButton.isEnabled = false`(`DesignSystem.swift:659`) 후 뷰 자체가 제거/재생성되므로 중복 트리거 차단. plan §1-5 준수.
- **메모리/스레드**: 모든 클로저 `[weak self]`, 응답은 `DispatchQueue.main.async` 내부 처리. 탭 전환 중 응답도 `guard let self` 패턴 유지.
- **홈 콘텐츠 가림 방지**: 오류 시 `tableView.isHidden = true`(`Home:165`), 해제 시 복구(`:173`). 적절.

### C2. 검색 데드락 해소 (15/15)

- **상태 변수 신설**: `hasLoadFailed`, `isReloading`, `pendingQuery` (`SearchViewController.swift:74-78`).
- **실패 기록**: `loadAllBroadcasts` guard 탈락 시 `hasLoadFailed = true`(`:165-169`). 무동작으로 끝나던 기존 데드락 제거.
- **자동 재로드 경로**: `runSearch`에서 `!hasLoadedAll` 시 `isReloading`/`hasLoadFailed` 3분기(`:252-266`) — 재로드 진행 중 / 실패 후 자동 재시도 / 초기 로딩 중. plan §2-2, §2-3 상태 전이와 일치.
- **재시도 성공 이어서 검색**: `group.notify`에서 `isReloading`이면 `pendingQuery`로 `runSearch` 재실행(`:189-195`).
- **reloadPool 초기화**: `hasLoadedAll/hasLoadFailed/isReloading` 모두 리셋(`:154-159`) — plan §2-5 준수.
- **확정 문구**: "검색 데이터를 다시 불러옵니다"(`:261`), "데이터를 다시 불러오고 있습니다"(`:256`), "데이터 준비 중입니다. 잠시 후 다시 시도해 주세요"(`:264`) — plan §2-4와 정확히 일치.
- **무한 루프 위험 없음**: 사용자 능동 검색이 트리거. 정상.

### C3. MY 탭 메시지 친화화 + 재시도 (15/15)

- **개발자 용어 제거**: 기존 `"로드 실패: \(err) ... .env의 SOOP_ID/PASSWORD 확인"` 완전 제거. `showErrorState(for:)`로 교체(`MyViewController.swift:127-128`). 노출 문구에 `err`/`.env`/`SOOP_ID` 등 0건.
- **에러 유형 분기 (I-3 대체구현 판정)**: `SOOPAPIError`에 `loginRequired` 케이스가 실제로 없음(`SOOPAPIClient.swift:51-58`에 `invalidURL/invalidResponse/decodingFailed/streamUnavailable/notLive/adultVerificationRequired`만 존재). 코딩 에이전트가 `AuthTicket` 쿠키 유무로 인증/네트워크를 구분한 것(`MyViewController.swift:218`)은 **타당한 합리적 대체구현**. 로그인 상태면 네트워크/서버 오류 문구, 미로그인이면 인증 오류 문구로 사용자에게 더 정확한 안내가 가능. 감점 없음.
- **확정 문구**: 인증 오류 "로그인 정보를 확인할 수 없습니다" / "SOOP 계정으로 로그인되어 있는지 확인해 주세요"(`:229-230`), 네트워크 "즐겨찾기를 불러오지 못했습니다" / "인터넷 연결을 확인하고 다시 시도해 주세요"(`:223-224`) — plan §3-5, design §1-4/§1-5와 정확히 일치.
- **아이콘**: 인증 `person.crop.circle.badge.exclamationmark`, 네트워크 `wifi.exclamationmark` — design §1-1 표 일치.
- **재시도**: `onRetry → loadFavorites()`(`:233`). `loadFavorites` 진입 시 `hideErrorState()`(`:108`), statusLabel 복구. 상태 전이 plan §3-4 준수.

### C4. 워드마크 z-order (5/5)

- `addBrandWordmark`에서 `addSubview` 직후 `bringSubviewToFront(brandLabel)`(`RootTabBarController.swift:103`).
- **I-4 대체/보강 판정**: 추가로 `viewDidLayoutSubviews`에서 재호출(`:53-57`). UITabBarController 콘텐츠 뷰(자식 NavigationController view)가 viewDidLoad 이후 늦게 붙는 특성을 고려한 **타당한 보강**. tvOS에서 탭 콘텐츠가 z-order상 워드마크를 덮는 실제 위험을 막음. 매 레이아웃마다 1회 `bringSubviewToFront` 호출은 비용 미미. 감점 없음.

### C5. 스켈레톤 타이밍 (10/10)

- **timeout 폴백 제거**: `showSkeleton`의 `asyncAfter(1.5)` 블록 삭제(diff 확인). plan §5-2 준수.
- **즉시 해제**: `.success`/`.failure` 양쪽 분기 초입에서 `hideSkeleton()`(`HomeViewController.swift:111, 118`).
- **group.notify 중복 제거**: `loadPopularLive` notify에서 `hideSkeleton()` 호출 제거(`:140-144`). 고아 스켈레톤 없음.
- `hideSkeleton`은 `skeletonView = nil` 처리로 중복 호출 안전(`:99-102`).

### C6. 검색 범위 안내 (5/5)

- 0건 시 `emptyLabel.attributedText = noResultsText(query)`(`SearchViewController.swift:273`). 1줄 "{검색어}에 대한 결과가 없습니다", 2줄 "인기 카테고리 상위 15개의 라이브 방송에서 검색한 결과입니다"(`:282-298`) — plan §6-4 / design §2-1과 정확히 일치.
- 폰트/색상: 1줄 `subsection`/`textSecondary`, 2줄 `body`/`textTertiary`(`:286-294`) — design §2-1 일치.
- `emptyLabel.numberOfLines = 0`(`:122`) 설정됨.

### C7. emptyLabel 겹침 방지 (3/5) — 감점

- `setEmptyStateVisible(_:)` 헬퍼로 두 `isHidden`을 항상 반대값으로 동시 설정(`:148-151`). `runSearch`/`updateSearchResults`/초기화 경로 모두 헬퍼 경유. 배타 표시 로직 자체는 design §2-3 준수.
- **감점 사유 (실사용 결함)**: `runSearch`의 자동 재로드/대기 분기(`:252-266`)는 토스트만 띄우고 **`return`하면서 `setEmptyStateVisible`을 호출하지 않는다.** 직전 화면 상태가 그대로 남는다. 시나리오:
  1. 검색 결과가 떠 있는 상태(resultsCollectionView 표시, emptyLabel 숨김)에서
  2. `reloadPool`(Play/Pause) 등으로 `hasLoadedAll=false`가 되거나 풀 로드가 실패한 뒤
  3. 사용자가 새 검색어를 입력하면 → 재로드/대기 분기로 빠지며 `return` → **이전 검색 결과 그리드(resultsCollectionView)가 그대로 노출된 채** "데이터를 다시 불러옵니다" 토스트만 뜬다. 입력한 검색어와 무관한 옛 결과가 화면에 남아 사용자가 혼란.
  - design §2-3 "모든 상태 전이에서 두 뷰 isHidden이 항상 반대"라는 규칙을 재로드 대기 상태에서 위반.

### C8. 빌드 성공 (10/10)

- tvOS 시뮬레이터(Apple TV 4K 3rd gen) Debug 빌드 `** BUILD SUCCEEDED **` 확인. 경고로 인한 실패 없음.

### C9. 디자인 시스템 일관성 (5/5)

- `ErrorStateView` 전 속성 DS 토큰 사용: `DS.Colors.primary/textPrimary/textSecondary/textTertiary`, `DS.Typography.cardTitle/subsection/body`, `DS.ButtonInsets.cta`, `DS.Corner.button`, `DS.Spacing.md/lg`(`DesignSystem.swift:583-648`).
- 토큰 없는 3개 수치(`errorIconSize=80`, `errorContainerMaxWidth=720`, `errorTitleSubtitleGap=8`)는 design §4-4가 명시 허용한 로컬 상수로 처리(`:577-579`). 예외 범위 내.
- 검색 안내 문구 색/폰트도 DS 토큰 사용(`SearchViewController.swift:286-294`). 하드코딩 매직 넘버/직접 UIColor 호출 없음.

### C10. Surgical change 원칙 (5/5)

- 변경 6개 파일 모두 I-1~I-7 범위 내. 범위 밖 코드 무변경.
- 고아 코드 없음: 제거된 `asyncAfter` timeout 블록은 I-5 요구. `hideSkeleton` 중복 호출 제거도 I-5 연계.
- 불필요 리팩터링/주석 정리 없음. 추가 주석은 모두 변경 의도 설명용.

---

## 3. 감점 항목 수정 지시

### C7 (3→5점 회복): 재로드/대기 분기에서도 화면 상태 동기화

`soop-app/SearchViewController.swift`의 `runSearch(_:)` 내 `if !hasLoadedAll { ... }` 블록(현재 252-267행)에서 각 분기 토스트 표시와 함께 빈 상태를 표시하고, `filtered`를 비워 옛 결과 그리드가 남지 않게 한다. 아래처럼 수정:

```swift
if !hasLoadedAll {
    // 아직 검색 가능한 풀이 없으므로 이전 결과 그리드를 숨기고 안내만 노출
    filtered = []
    resultsCollectionView.reloadData()
    emptyLabel.text = "검색 데이터를 준비하고 있습니다"   // 또는 기존 안내 문구 재사용
    setEmptyStateVisible(true)

    if isReloading {
        pendingQuery = query
        ToastView.show(in: view, message: "데이터를 다시 불러오고 있습니다", duration: 2.0)
    } else if hasLoadFailed {
        pendingQuery = query
        isReloading = true
        ToastView.show(in: view, message: "검색 데이터를 다시 불러옵니다", duration: 2.0)
        loadAllBroadcasts()
    } else {
        ToastView.show(in: view, message: "데이터 준비 중입니다. 잠시 후 다시 시도해 주세요", duration: 2.0)
    }
    return
}
```

- 핵심: `return` 전에 반드시 `setEmptyStateVisible(true)` + `filtered = []` + `reloadData()`로 옛 결과 그리드를 제거할 것.
- `emptyLabel`에 안내 문구를 넣을지 기존 "검색어를 입력해 보세요"를 유지할지는 재량이나, 최소한 resultsCollectionView가 숨겨져야 한다.
- 수정 후 재빌드(`** BUILD SUCCEEDED **`) 및 "결과 표시 → 풀 리셋/실패 → 새 검색어 입력 시 옛 그리드 미노출" 시나리오 확인.

---

## 4. 결론

- **총점: 98 / 100**
- **합격 여부: 불합격(100점 미달)** — C7 1개 항목 감점.
- C7 수정 지시 1건 반영 후 재검수 시 100점 도달 예상. 그 외 C1~C6, C8~C10은 기획·디자인 명세를 정확히 충족하며, I-3/I-4 대체구현은 모두 타당하여 감점 사유 아님.
