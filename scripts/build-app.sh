#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-"$ROOT_DIR/dist/StarBar.app"}"

cd "$ROOT_DIR"
swift build -c release

BINARY_PATH="$(find "$ROOT_DIR/.build" \( -path '*/Release/StarBar' -o -path '*/release/StarBar' \) -type f | head -n 1)"

if [[ -z "$BINARY_PATH" ]]; then
  echo "Could not find built StarBar binary in .build" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/StarBar"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
