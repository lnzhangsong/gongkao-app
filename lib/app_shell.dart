import 'package:flutter/material.dart';

import 'settings.dart';
import 'widgets/pad_home.dart';
import 'widgets/pomodoro_page.dart';
import 'widgets/settings_page.dart';

enum _Screen { calendar, pomodoro, settings }

/// 界面对切：台历 ⇄ 番茄钟 ⇄ 设置（默认台历）。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings});

  final Settings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Screen _screen = _Screen.calendar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    _iconBtn(Icons.timer_outlined, '番茄钟',
                        () => setState(() => _screen = _Screen.pomodoro)),
                  ],
                ),
              ),
          ],
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
      case _Screen.settings:
        return SettingsPage(
          settings: widget.settings,
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
