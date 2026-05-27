#!/bin/bash
# soop-app 빌드 스크립트
# Xcode가 있는 Mac에서 실행하세요

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛠️  soop-app tvOS 빌드"
echo "===================="

# 1. .env 확인
if [ ! -f .env ]; then
    echo "❌ .env 파일이 없습니다."
    echo "   .env.example을 복사해서 ID/비밀번호를 입력하세요:"
    echo "   cp .env.example .env"
    exit 1
fi

# .env 내용 검증
if grep -q "your_id\|your_password" .env; then
    echo "❌ .env에 기본값이 그대로 있습니다. ID와 비밀번호를 입력해주세요."
    exit 1
fi

echo "✅ .env 확인 완료"

# 2. Xcode 프로젝트 생성
echo ""
echo "📦 Xcode 프로젝트 생성 (xcodegen)..."
xcodegen generate
echo "✅ 프로젝트 생성 완료"

# 3. 빌드
echo ""
echo "🔨 tvOS 빌드 중..."
xcodebuild \
    -project soop-app.xcodeproj \
    -scheme soop-app \
    -destination "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)" \
    -configuration Debug \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO

echo ""
echo "===================="
echo "✅ 빌드 완료!"
echo ""
echo "📱 Apple TV 시뮬레이터에서 실행하려면:"
echo "   open soop-app.xcodeproj"
echo "   → Scheme: soop-app → Destination: Apple TV → ▶ Run"
echo ""
echo "📺 실제 Apple TV에 설치하려면:"
echo "   1. Apple TV → 설정 → 리모컨 및 기기 → 리모컨 앱 및 기기"
echo "   2. Mac과 Apple TV를 같은 Wi-Fi에 연결"
echo "   3. Xcode → Window → Devices and Simulators → Apple TV 선택 → Run"
