enum AppUpdateDelivery { store, direct }

enum AppUpdateUrgency { none, optional, required }

final class PlatformUpdatePolicy {
  const PlatformUpdatePolicy({
    required this.enabled,
    required this.latestVersion,
    required this.latestBuild,
    required this.minimumBuild,
    required this.delivery,
    required this.updateUri,
    required this.sha256,
    required this.releaseNotes,
  });

  final bool enabled;
  final String latestVersion;
  final int latestBuild;
  final int minimumBuild;
  final AppUpdateDelivery delivery;
  final Uri? updateUri;
  final String sha256;
  final String releaseNotes;

  AppUpdateUrgency evaluateUpdate({required int currentBuild}) {
    if (!enabled || currentBuild >= latestBuild) {
      return AppUpdateUrgency.none;
    }
    if (currentBuild < minimumBuild) {
      return AppUpdateUrgency.required;
    }
    return AppUpdateUrgency.optional;
  }
}

final class AppUpdatePolicy {
  const AppUpdatePolicy._({
    required this.ios,
    required this.android,
    required this.ohos,
  });

  static const int supportedSchemaVersion = 1;

  final PlatformUpdatePolicy ios;
  final PlatformUpdatePolicy android;
  final PlatformUpdatePolicy ohos;

  factory AppUpdatePolicy.fromJson(
    Map<String, dynamic> json, {
    required Uri policyUri,
  }) {
    if (policyUri.scheme != 'https' || policyUri.host.isEmpty) {
      throw const FormatException('更新策略地址必须是 HTTPS');
    }
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != supportedSchemaVersion) {
      throw FormatException('不支持的更新策略版本: $schemaVersion');
    }

    return AppUpdatePolicy._(
      ios: _parsePlatform(json, 'ios', policyUri),
      android: _parsePlatform(json, 'android', policyUri),
      ohos: _parsePlatform(json, 'ohos', policyUri),
    );
  }

  PlatformUpdatePolicy? policyFor(String operatingSystem) {
    switch (operatingSystem.toLowerCase()) {
      case 'ios':
        return ios;
      case 'android':
        return android;
      case 'ohos':
      case 'harmonyos':
        return ohos;
      default:
        return null;
    }
  }

  static PlatformUpdatePolicy _parsePlatform(
    Map<String, dynamic> root,
    String key,
    Uri policyUri,
  ) {
    final raw = root[key];
    if (raw is! Map) {
      throw FormatException('$key 必须是对象');
    }
    final json = raw.map((entryKey, value) => MapEntry('$entryKey', value));
    final enabled = _requiredBool(json, 'enabled');
    final latestVersion = _requiredString(json, 'latestVersion');
    final latestBuild = _requiredInt(json, 'latestBuild');
    final minimumBuild = _requiredInt(json, 'minimumBuild');
    final deliveryName = _requiredString(json, 'delivery');
    final updateUrl = _requiredString(json, 'updateUrl', allowEmpty: !enabled);
    final releaseNotes = _requiredString(
      json,
      'releaseNotes',
      allowEmpty: true,
    );
    final sha256 = _optionalString(json, 'sha256').toLowerCase();

    if (latestBuild < 0 || minimumBuild < 0) {
      throw FormatException('$key 构建号不能为负数');
    }
    if (minimumBuild > latestBuild) {
      throw FormatException('$key minimumBuild 不能大于 latestBuild');
    }
    if (sha256.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw FormatException('$key sha256 必须是 64 位十六进制字符串');
    }

    final delivery = switch (deliveryName) {
      'store' => AppUpdateDelivery.store,
      'direct' => AppUpdateDelivery.direct,
      _ => throw FormatException('$key 不支持的交付方式: $deliveryName'),
    };

    Uri? updateUri;
    if (updateUrl.isNotEmpty) {
      updateUri = policyUri.resolve(updateUrl);
      if (updateUri.scheme != 'https' || updateUri.host.isEmpty) {
        throw FormatException('$key 更新地址必须是 HTTPS');
      }
      if (delivery == AppUpdateDelivery.direct &&
          updateUri.origin != policyUri.origin) {
        throw FormatException('$key 直装包必须与更新策略同源');
      }
    }

    return PlatformUpdatePolicy(
      enabled: enabled,
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      minimumBuild: minimumBuild,
      delivery: delivery,
      updateUri: updateUri,
      sha256: sha256,
      releaseNotes: releaseNotes,
    );
  }
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key 必须是布尔值');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key 必须是整数');
  return value;
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  bool allowEmpty = false,
}) {
  final value = json[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException('$key 必须是${allowEmpty ? '' : '非空'}字符串');
  }
  return value.trim();
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('$key 必须是字符串');
  return value.trim();
}
