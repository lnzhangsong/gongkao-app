import 'package:flutter/material.dart';

import '../audio/ambience.dart';
import '../pomodoro/pomodoro_state.dart';
import 'ambience_bar.dart';

/// 番茄钟界面：大倒计时 / 控制 / 背景音。宽窄屏通用，单栏居中。
class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  final PomodoroState _state = PomodoroState();
  final Ambience _ambience = Ambience();

  @override
  void dispose() {
    _state.dispose();
    _ambience.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final int m = d.inMinutes;
    final int s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: _state,
      builder: (BuildContext context, _) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回台历'),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${_state.phase.label} · 第 ${_state.round} 轮',
                        style: text.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _fmt(_state.remaining),
                        style: text.displayLarge?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 320,
                        child: LinearProgressIndicator(
                          value: _state.progress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          FilledButton.tonal(
                            onPressed: _state.running ? _state.pause : _state.start,
                            child: Text(_state.running ? '暂停' : '开始'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: _state.reset,
                            child: const Text('重置'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: _state.skip,
                            child: const Text('跳过'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AmbienceBar(ambience: _ambience),
            ],
          ),
        );
      },
    );
  }
}
