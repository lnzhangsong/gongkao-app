import 'package:flutter/material.dart';

import 'widgets/pad_home.dart';
import 'widgets/pomodoro_page.dart';

/// 界面对切：台历 ⇄ 番茄钟（默认台历）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _pomodoro = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _pomodoro
                  ? PomodoroPage(
                      onBack: () => setState(() => _pomodoro = false),
                    )
                  : const PadHome(),
            ),
            if (!_pomodoro)
              Positioned(
                top: 12,
                right: 16,
                child: TextButton.icon(
                  onPressed: () => setState(() => _pomodoro = true),
                  icon: const Icon(Icons.timer_outlined, size: 20),
                  label: const Text('番茄钟'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
