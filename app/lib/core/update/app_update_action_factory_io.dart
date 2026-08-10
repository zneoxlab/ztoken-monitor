import 'dart:io';

import 'android_update_installer.dart';
import 'app_update_action_types.dart';

AppUpdateAction createAppUpdateAction() {
  if (Platform.isAndroid) {
    return AndroidUpdateInstaller().perform;
  }
  return (_) async => const AppUpdateActionResult(
    status: AppUpdateActionStatus.unavailable,
    message: '当前平台尚未配置更新入口',
  );
}

AppUpdateAvailability createAppUpdateAvailability() {
  if (Platform.isAndroid) {
    return AndroidUpdateInstaller().supports;
  }
  return (_) async => false;
}
