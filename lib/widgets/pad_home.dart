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
    _settings.addListener(_restartTimer);
  }

  /// 按设置里的间隔（重新）起自动轮播定时器。
  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_settings.interval, (_) => _next());
  }

  Future<void> _load() async {
    final List<CardItem> items = await _repo.load();
    if (!mounted) return;
    setState(() => _items = items);
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
    _settings.removeListener(_restartTimer);
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
        Expanded(flex: 6, child: _contentArea()),
      ],
    );
  }

  Widget _singleColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const DatePane(twoColumn: false),
        const SizedBox(height: 24),
        Expanded(child: _contentArea()),
      ],
    );
  }

  Widget _contentArea() {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '内容尚未就位，先看日期吧',
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
          child: ContentCard(item: item),
        ),
      ),
    );
  }
}
