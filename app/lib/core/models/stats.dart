import 'package:flutter/foundation.dart';

// ============================================================
// Stats 模型 —— 对照 docs/API.md GET /api/stats、saas-hub aggregateDevices。
// 手写 fromJson(无 freezed,GOAL.md 约定)。所有字段缺省安全回落:
//   null/类型不符 → 默认值,绝不抛(网络数据脏,UI 不能崩)。
//
// 覆盖范围(M1 Task 7 首页 + 设备 + 配额):
//   StatsSnapshot:顶层聚合(periods + devices + historyPreview + limits + 元信息)
//   Period:today/month/allTime 的总量与分项(client/model breakdown)
//   DeviceRecord:单设备明细
//   HistoryPreview/HistoryDay/HistoryMonth/HistorySummary:历史序列(热力图 + 趋势)
//   LimitsAgg/LimitsProvider/LimitsWindow:配额(预警卡 + 配额页)
// ============================================================

// ---- 通用数值工具:JSON 里的 number 可能是 int/double/String/null ----
int _toInt(dynamic v, [int d = 0]) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? d;
  return d;
}

double _toDouble(dynamic v, [double d = 0]) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? d;
  return d;
}

String _toStr(dynamic v, [String d = '']) =>
    v is String ? v : (v == null ? d : v.toString());
bool _toBool(dynamic v, [bool d = false]) => v is bool ? v : d;

Map<String, dynamic> _toMap(dynamic v) => v is Map<String, dynamic>
    ? v
    : (v is Map ? v.cast<String, dynamic>() : const {});

List<dynamic> _toList(dynamic v) => v is List ? v : const [];

// 一个时间段的用量:总量 + 按 client/model 的分项。
// clients/clientCosts/models/modelCosts/cache/clientModels 都是 {name: value} 映射。
@immutable
class Period {
  const Period({
    this.totalTokens = 0,
    this.costUsd = 0,
    this.clients = const {},
    this.clientCosts = const {},
    this.models = const {},
    this.modelCosts = const {},
    this.clientCacheReads = const {},
    this.clientCacheWrites = const {},
    this.clientOutputs = const {},
    this.clientModels = const {},
    this.modelCacheReads = const {},
    this.modelCacheWrites = const {},
    this.modelOutputs = const {},
  });

  final int totalTokens;
  final double costUsd;
  final Map<String, int> clients; // client → token 数
  final Map<String, double> clientCosts; // client → 花费
  final Map<String, int> models; // model → token 数
  final Map<String, double> modelCosts; // model → 花费
  // 缓存明细(展开行用):client/model → token 数
  final Map<String, int> clientCacheReads; // 输入·命中
  final Map<String, int> clientCacheWrites; // 缓存写入
  final Map<String, int> clientOutputs; // 输出
  final Map<String, Map<String, int>>
  clientModels; // client → {model → tokens}(主力模型)
  final Map<String, int> modelCacheReads;
  final Map<String, int> modelCacheWrites;
  final Map<String, int> modelOutputs;

  factory Period.fromJson(dynamic v) {
    final m = _toMap(v);
    return Period(
      totalTokens: _toInt(m['totalTokens']),
      costUsd: _toDouble(m['costUsd']),
      clients: _intMap(m['clients']),
      clientCosts: _doubleMap(m['clientCosts']),
      models: _intMap(m['models']),
      modelCosts: _doubleMap(m['modelCosts']),
      clientCacheReads: _intMap(m['clientCacheReads']),
      clientCacheWrites: _intMap(m['clientCacheWrites']),
      clientOutputs: _intMap(m['clientOutputs']),
      clientModels: _nestedIntMap(m['clientModels']),
      modelCacheReads: _intMap(m['modelCacheReads']),
      modelCacheWrites: _intMap(m['modelCacheWrites']),
      modelOutputs: _intMap(m['modelOutputs']),
    );
  }

  static Map<String, int> _intMap(dynamic v) {
    final m = _toMap(v);
    return m.map((k, val) => MapEntry(k, _toInt(val)));
  }

  static Map<String, double> _doubleMap(dynamic v) {
    final m = _toMap(v);
    return m.map((k, val) => MapEntry(k, _toDouble(val)));
  }

  // 嵌套 {client: {model: tokens}} 映射(脏数据容错)。
  static Map<String, Map<String, int>> _nestedIntMap(dynamic v) {
    final m = _toMap(v);
    return m.map((k, val) {
      final inner = _toMap(val);
      return MapEntry(k, inner.map((mk, mv) => MapEntry(mk, _toInt(mv))));
    });
  }
}

// 顶层聚合的三个时段。
@immutable
class Periods {
  const Periods({this.today, this.month, this.allTime});
  final Period? today;
  final Period? month;
  final Period? allTime;

  factory Periods.fromJson(dynamic v) {
    final m = _toMap(v);
    return Periods(
      today: m['today'] == null ? null : Period.fromJson(m['today']),
      month: m['month'] == null ? null : Period.fromJson(m['month']),
      allTime: m['allTime'] == null ? null : Period.fromJson(m['allTime']),
    );
  }
}

// ---- History(热力图 + 趋势)----
// historyPreview.daily 默认近 30 天,monthly 近 12 月(src/shared/history.js)。

@immutable
class HistoryBucket {
  const HistoryBucket({this.tokens = 0, this.cost = 0});
  final int tokens;
  final double cost;

  factory HistoryBucket.fromJson(dynamic v) {
    final m = _toMap(v);
    return HistoryBucket(
      tokens: _toInt(m['tokens']),
      cost: _toDouble(m['cost']),
    );
  }
}

Map<String, HistoryBucket> _historyBucketMap(dynamic v) {
  final m = _toMap(v);
  return m.map((k, val) => MapEntry(k, HistoryBucket.fromJson(val)));
}

@immutable
class HistoryDay {
  const HistoryDay({
    this.date = '',
    this.tokens = 0,
    this.cost = 0,
    this.activeTimeMs = 0,
    this.perClient = const {},
    this.perModel = const {},
  });
  final String date; // 'YYYY-MM-DD'
  final int tokens;
  final double cost;
  final int activeTimeMs;
  final Map<String, HistoryBucket> perClient;
  final Map<String, HistoryBucket> perModel;

  factory HistoryDay.fromJson(dynamic v) {
    final m = _toMap(v);
    return HistoryDay(
      date: _toStr(m['date']),
      tokens: _toInt(m['tokens']),
      cost: _toDouble(m['cost']),
      activeTimeMs: _toInt(m['activeTimeMs']),
      perClient: _historyBucketMap(m['perClient']),
      perModel: _historyBucketMap(m['perModel']),
    );
  }
}

@immutable
class HistoryMonth {
  const HistoryMonth({
    this.month = '',
    this.tokens = 0,
    this.cost = 0,
    this.activeTimeMs = 0,
    this.perClient = const {},
    this.perModel = const {},
  });
  final String month; // 'YYYY-MM'
  final int tokens;
  final double cost;
  final int activeTimeMs;
  final Map<String, HistoryBucket> perClient;
  final Map<String, HistoryBucket> perModel;

  factory HistoryMonth.fromJson(dynamic v) {
    final m = _toMap(v);
    return HistoryMonth(
      month: _toStr(m['month']),
      tokens: _toInt(m['tokens']),
      cost: _toDouble(m['cost']),
      activeTimeMs: _toInt(m['activeTimeMs']),
      perClient: _historyBucketMap(m['perClient']),
      perModel: _historyBucketMap(m['perModel']),
    );
  }
}

@immutable
class HistorySummary {
  const HistorySummary({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.activeDays = 0,
    this.totalTokens = 0,
    this.totalCost = 0,
  });
  final int currentStreak;
  final int longestStreak;
  final int activeDays;
  final int totalTokens;
  final double totalCost;

  factory HistorySummary.fromJson(dynamic v) {
    final m = _toMap(v);
    return HistorySummary(
      currentStreak: _toInt(m['currentStreak']),
      longestStreak: _toInt(m['longestStreak']),
      activeDays: _toInt(m['activeDays']),
      totalTokens: _toInt(m['totalTokens']),
      totalCost: _toDouble(m['totalCost']),
    );
  }
}

@immutable
class HistoryPreview {
  const HistoryPreview({
    this.daily = const [],
    this.monthly = const [],
    this.summary,
  });
  final List<HistoryDay> daily;
  final List<HistoryMonth> monthly;
  final HistorySummary? summary;

  factory HistoryPreview.fromJson(dynamic v) {
    final m = _toMap(v);
    return HistoryPreview(
      daily: _toList(m['daily']).map(HistoryDay.fromJson).toList(),
      monthly: _toList(m['monthly']).map(HistoryMonth.fromJson).toList(),
      summary: m['summary'] == null
          ? null
          : HistorySummary.fromJson(m['summary']),
    );
  }
}

// ---- Limits(配额预警 + 配额页)----
// limits.providers[].windows[]:百分比型(usedPercent)或信用型(metric:'credits',remaining=金额)。
// M1 首页只处理百分比型(usedPercent + resetsAt),信用型留后续(limitBalanceDisplay)。

@immutable
class LimitsWindow {
  const LimitsWindow({
    this.kind = '',
    this.label,
    this.title,
    this.usedPercent = 0,
    this.remainingPercent = 0,
    this.resetsAt = '',
    this.windowMinutes,
    this.resetDescription,
    this.metric,
    this.remaining,
    this.used,
    this.limit,
    this.currency,
    this.showMeter = true,
    this.detail,
  });
  final String kind; // 'session' / 'weekly' / 'billing' / …
  final String? label; // 展示标签(如 Total / Auto / 5-hour)
  final String? title; // 兼容旧字段
  final int usedPercent; // 0..100(百分比型)
  final int remainingPercent;
  final String resetsAt; // ISO 时间
  final int? windowMinutes; // 滚动窗口分钟数(如 300 = 5h)
  final String? resetDescription; // 无 resetsAt 时的说明
  final String? metric; // 'credits' = 余额型,'spend' = 消耗型
  final double? remaining; // 余额型:剩余金额
  final double? used; // 消耗型:已消耗金额
  final double? limit; // 消耗型:限额(有才画进度条)
  final String? currency; // 绝对金额的货币
  final bool showMeter; // false = 不画进度条(如 Claude credits)
  final String? detail; // 可选说明小字

  bool get isCredits => metric == 'credits';
  bool get isSpend => metric == 'spend';

  factory LimitsWindow.fromJson(dynamic v) {
    final m = _toMap(v);
    return LimitsWindow(
      kind: _toStr(m['kind']),
      label: _optionalStr(m['label'] ?? m['displayLabel'] ?? m['title']),
      title: _optionalStr(m['title']),
      usedPercent: _toInt(m['usedPercent']),
      remainingPercent: _toInt(m['remainingPercent']),
      resetsAt: _toStr(m['resetsAt']),
      windowMinutes: _optionalInt(
        m['windowMinutes'] ?? m['window_minutes'] ?? m['windowDurationMins'],
      ),
      resetDescription: _optionalStr(m['resetDescription']),
      metric: m['metric'] is String ? m['metric'] as String : null,
      remaining: m['remaining'] == null ? null : _toDouble(m['remaining']),
      used: m['used'] == null ? null : _toDouble(m['used']),
      limit: m['limit'] == null ? null : _toDouble(m['limit']),
      currency: m['currency'] is String ? m['currency'] as String : null,
      showMeter: m['showMeter'] is bool ? m['showMeter'] as bool : true,
      detail: m['detail'] is String ? m['detail'] as String : null,
    );
  }
}

@immutable
class LimitsProvider {
  const LimitsProvider({
    this.provider = '',
    this.status = '',
    this.source,
    this.accountKey,
    this.accountIdentity,
    this.windows = const [],
    this.accountEmail,
    this.accountName,
    this.accountLabel,
    this.planLabel,
    this.updatedAt,
  });
  final String provider; // claude/codex/cursor/…
  final String status; // 'ok' / 'warning' / 'exceeded' / 'unknown'
  final String? source; // 'oauth' / 'cli' / 'web' / 'rpc' / 'local' / 'api'
  final String? accountKey; // sha256:… 稳定账户标识
  final String? accountIdentity; // 可选跨设备稳定账户主体(新协议)
  final List<LimitsWindow> windows;
  final String? accountEmail;
  final String? accountName;
  final String? accountLabel; // 旧版 provider 短标签(兼容)
  final String? planLabel; // 显式套餐标签(Plus/Go/Zen)
  final String? updatedAt; // 该账户配额最后刷新时间

  factory LimitsProvider.fromJson(dynamic v) {
    final m = _toMap(v);
    return LimitsProvider(
      provider: _toStr(m['provider']),
      status: _toStr(m['status']),
      source: m['source'] is String ? m['source'] as String : null,
      accountKey: m['accountKey'] is String ? m['accountKey'] as String : null,
      accountIdentity: m['accountIdentity'] is String
          ? m['accountIdentity'] as String
          : null,
      windows: _toList(m['windows']).map(LimitsWindow.fromJson).toList(),
      accountEmail: m['accountEmail'] is String
          ? m['accountEmail'] as String
          : null,
      accountName: m['accountName'] is String
          ? m['accountName'] as String
          : null,
      accountLabel: m['accountLabel'] is String
          ? m['accountLabel'] as String
          : null,
      planLabel: m['planLabel'] is String ? m['planLabel'] as String : null,
      updatedAt: _optionalStr(m['updatedAt']),
    );
  }
}

String? _optionalStr(dynamic v) => v is String && v.isNotEmpty ? v : null;

int? _optionalInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

@immutable
class LimitsAgg {
  const LimitsAgg({this.updatedAt = '', this.providers = const []});
  final String updatedAt;
  final List<LimitsProvider> providers;

  factory LimitsAgg.fromJson(dynamic v) {
    final m = _toMap(v);
    return LimitsAgg(
      updatedAt: _toStr(m['updatedAt']),
      providers: _toList(m['providers']).map(LimitsProvider.fromJson).toList(),
    );
  }
}

// ---- DeviceRecord(单设备明细,设备页 + 首页设备数)----

@immutable
class DeviceRecord {
  const DeviceRecord({
    this.deviceId = '',
    this.hostname = '',
    this.platform = '',
    this.updatedAt = '',
    this.receivedAt = '',
    this.stale = false,
    this.osName,
    this.osVersion,
    this.agentVersion,
    this.agentRuntime,
    this.syncUploadIntervalMs,
    this.periods,
    this.limits,
  });
  final String deviceId;
  final String hostname;
  final String platform; // darwin-arm64 / win32-x64 / linux-x64 / ohos-arm64
  final String updatedAt; // 设备最后上报时间
  final String receivedAt; // hub 收到时间(判 stale 用)
  final bool stale;
  final String? osName;
  final String? osVersion;
  final String? agentVersion; // 采集器版本,如 "0.3.0"
  final String? agentRuntime; // "widget" / "headless-agent" / "embedded-hub"
  final int? syncUploadIntervalMs; // 0/缺省=实时,否则每 N 毫秒上报一次
  final Periods? periods; // 设备自己的 periods(未聚合)
  final LimitsAgg? limits;

  factory DeviceRecord.fromJson(dynamic v) {
    final m = _toMap(v);
    return DeviceRecord(
      deviceId: _toStr(m['deviceId']),
      hostname: _toStr(m['hostname']),
      platform: _toStr(m['platform']),
      updatedAt: _toStr(m['updatedAt']),
      receivedAt: _toStr(m['receivedAt']),
      stale: _toBool(m['stale']),
      osName: m['osName'] is String ? m['osName'] as String : null,
      osVersion: m['osVersion'] is String ? m['osVersion'] as String : null,
      agentVersion: m['agentVersion'] is String
          ? m['agentVersion'] as String
          : null,
      agentRuntime: m['agentRuntime'] is String
          ? m['agentRuntime'] as String
          : null,
      syncUploadIntervalMs: m['syncUploadIntervalMs'] is int
          ? m['syncUploadIntervalMs'] as int
          : null,
      periods: m['periods'] == null ? null : Periods.fromJson(m['periods']),
      limits: m['limits'] == null ? null : LimitsAgg.fromJson(m['limits']),
    );
  }
}

// ---- StatsSnapshot(GET /api/stats 顶层聚合)----

@immutable
class StatsSnapshot {
  const StatsSnapshot({
    this.staleAfterMs = 600000,
    this.subscriptionsUpdatedAt = '',
    this.notificationRulesUpdatedAt = '',
    this.periods,
    this.devices = const [],
    this.historyPreview,
    this.limits,
  });

  // staleAfterMs 默认 10 分钟(docs/API.md:默认 stale 阈值)
  final int staleAfterMs;
  // 订阅列表版本戳:空串/缺失 = "无变更"(GOAL.md §6.3.5)
  final String subscriptionsUpdatedAt;
  // SaaS 配额通知规则版本戳；缺失代表旧/自建 Hub，无需刷新规则文档。
  final String notificationRulesUpdatedAt;
  final Periods? periods; // 聚合后的 today/month/allTime
  final List<DeviceRecord> devices;
  final HistoryPreview? historyPreview;
  final LimitsAgg? limits; // 顶层聚合配额(按 account 合并)

  factory StatsSnapshot.fromJson(dynamic v) {
    final m = _toMap(v);
    return StatsSnapshot(
      staleAfterMs: _toInt(m['staleAfterMs'], 600000),
      subscriptionsUpdatedAt: _toStr(m['subscriptionsUpdatedAt']),
      notificationRulesUpdatedAt: _toStr(m['notificationRulesUpdatedAt']),
      periods: m['periods'] == null ? null : Periods.fromJson(m['periods']),
      devices: _toList(m['devices']).map(DeviceRecord.fromJson).toList(),
      historyPreview: m['historyPreview'] == null
          ? null
          : HistoryPreview.fromJson(m['historyPreview']),
      limits: m['limits'] == null ? null : LimitsAgg.fromJson(m['limits']),
    );
  }
}
