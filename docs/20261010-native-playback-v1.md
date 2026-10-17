# 네이티브 원본 재생 방식 추가 — 분석 · 기획 · 구현 · 검증 보고서

- **문서 버전**: v1 (단계 종료마다 갱신)
- **작성일**: 2026-10-10 시작
- **브랜치**: `feature/native-playback` (분기점 `main` = `199194e`)
- **요청**: "스트리밍 방식을 하나 추가… 설정탭에서 설정할 수 있게… https://github.com/PERISU21/SOOPTV-1080p 의 방식을 읽고 해당 방식과 현재 방식 중 선택… 기획 > 구현 > 검증… 문서화… 푸시 및 머지… 실기기 설치"
- **프로세스**: 분석 → 기획 → 구현 → 검증 → 푸시 · 머지 → 실기기 설치
- **실기기**: Apple TV 4K 2세대 "큰방"

---

## 0. 결론 요약

| 항목 | 결론 |
|------|------|
| 추가 방식 | **네이티브 원본 재생** — SOOP 미디어 서버 할당(`affslb getfc`) → TCP 비공식 프로토콜로 원본 H.264/AAC 수신 → 앱 내 TS 재포장 → 루프백 HLS → AVPlayer. CDN HLS를 거치지 않으므로 국내에서도 1080p 원본 수신 |
| 사용자 승인 이력 | 이 경로의 리스크(시청자 인증 없음·약관 제13조⑧13호·계정 정지 가능·참조 저장소 라이선스 없음)는 2026-10-03 사이클에서 전면 보고했고, 사용자가 이번에 저장소 URL을 명시하며 다시 요청해 진행한다. 라이선스 문제는 **코드를 한 줄도 복사하지 않고**(事实만 인용) Swift 재구현으로 회피 |
| 설정 탭 | 재생 방식 3-way: **자동(CDN·ABR)** / **고정 화질(CDN·고정)** / **네이티브 원본(1080p 직접 수신)**. 기존 2카드 구조 유지 + 3번째 카드 추가 |
| 보호 장치 | ① 공개 방송만(player_live_api RESULT=1 + grade<19 + BPWD≠Y 통과 시) ② 기존 공개 경로가 먼저 성공한 방송에만 ③ 캐시 서버에 쿠키·토큰·Referer 전송 금지(getfc만, HTTP) ④ 실패 시 기존 CDN 경로 자동 폴백 ⑤ 수신 무활동 16초 → 폴백 ⑥ 루프백 리스너는 127.0.0.1 전용 바인드 |
| 검증 | 프로토콜·먹서 macOS 하니스(패킷 파싱·FLV 대조 아님—TS 먹서 단독 컴파일) + 무음 AVPlayer 재생 + 설정 탭 UI + 빌드 경고 0 + 실기기 |
| 변경 범위 | 신규 3파일(`SOOPNativeReceiver.swift`, `TSMuxer.swift`, `LocalHLSServer.swift`), 수정 3파일(`PlaybackSettings.swift`, `SettingsViewController.swift`, `PlayerViewController.swift`), 문서 1 |

---

## 1. 분석

### 1-1. 참조 저장소 정독 (라이선스 없음 — 사실만 인용)

PERISU21/SOOPTV-1080p 0.7.6(HEAD `ff23f3d`, 2026-10-01, 파일 11개)을 읽기 전용 클론해 정독했다. 구조: Python 로컬 서버(루프백 18777) + mpv/FFmpeg + Brave 확장(hls.js). **어떤 코드도 복사하지 않았다.**

프로토콜 사실(`파일:줄` 인용):

| 항목 | 내용 |
|------|------|
| 서버 할당 | `http://affslb.sooplive.com:10035/getfc?bj=<bid>&bno=<번호>&stype=org` → 쿼리스트링 응답 `err_code=0` + `fc_ip`, `fc_port`. IP는 글로벌 검증(`soop_player.py:60-66`) |
| 프레이밍 | 16B 리틀엔디언 헤더: `magic(0x202):H, cmd:H, len:I, checksum(len^cmd^0x202):I, 0:I`. len>8MB 거부(`soop_media.py:10-17`) |
| 핸드셰이크 | `0xcb2e(broadNo, 0, quality_code)` → `0xcb2f(1)` → `0xcb30(quality_code, 0, 0, 2)` (`soop_player.py:168-170`) |
| 화질 코드 | **1080p=1, 720p=2**. 10(=2\|8, 720p+360p 동시)은 mid-stream 해상도 전환으로 MSE가 깨져 금지(`soop_player.py:145-147` 주석) |
| keep-alive | 4초마다 `0xcb30(quality_code, next_frame-30, 6)` — 라이브 엣트보다 뒤. 미래 프레임 요청은 연결을 영원히 멈춘다(`soop_player.py:182-185`) |
| 미디어 패킷 | cmd `0xc748`. body: `version:H, hdr_size:H, ext_size:H, raw_size:I`, kind@40(73·80=video, 65=audio), seq@40:8B(@20), dts@41:8B(100ns), cts@57:4B signed(`soop_media.py:40-68`) |
| 시간축 | 첫 dts − 10,000,000(1초)을 원점으로 100ns→ms. 오디오가 512ms 묶음으로 영상보다 먼저 올 수 있다(`soop_media.py:60-63`) |
| 페이로드 | 영상 = H.264 Annex B, 오디오 = AAC ADTS. **트랜스코딩 0** — 재포장만(`soop_media.py:4`) |
| 에코 | cmd `0x1bc4`는 받은 body를 그대로 반환(`soop_player.py:195-196`) |
| 무활동 | 16초 새 프레임 없으면 타임아웃(`soop_player.py:198-199`) |
| 중복 | 스트림별 sequence 단조 증가 검사로 스킵(`soop_media.py:53-57`) |
| 인증 | **없음** — 쿠키·토큰·서명 전송 0건. 브라우저 확장 경로도 로컬 서버에 토큰만 쓰고 캐시 서버엔 미전송 |
| 게이트 | 참조 구현은 `RESULT≠1`·`BPWD=Y`만 검사. 19+는 잡지 못한다(로그인 세션이면 RESULT=1 — 우리 2026-09-24 실측) |

### 1-2. 우리 문서 실측과의 교차검증

| 참조 코드 주장 | 우리 실측(2026-10-03 §1-2, 2026-10-05 §4-3) | 판정 |
|---------------|----------------------------------------------|------|
| 국내에서도 1080p 원본 수신 | 7개 공개 방송 전부 원본 그대로(1080p60·1440p·720p·세로) 수신 | ✅ 일치 |
| 지연이 짧다(캐시 원본) | 수신-벽시계 중앙값 0.009~0.010초 vs HLS 1.1초+ | ✅ |
| VIEWPRESET 명실일치 | 13개 성공 세션 전부 일치 | ✅ |
| AUD 없음(SOOP 스트림) | tvOS 실험: AUD 0개 → AVPlayer 재생 실패, 먹서 삽입 필요 | ✅ |
| PAT/PMT 매 세그먼트 필요 | 중간 합류 실패 실험과 일치 | ✅ |
| PCR 불필요 | 없어도 재생 | ✅ |
| 3세그먼트 후 시작 | 1개로 시작하면 stall 1회 | ✅ |
| quality_code 1=1080p | VIEWPRESET original/hd4k와 대응(실측 표) | ✅ |

### 1-3. tvOS에서 요구되는 것 (참조와 다른 부분)

참조 구조(Python+FFmpeg+mpv+브라우저)를 tvOS로 옮기면:

| 참조 | tvOS 앱 | 근거 |
|------|---------|------|
| FFmpeg `-c copy -f hls` | **Swift TS 먹서 직접 구현** | tvOS에 ffmpeg 없음. 2026-10-03 §1-4에서 Swift TS 먹서 프로토타입으로 AVPlayer 요구조건 실측 완료 |
| mpv 재생 | AVPlayer | — |
| 브라우저 hls.js | AVPlayer(루프백 HLS URL) | 리소스 로더 세그먼트 공급은 `-12881` 실패 → **NWListener 루프백 필수**(2026-10-03 §1-4 실측) |
| 서버 127.0.0.1 바인드 | `NWListener` + `requiredLocalEndpoint = 127.0.0.1` | 기본값·acceptLocalOnly 모두 `*:port` 바인드 실측(TN3179 — tvOS는 Local Network 보호 없음) |
| FLV 출력 | TS 세그먼트 + m3u8 | AVPlayer는 HLS |

### 1-4. 기존 코드 통합 지점

- `PlayerViewController.startPlayback()` — `info.viewURL`을 AVPlayer에 넘기는 단일 진입. 네이티브 모드면 이 지점에서 루프백 URL로 갈아끼운다.
- `PlaybackSettings.mode` — 현재 auto/fixed 2값. 네이티브 추가.
- `SettingsViewController` — 카드 배열에 3번째 카드.
- `SOOPAPIClient` — `player_live_api` 호출부에서 GRADE/BPWD 정보가 이미 흐른다. `StreamInfo`에 `grade`·`isPasswordRoom` 필드 추가 필요.
- 화질 메뉴(트랜스포트 바) — 네이티브 재생 중엔 CDN 등급과 무관하므로 '네이티브 1080p' 행 하나.

### 1-5. 리스크 평가 (2026-10-03 §1-5·§1-8에서 갱신 없음)

- 약관 제13조⑧13호(이용방식·기획의도 변경) — 비공식 클라이언트 리스크의 증폭. 계정 정지(제18조②) 가능.
- 참조 저장소 라이선스 없음 → **코드 미복제 원칙**으로 ours는 클린룸 재구현(프로토콜 사실만 인용).
- 지속성: 2017 RTMP 사례처럼 언제든 끊길 수 있음 → 폴백 필수.
- 실부하: 수신은 HTTP 1회(getfc) + TCP 1세션. 기존 HLS 세그먼트 폴링보다 오히려 적다.

---

## 2. 기획

### 2-1. 모드 구조

```
PlaybackMode: auto(0) | fixed(1) | native(2)
```

- 저장은 기존 `soop.playback.mode`(신규 키). 기존 `soop.player.quality`는 auto/fixed 공유값 유지.
- 기본값 auto. 업그레이드 설치 시 기존 사용자 값 유지.

### 2-2. 재생 흐름 (네이티브)

1. 기존 경로(`fetchStreamInfo`) 성공으로 **공개 방송 확인**(RESULT=1, grade<19, BPWD≠Y, 구독 전용 아님). 실패·제한 방송이면 네이티브 시도 자체를 안 한다.
2. `getfc` 할당(HTTP, 쿠키 없음) → `fc_ip:fc_port`.
3. TCP 연결 → 핸드셰이크(0xcb2e/0xcb2f/0xcb30, quality=1).
4. `0xc748` 수신 → TS 먹서(AUD 삽입·PAT/PMT 매 세그먼트·3세그먼트 버퍼).
5. 루프백 HLS(`127.0.0.1:<ephemeral>/index.m3u8`) → AVPlayer.
6. 4초 keep-alive, 16초 무프레임 → 폴백(기존 CDN 경로로 자동 전환).
7. 네이티브 실패(할당 실패·연결 실패·프레임 없음) → **자동으로 CDN 자동 모드로 폴백**, 토스트 1회.

### 2-3. 보호 장치 (변경 없음)

이전 사이클이 정리한 규칙 유지: 공개 방송 한정 / 기존 경로 성공 방송에만 / 캐시 서버에 인증 정보 미전송 / 거부 방송 폴백 금지(에러 카드로) / 19+·비번방·구독 전용은 네이티브 비활성.

### 2-4. UI

- 설정 탭: 3번째 카드 "네이티브 원본 (1080p)" — 상세: "SOOP 미디어 서버에서 원본을 직접 받아 재생합니다. CDN을 거치지 않아 국내에서도 1080p 원본을 볼 수 있습니다. 비공식 경로로 언제든 끊길 수 있으며, 실패 시 일반 재생으로 자동 전환됩니다"
- 플레이어: 네이티브 재생 중 화질 메뉴는 '네이티브 원본' 행. 프리롤 동안 "원본 연결 중…" 표시.
- 실패 토스트: "네이티브 재생 실패 — 일반 재생으로 전환했습니다"

### 2-5. 검증 계획

1. 프로토콜·먹서 하니스(macOS 단독 컴파일): 패킷 프레이밍 왕복, 헤더 파싱, TS 먹서 산출물을 ffprobe로 검증
2. 루프백 HLS + 무음 AVPlayer 재생(macOS)
3. 실제 SOOP 공개 방송으로 end-to-end(음소거, 40초 이내)
4. 시뮬레이터 UI(3카드) + 빌드 경고 0
5. 실기기 설치 후 수동 체크리스트

---

## 3. 구현

(구현 중 갱신)

---

## 4. 검증

### 4-1. macOS 하니스 — 먹서 단독 컴파일 (2026-10-12~16, `/tmp/soop-lb-harness`)

`SOOPNativeReceiver.swift` + `TSMuxer.swift` + `LocalHLSServer.swift`를 단일 파일로 결합해
CLI 하니스로 구동. 입력은 ffmpeg testsrc2(640x360@30, x264 `repeat-headers=1:aud=1:keyint=30`)와
sine AAC(48kHz)를 프레임/ADTS 단위로 분할한 것 — 서버 타이밍 재현(오디오 512ms 묶음·dts 100ns).

**발견·수정한 먹서 결함 4건 (전부 실측 재현으로 확정):**

| # | 결함 | 증상(실측) | 수정 |
|---|------|-----------|------|
| M1 | PES 마지막 TS 패킷의 잔여 공간을 `0x00`으로 패딩 | ffmpeg mpegts 디먹서가 남은 바이트를 다음 PES 조각으로 오인 → AAC `channel element 0.0 is not allocated` 세그먼트당 23건 | 잔여 공간에 adaptation field + `0xFF` stuffing(ISO 13818-1 2.4.3.4). 잔여 1바이트 케이스는 chunk를 1 줄여 AF 2바이트 확보 |
| M2 | M1 수정 뒤 `leftover==0`일 때 `packet[3]`이 초기값 `0x00`(afc=0, 규격 위반)으로 방치 | 해당 패킷 통째로 버려짐 → 비디오 slice 184바이트씩 절단(예: 2541→2357B) → `error while decoding MB 31 18, bytestream -9` | last 패킷 분기에 기본값 `0x10 \| cc` 부여 |
| M3 | PTS/DTS를 ms 왕복(`틱→ms→틱`)으로 계산 | 서로 다른 PTS가 같은 ms로 뭉개져 PES PTS 중복 → FFprobe `1.554656` 두 패킷 등 | `pesPayload`가 90kHz 틱을 직접 받도록 통일(100ns×9/1000) |
| M4 | `feedAudio`의 baseTicks가 origin(첫 dts−1초) 보정 없이 절대시각 / DTS 필드 prefix를 PTS와 동일한 `0x21`로 부호화 | 오디오 PTS가 비디오보다 origin(≈0.9초)만큼 늦음 — seg0 비디오 0.100~1.067초 vs 오디오 1.533~2.024초(첫 세그 시간 창 이탈) / B-frame 스트림에서 DTS 폐기 | 오디오도 `originTicks` 차감 + DTS prefix `0x11`(‘0001’) — PTS는 `0x21`(‘0010’) 유지(ISO 13818-1 2.4.3.7) |

**수정 후 검증 (전부 실측):**

| 검증 | 결과 |
|------|------|
| 세그먼트 5개 ffmpeg 디코드(`-v error -f null`) | **에러 0건** — M1/M2 수정 전에는 세그먼트당 45~138건 |
| 비디오 PTS | 30프레임 무중복, 전 구간 3000틱(33.3ms) 간격 |
| 오디오 PTS | 무중복, PES당 1920틱(21.3ms) — `lastAudioPTSTicks` 단조 보정 작동(272159/272160/272161 실측) |
| PTS≠DTS(B-frame) 부호화 | 인위적 cts 지그재그 시나리오에서 dts_time≠pts_time 정확히 인코딩 확인 |
| CC(continuity counter) | 비디오 561패킷·오디오 47패킷 불연속 0 |
| ES 무결성 | TS→카피 추출 ES의 IDR(8222B)·slice들이 원본 h264와 **바이너리 완전 일치** |
| PES 경계 | 24 PES 전부 `FF F1` 동기 시작, ADTS length 필드 == PES_packet_length−8 전건 일치 |
| 오디오·비디오 타임라인 정렬 | seg0 비디오 0.100 시작 = 오디오 0.100 시작(M4 수정 전 1.533) |
| Xcode 빌드(tvOS) | BUILD SUCCEEDED, Swift 경고 0 |

**하니스 AVPlayer `readyToPlay` 미도달에 대한 결론**: 로컬 mp4·ffmpeg 공식 HLS 산출물도
이 CLI 세션에서 전부 `status=0`에 머묾 — 헤드리스 환경의 AVFoundation 제약이지 먹서 결함이
아니다. 먹서 검증은 ffmpeg 디코드·ffprobe 타임스탬프·바이너리 대조로 대신했고, 실재생은
tvOS 시뮬레이터·실기기(T2)에서 확인한다.

### 4-2. tvOS 시뮬레이터 실측 — Apple 재생 개시까지 (2026-10-16~17, VerifyApp 하니스)

macOS의 헤드리스 AVFoundation 제약(로컬 mp4도 status=0)을 피해, tvOS 26.5 시뮬레이터에
최소 UIKit 앱(VerifyApp)을 올려 실제 앱 소스(TSMuxer+LocalHLSServer+SOOPNativeReceiver)를
그대로 링크해 검증했다. 판정 기준: readyToPlay 또는 currentTime 전진.

**격리 실험 결과:**

| 실험 | 결과 |
|------|------|
| ffmpeg 라이브 HLS(외부 서버) | PASS — 환경 정상 |
| ffmpeg 세그 + 우리 LocalHLSServer 중계 | **PASS — 서버 무죄** |
| ffmpeg ES + 우리 TSMuxer | FAIL(-12976) → 수정 후 **PASS** — 먹서가 범인 |
| 실SOOP 1080p(B-frame) 수신 → 먹서 → 서버 → AVPlayer | **PASS — 전 파이프라인 실증** |

**추가로 발견·수정한 결함 7건 (M5~M11):**

| # | 결함 | 증상 | 수정 |
|---|------|------|------|
| M5 | PAT의 PMT_PID 상위 마스크 `&0x0f`가 0x1000의 비트를 절단 | PMT_PID가 0x000으로 인코딩 — CoreMedia -12971 | `&0x1f` |
| M6 | PAT/PMT payload와 wrap()에 pointer_field 이중 삽입 | 섹션 1바이트 밀림 | payload 쪽 제거 |
| M7 | PMT ES_PID 상위바이트 reserved(111) 미부여 | 0x01 → ffmpeg는 통과, Apple -12976 | `0xe0 \|` 마스크 |
| M8 | LocalHLSServer MEDIA-SEQUENCE가 노출 창(6)과 무관하게 maxKept(12)까지 고정 | 같은 MEDIA-SEQUENCE의 엔트리 변경 → Apple -12312(URL not match) | 노출 창과 base 진행 동기화 |
| M9 | SOOPNativeReceiver keep-alive 타이머가 GCD 큐 스레드 RunLoop에 부착(발동 0회) | 서버가 초기 3세그 버스트 후 연결 종료 — 실서버 20초 뒤 cancel 실측 | DispatchSourceTimer로 교체 |
| M10 | 오디오 PES를 도착 순서로 세그 뒤쪽에 몰아 배치(첫 묶음 PTS 0.0초가 비디오 1.4초 뒤) | ffmpeg/Apple dts 역전 | pendingAudio 버퍼 + feedVideo 시각 interleave, 세그 시작보다 이른 오디오 폐기 |
| M11 | **B-frame 없는 프레임에도 PTS+DTS 강제 기재** | Apple mpeg2parser가 트랙 파싱 직후 **-12976**으로 재생 불가 — 이것이 핵심 결함 | `cts≠0`(B-frame)일 때만 PTS+DTS, 아니면 PTS만(ffmpeg muxer와 동일) |

부가 수정: PES_packet_length 16bit 오버플로(1080p IDR >65,535B → plen=0 미지정),
비디오 PES 전부 plen=0 통일, 세그마다 PCR 삽입(PMT가 PCR_PID 선언), SDT 추가,
EXTINF를 세그 실측 길이로(1080p60은 keyint 2초), 비디오 dts 1틱 역전 보정,
TS 잔여 공간 0xFF stuffing(M1) 및 afc=0 방지(M2).

### 4-3. 대기 중 항목

- 실기기(T2~T7) — §7 체크리스트
- 설정 탭 3카드 UI(T1) — 구현 완료, 실기기 확인 대기

---

## 5. 푸시 · 머지

(검증 후)

---

## 6. 실기기 설치

(설치 후)

---

## 7. 수동 테스트 체크리스트

| ID | 절차 | 기대 |
|----|------|------|
| T1 | 설정 탭 → 네이티브 카드 표시·포커스·선택 | 3카드 모두 라벨·설명·체크 노출 |
| T2 | 네이티브 선택 → 공개 방송 재생 | 프리롤 "원본 연결 중…" 후 1080p(원본) 재생 |
| T3 | 네이티브 재생 중 화질 메뉴 | '네이티브 원본' 행 + 현재 해상도 |
| T4 | 네이티브 재생 몇 분 시청 | 화질 저하 없음(원본 고정) |
| T5 | 네이티브로 두고 서버 죽는 방송(강제 종료 등) | 16초 내 CDN 자동 폴백 + 토스트 |
| T6 | 네이티브 모드에서 19+/비번방/구독방 진입 시도 | 네이티브 시도 없이 기존 CDN/인증 경로 유지 |
| T7 | 설정 auto/fixed로 되돌리고 재생 | 기존 동작 회귀 없음 |

## 8. 프로세스 기록

| 시각 | 단계 | 내용 |
|------|------|------|
| (기록 중) | | |
