import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/content_repo.dart';
import '../data/models.dart';
import '../settings.dart';
import 'content_card.dart';
import 'date_pane.dart';
import 'wallpaper_background.dart';

/// 台历自适应容器：LayoutBuilder 按宽度分流两栏 / 单栏，内容卡轮播。
class PadHome extends StatefulWidget {
  const PadHome({super.key, required this.settings});

  final Settings settings;

  @override
  State<PadHome> createState() => _PadHomeState();
}

class _PadHomeState extends State<PadHome> {
  final ContentRepo _repo = ContentRepo();

  /// 全量内容，按主题分组。
  Map<String, List<CardItem>> _byKind = <String, List<CardItem>>{};

  /// 当前主题下用于轮播的条目列表（由 _byKind 与设置推导）。
  List<CardItem> _items = <CardItem>[];
  int _index = 0;
  Timer? _timer;

  Settings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    // 首帧渲染完成后再加载内容，避免大 JSON 解析阻塞首帧导致窗口尺寸异常。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _restartTimer();
    _settings.addListener(_onSettingsChanged);
  }

  /// 设置变化：主题或参与项变化时重建列表，并重置定时器。
  void _onSettingsChanged() {
    _rebuildItems(reset: true);
    _restartTimer();
  }

  /// 按设置里的间隔（重新）起自动轮播定时器。
  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_settings.interval, (_) => _next());
  }

  Future<void> _load() async {
    final Map<String, List<CardItem>> byKind = await _repo.loadByKind();
    if (!mounted) return;
    setState(() => _byKind = byKind);
    _rebuildItems(reset: true);
  }

  /// 依据「当前主题」重建轮播列表。reset 时回到第一条。
  void _rebuildItems({bool reset = false}) {
    final String kind = _settings.currentKind;
    final List<CardItem> list = _byKind[kind] ?? <CardItem>[];
    setState(() {
      _items = list;
      if (reset || _index >= _items.length) _index = 0;
    });
  }

  void _next() {
    if (_items.isEmpty || !mounted) return;
    setState(() => _index = (_index + 1) % _items.length);
  }

  /// 手动切下一条：切完重置定时器，避免紧接着又被自动轮播切走。
  void _nextByUser() {
    _next();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: WallpaperBackground()),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool twoColumn = constraints.maxWidth >= wideBreakpoint;
              return Padding(
                padding: EdgeInsets.all(twoColumn ? 40 : 20),
                child: twoColumn ? _twoColumn() : _singleColumn(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _twoColumn() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          flex: 4,
          child: Align(
            alignment: Alignment.centerLeft,
            child: const DatePane(twoColumn: true),
          ),
        ),
        const SizedBox(width: 40),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _kindBar(),
              const SizedBox(height: 12),
              Expanded(child: _contentArea()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _singleColumn() {
    // 竖屏：hero 固定在上方定距处，位置不随内容长度变化；
    // 内容区占据剩余空间并在其中居中，内容长短只影响自身，不牵动 hero。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 72),
        const DatePane(twoColumn: false),
        const SizedBox(height: 28),
        _kindBar(),
        const SizedBox(height: 12),
        Expanded(child: _contentArea()),
      ],
    );
  }

  /// 主题选择条：只显示参与轮播的主题，点选后只看该类。窄窗自动换行。
  Widget _kindBar() {
    final List<String> kinds = allKinds
        .where((String k) => _settings.isKindEnabled(k))
        .toList(growable: false);
    final String cur = _settings.currentKind;
    return Wrap(
      spacing: 22,
      runSpacing: 4,
      children: <Widget>[
        for (final String kind in kinds) _kindTab(kind, kind == cur),
      ],
    );
  }

  Widget _kindTab(String kind, bool on) {
    final Color color = kindColor(kind);
    return InkWell(
      onTap: () => _settings.setCurrentKind(kind),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: on ? color : color.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  kind,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? Colors.white : Colors.white54,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Container(
              height: 2,
              width: 40,
              color: on ? Colors.white : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentArea({bool center = true}) {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '「${_settings.currentKind}」暂无内容',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final CardItem item = _items[_index];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _nextByUser,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
          alignment: center ? Alignment.center : Alignment.topLeft,
          children: <Widget>[
            ...previous,
            ?current,
          ],
        ),
        transitionBuilder: (Widget child, Animation<double> anim) =>
            FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey<String>('${item.kind}-${item.title}-$_index'),
          child: ContentCard(item: item, center: center),
        ),
      ),
    );
  }
}
