#!/bin/bash
# Generate app/tasker/AppIcon.icns from the runtime icon drawing code.
# Requires: iconutil (Xcode CLT), swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/app/tasker"
cd "$APP_ROOT"

WORK="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$WORK"

swift run -c release iconGen "$WORK"

iconutil -c icns "$WORK" -o AppIcon.icns
echo "Wrote $APP_ROOT/AppIcon.icns"

rm -rf "$(dirname "$WORK")"
