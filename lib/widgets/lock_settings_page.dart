import 'package:flutter/material.dart';

import '../kiosk.dart';
import '../lock_schedule.dart';
import '../settings.dart';
import 'kiosk_guide.dart';
import 'lock_sheets.dart';
import 'wallpaper_background.dart';

/// 锁定设置的独立页面。
///
/// 手机端的时钟首页只负责显示，所有开关 / 时段 / 强度都收在这里；
/// 平板设置页也从同一个页面进入，两端共用同一个 [Settings] 实例，
/// 任意一端改动都会立刻同步到另一端。
class LockSettingsPage extends StatefulWidget {
  const LockSettingsPage({
    super.key,
    required this.settings,
    required this.onBack,
  });

  final Settings settings;
  final VoidCallback onBack;

  @override
  State<LockSettingsPage> createState() => _LockSettingsPageState();
}

class _LockSettingsPageState extends State<LockSettingsPage>
    with WidgetsBindingObserver {
  KioskStatus _kiosk = const KioskStatus();

  /// 是否已经从原生侧取到过一次状态（用于避免首帧闪一下「待处理」）。
  bool _kioskLoaded = false;

  /// 读取状态的序号，防止并发返回时旧值覆盖新值。
  int _kioskSeq = 0;

  Settings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    _reloadKiosk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 去系统设置授权后返回，必须重新读一次，否则界面一直停在旧状态。
    if (state == AppLifecycleState.resumed) _reloadKiosk();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadKiosk() async {
    // 页面可能同时被 initState 与 resumed 触发，用序号防止旧结果覆盖新结果。
    final int seq = ++_kioskSeq;
    final KioskStatus st = await Kiosk.status();
    if (!mounted || seq != _kioskSeq) return;
    setState(() {
      _kiosk = st;
      _kioskLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<LockPeriod> periods = _settings.lockPeriods;
    final int totalMin = periods.fold<int>(
        0, (int sum, LockPeriod p) => sum + p.durationMinutes);
    final DateTime now = DateTime.now();
    final DateTime? skip = _settings.lockSkipUntil;
    final bool skipped = skip != null && now.isBefore(skip);
    final EdgeInsets insets = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF0E1116))),
          const Positioned.fill(child: WallpaperBackground(boost: 0.30)),
          Positioned.fill(
            child: ListView(
              padding:
                  EdgeInsets.fromLTRB(20, 8 + insets.top, 20, 32 + insets.bottom),
              children: <Widget>[
                _header(),
                const SizedBox(height: 18),
                _masterCard(),
                if (skip != null && skipped) _skipNotice(skip),
                const SizedBox(height: 24),
                _sectionTitle(
                  '锁定时段',
                  periods.isEmpty
                      ? '还没有时段'
                      : '${periods.length} 段 · 每天共 ${_hoursText(totalMin)}',
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < periods.length; i++)
                  _periodRow(i, periods[i], skipped: skipped),
                if (periods.isEmpty) _emptyState(),
                const SizedBox(height: 6),
                _addButton(),
                const SizedBox(height: 26),
                _strengthSection(),
                const SizedBox(height: 22),
                const Text(
                  '到点自动全屏锁定，可用「提前解锁本次」临时放行；'
                  '解锁早于开始时按跨午夜（次日）计算。',
                  style: TextStyle(
                      fontSize: 12, height: 1.6, color: Colors.white30),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 放行期间改时段不会重新锁上——把这件事说清楚，免得以为设置没生效。
  Widget _skipNotice(DateTime until) {
    final String hh = until.hour.toString().padLeft(2, '0');
    final String mm = until.minute.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_open_rounded,
              size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '本次已放行到 $hh:$mm。改时段不会重新锁上；'
              '想立刻锁回去，返回首页点「再次锁定」。',
              style: const TextStyle(
                  fontSize: 12, height: 1.6, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 22),
          color: Colors.white70,
          splashRadius: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(width: 6),
        const Text(
          '锁定设置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// 总开关卡片：一眼看清现在是开还是关。
  Widget _masterCard() {
    final bool on = _settings.lockEnabled;
    final bool configured = _settings.lockPeriods.isNotEmpty;
    final String sub = !on
        ? '打开后按下面的时段自动锁定'
        : !configured
            ? '已开启，但还没有时段，不会锁定'
            : '已开启 · 到点自动全屏锁定';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '自动锁定',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
          const Spacer(),
          Switch(
            value: on,
            onChanged: (bool v) => _settings.setLockEnabled(v),
            activeThumbColor: Colors.white,
            activeTrackColor: sheetAccent,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            sub,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ),
      ],
    );
  }

  /// 单段：整行可点进编辑弹层；正在生效的段高亮。
  Widget _periodRow(int index, LockPeriod p, {required bool skipped}) {
    final bool active =
        LockSchedule(<LockPeriod>[p]).activeEnd(DateTime.now()) != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: active
            ? sheetAccent.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _editPeriod(index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          fmtMinute(p.start),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            color: Colors.white,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 9),
                          child: Text('→',
                              style:
                                  TextStyle(fontSize: 14, color: Colors.white30)),
                        ),
                        Text(
                          fmtMinute(p.end),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            color: Colors.white,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        if (p.isAllDay)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text('全天',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white38)),
                          )
                        else if (p.crossesMidnight)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text('次日',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white38)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (active)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: sheetAccent.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      skipped ? '已放行' : '生效中',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                Text(
                  _rowDuration(p.durationMinutes),
                  style: const TextStyle(fontSize: 11, color: Colors.white30),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          '还没有时段，点下面一行添加',
          style: TextStyle(fontSize: 13, color: Colors.white30),
        ),
      );

  Widget _addButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton.icon(
        onPressed: _addPeriod,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('添加时段', style: TextStyle(fontSize: 14)),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white60,
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
      ),
    );
  }

  /// 锁定强度：屏幕固定 / 后台守护 / 开机自启。
  Widget _strengthSection() {
    final bool strict = _kiosk.deviceOwner;
    final bool pinOk = strict || _kiosk.supported;
    final bool ready = pinOk && _kiosk.overlay;
    // 首帧还没拿到原生状态时，副标题不急着下结论。
    final String head = !_kioskLoaded
        ? '读取中…'
        : ready
            ? '已就绪'
            : '有未处理的项';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            const Text(
              '锁定强度',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Text(
              head,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(width: 4),
            // 有些 ROM 的授权弹窗不会让 Activity 走 pause/resume，
            // 留一个手动重读的入口，免得只能退出页面才更新。
            InkResponse(
              onTap: _reloadKiosk,
              radius: 18,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.refresh, size: 15, color: Colors.white30),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await showKioskGuideSheet(context, status: _kiosk);
              // 弹层里可能刚去系统设置授过权，关掉后再读一次。
              await _reloadKiosk();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Column(
                children: <Widget>[
                  _strengthRow(
                    icon: Icons.lock_outline,
                    title: '系统锁定',
                    detail: strict
                        ? '严格模式 · 锁定期无法退出'
                        : pinOk
                            ? '已就绪 · 通知栏、控制中心、桌面均被拦下'
                            : '当前设备不支持系统锁定',
                    ok: pinOk,
                  ),
                  _strengthDivider(),
                  _strengthRow(
                    icon: Icons.shield_moon_outlined,
                    title: '后台守护',
                    detail: _kiosk.overlay
                        ? '被切走会自动拉回锁定界面'
                        : '未授权 · 切走后无法拉回',
                    ok: _kiosk.overlay,
                  ),
                  _strengthDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.restart_alt,
                            size: 16, color: Colors.white38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                '开机自启',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _settings.lockAutoStart
                                    ? '重启后仍在锁定期会直接锁定'
                                    : '已关闭 · 重启可以绕过锁定',
                                style: const TextStyle(
                                    fontSize: 11.5, color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _settings.lockAutoStart,
                          onChanged: (bool v) => _settings.setLockAutoStart(v),
                          activeThumbColor: Colors.white,
                          activeTrackColor: sheetAccent,
                          inactiveThumbColor: Colors.white70,
                          inactiveTrackColor: Colors.white24,
                        ),
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

  Widget _strengthRow({
    required IconData icon,
    required String title,
    required String detail,
    required bool ok,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ok ? Colors.white38 : const Color(0xFFB4794A),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: ok ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }

  Widget _strengthDivider() => Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.06),
      );

  /// 新增一段，并直接打开编辑弹层让人马上设时间。
  Future<void> _addPeriod() async {
    await _settings.addLockPeriod();
    if (!mounted) return;
    await _editPeriod(_settings.lockPeriods.length - 1);
  }

  Future<void> _editPeriod(int index) async {
    if (index < 0 || index >= _settings.lockPeriods.length) return;
    final PeriodSheetResult? result = await showPeriodSheet(
      context,
      title: '锁定时段 ${index + 1}',
      period: _settings.lockPeriods[index],
    );
    if (result == null) return;
    if (result.deleted) {
      await _settings.removeLockPeriod(index);
      return;
    }
    await _settings.setLockPeriod(index, result.period!);
  }

  static String _hoursText(int minutes) {
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    final int h = minutes ~/ 60;
    return h == 0 ? '$minutes 分钟' : '$h 小时 ${minutes % 60} 分';
  }

  /// 列表行里的时长要短，避免挤压时间块：4h / 1h30m / 45m。
  static String _rowDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m}m';
  }
}
