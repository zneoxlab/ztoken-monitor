import 'app_update_platform_web.dart'
    if (dart.library.io) 'app_update_platform_io.dart'
    as implementation;

final class AppUpdatePlatformInfo {
  const AppUpdatePlatformInfo({
    required this.operatingSystem,
    required this.currentBuild,
    required this.supported,
  });

  final String operatingSystem;
  final int currentBuild;
  final bool supported;
}

AppUpdatePlatformInfo currentAppUpdatePlatform() {
  final raw = implementation.readAppUpdatePlatform();
  return AppUpdatePlatformInfo(
    operatingSystem: raw.operatingSystem,
    currentBuild: raw.currentBuild,
    supported: raw.supported,
  );
}
