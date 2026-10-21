#!/bin/bash
# Release 빌드 → 고정 인증서로 재서명 → /Applications 교체 → 실행
# 같은 인증서로 서명하면 재빌드해도 손쉬운 사용 권한이 유지된다.
#   MALGEUL_SIGN_IDENTITY: 서명 인증서 이름/해시 (기본: 키체인의 첫 "Apple Development" 인증서)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Release/Malgeul.app"
DEST="/Applications/Malgeul.app"

IDENTITY="${MALGEUL_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "⚠ Apple Development 인증서가 없어 ad-hoc 서명합니다 (재빌드마다 권한 재허용 필요)" >&2
    IDENTITY="-"
fi

echo "▶ 빌드"
xcodebuild -project "$ROOT/Malgeul.xcodeproj" -scheme Malgeul -configuration Release \
    -derivedDataPath "$DERIVED" build -quiet

echo "▶ 서명: $IDENTITY"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Sources/Malgeul.entitlements" "$APP"
codesign --verify --strict "$APP"

echo "▶ 설치: $DEST"
pkill -x Malgeul 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "✓ 완료"
