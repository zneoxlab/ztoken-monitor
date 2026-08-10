#!/usr/bin/env bash
# Android / iOS / Web 构建前:用标准 Flutter SDK 拉依赖。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
echo "ok: mobile/web dependencies resolved (standard Flutter)"
