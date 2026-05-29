# v3.2 버그 수정 재검증 보고서

## 검증 방법
- 정적 코드 검토: PlayerViewController, MyViewController, SearchViewController 전체 + DesignSystem의 `loadImage` 구현체
- 빌드 상태: BUILD SUCCEEDED (사전 확인)
- 검토 시점: 2026-05-29
- 검토 대상 커밋 상태: working tree (uncommitted)

## 수정 검증 결과

### Fix #1: PlayerViewController retry AVPlayer 누수 [원본 #H1]
- 상태: ✓ 수정 확인
- 검증 근거:
  - `retryTapped()` (line 556-569): `errorContainer` 정리 후 `tearDownAVPlayer()`를 startPlayback 이전에 명시적으로 호출. 모든 상태 변수(`didFallback=false`, `retryCount=0`) 초기화 순서도 적절.
  - `tearDownAVPlayer()` (line 572-583): observer/presentationObserver invalidate→nil, avVC.player pause + replaceCurrentItem(nil), willMove(toParent: nil), view.removeFromSuperview, removeFromParent, avVC=nil 순서로 처리. UIKit 컨테이너 해제 정석 패턴.
  - 옵셔널 체이닝(`avVC?.`) 사용으로 nil-safe.
  - 원본 시나리오 (N회 retry → N개 AVPlayer 누적) 시: 매 retry에서 tearDownAVPlayer가 즉시 이전 인스턴스를 해제 → startPlayback이 새 인스턴스를 생성하므로 동시 살아있는 인스턴스 ≤ 1.
- 추가 우려 (사실상 무시 가능):
  - `pressesBegan` line 601 (`avVC.player?.pause()`)은 implicitly-unwrapped optional 접근. tearDownAVPlayer 직후 startPlayback 호출 전(동기 흐름 사이)에 메뉴 키 입력이 끼어들 가능성은 메인 스레드 동기 실행이므로 0. 이론적 위험만 있음.
  - line 311, 447의 `self.avVC.view.alpha = 1`은 observer 콜백 내부에 있고 observer는 avVC = vc 할당 이후 부착되므로 안전.

### Fix #2: MyLiveBroadcastCell 셀 재사용 시 fallback 잘못 표시 [원본 #H2]
- 상태: ✓ 수정 확인
- 검증 근거:
  - `MyLiveBroadcastCell.currentBJID: String?` 프로퍼티 추가 (line 360).
  - `configure(with:)` 진입 첫 줄에 `currentBJID = f.bjId` 기록 (line 438).
  - fallback closure에 `guard let self = self, !success, self.currentBJID == bjId else { return }` 삼중 가드 (line 462). 셀이 재사용되면 currentBJID가 새 BJ ID로 갱신되므로 옛 BJ의 closure는 가드에서 차단됨.
  - 기저 `loadImage` (DesignSystem.swift:556)는 이미 UUID 토큰으로 stale 콜백을 차단하므로 사실상 이중 방어 구조. 그러나 토큰은 imageView 레벨이고 currentBJID는 cell 레벨이라 서로 직교 — 안전망이 두 겹.
- 원본 시나리오 검증:
  1) 셀 A가 BJ X로 configure → currentBJID=X, liveURL_X 요청
  2) 스크롤로 셀 A 재사용 → currentBJID=Y, liveURL_Y 요청 (UUID 토큰도 갱신)
  3) liveURL_X 실패 콜백 도착 → `self.currentBJID(Y) == bjId(X)` 거짓 → fallback 미발화 → 정상
- 추가 우려: 없음.

### Fix #3: SearchViewController 검색 풀 확장 [원본 #M3]
- 상태: ✓ 수정 확인 (단, 부분 완화)
- 검증 근거:
  - line 121: `for cat in cats.prefix(15)` — 기존 5에서 15로 3배 확장. 주석도 v3.2 의도 명시.
  - 빌드/타입 시그니처 변경 없음.
- 추가 우려:
  - SOOP 카테고리는 500+개로 알려져 있어 prefix(15)도 여전히 ~3% 커버리지. 중하위 카테고리 BJ는 여전히 검색 결과에 안 잡힐 수 있음. 원본 보고서에서 권장한 "검색 API 변경" 또는 "검색 범위 안내" 대안은 미적용.
  - 부하 측면: 15개 카테고리 = 15회 fetchBroadcasts 동시 호출. 기존 5회 대비 부하 3배. 네트워크/메모리 점유 증가하지만 사용자가 명시적으로 검색 탭 진입 시점에만 1회 수행되므로 수용 가능.
  - 결과 0건 시 "상위 N개 카테고리 내 검색" 안내 메시지는 여전히 부재 → 사용자는 검색 실패 원인을 인지하지 못함.

## 잔여 이슈 (Medium/Low 중 미해결)
- **#M1**: RootTabBarController brandLabel z-order — `view.bringSubviewToFront(brandLabel)` 미추가. viewControllers 할당 직후 워드마크 가려질 위험 그대로.
- **#M2**: HomeViewController 스켈레톤 위 reloadData — 미수정.
- **#M3 잔여**: 위 Fix #3 추가 우려 참조 (커버리지 부분 개선만).
- **#M4**: SearchViewController emptyLabel ↔ resultsCollectionView 겹침 — 미수정. 다만 emptyLabel.isHidden 토글이 항상 이루어지므로 시각 깜빡임은 사소함.
- **#M5**: 네트워크 실패 시 사용자 알림 부재 — Home/Search/Explore의 `.failure` 케이스 침묵 그대로.
- **#L1~#L5**: 코드 품질 항목으로 사용성/안정성 영향 없음 (원본 검토에서 이미 안전 확인됨).

## 새로 도입된 버그
- 없음.
- 검증 사항:
  - `tearDownAVPlayer` 호출 후 옵셔널 체이닝으로 일관 접근, 새 startPlayback이 같은 동기 흐름에서 avVC를 재할당하므로 null deref 위험 없음.
  - `currentBJID` 비교는 fallback closure에만 적용 — 다른 셀 동작에 영향 없음. 옵셔널 String 비교는 nil ≠ 어떤 String이므로 첫 호출 시점에도 안전(이미 직전에 할당됨).
  - `cats.prefix(15)`은 `cats.count < 15`여도 Swift Collection이 자동으로 가용 개수만 반환 — out-of-bounds 없음.
  - 빌드 SUCCEEDED 확인됨.

## 최종 판정
- [x] 모든 Critical/High 버그 해결됨 → 배포 가능 (Medium/Low 잔여는 사용성 개선 항목으로 차기 마일스톤 권장)

## 최종 보고 요약
1. Critical/High 버그 모두 수정됐는가? → **YES**
   - #H1 PlayerViewController retry 누수: 완전 해결
   - #H2 MyLiveBroadcastCell 셀 재사용: 완전 해결
2. 새 버그 도입 여부 → **NO**
3. 배포 가능 여부 → **YES** (Critical/High 기준. Medium #M1/#M2/#M3잔여/#M4/#M5는 차기 작업으로 권고)
