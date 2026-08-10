#!/usr/bin/env bash
# 鸿蒙构建前:用 OpenHarmony Flutter SDK 拉依赖(写入 plugins.ohos)。
# Android / iOS / Web 请用标准 flutter pub get,勿混用。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_OHOS="${FLUTTER_OHOS:-/Users/xiaozhou/tools/flutter_ohos_3.41}"
cd "$ROOT"
"$FLUTTER_OHOS/bin/flutter" pub get
echo "ok: .flutter-plugins-dependencies now includes plugins.ohos"
