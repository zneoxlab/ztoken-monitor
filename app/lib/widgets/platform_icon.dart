import 'package:flutter/material.dart';

import '../theme/theme_extension.dart';
import 'provider_icon.dart';

String? platformIconAssetId(String platform, {String? osName}) {
  final p = platform.toLowerCase();
  final os = (osName ?? '').toLowerCase();
  if (p.contains('darwin') || p.contains('mac') || os.contains('mac')) return 'os-apple';
  if (p.contains('win') || os.contains('windows')) return 'os-windows';
  if (p.contains('linux') || p.contains('freebsd') || p.contains('openbsd') || os.contains('linux')) {
    return 'os-linux';
  }
  return null;
}

class PlatformIcon extends StatelessWidget {
  const PlatformIcon({super.key, required this.platform, this.osName, this.size = 34});

  final String platform;
  final String? osName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<AppThemeTokens>()!;
    final assetId = platformIconAssetId(platform, osName: osName);
    if (assetId != null && knownProviderIconIds.contains(assetId)) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: t.panel2, borderRadius: BorderRadius.circular(9)),
        alignment: Alignment.center,
        child: Image.asset(
          'assets/icons/$assetId.png',
          width: size * 0.62,
          height: size * 0.62,
          fit: BoxFit.contain,
        ),
      );
    }
    return _FallbackPlatformIcon(platform: platform, osName: osName, size: size);
  }
}

class _FallbackPlatformIcon extends StatelessWidget {
  const _FallbackPlatformIcon({required this.platform, required this.osName, required this.size});
  final String platform;
  final String? osName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _resolve();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.58, color: color),
    );
  }

  (IconData, Color) _resolve() {
    final p = platform.toLowerCase();
    final os = (osName ?? '').toLowerCase();
    if (p.contains('darwin') || p.contains('mac') || os.contains('mac')) {
      return (Icons.laptop_mac, const Color(0xFF9B8CF2));
    }
    if (p.contains('win') || os.contains('windows')) {
      return (Icons.laptop_windows, const Color(0xFF49A3B0));
    }
    if (p.contains('linux')) {
      return (Icons.computer_outlined, const Color(0xFF6BB6FF));
    }
    if (p.contains('ohos') || p.contains('harmony')) {
      return (Icons.phone_android, const Color(0xFFCC7C5E));
    }
    return (Icons.devices_other_outlined, const Color(0xFF7D8590));
  }
}
