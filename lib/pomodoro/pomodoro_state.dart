import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';

enum PomodoroPhase { focus, shortBreak, longBreak }

extension PomodoroPhaseLabel on PomodoroPhase {
  String get label => switch (this) {
        PomodoroPhase.focus => '专注中',
        PomodoroPhase.shortBreak => '短休息',
        PomodoroPhase.longBreak => '长休息',
      };

  Duration get total => switch (this) {
        PomodoroPhase.focus => Duration(minutes: pomodoroMinutes),
        PomodoroPhase.shortBreak => Duration(minutes: shortBreakMinutes),
        PomodoroPhase.longBreak => Duration(minutes: longBreakMinutes),
      };
}

/// 专注/短休/长休 状态机。
/// 用「目标时刻」而非累加 Timer，切后台被节流也不走慢。
class PomodoroState extends ChangeNotifier {
  PomodoroPhase _phase = PomodoroPhase.focus;
  int _round = 1; // 当前专注轮次（1-based）
  Duration _remaining = PomodoroPhase.focus.total;
  DateTime? _deadline; // 运行中的目标时刻；暂停时为 null
  Timer? _ticker;

  PomodoroPhase get phase => _phase;
  int get round => _round;
  Duration get remaining => _remaining;
  bool get running => _deadline != null;

  /// 0..1，已流逝比例。
  double get progress {
    final int total = _phase.total.inMilliseconds;
    if (total == 0) return 0;
    final double done = (total - _remaining.inMilliseconds) / total;
    return done.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void start() {
    if (running) return;
    _deadline = DateTime.now().add(_remaining);
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
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
    _remaining = _phase.total;
    notifyListeners();
  }

  /// 跳到下一阶段（不动轮次递增逻辑以外的状态）。
  void skip() {
    _advance();
    if (running) {
      _deadline = DateTime.now().add(_remaining);
    }
    notifyListeners();
  }

  void _tick() {
    final DateTime? d = _deadline;
    if (d == null) return;
    final Duration left = d.difference(DateTime.now());
    if (left <= Duration.zero) {
      _advance();
      _deadline = running ? DateTime.now().add(_remaining) : null;
    } else {
      _remaining = left;
    }
    notifyListeners();
  }

  /// 专注 → 短休 →（每 roundsPerLongBreak 轮）长休 → 循环。
  void _advance() {
    switch (_phase) {
      case PomodoroPhase.focus:
        _phase = _round % roundsPerLongBreak == 0
            ? PomodoroPhase.longBreak
            : PomodoroPhase.shortBreak;
      case PomodoroPhase.shortBreak:
        _round++;
        _phase = PomodoroPhase.focus;
      case PomodoroPhase.longBreak:
        _round++;
        _phase = PomodoroPhase.focus;
    }
    _remaining = _phase.total;
  }
}
