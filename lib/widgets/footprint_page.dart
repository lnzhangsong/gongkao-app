import 'package:flutter/material.dart';

import '../data/usage_stats.dart';
import 'wallpaper_background.dart';

/// 今日足迹：读取系统使用统计，列出当天用过的应用及时长。
/// 需在系统设置授予「使用情况访问」特殊权限；数据仅在本机展示。
class FootprintPage extends StatefulWidget {
  const FootprintPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<FootprintPage> createState() => _FootprintPageState();
}

class _FootprintPageState extends State<FootprintPage>
    with WidgetsBindingObserver {
  static const UsageStats _stats = UsageStats();

  bool _loading = true;
  bool _authorized = false;
  List<AppUsage> _usages = <AppUsage>[];
  List<UsageSegment> _segments = <UsageSegment>[];
  int _tab = 0; // 0=总览, 1=时间线

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回后自动重新检测授权并刷新。
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bool ok = await _stats.hasPermission();
    final List<AppUsage> list = ok ? await _stats.today() : <AppUsage>[];
    final List<UsageSegment> segs =
        ok ? await _stats.timeline() : <UsageSegment>[];
    if (!mounted) return;
    setState(() {
      _authorized = ok;
      _usages = list;
      _segments = segs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: WallpaperBackground()),
        Positioned.fill(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double pad = c.maxWidth < 600 ? 20 : 40;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _back(),
                      const SizedBox(height: 16),
                      _title(),
                      if (_authorized && !_loading) ...<Widget>[
                        const SizedBox(height: 14),
                        _tabBar(),
                      ],
                      const SizedBox(height: 16),
                      Expanded(child: _content()),
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

  Widget _title() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '今日足迹',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _authorized ? _summary() : 'TODAY  ·  需要「使用情况访问」权限',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 1,
            ),
          ),
        ],
      );

  String _summary() {
    if (_usages.isEmpty) return '今天还没有使用记录';
    final Duration total = _usages.fold(
      Duration.zero,
      (Duration a, AppUsage u) => a + u.duration,
    );
    return '共 ${_usages.length} 个应用 · 累计 ${_fmtDur(total)}';
  }

  Widget _tabBar() {
    Widget item(String label, int index) {
      final bool sel = _tab == index;
      return InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                  color: sel
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                width: 56,
                color: sel ? Colors.white : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        item('总览', 0),
        const SizedBox(width: 20),
        item('时间线', 1),
      ],
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      );
    }
    if (!_authorized) return _needPermission();
    return _tab == 0 ? _overview() : _timeline();
  }

  Widget _overview() {
    if (_usages.isEmpty) {
      return Center(
        child: Text(
          '今天还没有使用记录',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }
    final int maxMs = _usages.first.millis;
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _usages.length,
      separatorBuilder: (BuildContext context, int index) => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.10),
      ),
      itemBuilder: (BuildContext context, int i) => _row(_usages[i], maxMs),
    );
  }

  Widget _timeline() {
    if (_segments.isEmpty) {
      return Center(
        child: Text(
          '今天还没有可还原的时间线',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _segments.length,
      itemBuilder: (BuildContext context, int i) => _segRow(_segments[i]),
    );
  }

  Widget _segRow(UsageSegment s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              _fmtClock(s.startAt),
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.75),
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures()
                ],
              ),
            ),
          ),
          Container(
            width: 2,
            height: 34,
            margin: const EdgeInsets.only(right: 14, top: 2),
            color: Colors.white.withValues(alpha: 0.25),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtClock(s.startAt)} – ${_fmtClock(s.endAt)} · ${_fmtDur(s.duration)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtClock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _row(AppUsage u, int maxMs) {
    final double frac = maxMs == 0 ? 0 : u.millis / maxMs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  u.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _fmtDur(u.duration),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _needPermission() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '需要「使用情况访问」权限才能统计今天用过哪些应用。\n'
              '数据只在你的设备上展示，不会上传。',
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: _openSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: const Text('去授权',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 18),
                TextButton(
                  onPressed: _load,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(0, 52),
                  ),
                  child: const Text('已授权，刷新',
                      style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await _stats.openSettings();
  }

  static String _fmtDur(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes % 60;
    final int s = d.inSeconds % 60;
    if (h > 0) return '$h 时 $m 分';
    if (m > 0) return '$m 分 $s 秒';
    return '$s 秒';
  }
}
