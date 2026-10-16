import 'package:flutter/material.dart';

import '../settings.dart';
import '../tools/face_pitch.dart';
import '../tools/tool_states.dart';
import 'wallpaper_background.dart';

/// 工具页：倒计时 / 秒表。杂志式排版，Bing 模糊底，极简控件。
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.settings, required this.onBack});

  final Settings settings;
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
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                // 窄窗收紧边距，避免内容被挤到溢出。
                final double pad = c.maxWidth < 600 ? 20 : 40;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _back(),
                      const SizedBox(height: 4),
                      _tabs(c.maxWidth),
                      const SizedBox(height: 4),
                      Expanded(
                        child: PageView(
                          controller: _pc,
                          physics: const PageScrollPhysics(),
                          children: <Widget>[
                            _CountdownTab(key: ValueKey<bool>(true)),
                            _StopwatchTab(
                              key: ValueKey<bool>(false),
                              settings: widget.settings,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
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
  /// 窄窗下按可用宽度缩小字号/字距，保证两个 tab 同排放下；极窄时可横向滚动。
  Widget _tabs(double width) {
    final double scale = width < 420 ? 0.62 : (width < 560 ? 0.78 : 1.0);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _tab('COUNTDOWN  倒计时', 0, scale),
          SizedBox(width: 8 * scale),
          _tab('STOPWATCH  秒表', 1, scale),
        ],
      ),
    );
  }

  static const double _tabPad = 20;

  Widget _tab(String label, int index, double scale) {
    // 0..1：该 tab 的「选中程度」，随页面滚动实时变化。
    final double sel = (1 - (_page - index).abs()).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => _goTo(index),
      child: Padding(
        padding: EdgeInsets.only(
          left: index == 0 ? 0 : _tabPad * scale,
          right: _tabPad * scale,
          top: 10,
          bottom: 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 22 * scale,
                letterSpacing: 3 * scale,
                fontWeight: FontWeight.w600,
                color: Color.lerp(Colors.white38, Colors.white, sel),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 3,
              width: 150 * sel * scale,
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

/// 固定 时:分:秒（各两位补零），与设置滚轮显示一致。
String _fmtHms(Duration d) {
  final String h = d.inHours.toString().padLeft(2, '0');
  final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// 主数字 + 小一号的毫秒（.cs）后缀。
/// [hms] 为真时始终显示 时:分:秒 三段（倒计时用，与设置界面一致）；
/// 否则小时为 0 时省略时位（秒表用）。
/// 用 FittedBox 按可用宽度缩放，窄窗下自动缩小、宽窗保持原大小。
Widget _bigWithMillis(Duration d, {bool hms = false}) {
  final int cs = (d.inMilliseconds % 1000) ~/ 10;
  return SizedBox(
    width: double.infinity,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: hms ? _fmtHms(d) : _fmt(d), style: _bigNum),
            TextSpan(
              text: '.${cs.toString().padLeft(2, '0')}',
              style: _bigNum.copyWith(fontSize: 56, color: Colors.white54),
            ),
          ],
        ),
      ),
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
        final bool running = _t.running;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _caps(running
                ? 'TIME REMAINING  剩余'
                : 'DURATION  时长  ·  上下拨动各位数字'),
            const SizedBox(height: 14),
            // 运行中纯展示；未运行时按位滚轮（时:分:秒，各自独立可拨）。
            if (running)
              _bigWithMillis(_t.remaining, hms: true)
            else
              _TimeWheels(
                key: const ValueKey<String>('countdown-wheels'),
                syncTo: _t.remaining,
                onChanged: (Duration d) => _t.setDuration(d),
              ),
            const SizedBox(height: 16),
            _thinBar(running ? _t.progress : 0),
            if (_t.finished) ...<Widget>[
              const SizedBox(height: 12),
              _caps('TIME IS UP  时间到', color: Colors.white),
            ],
            const SizedBox(height: 28),
            // 左右滑动切换预设（沿用原设计）。
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
                  _caps('QUICK PICK  快捷时长  ·  左右滑动切换'),
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

/// 按时:分:秒三位独立滚轮，视觉连排如普通大字，每格 1 单位、不加速。
/// 自持控制器与选中态，父级重建不打断滑动；仅通过 [onChanged] 上报时长。
/// [syncTo] 变化（暂停/重置等）时会把三段硬跳到该值。
class _TimeWheels extends StatefulWidget {
  const _TimeWheels({super.key, required this.syncTo, required this.onChanged});

  final Duration syncTo;
  final ValueChanged<Duration> onChanged;

  @override
  State<_TimeWheels> createState() => _TimeWheelsState();
}

class _TimeWheelsState extends State<_TimeWheels> {
  late final FixedExtentScrollController _hc;
  late final FixedExtentScrollController _mc;
  late final FixedExtentScrollController _sc;

  /// 单格高度，与大字行高一致。
  static const double _extent = 132;

  @override
  void initState() {
    super.initState();
    _hc = FixedExtentScrollController(initialItem: widget.syncTo.inHours);
    _mc =
        FixedExtentScrollController(initialItem: widget.syncTo.inMinutes % 60);
    _sc =
        FixedExtentScrollController(initialItem: widget.syncTo.inSeconds % 60);
  }

  @override
  void didUpdateWidget(_TimeWheels old) {
    super.didUpdateWidget(old);
    if (widget.syncTo != old.syncTo) _jumpTo(widget.syncTo);
  }

  /// 把三段跳到指定值（暂停/重置后回到剩余时间）。
  void _jumpTo(Duration d) {
    if (_hc.hasClients) _hc.jumpToItem(d.inHours);
    if (_mc.hasClients) _mc.jumpToItem(d.inMinutes % 60);
    if (_sc.hasClients) _sc.jumpToItem(d.inSeconds % 60);
  }

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _report() {
    widget.onChanged(Duration(
      hours: _hc.selectedItem,
      minutes: _mc.selectedItem,
      seconds: _sc.selectedItem,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // 底层用整串文本渲染（冒号字形与运行态完全一致），上层叠三段透明滚轮接收手势。
    // 外层容器与运行态 _bigWithMillis 保持同款（width:infinity + FittedBox），避免切换时跳动。
    final String hh = _hc.hasClients
        ? _hc.selectedItem.toString().padLeft(2, '0')
        : widget.syncTo.inHours.toString().padLeft(2, '0');
    final String mm = _mc.hasClients
        ? _mc.selectedItem.toString().padLeft(2, '0')
        : (widget.syncTo.inMinutes % 60).toString().padLeft(2, '0');
    final String ss = _sc.hasClients
        ? _sc.selectedItem.toString().padLeft(2, '0')
        : (widget.syncTo.inSeconds % 60).toString().padLeft(2, '0');
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Stack(
          children: <Widget>[
            // 视觉层：整串文本，冒号与运行态同源。作为 Stack 尺寸基准。
            Text('$hh:$mm:$ss', style: _bigNum),
            // 手势层：三段透明滚轮，各自独立可拨，覆盖在文本上。
            Positioned.fill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _seg(_hc, 24),
                  _gap(_colonWidth),
                  _seg(_mc, 60),
                  _gap(_colonWidth),
                  _seg(_sc, 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gap(double w) => SizedBox(width: w);

  /// 单段滚轮：等宽两位数字，外观与倒计时大字一致（无透视、无淡出）。
  /// 透明滚动区：仅接收手势并维护选中项；数字由底层整串文本统一绘制。
  /// 宽度取 '_bigNum' 下两位数字的自然宽度，与整串文本 'HH:MM:SS' 对齐。
  Widget _seg(FixedExtentScrollController c, int count) {
    return SizedBox(
      width: _segWidth,
      child: ListWheelScrollView.useDelegate(
        controller: c,
        itemExtent: _extent,
        perspective: 0.0001,
        diameterRatio: 100,
        overAndUnderCenterOpacity: 1,
        squeeze: 1,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (_) => _report(),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (BuildContext context, int i) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// '_bigNum' 下 '00' 的自然宽度（含字距），用于让三段滚轮与整串文本对齐。
final double _segWidth = () {
  final TextPainter tp = TextPainter(
    text: const TextSpan(text: '00', style: _bigNum),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}();

/// '_bigNum' 下 ':' 的自然宽度，用于滚轮三段之间的间距。
final double _colonWidth = () {
  final TextPainter tp = TextPainter(
    text: const TextSpan(text: ':', style: _bigNum),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}();

// ---------------- 秒表 ----------------
class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab({super.key, required this.settings});
  final Settings settings;
  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab> {
  final StopwatchTimer _w = StopwatchTimer();

  /// 抬头检测：秒表运行且设置里已启用时自动开相机；暂停/停止即释放。
  final FacePitchMonitor _face = FacePitchMonitor();

  /// 上次是否已应用设置里的基准/阈值，避免重复写入。
  bool _appliedSettings = false;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    // 每次抬头自动计一次（与手点「计次」等效，写入 Lap 列表）。
    _face.onHeadUp = (DateTime at, int? gap) {
      _w.lap();
    };
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _face.dispose();
    _w.dispose();
    super.dispose();
  }

  /// 设置变化：把启用状态/阈值/基准同步到检测器，并按需开关相机。
  void _onSettings() {
    _applyFaceSettings();
    _syncCamera();
  }

  void _applyFaceSettings() {
    final Settings s = widget.settings;
    _face.thresholdDelta.value = s.faceThreshold;
    _face.holdDuration = s.faceHold;
    final double? b = s.faceBaseline;
    if (b != null && _face.baseline.value != b) _face.baseline.value = b;
  }

  /// 秒表运行状态变化时同步相机（仅在启用检测且运行时开）。
  void _syncCamera() {
    final bool want = widget.settings.faceEnabled && _w.running;
    if (want && !_face.active) {
      _applyFaceSettings();
      _face.start();
    } else if (!want && _face.active) {
      _face.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_w, widget.settings]),
      builder: (BuildContext context, _) {
        // 运行态或设置变化时确保相机与之一致。
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
        if (!_appliedSettings) {
          _appliedSettings = true;
          _applyFaceSettings();
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              _caps('ELAPSED  已用时'),
              const SizedBox(height: 14),
              _bigWithMillis(_w.elapsed),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _textAction(_w.running ? '暂停' : '开始',
                          _w.running ? _w.pause : _w.start, primary: true),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _textAction('计次', _w.running ? _w.lap : null),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: _textAction('重置', _w.reset)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (int i = 0; i < _w.laps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      _caps('LAP ${(_w.laps.length - i).toString().padLeft(2, '0')}'),
                      const SizedBox(width: 14),
                      // 本段用时（距上次计次）为主。
                      Text(
                        _fmt(_w.laps[i].segment, withMillis: true),
                        style: const TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                      const Spacer(),
                      // 累计用时为次。
                      Text(
                        _fmt(_w.laps[i].total, withMillis: true),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.5),
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
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

/// 细进度条（缓动跟随，避免跳变）。随可用宽度自适应，最宽 420。
Widget _thinBar(double v) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
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

/// 文字动作按钮：primary 时加边框强调。命中区最小 60 高，便于触按。
Widget _textAction(String label, VoidCallback? onTap, {bool primary = false}) {
  final bool on = onTap != null;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Opacity(
      opacity: on ? 1 : 0.35,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: primary
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          border: primary
              ? Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5)
              : Border.all(color: Colors.white30, width: 1),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60, minWidth: 132),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 22,
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

/// 文字选项按钮：选中时加下划线并加粗，用于快捷时长。
Widget _textChoice(String label, bool selected, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? Colors.white : Colors.white54,
              ),
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
