import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'settings.dart';
import 'widgets/footprint_page.dart';
import 'widgets/pad_home.dart';
import 'widgets/pomodoro_page.dart';
import 'widgets/settings_page.dart';
import 'widgets/tools_page.dart';

enum _Screen { calendar, pomodoro, tools, settings, footprint }

/// 界面对切：台历 ⇄ 番茄钟 ⇄ 计时工具 ⇄ 今日足迹 ⇄ 设置（默认台历）。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings});

  final Settings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Screen _screen = _Screen.calendar;

  /// 台历页「再按一次退出」的时间戳。
  DateTime? _lastBackAt;

  /// 返回键：子页先回台历；台历页两秒内连按两次才退出。
  Future<void> _onPop(bool didPop, Object? result) async {
    if (didPop) return;
    if (_screen != _Screen.calendar) {
      setState(() => _screen = _Screen.calendar);
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    Fluttertoast.showToast(
      msg: '再按一次退出',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: _body()),
              if (_screen == _Screen.calendar)
                Positioned(
                  top: 8,
                  right: 12,
                  child: Row(
                    children: <Widget>[
                      _iconBtn(Icons.settings_outlined, '设置',
                          () => setState(() => _screen = _Screen.settings)),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.hourglass_bottom_outlined, '计时工具',
                          () => setState(() => _screen = _Screen.tools)),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.timer_outlined, '番茄钟',
                          () => setState(() => _screen = _Screen.pomodoro)),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.insights_outlined, '今日足迹',
                          () => setState(() => _screen = _Screen.footprint)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_screen) {
      case _Screen.calendar:
        return PadHome(settings: widget.settings);
      case _Screen.pomodoro:
        return PomodoroPage(
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
      case _Screen.tools:
        return ToolsPage(
          settings: widget.settings,
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
      case _Screen.settings:
        return SettingsPage(
          settings: widget.settings,
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
      case _Screen.footprint:
        return FootprintPage(
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
    }
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        tooltip: tip,
        icon: Icon(icon, size: 22),
        color: Colors.white.withValues(alpha: 0.55),
        splashRadius: 22,
      );
}
