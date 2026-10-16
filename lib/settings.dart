import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

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
