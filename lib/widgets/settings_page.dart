import 'package:flutter/material.dart';

import '../config.dart';
import '../settings.dart';

/// 设置页：轮播间隔滑块（5–120 秒）+ 主题参与开关。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.onBack});

  final Settings settings;
  final VoidCallback onBack;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (BuildContext context, _) {
        final int sec = widget.settings.intervalSeconds;
        return Padding(
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回台历'),
                ),
              ),
              const SizedBox(height: 24),
              Text('设置', style: text.headlineMedium),
              const SizedBox(height: 32),
              Text('词条切换频率', style: text.titleLarge),
              const SizedBox(height: 6),
              Text('当前：每 $sec 秒切换一次', style: text.bodyMedium),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Text('${Settings.minInterval}s', style: text.labelSmall),
                  Expanded(
                    child: Slider(
                      value: sec.toDouble(),
                      min: Settings.minInterval.toDouble(),
                      max: Settings.maxInterval.toDouble(),
                      divisions:
                          (Settings.maxInterval - Settings.minInterval) ~/ 5,
                      label: '$sec s',
                      onChanged: (double v) =>
                          widget.settings.setIntervalSeconds(v.round()),
                    ),
                  ),
                  Text('${Settings.maxInterval}s', style: text.labelSmall),
                ],
              ),
              const SizedBox(height: 32),
              Text('参与轮播的主题', style: text.titleLarge),
              const SizedBox(height: 6),
              Text('至少保留一个主题。关闭的主题不会出现在台历上。',
                  style: text.bodyMedium),
              const SizedBox(height: 8),
              for (final String kind in allKinds)
                _kindSwitch(kind, widget.settings.isKindEnabled(kind)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kindSwitch(String kind, bool value) {
    // 只剩一个时禁止再关，避免全部关闭。
    final bool canToggleOff = widget.settings.enabledKinds.length > 1;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: value && !canToggleOff
          ? null
          : (bool v) => widget.settings.setKindEnabled(kind, v),
      title: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: kindColor(kind),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(kind),
        ],
      ),
    );
  }
}
