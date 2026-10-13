import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// 应用设置（持久化到 shared_preferences）。
/// 目前只有轮播间隔；后续设置项往这里加。
class Settings extends ChangeNotifier {
  static const String _kInterval = 'card_interval_seconds';

  int _intervalSeconds = cardInterval.inSeconds;
  int get intervalSeconds => _intervalSeconds;
  Duration get interval => Duration(seconds: _intervalSeconds);

  /// 间隔可选范围（秒），与设置页滑块一致。
  static const int minInterval = 5;
  static const int maxInterval = 120;

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? v = prefs.getInt(_kInterval);
    if (v != null) {
      _intervalSeconds = v.clamp(minInterval, maxInterval);
      notifyListeners();
    }
  }

  Future<void> setIntervalSeconds(int seconds) async {
    final int v = seconds.clamp(minInterval, maxInterval);
    if (v == _intervalSeconds) return;
    _intervalSeconds = v;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInterval, v);
  }
}
