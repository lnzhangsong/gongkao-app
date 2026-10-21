import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lock_schedule.dart';

/// 深色弹层配色：与本页一致的夜间风格，不受浅色主题影响。
const Color sheetBg = Color(0xFF15181D);
const Color sheetAccent = Color(0xFF3B82F6);

/// 滚轮式时间选择（底部弹层）。返回 null 表示取消。
///
/// 不用 Material 默认的 24 小时表盘：390dp 宽的手机上它会叠成内外两圈
/// （00–11 / 12–23），数字互相挤压、几乎点不准；滚轮在窄屏上更准也更好读。
Future<TimeOfDay?> showTimeWheelSheet(
  BuildContext context, {
  required String title,
  required int minutes,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (BuildContext ctx) =>
        _TimeWheelSheet(title: title, minutes: minutes),
  );
}

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({required this.title, required this.minutes});

  final String title;
  final int minutes;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  /// 常用时刻：整点为主，覆盖早/午/晚三个高频区间。
  static const List<int> _presets = <int>[
    0,
    8 * 60,
    12 * 60,
    14 * 60,
    18 * 60,
    22 * 60,
  ];

  @override
  void initState() {
    super.initState();
    _hour = widget.minutes ~/ 60 % 24;
    _minute = widget.minutes % 60;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _jumpTo(int minutes) {
    final int h = minutes ~/ 60 % 24;
    final int m = minutes % 60;
    if (h == _hour && m == _minute) return;
    setState(() {
      _hour = h;
      _minute = m;
    });
    const Duration d = Duration(milliseconds: 260);
    _hourCtrl.animateToItem(h, duration: d, curve: Curves.easeOutCubic);
    _minuteCtrl.animateToItem(m, duration: d, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final int total = _hour * 60 + _minute;
    return Material(
      color: sheetBg,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _Grabber(),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_pad(_hour)}:${_pad(_minute)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: sheetAccent,
                    letterSpacing: 1,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 上下渐隐：滚轮边缘不硬切，更像机械滚轮的手感。
            ShaderMask(
              shaderCallback: (Rect bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: <double>[0.0, 0.28, 0.72, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: SizedBox(
                height: 176,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // 选中带：给中间那一行一个落点。
                    IgnorePointer(
                      child: Container(
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 34),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _wheel(
                          childCount: 24,
                          selected: _hour,
                          controller: _hourCtrl,
                          label: _pad,
                          onChanged: (int i) => setState(() => _hour = i),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            ':',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                        _wheel(
                          childCount: 60,
                          selected: _minute,
                          controller: _minuteCtrl,
                          label: _pad,
                          onChanged: (int i) => setState(() => _minute = i),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 常用时刻：横向可滚，窄屏也不会折成两行。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final int p in _presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _presetChip(p, selected: p == total),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        foregroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        TimeOfDay(hour: _hour, minute: _minute),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: sheetAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '确定',
                        style:
                            TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheel({
    required int childCount,
    required int selected,
    required FixedExtentScrollController controller,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 92,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 44,
        perspective: 0.003,
        diameterRatio: 1.5,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (int i) {
          HapticFeedback.selectionClick();
          onChanged(i);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: childCount,
          builder: (BuildContext ctx, int i) {
            final bool on = i == selected;
            return Center(
              child: Text(
                label(i),
                style: TextStyle(
                  fontSize: on ? 26 : 20,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  color: on ? Colors.white : Colors.white30,
                  height: 1,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _presetChip(int minutes, {required bool selected}) {
    return GestureDetector(
      onTap: () => _jumpTo(minutes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? sheetAccent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? sheetAccent.withValues(alpha: 0.7) : Colors.transparent,
          ),
        ),
        child: Text(
          fmtMinute(minutes),
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}

String _pad(int v) => v.toString().padLeft(2, '0');

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

// ── 时段编辑弹层 ──────────────────────────────────────────────────────

/// 时段编辑的结果：改好的时段 / 被删除 / null（放弃）。
class PeriodSheetResult {
  const PeriodSheetResult.done(LockPeriod this.period) : deleted = false;
  const PeriodSheetResult.deleted()
      : period = null,
        deleted = true;

  final LockPeriod? period;
  final bool deleted;
}

/// 编辑一段锁定时段：开始 / 解锁两个时间各自弹出滚轮选择，
/// 删除放在弹层内部（页面上不再放小叉），避免误触把时段删掉。
Future<PeriodSheetResult?> showPeriodSheet(
  BuildContext context, {
  required String title,
  required LockPeriod period,
}) {
  return showModalBottomSheet<PeriodSheetResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (BuildContext ctx) => _PeriodSheet(title: title, initial: period),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.title, required this.initial});

  final String title;
  final LockPeriod initial;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late LockPeriod _period = widget.initial;

  Future<void> _pick({required bool isStart}) async {
    final int current = isStart ? _period.start : _period.end;
    final TimeOfDay? picked = await showTimeWheelSheet(
      context,
      title: isStart ? '开始锁定时间' : '解锁时间',
      minutes: current,
    );
    if (!mounted || picked == null) return;
    final int value = picked.hour * 60 + picked.minute;
    setState(() {
      _period = isStart
          ? _period.copyWith(start: value)
          : _period.copyWith(end: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: sheetBg,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _Grabber(),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_period.label} · ${_durationText(_period.durationMinutes)}',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
            const SizedBox(height: 14),
            _timeRow('开始锁定', _period.start, () => _pick(isStart: true)),
            const SizedBox(height: 10),
            _timeRow('解锁时间', _period.end, () => _pick(isStart: false)),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '解锁早于开始时按跨午夜处理（次日）；起止相同时为全天锁定。',
                style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white30),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pop(const PeriodSheetResult.deleted()),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('删除该时段', style: TextStyle(fontSize: 14)),
                ),
                const Spacer(),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context)
                        .pop(PeriodSheetResult.done(_period)),
                    style: FilledButton.styleFrom(
                      backgroundColor: sheetAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '完成',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(String label, int minutes, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const Spacer(),
              Text(
                fmtMinute(minutes),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: Colors.white,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  static String _durationText(int minutes) {
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    final int h = minutes ~/ 60;
    return h == 0 ? '$minutes 分钟' : '$h 小时 ${minutes % 60} 分';
  }
}

