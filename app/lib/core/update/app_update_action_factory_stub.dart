import 'app_update_action_types.dart';

AppUpdateAction createAppUpdateAction() {
  return (_) async => const AppUpdateActionResult(
    status: AppUpdateActionStatus.unavailable,
    message: '当前平台尚未配置更新入口',
  );
}

AppUpdateAvailability createAppUpdateAvailability() {
  return (_) async => false;
}
