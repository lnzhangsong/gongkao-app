// 单个应用的限用规则：独立时段 + 锁机时段叠加。
//
// 与整机锁定的区别：整机锁定占的是**整块屏幕**，人根本进不去任何应用；
// 应用限制管的是「某个应用在某个时段不许用」，即使整机没锁也照拦。
// 两者叠加的那条规则（duringLock）真正起作用的场景是**锁机时段内点了提前解锁**：
// 整机放行了，但这类应用仍然不许用。

import 'lock_schedule.dart';

/// 一条应用限用规则。
class AppLimit {
  const AppLimit({
    required this.package,
    required this.label,
    this.periods = const <LockPeriod>[],
    this.duringLock = true,
    this.locked = false,
  });

  /// 应用包名，如 `com.tencent.mm`。
  final String package;

  /// 展示名。原生侧查不到时回落到包名。
  final String label;

  /// 独立限用时段（与整机锁定时段无关）。
  final List<LockPeriod> periods;

  /// 整机锁定时段内是否也拦住它。
  ///
  /// 注意判据是「锁机时段本身」而不是「此刻是否已被锁住」：提前解锁后整机虽然
  /// 放行了，但在锁机时段内这类应用依然不该用。
  final bool duringLock;

  /// 是否给这一条单独上锁。
  ///
  /// 上锁后：**只要它正在限制中**，规则就不能改、不能删，锁也解不开；
  /// 不在限制时段里时可以正常修改。
  final bool locked;

  /// 命中后如何处理：交给原生侧 `pm disable-user` 直接禁用（需要 Shizuku），
  /// 没有 Shizuku 时降级成「点开再弹回桌面」。
  ///
  /// 早期版本这里还有一个「彻底停止」开关（无障碍跳应用详情页点「强行停止」）。
  /// 走 ADB 真正禁用之后它就没意义了——应用已经被禁用，进程自然也起不来，
  /// 而且那个方案每次都要闪一下系统设置页。现已移除。

  /// 至少有一条规则才算启用。
  bool get enabled => duringLock || periods.isNotEmpty;

  /// 规则摘要，用于列表副标题。
  String get summary {
    final List<String> parts = <String>[];
    if (periods.isNotEmpty) {
      parts.add(periods.map((LockPeriod p) => p.label).join('、'));
    }
    if (duringLock) parts.add('锁定时段内也拦');
    if (parts.isEmpty) return '未设置时段';
    return parts.join(' · ');
  }

  AppLimit copyWith({
    String? label,
    List<LockPeriod>? periods,
    bool? duringLock,
    bool? locked,
  }) =>
      AppLimit(
        package: package,
        label: label ?? this.label,
        periods: periods ?? this.periods,
        duringLock: duringLock ?? this.duringLock,
        locked: locked ?? this.locked,
      );

  /// 持久化格式：`包名|名称|是否叠加|480-720,900-1080|l`。
  ///
  /// 名称走 [Uri.encodeComponent]，应用名里带 `|` 也不会把格式拆坏。
  /// 末段 `l` 表示这条已上锁；更早的版本这一位存的是「彻底停止」(`1`)，
  /// 用不同字符区分，老数据不会被误读成已上锁。
  String encode() {
    final String name = Uri.encodeComponent(label);
    final String rules =
        periods.map((LockPeriod p) => p.encode()).join(',');
    return '$package|$name|${duringLock ? 1 : 0}|$rules|${locked ? 'l' : ''}';
  }

  /// 解析持久化串；格式不对返回 null（旧数据 / 脏数据一律丢弃）。
  static AppLimit? parse(String raw) {
    final List<String> parts = raw.split('|');
    if (parts.length < 3) return null;
    final String pkg = parts[0].trim();
    if (pkg.isEmpty) return null;
    final String decoded = _safeDecode(parts[1]);
    final List<LockPeriod> periods = <LockPeriod>[];
    if (parts.length > 3 && parts[3].isNotEmpty) {
      for (final String one in parts[3].split(',')) {
        final LockPeriod? p = LockPeriod.parse(one.trim());
        if (p != null) periods.add(p);
      }
    }
    // 旧版本在末尾多存了一段「彻底停止」（'1' 或 '0'），与这里的 'l' 不同，
    // 不会被误判成已上锁。
    return AppLimit(
      package: pkg,
      label: decoded.isEmpty ? pkg : decoded,
      periods: periods,
      duringLock: parts[2] == '1',
      locked: parts.length > 4 && parts[4] == 'l',
    );
  }

  static String _safeDecode(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }
}

/// 此刻该应用是否受限；受限则返回解除时刻（取最晚的一条），否则 null。
///
/// [lockEnd] 是**整机锁定时段**的解锁时刻（不受「提前解锁」影响）：
/// 提前解锁只放行整机，不该让这类应用跟着放行。
DateTime? appLimitEnd(
  AppLimit limit,
  DateTime now, {
  DateTime? lockEnd,
}) {
  DateTime? best;
  if (limit.duringLock && lockEnd != null) best = lockEnd;
  for (final LockPeriod p in limit.periods) {
    final DateTime? end = LockSchedule(<LockPeriod>[p]).activeEnd(now);
    if (end == null) continue;
    if (best == null || end.isAfter(best)) best = end;
  }
  return best;
}

/// 一组规则里此刻生效的那些：包名 → 解除时刻。
Map<String, DateTime> activeLimits(
  List<AppLimit> limits,
  DateTime now, {
  DateTime? lockEnd,
}) {
  final Map<String, DateTime> out = <String, DateTime>{};
  for (final AppLimit l in limits) {
    final DateTime? end = appLimitEnd(l, now, lockEnd: lockEnd);
    if (end != null) out[l.package] = end;
  }
  return out;
}
