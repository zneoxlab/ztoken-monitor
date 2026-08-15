'use strict';

// electron-builder writes the marketing version into LSMinimumSystemVersion,
// while electron-updater compares update metadata against Darwin's os.release().
// 本分支未引入 macOS WidgetKit，因此不包含上游的 Widget 最低版本常量与运行时判断。
const MAC_APP_MIN_VERSION = '12.0';
const MAC_APP_MIN_DARWIN_VERSION = '21.0.0';

module.exports = {
  MAC_APP_MIN_DARWIN_VERSION,
  MAC_APP_MIN_VERSION
};
