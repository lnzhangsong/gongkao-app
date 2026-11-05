import 'package:flutter/material.dart';

import '../app_limit.dart';
import '../kiosk.dart';
import '../lock_schedule.dart';
import '../settings.dart';
import 'lock_sheets.dart';

// 应用限制的两个弹层：挑应用、给某个应用配时段。
//
// 配色沿用锁定设置页的夜间风格（不受浅色主题影响），和时段弹层保持一致。

/// 从已安装应用里挑一个加进限制列表。
///
/// [exclude] 是已经在列表里的包名，避免重复添加。
Future<InstalledApp?> showAppPickerSheet(
  BuildContext context, {
  required Set<String> exclude,
}) {
  return showModalBottomSheet<InstalledApp>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (BuildContext ctx) => _AppPickerSheet(exclude: exclude),
  );
}

class _AppPickerSheet extends StatefulWidget {
  const _AppPickerSheet({required this.exclude});

  final Set<String> exclude;

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  List<InstalledApp> _all = const <InstalledApp>[];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<InstalledApp> apps = await Kiosk.listApps();
    if (!mounted) return;
    setState(() {
      _all = apps.where((InstalledApp a) => !widget.exclude.contains(a.package)).toList();
      _loading = false;
    });
  }

  List<InstalledApp> get _filtered {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((InstalledApp a) =>
            a.label.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.72;
    return Material(
      color: sheetBg,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            children: <Widget>[
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const Text(
                    '选择应用',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (String v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14, color: Colors.white),
                cursorColor: sheetAccent,
                decoration: InputDecoration(
                  hintText: '搜索应用名或包名',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.white30),
                  prefixIcon:
                      const Icon(Icons.search, size: 18, color: Colors.white30),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: sheetAccent),
        ),
      );
    }
    final List<InstalledApp> items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _all.isEmpty ? '没有可选的应用' : '没有匹配的应用',
          style: const TextStyle(fontSize: 13, color: Colors.white30),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (BuildContext ctx, int i) {
        final InstalledApp a = items[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).pop(a),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(
                children: <Widget>[
                  _AppAvatar(label: a.label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          a.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.package,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white30),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 应用首字圆形图标：拿不到真实图标时也有个视觉落点。
class _AppAvatar extends StatelessWidget {
  const _AppAvatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // 用 runes 取首个码位：直接 substring(0,1) 遇到 emoji 会截成半个字符。
    final String ch =
        label.isEmpty ? '?' : String.fromCharCode(label.runes.first);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        ch,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
        ),
      ),
    );
  }
}

/// 给某个应用配置限用规则：独立时段 + 是否叠加锁机时段。
Future<void> showAppLimitSheet(
  BuildContext context, {
  required Settings settings,
  required AppLimit limit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (BuildContext ctx) =>
        _AppLimitSheet(settings: settings, initial: limit),
  );
}

class _AppLimitSheet extends StatefulWidget {
  const _AppLimitSheet({required this.settings, required this.initial});

  final Settings settings;
  final AppLimit initial;

  @override
  State<_AppLimitSheet> createState() => _AppLimitSheetState();
}

class _AppLimitSheetState extends State<_AppLimitSheet> {
  late AppLimit _limit = widget.initial;

  Future<void> _apply(AppLimit next) async {
    setState(() => _limit = next);
    await widget.settings.updateAppLimit(next);
  }

  Future<void> _addPeriod() async {
    final LockPeriod base = _limit.periods.isEmpty
        ? const LockPeriod(start: 8 * 60, end: 12 * 60)
        : LockPeriod(
            start: _limit.periods.last.end,
            end: (_limit.periods.last.end + 4 * 60) % kDayMinutes,
          );
    final List<LockPeriod> next = <LockPeriod>[..._limit.periods, base];
    await _apply(_limit.copyWith(periods: next));
    if (!mounted) return;
    await _editPeriod(next.length - 1);
  }

  Future<void> _editPeriod(int index) async {
    if (index < 0 || index >= _limit.periods.length) return;
    final PeriodSheetResult? r = await showPeriodSheet(
      context,
      title: '限用时段 ${index + 1}',
      period: _limit.periods[index],
    );
    if (r == null) return;
    final List<LockPeriod> next = List<LockPeriod>.of(_limit.periods);
    if (r.deleted) {
      next.removeAt(index);
    } else {
      next[index] = r.period!;
    }
    await _apply(_limit.copyWith(periods: next));
  }

  Future<void> _remove() async {
    await widget.settings.removeAppLimit(_limit.package);
    if (mounted) Navigator.of(context).pop();
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
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                _AppAvatar(label: _limit.label),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _limit.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '到点打开会被弹回，直到时段结束',
                        style: TextStyle(fontSize: 11.5, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 叠加规则放在最上面：它和下面的独立时段是并行的两套判据。
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '锁定时段内也拦',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '锁机时提前解锁了，这个应用依然不许用',
                          style:
                              TextStyle(fontSize: 11.5, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _limit.duringLock,
                    onChanged: (bool v) =>
                        _apply(_limit.copyWith(duringLock: v)),
                    activeThumbColor: Colors.white,
                    activeTrackColor: sheetAccent,
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white24,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Text(
                  '独立限用时段',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  _limit.periods.isEmpty ? '未设置' : '${_limit.periods.length} 段',
                  style: const TextStyle(fontSize: 12, color: Colors.white30),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < _limit.periods.length; i++)
              _periodRow(i, _limit.periods[i]),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: TextButton.icon(
                onPressed: _addPeriod,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('添加时段', style: TextStyle(fontSize: 13.5)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white60,
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _remove,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('移除该应用', style: TextStyle(fontSize: 14)),
                ),
                const Spacer(),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
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

  Widget _periodRow(int index, LockPeriod p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _editPeriod(index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            child: Row(
              children: <Widget>[
                Text(
                  p.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
