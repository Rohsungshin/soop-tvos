# Handover: 실시간 영상 미출력 수정 — Cycle 1
> 날짜: 2026-05-22 | 파일: soop-app/ViewController.swift

---

## 상태: 코드 수정 완료, 실기기 검증 대기

빌드 검증: **tvOS Simulator BUILD SUCCEEDED** (Warning only, no errors)

---

## 핵심 문제 요약

Apple TV tvOS WKWebView에서 SOOP 실시간 영상이 전혀 재생되지 않는 문제.

### 근본 원인 (4개)

#### 버그 1 — [결정적] MSE 조기 종료 (ViewController.swift:741-745 구간)
```javascript
// 수정 전 — hlsCaptureJS() 안에서 MSE 검출 시 함수 전체 return
if(typeof window.MediaSource!=='undefined'&&...){
    log('MSE available — skip');
    return;   // ← XHR/fetch 인터셉터가 설치 안 됨
}
```
**tvOS WKWebView에서 `window.MediaSource`는 존재하지만 live HLS에서 동작 불안정**.
이 조기 종료 때문에 XHR·fetch·video.src 인터셉터가 전혀 설치되지 않아
m3u8 URL이 Swift에 한 번도 전달되지 않음 → AVPlayer가 호출되지 않음.

**수정**: 조기 종료 제거. MSE 존재 여부와 무관하게 항상 인터셉터 설치.

#### 버그 2 — XHR request URL 미캡처
```javascript
// 수정 전: response body만 스캔, request URL은 무시
XMLHttpRequest.prototype.open=function(m,u){
    this._su=String(u||'');
    return ox.apply(this,arguments);  // sendHLS 호출 없음
};
```
hls.js가 `https://.../playlist.m3u8` 로 XHR 요청을 보내면 URL 자체에 .m3u8이 있지만
response body가 올 때까지 기다리다 포착에 실패하는 경우 존재.

**수정**: `open()`에서 즉시 `sendHLS(this._su)` 호출 추가.

#### 버그 3 — Hls.isSupported 패치가 MSE 있을 때 동작 안 함
```javascript
// 수정 전: MSE 없을 때만 패치
if(typeof window.MediaSource==='undefined'|| ...){
    window.Hls.isSupported = function(){ ... };
}
```
tvOS에서 MediaSource가 있으므로 이 블록은 **항상 건너뜀**. 결과적으로 hls.js가
MSE path를 선택 → tvOS에서 live stream 재생 불안정.

**수정**: MSE 조건 제거. tvOS native HLS가 지원되면 항상 `Hls.isSupported()=false` 반환.
→ hls.js가 native path 선택 → `video.src = m3u8_url` 설정 → video.src setter 인터셉터가 URL 캡처 → AVPlayer.

#### 버그 4 — HLS 탐색 트리거가 play/vod 서브도메인에만 한정
```swift
// 수정 전
if urlStr.contains("play.sooplive.com") || urlStr.contains("vod.sooplive.com") {
// 수정 후
if urlStr.contains("sooplive.com") || urlStr.contains("afreeca.tv") {
```
스트리머 페이지 (`www.sooplive.com/{id}`)에서는 HLS URL 탐색이 전혀 실행되지 않았음.
`tryHLSSearch()` 내부 guard도 동일하게 수정.

---

## 수정된 파일 및 라인

| 위치 | 수정 내용 |
|------|----------|
| `ViewController.swift:740-743` | hlsCaptureJS — MSE 조기 종료 제거 |
| `ViewController.swift:806-807` | hlsCaptureJS — XHR open에서 request URL 즉시 sendHLS |
| `ViewController.swift:830-831` | hlsCaptureJS — fetch에서 request URL 즉시 sendHLS |
| `ViewController.swift:1043-1065` | videoAutoplayJS — Hls.isSupported 패치 MSE 조건 제거 |
| `ViewController.swift:1745` | tryHLSSearch — URL 조건 sooplive.com/afreeca.tv 전체로 확장 |
| `ViewController.swift:1877-1880` | didFinishNavigation — HLS 탐색 트리거 전체 도메인으로 확장 |

---

## 실기기 테스트 시 확인 포인트

### 정상 동작 기대 흐름
1. 앱 실행 → `www.sooplive.com` 홈 로드
2. 스트리머 목록에서 라이브 중인 스트리머 선택 (리모컨 방향키 + Select)
3. `play.sooplive.com/...` 또는 스트리머 페이지로 이동
4. Xcode 콘솔에 `[HLS] FOUND https://...playlist.m3u8?token=...` 로그 출력
5. AVPlayerViewController가 전체화면으로 present
6. 실시간 영상 재생

### 디버그 확인 방법 (Xcode 콘솔)
- `[HLS] MSE: true — always intercepting` → 버그1 수정 확인
- `[HLS] XHR GET https://.../.../playlist.m3u8` → 버그2 수정 확인
- `[HLS] FOUND https://...` → URL 캡처 성공
- `[AVPlayer] playing: https://...` → AVPlayer 시작 확인

### 만약 영상이 여전히 안 나올 경우 확인할 것
1. `[HLS] FOUND`가 없는 경우: SOOP이 XHR/fetch가 아닌 다른 방식으로 URL 주입 가능성
   → 화면 우측 영상 진단 오버레이(파란 박스)에서 `V0 rs=?` 확인
2. AVPlayer는 뜨지만 영상이 검정인 경우: m3u8 토큰 만료 또는 DRM 문제
3. 로그인이 안 된 경우: 리모컨으로 수동 로그인 후 재시도

---

## 다음 Cycle에서 할 것 (실기기 테스트 후)

- 영상이 나오면: 스트리머 탐색 UX 개선, 볼륨/풀스크린 컨트롤 확인
- 영상이 안 나오면: 콘솔 로그 기반 추가 분석 → Cycle 2
  - 가능성 1: SOOP이 WebSocket으로 스트림 URL 전달 → WebSocket 인터셉터 추가 필요
  - 가능성 2: URL 토큰 인증 방식 변경 → API 직접 호출 방식 필요
  - 가능성 3: 로그인 상태 문제 → LoginManager 자동 로그인 활성화 검토
