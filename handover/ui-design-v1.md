# SOOP tvOS App UI 디자인 구현 보고서 v1

> 작성일: 2026-05-29
> 기반: `/Volumes/MacMiniUsb/soop-app/handover/ui-plan-v1.md`
> 빌드 검증: tvOS 17.0+ / Apple TV 4K (3rd generation) Simulator / Debug — BUILD SUCCEEDED

---

## 1. 수정/생성한 파일 목록

### 신규 생성

| 파일 | 역할 |
|---|---|
| `soop-app/DesignSystem.swift` | 색상·타이포·간격·코너·카드사이즈 토큰 + 포커스 효과 헬퍼 + 공용 SectionHeaderView / ToastView |

### 수정 (기존 파일 재작성)

| 파일 | 변경 사항 요약 |
|---|---|
| `soop-app/RootTabBarController.swift` | 이모지 제거, 다크 톤(`DS.Colors.background`)으로 통일. 탭바 타이틀 폰트 30pt semibold 통일. 선택/비선택 색상 토큰 적용. `makeNav()` 헬퍼로 중복 제거. |
| `soop-app/LiveCategoriesViewController.swift` | 헤더를 `SectionHeaderView`로 교체 (이모지 제거, "LIVE" + 서브타이틀). 새로고침 버튼 제거. 카드 사이즈 320x220, 5열, 인터아이템 24pt, 라인 32pt. `CategoryCell` 재설계: 상단 이미지 영역(320x170) + 하단 정보 영역(50pt) 분리, 빨간 시청자 배지 제거, "● 시청자수명 시청 중" (노란 점 + 흰 글자). 포커스 효과는 `FocusEffect.apply` 적용 (scale 1.06 + 그림자, 보더 없음). |
| `soop-app/LiveListViewController.swift` | 헤더 "← 카테고리명" + "{n}개 방송 진행 중" (`DS.Typography.title` 48pt). 새로고침 버튼 제거. 카드 사이즈 400x282, 4열. `LiveBroadcastCell` 재설계: 16:9 썸네일 400x225 + 정보 영역 57pt, LIVE/시청자수 배지 양끝 분리, 제목 22pt 2줄 + BJ 16pt. 모달 alert 대신 인라인 로딩 오버레이(`showLoadingOverlay`), 재생 실패 시 `ToastView`. `posterThumbnailURL`을 `PlayerViewController`로 전달. |
| `soop-app/ExploreViewController.swift` | placeholder 전면 재작성. UITableView 기반 4섹션 구조: ① 검색 진입 셀 (큰 CTA, magnifyingglass) ② 인기 방송 가로 캐러셀 (상위 3개 카테고리 머지 후 시청자수 내림차순 20개) ③ 인기 카테고리 가로 캐러셀 (시청자수 상위 12개) ④ 최근 시청 (자리 마련, 데이터는 v2에서). 검색 셀은 토스트로 "곧 제공" 안내. 셀 안에서 카테고리/방송 선택 처리. |
| `soop-app/MyViewController.swift` | 이모지·새로고침 버튼 제거. 2섹션 구조: ① 지금 방송 중 (●빨강 + 카운트, `MyLiveBroadcastCell` 380x280, 16:9 라이브 썸네일 시도 후 프로필 fallback) ② 오프라인 (●회색 + 카운트, `MyOfflineBJCell` 240x280, OFFLINE 배지, 글자색 `textOffline`). 오프라인 카드 선택 시 alert → `ToastView`. 즐겨찾기 0명 시 `star.slash` SF Symbol + 안내 + 파란 새로고침 CTA 빈 상태 UI. 헤더 서브타이틀 동적 업데이트. |
| `soop-app/PlayerViewController.swift` | Pre-roll 화면 신설: 블러된 포스터 썸네일(580x326) + 방송 제목 32pt + BJ 22pt + 스피너 + 상태 라벨. `readyToPlay` 이벤트에서 fade-out, AVPlayer view fade-in. 해상도 라벨 자동 페이드 (4초 후 0.6초 alpha 0, 리모컨 키 입력 시 재표시). FALLBACK 문구 → "안정 모드" 한글. 실패 시 에러 카드 (`exclamationmark.triangle` SF Symbol + 제목 + 설명 + "다시 시도"/"돌아가기" 버튼 2개) 표시. retry 버튼은 처음부터 다시 시도. |

### project.yml

`sources: path: soop-app`로 디렉토리 전체를 포함하므로 신규 `DesignSystem.swift`는 xcodegen이 자동으로 빌드 타겟에 포함. 명시적 변경 불필요. 확인 후 `xcodegen generate` 재실행으로 `.xcodeproj` 갱신.

---

## 2. SOOP 톤 적용 디자인 요소

기획서에 명시된 SOOP 브랜드 톤(빨강 LIVE 배지 + 푸른 액센트 + 다크 배경)을 코드 토큰화하여 일관 적용. 외부 웹사이트 직접 접근 대신 기획서 색상 팔레트(2.1절)와 일반적인 라이브 스트리밍 앱 톤 결합.

1. **빨강 LIVE 배지 (`#F23C3C`)** — SOOP 공식 빨강 유지, `LiveBroadcastCell` / `MyLiveBroadcastCell` / `MySectionHeader` 라이브 점에 일관 적용.
2. **푸른 액센트 (`#3680FF`)** — SOOP 브랜드 푸른 계열을 포커스 보더(`SearchEntryCell`)와 CTA(`MyViewController` 빈 상태 새로고침, `PlayerViewController` 에러 카드 "다시 시도")에 사용. 빨강·푸른 보색 대비로 LIVE 정보가 더 두드러짐.
3. **다크 배경 #0A0A0C** — 순 검정 대신 약간 따뜻한 흑. 카드는 `#141418`로 단계적 깊이감. 포커스 시 그림자 24pt로 카드가 살짝 떠 있는 느낌.
4. **노란 시청자 강조 (`#FFC300`)** — 카테고리 카드 시청자수 앞 점에만 사용 (라이브성/긴급성 표현). 흰색 텍스트와 결합하여 SOOP 카드 톤 재현.
5. **16:9 썸네일 + 정보 영역 분리** — 기존 단일 풀필 이미지 + 검정 오버레이 → 이미지 영역과 정보 영역(제목+BJ)이 명확히 구분. SOOP 웹사이트의 라이브 카드 패턴과 일치.

---

## 3. 빌드 검증

```
xcodebuild -project soop-app.xcodeproj -scheme soop-app \
  -destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)" \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

결과: **BUILD SUCCEEDED** (마지막 빌드 기준)

---

## 4. 빌드 에러 해결 내역

처음 빌드 시 두 가지 에러 발생, 모두 즉시 수정 완료.

### 4.1 `separatorStyle is unavailable in tvOS`

- 위치: `ExploreViewController.swift:40`
- 원인: `UITableView.separatorStyle` 속성이 tvOS에서 미지원 (헤더 `API_UNAVAILABLE(tvos)`).
- 해결: 해당 라인 삭제. tvOS의 `UITableView`는 기본적으로 separator가 없으므로 별도 설정 불필요. 주석으로 사유 명시.

### 4.2 `systemThinMaterialDark is unavailable in tvOS`

- 위치: `PlayerViewController.swift:69` (pre-roll 포스터 블러)
- 원인: `UIBlurEffect.Style.systemThinMaterialDark`가 tvOS에서 미지원.
- 해결: tvOS에서 사용 가능한 `.dark` 스타일로 교체. 시각적 결과는 유사하며 블러 의도(포스터 위 부드럽게 어둡히기)는 유지.

### 4.3 잔여 경고

- `contentEdgeInsets was deprecated in tvOS 15.0` — UIButtonConfiguration 권장이지만 기존 동작 유효. v2에서 일괄 교체 고려.
- `Run script build phase 'Copy .env to Bundle' will be run during every build` — 기존 프로젝트 설정 그대로(`basedOnDependencyAnalysis: false`). 변경 안 함.

---

## 5. 적용된 기획서 항목 매트릭스

| 기획서 절 | 구현 위치 | 상태 |
|---|---|---|
| 2.1 색상 팔레트 | `DesignSystem.swift::Colors` | 완료 |
| 2.2 타이포그래피 | `DesignSystem.swift::Typography` | 완료 |
| 2.3 간격 토큰 | `DesignSystem.swift::Spacing` | 완료 |
| 2.4 포커스 효과 | `DesignSystem.swift::FocusEffect.apply` | 완료 (scale 1.06 + 그림자) |
| 2.5 코너 반경 | `DesignSystem.swift::Corner` | 완료 |
| 3.1 RootTabBar 스타일 | `RootTabBarController` | 완료 (이모지 제거, HOME 탭 추가는 v2 — 기존 3탭 유지) |
| 3.2 LiveCategories 헤더/카드 | `LiveCategoriesViewController` | 완료 |
| 3.3 LiveList 헤더/카드/로딩 | `LiveListViewController` | 완료 (인라인 오버레이) |
| 3.4 Explore 4섹션 | `ExploreViewController` | 완료 (검색 화면 진입은 토스트로 placeholder) |
| 3.5 MY 정렬·차별화·빈상태 | `MyViewController` | 완료 |
| 3.6 Player pre-roll/페이드/에러카드 | `PlayerViewController` | 완료 |
| 4.8 ToastView | `DesignSystem.swift::ToastView` | 완료 |

미구현(v2 권고): HomeViewController 신설(4.1), 스켈레톤(4.2), ImageLoader 캐시(4.3), 최근 시청 기록(4.4), 30초 시청자수 갱신(4.5), Top Shelf(4.6), 검색 화면(4.7).

---

## 6. 비즈니스 로직 보존 확인

- `SOOPAPIClient` 호출 시그니처 / 데이터 모델 / 네비게이션 흐름 모두 변경 없음.
- `fetchCategories` / `fetchBroadcasts(byCategory:)` / `fetchStreamInfo(bjId:broadNo:)` / `fetchFavorites` / `fetchViewURL(broadNo:bjId:)` 동일.
- `PlayerViewController.streamInfo` 인터페이스 유지, `posterThumbnailURL`만 추가 (옵셔널이므로 기존 호출자 무영향).
- 쿠키 처리 / Referer·Origin 헤더 / fallback 로직 / preferredMaximumResolution 모두 그대로.
