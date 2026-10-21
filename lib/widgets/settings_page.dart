import 'package:flutter/material.dart';

import '../config.dart';
import '../settings.dart';
import '../tools/face_pitch.dart';
import 'lock_settings_page.dart';

/// 设置页：轮播间隔滑块（5–120 秒）+ 主题参与开关。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.onBack});

  final Settings settings;
  final VoidCallback onBack;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 采样用的临时检测器（设置页独立开相机采样，不依赖秒表页）。
  final FacePitchMonitor _monitor = FacePitchMonitor();
  bool _sampling = false;

  @override
  void dispose() {
    _monitor.dispose();
    super.dispose();
  }

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
              const SizedBox(height: 32),
              Text('秒表抬头计数', style: text.titleLarge),
              const SizedBox(height: 6),
              Text('开启后，秒表一启动即用前置摄像头检测抬头并自动计次。'
                  '画面只在内存分析，不保存、不上传。',
                  style: text.bodyMedium),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.settings.faceEnabled,
                onChanged: (bool v) => widget.settings.setFaceEnabled(v),
                title: const Text('启用抬头计数'),
              ),
              _faceCalibration(text),
              _faceThresholdSlider(text),
              _faceHoldSlider(text),
              const SizedBox(height: 32),
              Text('手机锁定', style: text.titleLarge),
              const SizedBox(height: 6),
              Text(
                '手机端到点锁定屏幕。这里与手机端的「锁定设置」是同一份数据，'
                '任一端改动都会立刻同步。',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _openLockSettings,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('打开锁定设置'),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    widget.settings.lockEnabled
                        ? '自动锁定已开启 · ${widget.settings.lockPeriods.length} 段'
                        : '自动锁定未开启',
                    style: text.bodyMedium,
                  ),
                ],
              ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 双向采样校准：低头/抬头各采一次，自动定基准与阈值。
  Widget _faceCalibration(TextTheme text) {
    final Settings s = widget.settings;
    final bool on = s.faceEnabled && !_sampling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        Text('校准', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('低头对屏点「采低头」，抬头看时点「采抬头」，各一次即可自动定阈值。',
            style: text.labelSmall),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            OutlinedButton(
              onPressed: on ? () => _sample(isUp: false) : null,
              child: Text('采低头 ${_fmtAngle(s.faceDownAngle)}'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: on ? () => _sample(isUp: true) : null,
              child: Text('采抬头 ${_fmtAngle(s.faceUpAngle)}'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: s.faceEnabled ? s.clearFaceBaseline : null,
              child: const Text('清除'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _sampling
              ? '采样中…请保持姿态'
              : (s.faceBaseline == null
                  ? '尚未校准'
                  : '基准 ${s.faceBaseline!.toStringAsFixed(1)}° · '
                      '阈值 ${s.faceThreshold.toStringAsFixed(1)}°'),
          style: text.bodyMedium,
        ),
      ],
    );
  }

  static String _fmtAngle(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';

  /// 打开锁定设置：手机端与平板端共用同一个页面、同一个 Settings 实例。
  Future<void> _openLockSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => LockSettingsPage(
          settings: widget.settings,
          onBack: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _sample({required bool isUp}) async {
    setState(() => _sampling = true);
    try {
      final double? angle = await _monitor.sampleAvg();
      if (angle == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未检测到人脸，请正对摄像头后重试')),
          );
        }
        return;
      }
      await widget.settings.setFaceSample(up: isUp ? angle : null, down: isUp ? null : angle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已记录${isUp ? '抬头' : '低头'}角度：${angle.toStringAsFixed(1)}°')),
        );
      }
    } finally {
      if (mounted) setState(() => _sampling = false);
    }
  }

  /// 抬头判定阈值滑块（相对基准角的抬升量）。
  Widget _faceThresholdSlider(TextTheme text) {
    final double th = widget.settings.faceThreshold;
    final bool on = widget.settings.faceEnabled;
    return Opacity(
      opacity: on ? 1 : 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 12),
          Text('判定阈值：${th.toStringAsFixed(1)}°', style: text.bodyMedium),
          const SizedBox(height: 4),
          Text('抬头角度需超过「基准 + 阈值」才计一次。调大更稳、调小更灵。',
              style: text.labelSmall),
          Row(
            children: <Widget>[
              Text('${Settings.minFaceThreshold.round()}°',
                  style: text.labelSmall),
              Expanded(
                child: Slider(
                  value: th,
                  min: Settings.minFaceThreshold,
                  max: Settings.maxFaceThreshold,
                  divisions:
                      (Settings.maxFaceThreshold - Settings.minFaceThreshold)
                          .round(),
                  label: '${th.toStringAsFixed(1)}°',
                  onChanged: on
                      ? (double v) => widget.settings.setFaceThreshold(v)
                      : null,
                ),
              ),
              Text('${Settings.maxFaceThreshold.round()}°',
                  style: text.labelSmall),
            ],
          ),
        ],
      ),
    );
  }

  /// 需连续保持抬头多久才计一次（去抖）。
  Widget _faceHoldSlider(TextTheme text) {
    final int hold = widget.settings.faceHoldSeconds;
    final bool on = widget.settings.faceEnabled;
    return Opacity(
      opacity: on ? 1 : 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 12),
          Text('保持时长：$hold 秒', style: text.bodyMedium),
          const SizedBox(height: 4),
          Text('需连续保持抬头达该时长才计一次，防止抖动误计。', style: text.labelSmall),
          Row(
            children: <Widget>[
              Text('${Settings.minFaceHoldSeconds}s', style: text.labelSmall),
              Expanded(
                child: Slider(
                  value: hold.toDouble(),
                  min: Settings.minFaceHoldSeconds.toDouble(),
                  max: Settings.maxFaceHoldSeconds.toDouble(),
                  divisions: Settings.maxFaceHoldSeconds -
                      Settings.minFaceHoldSeconds,
                  label: '$hold s',
                  onChanged: on
                      ? (double v) =>
                          widget.settings.setFaceHoldSeconds(v.round())
                      : null,
                ),
              ),
              Text('${Settings.maxFaceHoldSeconds}s', style: text.labelSmall),
            ],
          ),
        ],
      ),
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
