import 'package:flutter/material.dart';

import '../tools/tool_states.dart';
import 'wallpaper_background.dart';

/// 工具页：倒计时 / 秒表。杂志式排版，Bing 模糊底，极简控件。
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final PageController _pc = PageController();

  /// 当前页（0=倒计时, 1=秒表），用于 tab 高亮与滑动方向判断。
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pc.addListener(() {
      if (!_pc.hasClients) return;
      setState(() => _page = _pc.page ?? 0);
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _goTo(int index) => _pc.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: WallpaperBackground()),
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _back(),
                  const SizedBox(height: 4),
                  _tabs(),
                  const SizedBox(height: 4),
                  Expanded(
                    child: PageView(
                      controller: _pc,
                      physics: const PageScrollPhysics(),
                      children: const <Widget>[
                        _CountdownTab(key: ValueKey<bool>(true)),
                        _StopwatchTab(key: ValueKey<bool>(false)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _back() => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 22),
          label: const Text('返回台历', style: TextStyle(fontSize: 16)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      );

  /// 极简 Tab：小号大写 + 大字距，选中态用滑动下划线。
  /// 下划线与文字色随 PageView 滚动进度实时联动（跟手）。
  /// 左侧用负内边距抵消 InkWell 的水平 padding，使文字与正文左边缘对齐。
  Widget _tabs() => Row(
        children: <Widget>[
          _tab('COUNTDOWN  倒计时', 0),
          const SizedBox(width: 8),
          _tab('STOPWATCH  秒表', 1),
        ],
      );

  static const double _tabPad = 20;

  Widget _tab(String label, int index) {
    // 0..1：该 tab 的「选中程度」，随页面滚动实时变化。
    final double sel = (1 - (_page - index).abs()).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => _goTo(index),
      child: Padding(
        padding: EdgeInsets.only(
          left: index == 0 ? 0 : _tabPad,
          right: _tabPad,
          top: 10,
          bottom: 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 22,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
                color: Color.lerp(Colors.white38, Colors.white, sel),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 3,
              width: 150 * sel,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(Duration d, {bool withMillis = false}) {
  final int h = d.inHours;
  final int m = d.inMinutes % 60;
  final int s = d.inSeconds % 60;
  final String base = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  if (!withMillis) return base;
  final int cs = (d.inMilliseconds % 1000) ~/ 10;
  return '$base.${cs.toString().padLeft(2, '0')}';
}

/// 主数字 + 小一号的毫秒（.cs）后缀。
Widget _bigWithMillis(Duration d) {
  final int cs = (d.inMilliseconds % 1000) ~/ 10;
  return Text.rich(
    TextSpan(
      children: <InlineSpan>[
        TextSpan(text: _fmt(d), style: _bigNum),
        TextSpan(
          text: '.${cs.toString().padLeft(2, '0')}',
          style: _bigNum.copyWith(fontSize: 56, color: Colors.white54),
        ),
      ],
    ),
  );
}

/// 大号等宽数字，杂志式主视觉。
const TextStyle _bigNum = TextStyle(
  fontSize: 140,
  fontWeight: FontWeight.w200,
  height: 0.95,
  color: Colors.white,
  letterSpacing: -2,
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

// ---------------- 倒计时 ----------------
class _CountdownTab extends StatefulWidget {
  const _CountdownTab({super.key});
  @override
  State<_CountdownTab> createState() => _CountdownTabState();
}

class _CountdownTabState extends State<_CountdownTab> {
  final CountdownTimer _t = CountdownTimer();
  static const List<int> _presets = <int>[1, 5, 10, 25, 60];

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Future<void> _custom(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _t.total.inHours,
        minute: _t.total.inMinutes % 60,
      ),
    );
    if (picked != null) {
      _t.setDuration(Duration(hours: picked.hour, minutes: picked.minute));
    }
  }

  /// 按预设顺序切换时长（dir=-1 上一个，+1 下一个）。
  void _cyclePreset(int dir) {
    int i = _presets.indexWhere((int m) => _t.total == Duration(minutes: m));
    if (i < 0) i = 0;
    i = (i + dir).clamp(0, _presets.length - 1);
    _t.setDuration(Duration(minutes: _presets[i]));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (BuildContext context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _caps('TIME REMAINING  剩余'),
            const SizedBox(height: 14),
            _bigWithMillis(_t.remaining),
            const SizedBox(height: 16),
            _thinBar(_t.progress),
            if (_t.finished) ...<Widget>[
              const SizedBox(height: 12),
              _caps('TIME IS UP  时间到', color: Colors.white),
            ],
            const SizedBox(height: 28),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (DragEndDetails d) {
                final double v = d.primaryVelocity ?? 0;
                if (v < -150) {
                  _cyclePreset(1);
                } else if (v > 150) {
                  _cyclePreset(-1);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _caps('DURATION  时长  ·  左右滑动切换'),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final int m in _presets)
                          _textChoice('$m 分', _t.total == Duration(minutes: m),
                              () => _t.setDuration(Duration(minutes: m))),
                        _textChoice('自定义', false, () => _custom(context),
                            icon: Icons.edit_outlined),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: <Widget>[
                  _textAction(_t.running ? '暂停' : '开始',
                      _t.running ? _t.pause : _t.start, primary: true),
                  _textAction('重置', _t.reset),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------- 秒表 ----------------
class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab({super.key});
  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab> {
  final StopwatchTimer _w = StopwatchTimer();

  @override
  void dispose() {
    _w.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _w,
      builder: (BuildContext context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 24),
            _caps('ELAPSED  已用时'),
            const SizedBox(height: 14),
            _bigWithMillis(_w.elapsed),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                children: <Widget>[
                  _textAction(_w.running ? '暂停' : '开始',
                      _w.running ? _w.pause : _w.start, primary: true),
                  _textAction('计次', _w.running ? _w.lap : null),
                  _textAction('重置', _w.reset),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _w.laps.length,
                itemBuilder: (BuildContext context, int i) {
                  final int n = _w.laps.length - i;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: <Widget>[
                        _caps('LAP ${n.toString().padLeft(2, '0')}'),
                        const Spacer(),
                        Text(
                          _fmt(_w.laps[i], withMillis: true),
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------- 共用极简组件 ----------------

/// 小号大写 + 大字距标签。
Widget _caps(String s, {Color color = Colors.white54}) => Text(
      s,
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 3,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );

/// 细进度条（缓动跟随，避免跳变）。
Widget _thinBar(double v) => SizedBox(
      width: 420,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          tween: Tween<double>(begin: 0, end: v),
          builder: (BuildContext context, double value, _) =>
              LinearProgressIndicator(
            value: value,
            minHeight: 2,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        ),
      ),
    );

/// 文字选项：选中态白色 + 下划线，未选中半透明。
Widget _textChoice(String label, bool selected, VoidCallback onTap,
        {IconData? icon}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon,
                      size: 16, color: selected ? Colors.white : Colors.white54),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? Colors.white : Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 2,
              width: 44,
              color: selected ? Colors.white : Colors.transparent,
            ),
          ],
        ),
      ),
    );

/// 文字动作按钮：primary 时加下划线与细边框强调，命中区最小 48。
Widget _textAction(String label, VoidCallback? onTap, {bool primary = false}) {
  final bool on = onTap != null;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Opacity(
      opacity: on ? 1 : 0.35,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: primary
              ? Border.all(color: Colors.white70, width: 1.5)
              : Border.all(color: Colors.white24, width: 1),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52, minWidth: 108),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
