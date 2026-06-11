# SOOP tvOS 앱 오류·빈 상태 UX 개선 재검수 보고서

- **문서 버전**: v1.1
- **검수일**: 2026-06-11
- **대상**: git 작업 트리 미커밋 변경분 (C7 수정 반영분)
- **기준 문서**: consulting-v1.0 §4 배점표, design-v1.0 §2-3
- **이전 검수**: 2026-06-11-inspection-v1.0.md (총점 98/100, C7 −2 감점)
- **검수자**: 검수 에이전트

---

## 1. 최종 점수표 (v1.0 대비 변동)

| 체크 포인트 | 배점 | v1.0 | v1.1 | 변동 | 판정 |
|------------|------|------|------|------|------|
| C1. 홈/탐색 오류 상태 + 재시도 (I-1) | 25 | 25 | 25 | — | 합격 |
| C2. 검색 데드락 해소 (I-2) | 15 | 15 | 15 | — | 합격 |
| C3. MY 탭 메시지 친화화 + 재시도 (I-3) | 15 | 15 | 15 | — | 합격 |
| C4. 워드마크 z-order (I-4) | 5 | 5 | 5 | — | 합격 |
| C5. 스켈레톤 타이밍 (I-5) | 10 | 10 | 10 | — | 합격 |
| C6. 검색 범위 안내 (I-6) | 5 | 5 | 5 | — | 합격 |
| C7. emptyLabel 겹침 방지 (I-7) | 5 | 3 | **5** | **+2** | 합격 |
| C8. 빌드 성공 | 10 | 10 | 10 | — | 합격 |
| C9. 디자인 시스템 일관성 | 5 | 5 | 5 | — | 합격 |
| C10. Surgical change 원칙 | 5 | 5 | 5 | — | 합격 |
| **총점** | **100** | **98** | **100** | **+2** | **합격** |

---

## 2. C7 재검증 근거 (SearchViewController.swift)

v1.0 감점 사유는 `runSearch(_:)`의 `!hasLoadedAll` 분기가 토스트만 띄우고 `return`하면서
`setEmptyStateVisible`을 호출하지 않아, "결과 표시 → 풀 리셋/실패 → 새 검색어 입력" 시
이전 검색 결과 그리드(resultsCollectionView)가 그대로 노출되는 실사용 결함이었다.

수정 후 코드(`SearchViewController.swift:252-273`):

- **분기 진입 즉시 옛 그리드 제거**: `filtered = []` (254행) + `resultsCollectionView.reloadData()` (255행).
  이전 검색 결과 셀이 0개로 갱신되어 그리드에 옛 결과가 남지 않는다.
- **3개 하위 분기별 emptyLabel 상태 문구**:
  - 재로드 진행 중(`isReloading`): "데이터를 다시 불러오고 있습니다" (259행)
  - 풀 로드 실패(`hasLoadFailed`): "검색 데이터를 다시 불러옵니다" (265행), `loadAllBroadcasts()` 자동 재로드(267행)
  - 초기 로딩 중(그 외): "데이터 준비 중입니다. 잠시 후 다시 시도해 주세요" (269행)
- **return 직전 배타 표시 확정**: `setEmptyStateVisible(true)` (272행) → emptyLabel 표시 + resultsCollectionView 숨김.
  세 분기 공통 경로에서 한 번만 호출되어 누락 위험 없음.

design §2-3 "모든 상태 전이에서 두 뷰 isHidden이 항상 반대" 규칙을, v1.0에서 위반했던
재로드/대기 상태에서도 이제 준수한다. C7 만점(5/5) 회복.

### 전 상태 배타 규칙 재검증

| 상태 | 경로 (라인) | emptyLabel | resultsCollectionView | 판정 |
|------|-----------|-----------|----------------------|------|
| 초기 표시 | `setupUI` 끝 `setEmptyStateVisible(true)` (144) | 표시 | 숨김 | OK |
| 검색어 없음 (빈 문자열) | `runSearch` 빈 분기 (245-250) | 표시 | 숨김 | OK |
| 재로드 대기/진행/실패 | `!hasLoadedAll` 분기 (252-273) | 표시 | 숨김 (filtered=[] 후 reload) | OK |
| 검색 결과 있음 | `setEmptyStateVisible(false)` (282) | 숨김 | 표시 | OK |
| 검색 결과 0건 | `setEmptyStateVisible(filtered.isEmpty)` (282) | 표시 | 숨김 | OK |
| textDidChange 빈 입력 | `updateSearchResults` else if (316-321) | 표시 | 숨김 | OK |

모든 상태 전이가 `setEmptyStateVisible(_:)` 단일 헬퍼(`:148-151`)를 경유하여
두 `isHidden`을 항상 반대값으로 동시 설정한다. 직접 `isHidden` 단독 설정 잔존 코드 0건.

---

## 3. 회귀 점검 결과

### 3-1. pendingQuery 처리 후 결과 복원 흐름 (C2 연계)
- 실패 후 새 검색어 입력 → `hasLoadFailed` 분기에서 `pendingQuery = query`, `isReloading = true`,
  `loadAllBroadcasts()` 호출.
- 재로드 성공 시 `group.notify`에서 `isReloading` 확인 → `pendingQuery`로 `runSearch(q)` 재실행(`:189-195`).
  이때 `hasLoadedAll = true`이므로 필터 경로로 진입, `setEmptyStateVisible(filtered.isEmpty)`로
  결과 그리드 또는 0건 안내가 정상 표시된다.
- 재로드 진행 중 추가 입력 → `isReloading` 분기에서 `pendingQuery`만 최신 검색어로 갱신, 중복 재로드 없음.
- **회귀 없음.** C2 만점 유지.

### 3-2. 즉시 필터링(textDidChange) 경로 emptyLabel 문구 어긋남 점검
- `updateSearchResults`(2글자 이상) → `runSearch` 진입. 0건이면 `noResultsText` attributedText로
  덮어쓰므로(`:280`), `!hasLoadedAll` 분기에서 설정했던 plain text "데이터를 다시 불러오고 있습니다" 등이
  남아 어긋나는 경우 없음.
- 풀 로드 완료 후 결과가 있으면 그리드 표시(emptyLabel 숨김)되어 이전 문구가 보이지 않는다.
- emptyLabel은 plain `text`와 `attributedText`를 혼용하나, 각 경로가 매번 둘 중 하나를 갱신하고
  표시 시점에 최신값으로 덮어쓰므로 잔상 문구 노출 없음.
- **회귀 없음.** C6 만점 유지.

### 3-3. 다른 코드 변경 혼입 여부 (C10 연계)
- `git diff soop-app/SearchViewController.swift` 확인 결과, 변경분은 전부 I-2/I-6/I-7 범위 내:
  상태 변수 3개 신설, `setEmptyStateVisible` 헬퍼, `loadAllBroadcasts` 실패 기록/재로드 복원,
  `runSearch` 빈 상태 배타화, `noResultsText` 헬퍼.
- C7 재수정으로 추가된 라인은 `!hasLoadedAll` 분기 내 `filtered=[]`/`reloadData`/`setEmptyStateVisible`/
  분기별 emptyLabel.text 뿐. 범위 밖 코드·무관 리팩터링·고아 코드 없음.
- 나머지 5개 파일(DesignSystem/Explore/Home/My/RootTabBar)은 v1.0 검수 시점 대비 변동 없음(C7는 Search 전용 수정).
- **회귀 없음.** C10 만점 유지.

### 3-4. C1/C3/C4/C5/C8/C9 회귀
- 이번 수정은 `SearchViewController.swift` 단일 파일에 국한되어 홈/탐색/MY/RootTabBar/DesignSystem에
  영향을 주지 않음. 해당 항목 v1.0 만점 그대로 유지.
- 빌드(C8): tvOS 시뮬레이터(Apple TV 4K 3rd gen) Debug 빌드 `** BUILD SUCCEEDED **` 재확인. 신규 경고/오류 없음.
- DS 토큰(C9): C7 수정 추가 라인은 문자열·`filtered`/`reloadData`/헬퍼 호출뿐으로 색상·폰트 하드코딩 미발생.

---

## 4. 결론

- **총점: 100 / 100**
- **합격 여부: 합격(100점 달성)**
- v1.0 감점 항목 C7(−2)이 지시대로 정확히 수정되어 만점 회복. 그 외 9개 항목 회귀 없음.
- 빌드 성공. 검수 단계 완료 — 가상 테스트 단계로 진행 가능.
