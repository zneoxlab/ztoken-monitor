import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format/formatters.dart' show DisplayCurrency;
import '../limits/limit_display_mode.dart';
import '../../theme/theme_mode.dart' show AppThemeMode, AppMaterial;

// ============================================================
// 偏好存储 —— 主题 / 材质 / 显示货币 / 自建 Hub 本地通知回退。
// 用 shared_preferences:iOS/Android 官方 + 鸿蒙 SIG 适配包自动接管。
// 全部本地持久化,不随账户同步(GOAL.md §7)。
// 启动时异步加载已存值,变更时同步写盘。
// ============================================================

// 存储键常量:迁移视为兼容性表面。
class PrefsKeys {
  const PrefsKeys._();
  static const themeMode = 'ui.theme_mode'; // AppThemeMode.name
  static const material = 'ui.material'; // AppMaterial.name
  static const displayCurrency = 'ui.display_currency'; // DisplayCurrency.code
  static const notifyEnabled = 'notify.enabled';
  static const notifyThresholdPercent = 'notify.threshold_percent'; // int 0-100
  static const limitDisplayMode = 'limits.display_mode'; // remaining / used
  static const hubUrl = 'hub.url'; // Hub 地址,可改自建
  static const sseEnabled = 'sse.enabled'; // 实时推送开关,false 则降级轮询
  // 记住账号密码(用户主动勾选):本地明文存邮箱+密码,仅为免输便利。
  // 与凭证(token)分离:token 走 secure_storage,这里只存登录表单的预填值。
  static const rememberCredentials = 'auth.remember';
  static const savedEmail = 'auth.saved_email';
  static const savedPassword = 'auth.saved_password';
  static const limitProviderOrder = 'limits.provider_order';
  // Android/Harmony 桌面小组件固定展示的额度账户(limitEntryKey,最多 2 个)。
  // 空串表示按风险智能选择；新增键必须保持旧版本缺失时的默认行为。
  static const homeWidgetPinnedLimits = 'home_widget.pinned_limits';
  static const appUpdateLastCheckAt = 'app_update.last_check_at';
  // 最近处理过的服务端通知事件，避免冷启动事件与前台回调重复跳转。
  static const handledPushEventIds = 'push.handled_event_ids';
}

// 默认 Hub 地址:SaaS 云端(GOAL.md §6.0)。
const kDefaultHubUrl = 'https://token-hub.zneox.com';

// 全部应用设置。notify* 仅供自建 Hub 的旧本地差分提醒兼容；SaaS 使用
// notification_rules 文档，不再把这个全局默认当作用户授权。
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.material = AppMaterial.solid,
    this.displayCurrency = DisplayCurrency.usd,
    this.notifyEnabled = true,
    this.notifyThresholdPercent = 80,
    this.limitDisplayMode = LimitDisplayMode.remaining,
    this.hubUrl = kDefaultHubUrl,
    this.sseEnabled = true, // 实时推送默认开,false 降级轮询
    this.rememberCredentials = true, // 默认记住账号密码(登录态保持便利)
    this.savedEmail = '',
    this.savedPassword = '',
    this.limitProviderOrder = '',
    this.homeWidgetPinnedLimits = '',
  });

  final AppThemeMode themeMode;
  final AppMaterial material;
  final DisplayCurrency displayCurrency;
  final bool notifyEnabled;
  final int notifyThresholdPercent; // 配额剩余低于此百分比时本地提醒
  final LimitDisplayMode limitDisplayMode; // 配额百分比显示“剩余”或“已用”
  final String hubUrl; // Hub 地址,默认 SaaS 云端,可改自建(GOAL.md §6.0)
  final bool sseEnabled; // 实时推送开关,false 降级 60s 轮询
  final bool rememberCredentials; // 是否记住账号密码(登录表单预填)
  final String savedEmail; // 记住的邮箱(rememberCredentials=true 时有效)
  final String savedPassword; // 记住的密码(明文,同 OS 用户可读)
  final String limitProviderOrder; // 配额列表拖拽顺序(逗号分隔 entry key)
  final String homeWidgetPinnedLimits; // 桌面小组件固定额度账户,空=智能选择

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppMaterial? material,
    DisplayCurrency? displayCurrency,
    bool? notifyEnabled,
    int? notifyThresholdPercent,
    LimitDisplayMode? limitDisplayMode,
    String? hubUrl,
    bool? sseEnabled,
    bool? rememberCredentials,
    String? savedEmail,
    String? savedPassword,
    String? limitProviderOrder,
    String? homeWidgetPinnedLimits,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      material: material ?? this.material,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      notifyEnabled: notifyEnabled ?? this.notifyEnabled,
      notifyThresholdPercent:
          notifyThresholdPercent ?? this.notifyThresholdPercent,
      limitDisplayMode: limitDisplayMode ?? this.limitDisplayMode,
      hubUrl: hubUrl ?? this.hubUrl,
      sseEnabled: sseEnabled ?? this.sseEnabled,
      rememberCredentials: rememberCredentials ?? this.rememberCredentials,
      savedEmail: savedEmail ?? this.savedEmail,
      savedPassword: savedPassword ?? this.savedPassword,
      limitProviderOrder: limitProviderOrder ?? this.limitProviderOrder,
      homeWidgetPinnedLimits:
          homeWidgetPinnedLimits ?? this.homeWidgetPinnedLimits,
    );
  }

  // 序列化到 SharedPreferences:用枚举 name 字符串,可读且前向兼容。
  Map<String, Object> toPrefs() => {
    PrefsKeys.themeMode: themeMode.name,
    PrefsKeys.material: material.name,
    PrefsKeys.displayCurrency: displayCurrency.code,
    PrefsKeys.notifyEnabled: notifyEnabled,
    PrefsKeys.notifyThresholdPercent: notifyThresholdPercent,
    PrefsKeys.limitDisplayMode: limitDisplayMode.name,
    PrefsKeys.hubUrl: hubUrl,
    PrefsKeys.sseEnabled: sseEnabled,
    PrefsKeys.rememberCredentials: rememberCredentials,
    PrefsKeys.savedEmail: savedEmail,
    PrefsKeys.savedPassword: savedPassword,
    PrefsKeys.limitProviderOrder: limitProviderOrder,
    PrefsKeys.homeWidgetPinnedLimits: homeWidgetPinnedLimits,
  };

  // 反序列化:未知/缺失值回落默认(前向兼容旧版本)。
  static AppSettings fromPrefs(SharedPreferences prefs) {
    AppThemeMode parseThemeMode(String? v) {
      if (v == null) return AppThemeMode.system;
      for (final m in AppThemeMode.values) {
        if (m.name == v) return m;
      }
      return AppThemeMode.system;
    }

    AppMaterial parseMaterial(String? v) {
      if (v == null) return AppMaterial.solid;
      for (final m in AppMaterial.values) {
        if (m.name == v) return m;
      }
      return AppMaterial.solid;
    }

    return AppSettings(
      themeMode: parseThemeMode(prefs.getString(PrefsKeys.themeMode)),
      material: parseMaterial(prefs.getString(PrefsKeys.material)),
      displayCurrency: DisplayCurrency.fromCode(
        prefs.getString(PrefsKeys.displayCurrency),
      ),
      notifyEnabled: prefs.getBool(PrefsKeys.notifyEnabled) ?? true,
      notifyThresholdPercent:
          prefs.getInt(PrefsKeys.notifyThresholdPercent) ?? 80,
      limitDisplayMode: parseLimitDisplayMode(
        prefs.getString(PrefsKeys.limitDisplayMode),
      ),
      hubUrl: prefs.getString(PrefsKeys.hubUrl) ?? kDefaultHubUrl,
      sseEnabled: prefs.getBool(PrefsKeys.sseEnabled) ?? true,
      rememberCredentials: prefs.getBool(PrefsKeys.rememberCredentials) ?? true,
      savedEmail: prefs.getString(PrefsKeys.savedEmail) ?? '',
      savedPassword: prefs.getString(PrefsKeys.savedPassword) ?? '',
      limitProviderOrder: prefs.getString(PrefsKeys.limitProviderOrder) ?? '',
      homeWidgetPinnedLimits:
          prefs.getString(PrefsKeys.homeWidgetPinnedLimits) ?? '',
    );
  }
}

// 设置 Notifier:持有当前 AppSettings,变更时持久化。
// 启动时由 settingsInitProvider 异步加载首帧;之后所有 setX 同步更新状态 + 写盘。
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._prefs) : super(const AppSettings());

  final SharedPreferences _prefs;

  // 启动加载:从磁盘恢复已存设置。在 settingsInitProvider 中调用。
  Future<void> load() async {
    state = AppSettings.fromPrefs(_prefs);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(PrefsKeys.themeMode, mode.name);
  }

  Future<void> setMaterial(AppMaterial material) async {
    state = state.copyWith(material: material);
    await _prefs.setString(PrefsKeys.material, material.name);
  }

  Future<void> setDisplayCurrency(DisplayCurrency currency) async {
    state = state.copyWith(displayCurrency: currency);
    await _prefs.setString(PrefsKeys.displayCurrency, currency.code);
  }

  Future<void> setNotifyEnabled(bool enabled) async {
    state = state.copyWith(notifyEnabled: enabled);
    await _prefs.setBool(PrefsKeys.notifyEnabled, enabled);
  }

  Future<void> setNotifyThresholdPercent(int percent) async {
    final clamped = percent.clamp(1, 100);
    state = state.copyWith(notifyThresholdPercent: clamped);
    await _prefs.setInt(PrefsKeys.notifyThresholdPercent, clamped);
  }

  Future<void> setLimitDisplayMode(LimitDisplayMode mode) async {
    state = state.copyWith(limitDisplayMode: mode);
    await _prefs.setString(PrefsKeys.limitDisplayMode, mode.name);
  }

  Future<void> setHubUrl(String url) async {
    final trimmed = url.trim();
    // 去掉末尾斜杠,避免 baseUrl 拼接出双斜杠
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    state = state.copyWith(
      hubUrl: normalized.isEmpty ? kDefaultHubUrl : normalized,
    );
    await _prefs.setString(PrefsKeys.hubUrl, state.hubUrl);
  }

  // 实时推送开关:off 时 sseClient 降级为 60s 轮询(下次连接生效)。
  Future<void> setSseEnabled(bool enabled) async {
    state = state.copyWith(sseEnabled: enabled);
    await _prefs.setBool(PrefsKeys.sseEnabled, enabled);
  }

  // 记住账号密码开关:关掉时同时清掉已存的邮箱+密码。
  Future<void> setRememberCredentials(bool enabled) async {
    state = state.copyWith(rememberCredentials: enabled);
    await _prefs.setBool(PrefsKeys.rememberCredentials, enabled);
    if (!enabled) {
      state = state.copyWith(savedEmail: '', savedPassword: '');
      await _prefs.remove(PrefsKeys.savedEmail);
      await _prefs.remove(PrefsKeys.savedPassword);
    }
  }

  // 保存登录表单的邮箱+密码(rememberCredentials=true 时由登录页调用)。
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    if (!state.rememberCredentials) return;
    state = state.copyWith(savedEmail: email, savedPassword: password);
    await _prefs.setString(PrefsKeys.savedEmail, email);
    await _prefs.setString(PrefsKeys.savedPassword, password);
  }

  Future<void> setLimitProviderOrder(String order) async {
    state = state.copyWith(limitProviderOrder: order);
    await _prefs.setString(PrefsKeys.limitProviderOrder, order);
  }

  Future<void> setHomeWidgetPinnedLimits(String entries) async {
    final normalized = entries
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .join(',');
    state = state.copyWith(homeWidgetPinnedLimits: normalized);
    if (normalized.isEmpty) {
      await _prefs.remove(PrefsKeys.homeWidgetPinnedLimits);
    } else {
      await _prefs.setString(PrefsKeys.homeWidgetPinnedLimits, normalized);
    }
  }
}

// SharedPreferences 实例 provider:同步可用。
// main() 在 runApp 前 await 初始化并通过 ProviderScope.overrides 注入,
// 故此处直接 read;测试时同样 override 注入 mock 实例。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError('sharedPreferencesProvider 未注入:main() 应 override 注入已初始化实例');
});

// SettingsNotifier provider:依赖 SharedPreferences(已就绪),创建并 load。
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final notifier = SettingsNotifier(prefs);
  // 创建后立即加载已存值(异步,加载完触发状态更新)
  notifier.load();
  return notifier;
});
