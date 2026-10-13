import 'package:flutter/services.dart';

/// 单个应用当天使用记录。
class AppUsage {
  const AppUsage({
    required this.package,
    required this.label,
    required this.millis,
  });

  final String package;
  final String label;
  final int millis;

  Duration get duration => Duration(milliseconds: millis);
}

/// 单段前台使用记录（某 App 从 start 到 end 处于前台）。
class UsageSegment {
  const UsageSegment({
    required this.package,
    required this.label,
    required this.start,
    required this.end,
    required this.millis,
  });

  final String package;
  final String label;
  final int start;
  final int end;

  final int millis;

  Duration get duration => Duration(milliseconds: millis);
  DateTime get startAt => DateTime.fromMillisecondsSinceEpoch(start);
  DateTime get endAt => DateTime.fromMillisecondsSinceEpoch(end);
}

/// 读取系统「使用情况访问」统计（今日足迹）。
/// 需要用户在系统设置里手动授予特殊权限；未授权时 [hasPermission] 为 false。
class UsageStats {
  const UsageStats();

  static const MethodChannel _ch =
      MethodChannel('com.gongkao.gongkao_pad/usage');

  Future<bool> hasPermission() async {
    try {
      final bool? ok = await _ch.invokeMethod<bool>('hasPermission');
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _ch.invokeMethod<void>('openSettings');
    } on PlatformException {
      // 忽略：部分 ROM 可能无此设置页。
    }
  }

  Future<List<AppUsage>> today() async {
    try {
      final List<dynamic>? raw = await _ch.invokeMethod<List<dynamic>>('todayUsage');
      if (raw == null) return <AppUsage>[];
      return raw
          .cast<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => AppUsage(
                package: m['package'] as String? ?? '',
                label: m['label'] as String? ?? '',
                millis: (m['millis'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } on PlatformException {
      return <AppUsage>[];
    }
  }

  /// 今日前台切换时间线（按时间升序）。
  Future<List<UsageSegment>> timeline() async {
    try {
      final List<dynamic>? raw =
          await _ch.invokeMethod<List<dynamic>>('todayTimeline');
      if (raw == null) return <UsageSegment>[];
      return raw
          .cast<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> m) => UsageSegment(
                package: m['package'] as String? ?? '',
                label: m['label'] as String? ?? '',
                start: (m['start'] as num?)?.toInt() ?? 0,
                end: (m['end'] as num?)?.toInt() ?? 0,
                millis: (m['millis'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } on PlatformException {
      return <UsageSegment>[];
    }
  }
}
