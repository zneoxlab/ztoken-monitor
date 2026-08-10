import 'app_update_policy.dart';

enum AppUpdateActionStatus { launched, permissionRequired, unavailable, failed }

final class AppUpdateActionResult {
  const AppUpdateActionResult({required this.status, this.message = ''});

  final AppUpdateActionStatus status;
  final String message;
}

typedef AppUpdateAction =
    Future<AppUpdateActionResult> Function(PlatformUpdatePolicy policy);

typedef AppUpdateAvailability =
    Future<bool> Function(PlatformUpdatePolicy policy);
