// 锁定时段的纯逻辑：解析、格式化、判断此刻是否锁定、求下一次状态切换。
// 不依赖 Flutter 与 Settings，手机端页面与返回键逻辑共用同一套判定。

/// 一天的总分钟数。
const int kDayMinutes = 24 * 60;

/// 一条锁定时段，起止均为当日分钟数（0..1439）。
/// - `start == end` 视为「全天锁定」；
/// - `end < start` 视为跨午夜（如 22:00 → 次日 06:00）。
class LockPeriod {
  const LockPeriod({required this.start, required this.end});

  final int start;
  final int end;

  bool get isAllDay => start == end;
  bool get crossesMidnight => end < start;

  /// 该段持续的分钟数（跨午夜与全天都按环形计算）。
  int get durationMinutes {
    if (isAllDay) return kDayMinutes;
    final int d = (end - start) % kDayMinutes;
    return d == 0 ? kDayMinutes : d;
  }

  /// 解析持久化格式 "480-720"；非法返回 null。
  static LockPeriod? parse(String raw) {
    final List<String> parts = raw.split('-');
    if (parts.length != 2) return null;
    final int? a = int.tryParse(parts[0]);
    final int? b = int.tryParse(parts[1]);
    if (a == null || b == null) return null;
    if (a < 0 || a >= kDayMinutes || b < 0 || b >= kDayMinutes) return null;
    return LockPeriod(start: a, end: b);
  }

  String encode() => '$start-$end';

  LockPeriod copyWith({int? start, int? end}) =>
      LockPeriod(start: start ?? this.start, end: end ?? this.end);

  /// 展示文案："08:00 → 12:00" / "22:00 → 次日 06:00" / "全天"。
  String get label {
    if (isAllDay) return '全天';
    final String tail =
        crossesMidnight ? '次日 ${fmtMinute(end)}' : fmtMinute(end);
    return '${fmtMinute(start)} → $tail';
  }

  /// 以「某天的 0 点」为锚，算出该段的开始时刻。
  DateTime startOn(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(Duration(minutes: start));

  /// 该段的结束时刻（跨午夜自然落到次日）。
  DateTime endOn(DateTime day) =>
      startOn(day).add(Duration(minutes: durationMinutes));
}

/// 一组时段构成的日程表。
class LockSchedule {
  const LockSchedule(this.periods);

  final List<LockPeriod> periods;

  bool get isEmpty => periods.isEmpty;

  /// 此刻生效中、且**结束最晚**的那一段（决定解锁时刻）。
  ({DateTime start, DateTime end})? activeWindow(DateTime now) {
    ({DateTime start, DateTime end})? best;
    for (final LockPeriod p in periods) {
      // 跨午夜/全天会跨日，前后各看一天即可覆盖。
      for (int offset = -1; offset <= 1; offset++) {
        final DateTime day =
            DateTime(now.year, now.month, now.day + offset);
        final DateTime s = p.startOn(day);
        final DateTime e = p.endOn(day);
        if (now.isBefore(s) || !now.isBefore(e)) continue;
        if (best == null || e.isAfter(best.end)) {
          best = (start: s, end: e);
        }
      }
    }
    return best;
  }

  /// 此刻若处于某段锁定中，返回该段的结束时刻；否则 null。
  /// 多段重叠时取最晚结束的那一段（保证不会提前放行）。
  ///
  /// [skipAt] 是按「提前解锁」的时刻，[skipUntil] 是放行到哪一刻：
  /// 只放过**在按下那一刻已经开始**的段（也就是眼前这一次连续锁定），
  /// 之后才开始的新段不受影响——否则上一段的放行会把下一段一起吞掉。
  DateTime? activeEnd(
    DateTime now, {
    DateTime? skipAt,
    DateTime? skipUntil,
  }) {
    final bool skipping = skipAt != null &&
        skipUntil != null &&
        now.isBefore(skipUntil);
    DateTime? best;
    for (final LockPeriod p in periods) {
      for (int offset = -1; offset <= 1; offset++) {
        final DateTime day =
            DateTime(now.year, now.month, now.day + offset);
        final DateTime s = p.startOn(day);
        final DateTime e = p.endOn(day);
        if (now.isBefore(s) || !now.isBefore(e)) continue;
        // 按下放行时这一段已经在跑 → 放行它；之后才开始的段照常锁。
        if (skipping && !s.isAfter(skipAt)) continue;
        if (best == null || e.isAfter(best)) best = e;
      }
    }
    return best;
  }

  /// 「提前解锁」实际放过的那些段（按下那一刻已经开始）里，最晚的结束时刻。
  ///
  /// 改时段后用它重算放行截止：用户常常正是处在放行状态里调整规则，
  /// 一保存就锁回去会把人关在门外；但放行范围要跟着新时段走——
  /// 新改出来的、按下之后才开始的段不在其中，照常锁。
  DateTime? releasedEnd(DateTime now, {required DateTime skipAt}) {
    DateTime? best;
    for (final LockPeriod p in periods) {
      for (int offset = -1; offset <= 1; offset++) {
        final DateTime day =
            DateTime(now.year, now.month, now.day + offset);
        final DateTime s = p.startOn(day);
        final DateTime e = p.endOn(day);
        // 此刻没在跑，或按下放行时还没开始 → 不属于本次放行。
        if (now.isBefore(s) || !now.isBefore(e)) continue;
        if (s.isAfter(skipAt)) continue;
        if (best == null || e.isAfter(best)) best = e;
      }
    }
    return best;
  }

  /// 下一次状态切换：(时刻, 是否开始锁定)。无时段时返回 null。
  (DateTime, bool)? nextSwitch(DateTime now) {
    DateTime? at;
    bool starts = false;
    for (final LockPeriod p in periods) {
      for (int offset = -1; offset <= 2; offset++) {
        final DateTime day =
            DateTime(now.year, now.month, now.day + offset);
        final List<(DateTime, bool)> marks = <(DateTime, bool)>[
          (p.startOn(day), true),
          (p.endOn(day), false),
        ];
        for (final (DateTime t, bool isStart) in marks) {
          if (!t.isAfter(now)) continue;
          if (at == null || t.isBefore(at)) {
            at = t;
            starts = isStart;
          }
        }
      }
    }
    if (at == null) return null;
    return (at, starts);
  }

  /// 主开关 + 临时解锁 + 时段，合成「此刻的锁定结束时刻」。
  ///
  /// [skipAt] / [skipUntil] 见 [activeEnd]：只放过按下那一刻已经开始的段，
  /// 尚未开始的下一段照常锁。
  DateTime? lockedEnd(
    DateTime now, {
    required bool enabled,
    DateTime? skipAt,
    DateTime? skipUntil,
  }) {
    if (!enabled || isEmpty) return null;
    return activeEnd(now, skipAt: skipAt, skipUntil: skipUntil);
  }
}

/// 组合判断：锁定中返回解锁时刻，否则 null。页面与返回键都走这一条。
DateTime? lockedEndNow({
  required bool enabled,
  required List<LockPeriod> periods,
  required DateTime now,
  DateTime? skipAt,
  DateTime? skipUntil,
}) =>
    LockSchedule(periods).lockedEnd(
      now,
      enabled: enabled,
      skipAt: skipAt,
      skipUntil: skipUntil,
    );

/// 分钟数 → "08:05"。
String fmtMinute(int minutes) {
  final int m = minutes % kDayMinutes;
  return '${_two(m ~/ 60)}:${_two(m % 60)}';
}

/// 倒计时 → "01:23:45"（超过一天时带上天数）。
String fmtHms(Duration d) {
  final Duration v = d.isNegative ? Duration.zero : d;
  final int h = v.inHours;
  final String body =
      '${_two(h % 24)}:${_two(v.inMinutes % 60)}:${_two(v.inSeconds % 60)}';
  return v.inDays > 0 ? '${v.inDays}天 $body' : body;
}

String _two(int v) => v.toString().padLeft(2, '0');
