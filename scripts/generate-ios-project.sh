#!/usr/bin/env bash
# Gera Companion.xcodeproj a partir de project.yml (requer XcodeGen).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/apps/ios"

find_xcodegen() {
  if command -v xcodegen >/dev/null 2>&1; then
    command -v xcodegen
    return
  fi
  if [[ -x /tmp/xcodegen-bin/xcodegen/bin/xcodegen ]]; then
    echo /tmp/xcodegen-bin/xcodegen/bin/xcodegen
    return
  fi
  return 1
}

if ! XCG="$(find_xcodegen)"; then
  echo "XcodeGen não encontrado."
  echo "  brew install xcodegen"
  echo "  ou baixe: https://github.com/yonaskolb/XcodeGen/releases"
  exit 1
fi

cd "$IOS"
"$XCG" generate
echo "OK → $IOS/Companion.xcodeproj"
echo "Abra no Xcode 15+ e selecione um simulador iPhone (iOS 16.2+)."
