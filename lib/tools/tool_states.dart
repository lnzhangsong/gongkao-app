import 'dart:async';

import 'package:flutter/foundation.dart';

/// 通用倒计时：设定时长 → 倒着走 → 归零。
/// 用「目标时刻」而非累加，切后台被节流也不走慢。
class CountdownTimer extends ChangeNotifier {
  Duration _total = const Duration(minutes: 5);
  Duration _remaining = const Duration(minutes: 5);
  DateTime? _deadline;
  Timer? _ticker;

  Duration get total => _total;
  Duration get remaining => _remaining;
  bool get running => _deadline != null;
  bool get finished => _remaining <= Duration.zero;

  /// 0..1，已流逝比例。
  double get progress {
    final int t = _total.inMilliseconds;
    if (t == 0) return 0;
    return ((t - _remaining.inMilliseconds) / t).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 设定时长（会自动停止并回到起点）。
  void setDuration(Duration d) {
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    _total = d;
    _remaining = d;
    notifyListeners();
  }

  void start() {
    if (running || finished) return;
    _deadline = DateTime.now().add(_remaining);
    _ticker ??=
        Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _tick();
    _deadline = null;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    _remaining = _total;
    notifyListeners();
  }

  void _tick() {
    final DateTime? d = _deadline;
    if (d == null) return;
    final Duration left = d.difference(DateTime.now());
    if (left <= Duration.zero) {
      _remaining = Duration.zero;
      _deadline = null;
      _ticker?.cancel();
      _ticker = null;
    } else {
      _remaining = left;
    }
    notifyListeners();
  }
}

/// 秒表（正计时）：可计圈。
class StopwatchTimer extends ChangeNotifier {
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  Duration _accumulated = Duration.zero;
  Timer? _ticker;
  final List<Duration> _laps = <Duration>[];

  Duration get elapsed => _elapsed;
  bool get running => _startedAt != null;
  List<Duration> get laps => List<Duration>.unmodifiable(_laps);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void start() {
    if (running) return;
    _startedAt = DateTime.now();
    _ticker ??=
        Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _accumulated = _elapsed;
    _startedAt = null;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _accumulated = Duration.zero;
    _elapsed = Duration.zero;
    _laps.clear();
    notifyListeners();
  }

  /// 记一圈（记录当前累计时间）。
  void lap() {
    if (!running) return;
    _laps.insert(0, _elapsed);
    notifyListeners();
  }

  void _tick() {
    final DateTime? s = _startedAt;
    if (s == null) return;
    _elapsed = _accumulated + DateTime.now().difference(s);
    notifyListeners();
  }
}
