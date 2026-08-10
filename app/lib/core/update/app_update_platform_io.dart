import 'dart:io';

import '../app_version.dart';

({String operatingSystem, int currentBuild, bool supported})
readAppUpdatePlatform() {
  final operatingSystem = Platform.operatingSystem.toLowerCase();
  switch (operatingSystem) {
    case 'android':
    case 'ios':
      return (
        operatingSystem: operatingSystem,
        currentBuild: kAppBuildNumber,
        supported: true,
      );
    case 'ohos':
    case 'harmonyos':
      return (
        operatingSystem: 'ohos',
        currentBuild: kOhosBuildNumber,
        supported: true,
      );
    default:
      return (
        operatingSystem: operatingSystem,
        currentBuild: 0,
        supported: false,
      );
  }
}
