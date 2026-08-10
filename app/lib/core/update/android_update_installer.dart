import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'app_update_action_types.dart';
import 'app_update_policy.dart';

typedef ApkDownloader =
    Future<void> Function(Uri source, String destinationPath);

final class AndroidUpdateInstaller {
  AndroidUpdateInstaller({MethodChannel? channel, ApkDownloader? downloader})
    : _channel = channel ?? const MethodChannel(_channelName),
      _downloader = downloader ?? _download;

  static const _channelName = 'com.zneox.ztoken_monitor/app_update';
  static const _apkFileName = 'zt-monitor-update.apk';

  final MethodChannel _channel;
  final ApkDownloader _downloader;

  Future<bool> supports(PlatformUpdatePolicy policy) async {
    if (policy.delivery != AppUpdateDelivery.direct ||
        policy.updateUri?.scheme != 'https' ||
        policy.sha256.length != 64) {
      return false;
    }
    try {
      return await _channel.invokeMethod<String>('getDistribution') ==
          'website';
    } catch (_) {
      return false;
    }
  }

  Future<AppUpdateActionResult> perform(PlatformUpdatePolicy policy) async {
    if (policy.delivery != AppUpdateDelivery.direct) {
      return const AppUpdateActionResult(
        status: AppUpdateActionStatus.unavailable,
        message: '当前版本请通过应用商店更新',
      );
    }
    final updateUri = policy.updateUri;
    if (updateUri == null ||
        updateUri.scheme != 'https' ||
        policy.sha256.length != 64) {
      return const AppUpdateActionResult(
        status: AppUpdateActionStatus.unavailable,
        message: '官网更新缺少有效的 HTTPS 地址或 SHA-256 校验值',
      );
    }

    try {
      final distribution = await _channel.invokeMethod<String>(
        'getDistribution',
      );
      if (distribution != 'website') {
        return const AppUpdateActionResult(
          status: AppUpdateActionStatus.unavailable,
          message: '应用商店版不支持直接安装 APK',
        );
      }

      final cacheDirectory = await _channel.invokeMethod<String>(
        'getCacheDirectory',
      );
      if (cacheDirectory == null || cacheDirectory.trim().isEmpty) {
        throw const FileSystemException('无法获取安全缓存目录');
      }
      final destination =
          '${cacheDirectory.replaceAll(RegExp(r'/+$'), '')}/'
          '$_apkFileName';
      await _downloader(updateUri, destination);

      final status = await _channel.invokeMethod<String>(
        'verifyAndInstallApk',
        {'path': destination, 'sha256': policy.sha256.toLowerCase()},
      );
      return switch (status) {
        'installerOpened' => const AppUpdateActionResult(
          status: AppUpdateActionStatus.launched,
          message: '已打开系统安装器',
        ),
        'permissionRequired' => const AppUpdateActionResult(
          status: AppUpdateActionStatus.permissionRequired,
          message: '请允许安装未知应用，然后再次点击更新',
        ),
        _ => const AppUpdateActionResult(
          status: AppUpdateActionStatus.failed,
          message: '系统安装器未能打开',
        ),
      };
    } on PlatformException catch (error) {
      final message = error.code == 'sha_mismatch'
          ? '安装包 SHA-256 校验失败，已停止安装'
          : '无法启动系统安装流程';
      return AppUpdateActionResult(
        status: AppUpdateActionStatus.failed,
        message: message,
      );
    } catch (_) {
      return const AppUpdateActionResult(
        status: AppUpdateActionStatus.failed,
        message: '安装包下载或处理失败，请稍后重试',
      );
    }
  }

  static Future<void> _download(Uri source, String destinationPath) async {
    final target = File(destinationPath);
    final partial = File('$destinationPath.part');
    await target.delete().catchError((_) => target);
    await partial.delete().catchError((_) => partial);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
        followRedirects: false,
      ),
    );
    try {
      await dio.downloadUri(source, partial.path, deleteOnError: true);
      await partial.rename(target.path);
    } finally {
      dio.close(force: true);
    }
  }
}
