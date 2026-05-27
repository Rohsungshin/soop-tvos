#!/bin/bash
# .env → 빌드产物 Resources에 복사
# 빌드 시 Xcode가 자동 실행

SRC_ENV="${SRCROOT}/.env"
DST_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [ -f "$SRC_ENV" ]; then
    cp "$SRC_ENV" "$DST_DIR/.env"
    echo "✅ .env → Resources 복사 완료"
else
    echo "⚠️ .env 파일 없음 — 로그인 정보 누락 가능"
fi
