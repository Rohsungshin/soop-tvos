# 📺 soop-app — SOOP Live tvOS Browser

Apple TV에서 [SOOP Live (구 아프리카TV)](https://www.sooplive.com/)를 시청하기 위한 tvOS 브라우저 앱입니다.

## 기능

- 🔐 자동 로그인 — `.env`에 ID/비밀번호 저장 후 시스템 브라우저로 SOOP 접속
- 📺 ASWebAuthenticationSession — tvOS 17.4+ 시스템 브라우저 활용
- 🎮 Siri Remote 지원 — Select(접속), Menu(홈), Play/Pause(새로고침)

## 제한사항

> ⚠️ tvOS에는 WebKit 프레임워크가 없어 WKWebView를 사용할 수 없습니다.
> 대신 `ASWebAuthenticationSession`으로 시스템 브라우저를 띄워 SOOP에 접속합니다.
> 쿠키가 유지되므로 첫 로그인 후에는 자동 인증됩니다.

## 사용 방법

### 1. `.env`에 SOOP 계정 정보 입력
```bash
SOOP_ID=본인ID
SOOP_PASSWORD=본인비번
```

### 2. 빌드
```bash
cd /Volumes/MacMiniUsb/soop-app
xcodegen generate
open soop-app.xcodeproj
```

### 3. Xcode에서 실행
- Scheme: `soop-app`
- Destination: `Apple TV 4K (3rd generation)` (시뮬레이터) 또는 실기기
- ▶ Run

### 4. Apple TV 리모컨 조작
| 버튼 | 동작 |
|------|------|
| Select | SOOP 접속 |
| Menu | 홈으로 |
| Play/Pause | 새로고침 |

## 프로젝트 구조
```
soop-app/
├── soop-app/
│   ├── AppDelegate.swift           # 엔트리 포인트
│   ├── TVBrowserViewController.swift  # tvOS 메인 브라우저
│   ├── iOSViewController.swift     # iOS WKWebView 브라우저 (예비)
│   ├── LoginManager.swift          # .env 자격증명 관리 + JS 자동로그인
│   ├── OverlayView.swift           # iOS URL 오버레이
│   ├── Info.plist
│   ├── soop-app.entitlements
│   └── Assets.xcassets/
├── scripts/
│   └── copy-env.sh                # .env → Bundle 복사
├── project.yml                     # xcodegen 설정
├── .env                            # 자격증명 (gitignore)
└── .env.example                    # 템플릿
```

## 빌드 환경
- Xcode 26.5+
- tvOS 17.4+ (ASWebAuthenticationSession 필요)
- xcodegen (프로젝트 생성)
