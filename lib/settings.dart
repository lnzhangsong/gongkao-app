import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'lock_schedule.dart';

/// 应用设置（持久化到 shared_preferences）。
class Settings extends ChangeNotifier {
  static const String _kInterval = 'card_interval_seconds';
  static const String _kEnabledKinds = 'enabled_kinds';
  static const String _kCurrentKind = 'current_kind';
  static const String _kFaceEnabled = 'face_enabled';
  static const String _kFaceThreshold = 'face_threshold';
  static const String _kFaceBaseline = 'face_baseline';
  static const String _kFaceUpAngle = 'face_up_angle';
  static const String _kFaceDownAngle = 'face_down_angle';
  static const String _kFaceHoldSeconds = 'face_hold_seconds';
  static const String _kLockEnabled = 'lock_enabled';
  static const String _kLockPeriods = 'lock_periods';
  static const String _kLockSkipUntil = 'lock_skip_until';
  static const String _kLockSkipAt = 'lock_skip_at';
  static const String _kLockAutoStart = 'lock_auto_start';

  int _intervalSeconds = cardInterval.inSeconds;
  int get intervalSeconds => _intervalSeconds;
  Duration get interval => Duration(seconds: _intervalSeconds);

  /// 抬头检测总开关。开启后秒表一启动即自动检测。
  bool _faceEnabled = false;
  bool get faceEnabled => _faceEnabled;

  /// 抬头判定阈值（相对基准角的抬升量，度）。
  double _faceThreshold = 2;
  double get faceThreshold => _faceThreshold;

  /// 上次校准得到的低头基准角（度）。null 表示尚未校准。
  double? _faceBaseline;
  double? get faceBaseline => _faceBaseline;

  /// 采样得到的抬头角 / 低头角（用户手动各采一次）。
  double? _faceUpAngle;
  double? get faceUpAngle => _faceUpAngle;
  double? _faceDownAngle;
  double? get faceDownAngle => _faceDownAngle;

  /// 需连续保持抬头多久才计一次（秒）。去抖，避免瞬时抖动误计。
  int _faceHoldSeconds = 2;
  int get faceHoldSeconds => _faceHoldSeconds;
  Duration get faceHold => Duration(seconds: _faceHoldSeconds);

  /// 按时锁定手机（仅手机端生效，平板端不受影响）。
  bool _lockEnabled = false;
  bool get lockEnabled => _lockEnabled;

  /// 锁定时段列表。默认给一段 08:00–12:00 作示例，用户可增删改。
  List<LockPeriod> _lockPeriods = <LockPeriod>[
    const LockPeriod(start: 8 * 60, end: 12 * 60),
  ];
  List<LockPeriod> get lockPeriods => List<LockPeriod>.unmodifiable(_lockPeriods);

  /// 本次提前解锁的有效期（到该时刻前不锁）。null 表示无。
  DateTime? _lockSkipUntil;
  DateTime? get lockSkipUntil => _lockSkipUntil;

  /// 按下「提前解锁」的时刻。放行只作用于这一刻**已经开始的段**，
  /// 之后才开始的新段照常锁（否则上一段会把下一段一起吞掉）。
  DateTime? _lockSkipAt;
  DateTime? get lockSkipAt => _lockSkipAt;

  /// 开机自启：开机后自动拉起应用（锁定期内则无条件拉起并锁定）。
  bool _lockAutoStart = true;
  bool get lockAutoStart => _lockAutoStart;

  /// 参与轮播的主题集合。空集合视为全部参与（兜底）。
  final Set<String> _enabledKinds = <String>{...allKinds};
  Set<String> get enabledKinds => Set<String>.unmodifiable(_enabledKinds);

  /// 当前查看的主题。
  String _currentKind = allKinds.first;
  String get currentKind => _currentKind;

  /// 间隔可选范围（秒），与设置页滑块一致。
  static const int minInterval = 5;
  static const int maxInterval = 120;

  bool isKindEnabled(String kind) => _enabledKinds.contains(kind);

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? v = prefs.getInt(_kInterval);
    if (v != null) {
      _intervalSeconds = v.clamp(minInterval, maxInterval);
    }
    final List<String>? kinds = prefs.getStringList(_kEnabledKinds);
    if (kinds != null) {
      _enabledKinds
        ..clear()
        ..addAll(kinds.where(allKinds.contains));
    }
    final String? cur = prefs.getString(_kCurrentKind);
    if (cur != null && allKinds.contains(cur)) {
      _currentKind = cur;
    }
    _faceEnabled = prefs.getBool(_kFaceEnabled) ?? false;
    final double? th = prefs.getDouble(_kFaceThreshold);
    if (th != null) _faceThreshold = th.clamp(minFaceThreshold, maxFaceThreshold);
    _faceBaseline = prefs.getDouble(_kFaceBaseline);
    _faceUpAngle = prefs.getDouble(_kFaceUpAngle);
    _faceDownAngle = prefs.getDouble(_kFaceDownAngle);
    final int? hold = prefs.getInt(_kFaceHoldSeconds);
    if (hold != null) _faceHoldSeconds = hold.clamp(minFaceHoldSeconds, maxFaceHoldSeconds);
    _lockEnabled = prefs.getBool(_kLockEnabled) ?? false;
    final List<String>? rawPeriods = prefs.getStringList(_kLockPeriods);
    if (rawPeriods != null) {
      _lockPeriods = <LockPeriod>[
        for (final String raw in rawPeriods) ?LockPeriod.parse(raw),
      ];
    }
    // 放行按「段实例」记录：skipUntil 是这一段结束，skipStart 是这一段开始。
    // 只有带 skipStart 的记录才作数——旧版只有时间窗的记录无法区分重叠段，直接丢弃。
    final int? skip = prefs.getInt(_kLockSkipUntil);
    final int? skipAt = prefs.getInt(_kLockSkipAt);
    if (skip != null && skipAt != null) {
      final DateTime until = DateTime.fromMillisecondsSinceEpoch(skip);
      if (until.isAfter(DateTime.now())) {
        _lockSkipUntil = until;
        _lockSkipAt = DateTime.fromMillisecondsSinceEpoch(skipAt);
      }
    }
    _lockAutoStart = prefs.getBool(_kLockAutoStart) ?? true;
    _normalizeCurrentKind();
    notifyListeners();
  }

  /// 阈值可选范围（度），与设置页滑块一致。
  static const double minFaceThreshold = 1;
  static const double maxFaceThreshold = 20;

  /// 保持抬头时长可选范围（秒）。
  static const int minFaceHoldSeconds = 1;
  static const int maxFaceHoldSeconds = 10;

  Future<void> setFaceEnabled(bool on) async {
    if (on == _faceEnabled) return;
    _faceEnabled = on;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFaceEnabled, on);
  }

  Future<void> setFaceHoldSeconds(int seconds) async {
    final int v = seconds.clamp(minFaceHoldSeconds, maxFaceHoldSeconds);
    if (v == _faceHoldSeconds) return;
    _faceHoldSeconds = v;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFaceHoldSeconds, v);
  }

  Future<void> setFaceThreshold(double deg) async {
    final double v = deg.clamp(minFaceThreshold, maxFaceThreshold);
    if (v == _faceThreshold) return;
    _faceThreshold = v;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFaceThreshold, v);
  }

  Future<void> setFaceBaseline(double deg) async {
    _faceBaseline = deg;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFaceBaseline, deg);
  }

  Future<void> clearFaceBaseline() async {
    _faceBaseline = null;
    _faceUpAngle = null;
    _faceDownAngle = null;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFaceBaseline);
    await prefs.remove(_kFaceUpAngle);
    await prefs.remove(_kFaceDownAngle);
  }

  /// 记录一次采样（抬头或低头），并在两者都具备时自动定基准与阈值。
  /// 基准 = 低头角；阈值 = (抬头角 - 低头角) / 2。
  Future<void> setFaceSample({double? up, double? down}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (up != null) {
      _faceUpAngle = up;
      await prefs.setDouble(_kFaceUpAngle, up);
    }
    if (down != null) {
      _faceDownAngle = down;
      await prefs.setDouble(_kFaceDownAngle, down);
    }
    if (_faceUpAngle != null && _faceDownAngle != null) {
      _faceBaseline = _faceDownAngle;
      final double mid = (_faceUpAngle! - _faceDownAngle!) / 2;
      _faceThreshold =
          mid.clamp(minFaceThreshold, maxFaceThreshold).toDouble();
      await prefs.setDouble(_kFaceBaseline, _faceBaseline!);
      await prefs.setDouble(_kFaceThreshold, _faceThreshold);
    }
    notifyListeners();
  }

  Future<void> setIntervalSeconds(int seconds) async {
    final int v = seconds.clamp(minInterval, maxInterval);
    if (v == _intervalSeconds) return;
    _intervalSeconds = v;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInterval, v);
  }

  /// 开关某主题是否参与轮播。至少保留一个，避免全部关闭。
  Future<void> setKindEnabled(String kind, bool enabled) async {
    if (enabled) {
      _enabledKinds.add(kind);
    } else {
      if (_enabledKinds.length <= 1) return;
      _enabledKinds.remove(kind);
    }
    _normalizeCurrentKind();
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kEnabledKinds, _enabledKinds.toList());
    await prefs.setString(_kCurrentKind, _currentKind);
  }

  /// 选择当前查看的主题（须为已启用的主题）。
  Future<void> setCurrentKind(String kind) async {
    if (!_enabledKinds.contains(kind) || kind == _currentKind) return;
    _currentKind = kind;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentKind, kind);
  }

  /// 开关按时锁定。
  Future<void> setLockEnabled(bool on) async {
    if (on == _lockEnabled) return;
    _lockEnabled = on;
    if (!on) {
      _lockSkipUntil = null;
      _lockSkipAt = null;
    }
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLockEnabled, on);
    if (!on) {
      await prefs.remove(_kLockSkipUntil);
      await prefs.remove(_kLockSkipAt);
    }
  }

  /// 新增一段：接在最后一段之后，默认 4 小时（环形不越过一天）。
  Future<void> addLockPeriod() async {
    final int start = _lockPeriods.isEmpty ? 8 * 60 : _lockPeriods.last.end;
    _lockPeriods = <LockPeriod>[
      ..._lockPeriods,
      LockPeriod(start: start, end: (start + 4 * 60) % kDayMinutes),
    ];
    await _saveLockPeriods();
  }

  /// 改某一段的开始或结束时刻（分钟数）。
  Future<void> setLockPeriod(int index, LockPeriod period) async {
    if (index < 0 || index >= _lockPeriods.length) return;
    final List<LockPeriod> next = List<LockPeriod>.of(_lockPeriods);
    next[index] = period;
    _lockPeriods = next;
    await _saveLockPeriods();
  }

  Future<void> removeLockPeriod(int index) async {
    if (index < 0 || index >= _lockPeriods.length) return;
    final List<LockPeriod> next = List<LockPeriod>.of(_lockPeriods)
      ..removeAt(index);
    _lockPeriods = next;
    await _saveLockPeriods();
  }

  /// 开关「开机自启」。
  Future<void> setLockAutoStart(bool on) async {
    if (on == _lockAutoStart) return;
    _lockAutoStart = on;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLockAutoStart, on);
  }

  /// 记录「本次提前解锁」：从 [at] 这一刻起，放过当时已经在跑的段，直到 [until]。
  ///
  /// 必须带上按下时刻——放行只作用于**已经开始的段**；只记结束时刻的话，
  /// 之后才开始（甚至与当前段重叠）的下一段会被一起放行。
  Future<void> setLockSkip({required DateTime at, required DateTime until}) async {
    _lockSkipAt = at;
    _lockSkipUntil = until;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLockSkipAt, at.millisecondsSinceEpoch);
    await prefs.setInt(_kLockSkipUntil, until.millisecondsSinceEpoch);
  }

  /// 撤销「本次提前解锁」：当前若仍在锁定时段内，会立刻重新锁上。
  Future<void> clearLockSkip() async {
    if (_lockSkipUntil == null && _lockSkipAt == null) return;
    _lockSkipAt = null;
    _lockSkipUntil = null;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLockSkipAt);
    await prefs.remove(_kLockSkipUntil);
  }

  Future<void> _saveLockPeriods() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kLockPeriods,
      _lockPeriods.map((LockPeriod p) => p.encode()).toList(),
    );
    // 先按新时段重算放行截止，再通知界面——否则界面会拿旧值先闪一下锁定态。
    await _recalcSkipAfterPeriodEdit(prefs);
    notifyListeners();
  }

  /// 改完时段后重算「提前解锁」的截止时刻，而不是直接清掉。
  ///
  /// 真实使用路径几乎都是「点了提前解锁 → 进设置调规则」，一保存就把放行
  /// 撤销，人会立刻被锁回去，等于改不了设置（2026-10-22 反馈）。放行是显式
  /// 动作，不该被编辑动作撤销；但它的范围要跟着新时段收缩/延展：只覆盖
  /// 按下那一刻已经开始的段，之后才开始的段照常锁。
  Future<void> _recalcSkipAfterPeriodEdit(SharedPreferences prefs) async {
    final DateTime? at = _lockSkipAt;
    final DateTime? until = _lockSkipUntil;
    if (at == null || until == null) return;
    final DateTime now = DateTime.now();

    // 已自然到期：顺手清干净，免得界面还说「已放行」。
    final DateTime? next =
        now.isBefore(until) ? LockSchedule(_lockPeriods).releasedEnd(now, skipAt: at) : null;
    if (next == null) {
      _lockSkipAt = null;
      _lockSkipUntil = null;
      await prefs.remove(_kLockSkipAt);
      await prefs.remove(_kLockSkipUntil);
      return;
    }
    if (next != until) {
      _lockSkipUntil = next;
      await prefs.setInt(_kLockSkipUntil, next.millisecondsSinceEpoch);
    }
  }

  /// 若当前主题被禁用，则回落到第一个启用主题。
  void _normalizeCurrentKind() {
    if (_enabledKinds.isEmpty) {
      _enabledKinds.addAll(allKinds);
    }
    if (!_enabledKinds.contains(_currentKind)) {
      _currentKind = allKinds.firstWhere(_enabledKinds.contains);
    }
  }
}
