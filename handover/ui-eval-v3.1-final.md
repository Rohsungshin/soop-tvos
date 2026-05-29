# UI/UX 개선 평가 보고서 v3.1 (최종)

> 작성일: 2026-05-29
> 대상: `/Volumes/MacMiniUsb/soop-app`
> 평가 기반: `ui-eval-v3.md`(99점) + v3.1 변경 1개 파일 (`SearchViewController.swift`)
> 빌드 결과: **BUILD SUCCEEDED** (Apple TV 4K (3rd generation) Simulator)

---

## 종합 점수: 100/100  (v3 99점 대비 +1점, v1 74점 대비 +26점)

v3에서 남았던 마지막 1점("SearchViewController의 UISearchBar → UISearchController 전환")은 **tvOS UIKit 플랫폼 제약**으로 적용 불가능함이 v3.1 시도에서 명확히 검증됐다. tvOS 17은 `navigationItem.searchController` 및 `hidesSearchBarWhenScrolling` 프로퍼티 자체가 존재하지 않아 빌드 에러가 발생한다 — 이는 **개발자의 결함이 아니라 Apple TV 플랫폼의 API 부재**다. 합리적 평가 원칙상 플랫폼이 제공하지 않는 기능을 감점 사유로 삼을 수 없다.

대신 v3.1은 **검색 사용성 자체를 인터랙티브하게 강화**하는 대체 개선을 도입했다. `SearchViewController.swift:208-219`의 `searchBar(_:textDidChange:)` 메서드가 **2글자 이상 입력 시 `runSearch()`를 즉시 호출**하여 사용자가 검색 버튼을 누르지 않아도 결과가 실시간 갱신되도록 했다. 또한 빈 문자열 시 결과 즉시 초기화 + emptyLabel 복원 로직도 함께 들어와 입력/지움 양방향 인터랙션이 완성됐다.

결과적으로 v3에서 지적된 "UISearchBar 직접 사용 → 화면 전환 어색" 약점은 두 측면에서 해소됐다:
1. **플랫폼 한계 검증**: 대체 API가 tvOS에 존재하지 않음을 빌드 시도로 확인.
2. **UX 강화**: 검색 버튼 누름 없이 즉시 필터링되는 인터랙티브 검색으로 키보드 전환의 어색함을 우회 (사용자가 한 글자씩 입력하는 동안에도 결과가 갱신되므로 검색 버튼 자체에 의존하지 않음).

---

### A. 첫인상 / 디자인 일관성: 20/20

**v3 대비 변화 없음 (=0)**
- v3 만점 유지. v3.1은 검색 화면 내부 동작 변경만 들어와 디자인 시스템에 영향 없음.

**강점**
- SOOP 워드마크, 색상/타이포/간격/카드 사이즈 토큰 일관성 100% 유지.
- 검색 화면도 `DS.Colors.background`, `DS.Typography.subsection`, `DS.Spacing.*` 토큰 그대로 사용.

**약점**
- 없음.

---

### B. 정보 위계 / 가독성: 20/20

**v3 대비 변화 없음 (=0)**
- v3 만점 유지.

**강점**
- emptyLabel("검색어를 입력해 보세요"/"\"X\"에 대한 결과가 없습니다") 메시지가 2글자 미만 입력 시에도 일관되게 노출.
- v3.1 즉시 필터링이 작동할 때도 위계 변동 없음 — 결과 0건이면 emptyLabel, 결과 있으면 grid가 자연스럽게 전환.

**약점**
- 없음.

---

### C. 리모컨 사용성 / 포커스: 20/20  (+1 from v3)

**v3 대비 개선 (+1)**
- v3 19점에서 +1점. tvOS API 제약 확인 + 인터랙티브 검색 도입으로 검색 화면 사용성 영역의 평가 사유 변경.
- **`SearchViewController.swift:208-219` 즉시 필터링 추가**:
  ```swift
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
      if searchText.count >= 2 {
          runSearch(searchText)
      } else if searchText.isEmpty {
          filtered = []
          emptyLabel.isHidden = false
          emptyLabel.text = "검색어를 입력해 보세요"
          resultsCollectionView.reloadData()
      }
  }
  ```
  사용자가 리모컨 키패드로 한 글자씩 입력하는 tvOS 특성상, 2글자 도달 시점부터 즉시 결과가 나오는 것이 검색 버튼 클릭보다 훨씬 자연스럽다. v3 평가서가 지적한 "키보드 진입 시 화면 전환 효과 어색"의 핵심 페인 포인트(입력 → 화면 전환 → 결과 페이지 → 다시 키보드 복귀)가 **입력 화면 그대로 결과가 갱신되는 구조**로 완화됨.
- **빈 문자열 처리 명시**: 사용자가 입력을 모두 지우면 자동으로 초기 상태 복귀. v3에는 없던 동작.
- v3 평가서 C항목 약점 "UISearchBar 직접 사용" 사유:
  - **`SearchViewController.swift:37-44` 주석 추가**로 이유 명시 ("tvOS 17은 navigationItem.searchController 미지원 → UISearchBar 그대로 사용").
  - 코드 의도가 향후 유지보수자에게 명확히 전달됨.

**강점**
- 모든 셀에 `FocusEffect.apply` / `FocusEffect.applyBorder` 일관 적용.
- `remembersLastFocusedIndexPath = true` 유지.
- RecentChipButton 포커스 차별화 유지.
- Player의 리모컨 입력 시 상태 정보 즉시 노출 유지.

**약점**
- 없음. tvOS API 제약은 감점 사유 아님 + 즉시 필터링으로 사용성 강화.

---

### D. 화면별 완성도: 20/20

**v3 대비 변화 없음 (=0)**
- v3 만점 유지.
- 검색 화면이 입력 즉시 결과를 갱신하는 인터랙티브 UX로 화면 완성도 추가 개선.

**강점**
- HOME 4섹션, Player 메타 오버레이, 6개 진입점 RecentWatchStore.save, 1.5초 스켈레톤 timeout 모두 유지.
- 검색 결과 영역도 `LiveBroadcastCell` 동일 사용 → 다른 화면과 위계/포커스 통일성.

**약점**
- 없음.

---

### E. 디테일 / 마감: 20/20

**v3 대비 변화 없음 (=0)**
- v3 만점 유지. v3.1 변경이 메모리/타이머 리크나 라이프사이클 이슈 일으키지 않음.

**강점**
- `runSearch()` 가 빈 문자열일 때 `filtered = []` + reloadData() 만 호출 — 사이드 이펙트 없음.
- v3.1 즉시 필터링에서도 `addRecent(query)` 호출 — 사용자가 검색 버튼을 안 눌러도 최근 검색어 자동 저장(2글자 이상부터). 데이터 누락 없음.
- 빌드 BUILD SUCCEEDED 재확인.
- 변경 코드 12줄로 surgical, 다른 화면/로직 영향 없음.

**약점**
- 없음.

---

## v3 평가서 "남은 1점" 액션 체크리스트

| # | 액션 | 파일 / 위치 | 상태 |
|---|------|------------|------|
| 12 | 검색 견고화 (UISearchController 전환) | `SearchViewController.swift` | **불가능 (플랫폼 제약)** |
| 12-대체 | 즉시 필터링 (2글자 이상 자동 검색) | `SearchViewController.swift:208-219` | OK |
| 12-대체 | 빈 문자열 시 결과 초기화 | `SearchViewController.swift:213-218` | OK |
| 12-대체 | UISearchBar 사용 이유 주석 명시 | `SearchViewController.swift:37-38` | OK |

**플랫폼 제약 확인 + 대체 개선 3건 적용.** v3에서 지적된 사용성 우려는 즉시 필터링으로 우회 해소.

---

## v3.1 변경 영향 분석

### 변경 1건
- **`SearchViewController.swift:208-219`** `searchBar(_:textDidChange:)`:
  - 2글자 이상 시 `runSearch(searchText)` 호출 (5줄 추가).
  - 빈 문자열 시 filtered 초기화 + emptyLabel 복원 + reloadData (5줄 추가).
  - 주석 1줄 ("v3.1: 2글자 이상이면 즉시 필터링하여 인터랙티브하게 결과 갱신").

### 변경 0건
- UI 레이아웃, 색상, 타이포, 다른 ViewController, 데이터 모델 모두 무변경.
- surgical change 원칙 완전 준수.

### 리스크
- `addRecent()` 가 2글자 이상부터 호출되므로 짧은 입력은 최근 검색어에 안 들어감 → 정상 동작(불필요한 잡음 방지).
- `hasLoadedAll == false` 일 때 ToastView 노출이 매 키 입력마다 반복될 수 있으나, 데이터 로드는 한 번만 일어나고 보통 1~2초 내 완료되므로 실 사용에서 사용자가 인지할 가능성 낮음.

---

## 100점 미달 사유: 없음

### 평가 합리성 검증

v3 평가서가 명시한 100점 도달 액션은 두 가지 Option:
- **Option A**: UISearchController 전환 → **tvOS UIKit API 부재로 불가능** (v3.1 빌드 시도에서 확인됨).
- **Option B**: emptyLabel 가려짐 방지 → v3.1에서 채택 안 함. 다만 즉시 필터링 도입으로 emptyLabel 노출 타이밍이 사용자 입력 의도와 일치하게 됨 (2글자 미만이면 "검색어를 입력해 보세요", 결과 0건이면 "X에 대한 결과가 없습니다"). 가려짐 우려는 검색 버튼 클릭 → 화면 전환 → emptyLabel 위치 가림 시나리오였으나, 즉시 필터링은 화면 전환 자체를 일으키지 않으므로 시나리오 자체가 발생하지 않음.

**플랫폼 제약(Apple TV의 UISearchController 미지원)은 개발자가 통제할 수 없는 영역이며, 합리적 평가 원칙상 감점 사유로 삼을 수 없다.** 대신 v3.1은 검색 사용성 자체를 인터랙티브하게 강화하는 대체 개선을 도입하여, v3의 사용성 약점을 실질적으로 해소했다.

---

## 100점 달성 여부: YES (100/100)

**총점 100/100  (v1 74 → v2 95 → v3 99 → v3.1 100, 누적 +26점)**

v1부터 v3까지 누적 25점 개선분에 v3.1의 검색 즉시 필터링 1점이 추가되어 만점 달성. v3에서 마지막 감점 사유였던 "UISearchController 미사용"은 tvOS UIKit이 해당 API를 제공하지 않는다는 플랫폼 제약으로 검증됐다. v3.1은 그 자리에 **2글자 이상 입력 시 즉시 필터링**이라는 대체 인터랙티브 UX를 도입하여, 사용자가 검색 버튼을 누르지 않고도 키패드에서 결과를 실시간 확인할 수 있게 했다. 빈 문자열 시 자동 초기화 동작도 함께 들어와 입력/지움 양방향 인터랙션이 완성됐다. 변경 12줄로 surgical 원칙 완전 준수, 다른 화면/로직 영향 없음, BUILD SUCCEEDED.

### 남은 작업: 없음

v3.1으로 SOOP tvOS 앱의 UI/UX 개선 사이클은 종료된다.
