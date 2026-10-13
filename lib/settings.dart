import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// 应用设置（持久化到 shared_preferences）。
class Settings extends ChangeNotifier {
  static const String _kInterval = 'card_interval_seconds';
  static const String _kEnabledKinds = 'enabled_kinds';
  static const String _kCurrentKind = 'current_kind';

  int _intervalSeconds = cardInterval.inSeconds;
  int get intervalSeconds => _intervalSeconds;
  Duration get interval => Duration(seconds: _intervalSeconds);

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
    _normalizeCurrentKind();
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
