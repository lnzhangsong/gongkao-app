import 'dart:async';

import 'package:flutter/material.dart';

import '../app_limit.dart';
import '../kiosk.dart';
import '../lock_schedule.dart';
import '../settings.dart';
import 'app_limit_sheets.dart';
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

  /// Shizuku 状态：not_installed / not_running / denied / ready。
  ///
  /// 只有 ready 才能 `pm disable-user`，也就是到点把应用真正禁用掉。
  String _shizuku = 'unknown';

  /// 有「已上锁且正在生效」的时段时，自动锁定总开关也跟着只读。
  ///
  /// 只管总开关和开机自启：这两项是绕过所有时段的旁路，
  /// 留着可改等于给了一把万能钥匙。
  bool _masterLocked = false;

  /// 应用限制里最晚的解除时刻（只统计已上锁、且正在生效的规则）。
  DateTime? _appLockEnd;

  /// 定时重算 [_locked]：跨过时段边界时页面要自己醒过来。
  Timer? _ticker;

  Settings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    _reloadKiosk();
    _reloadGuard();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      // 无条件重建：这段里「生效中」标签、解除时刻、只读态都跟当前时间有关，
      // 与其逐项比对不如整体刷一次，页面不大，代价可以忽略。
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 去系统设置授权后返回，必须重新读一次，否则界面一直停在旧状态。
    if (state == AppLifecycleState.resumed) {
      _reloadKiosk();
      _reloadGuard();
    }
  }

  /// 刷新 Shizuku 状态（应用限制能不能到点禁用，全看它）。
  Future<void> _reloadGuard() async {
    final String shizuku = await Kiosk.shizukuStatus();
    if (!mounted) return;
    setState(() => _shizuku = shizuku);
  }

  /// 把被本应用禁用的应用全部恢复回来（防手滑，也是规则配错时的出口）。
  Future<void> _restoreAll() async {
    final int n = await Kiosk.restoreDisabledApps();
    if (!mounted) return;
    final String msg = n < 0
        ? '无法恢复：Shizuku 未就绪'
        : (n == 0 ? '没有被禁用的应用' : '已恢复 $n 个应用');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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
    final DateTime? guardEnd = _lockedEnd(periods, now);
    // 自动锁定关着就没所谓「锁定期间」：这时总开关必须能自由开关，
    // 否则会出现「想开却开不了、提示条还说你正在锁定」的怪状态。
    _masterLocked = guardEnd != null && _settings.lockEnabled;

    // 应用限制：只有当「已上锁的那些规则」里真有正在生效的，才算被保护。
    // 判据和下面 _appLimitSection 一致——用整机时段本身，不看提前解锁。
    final Map<String, DateTime> limiting = activeLimits(
      _settings.appLimits,
      now,
      lockEnd: _settings.lockEnabled
          ? LockSchedule(_settings.lockPeriods).activeEnd(now)
          : null,
    );
    DateTime? appEnd;
    for (final AppLimit l in _settings.appLimits) {
      if (!l.locked) continue;
      final DateTime? e = limiting[l.package];
      if (e == null) continue;
      if (appEnd == null || e.isAfter(appEnd)) appEnd = e;
    }
    _appLockEnd = appEnd;
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
                if (_masterLocked && guardEnd != null) _lockedNotice(guardEnd),
                if (skip != null && skipped) _skipNotice(skip),
                const SizedBox(height: 24),
                _sectionTitle(
                  '锁定时段',
                  periods.isEmpty
                      ? '还没有时段'
                      : '${periods.length} 段 · 每天共 ${_hoursText(totalMin)}',
                ),
                const SizedBox(height: 6),
                const Text(
                  '右侧两个小图标，从左到右：钥匙 = 这一段还给不给「提前解锁」；'
                  '锁 = 生效期间不许改这一条。',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.5, color: Colors.white30),
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < periods.length; i++)
                  _periodRow(i, periods[i], skipped: skipped),
                if (periods.isEmpty) _emptyState(),
                const SizedBox(height: 6),
                _addButton(),
                const SizedBox(height: 26),
                _mottoSection(),
                const SizedBox(height: 26),
                _appLimitSection(),
                const SizedBox(height: 26),
                _strengthSection(),
                const SizedBox(height: 22),
                const Text(
                  '到点自动全屏锁定；留着钥匙的时段可以用「提前解锁本次」临时放行，'
                  '关掉钥匙的就只能等。解锁早于开始时按跨午夜（次日）计算。',
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

  /// 有加锁的时段正在生效时的提示条。
  ///
  /// 「提前解锁」也照样拦：那个只放行屏幕，不放开规则修改。
  Widget _lockedNotice(DateTime until) {
    final String hh = until.hour.toString().padLeft(2, '0');
    final String mm = until.minute.toString().padLeft(2, '0');
    final DateTime now = DateTime.now();
    final bool tomorrow =
        until.year != now.year || until.month != now.month || until.day != now.day;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: sheetAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sheetAccent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_clock_rounded, size: 16, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '有加锁的时段正在生效，它和上面的总开关都改不了。'
              '${tomorrow ? '明天 ' : ''}$hh:$mm 解除后可以调整。',
              style: const TextStyle(
                  fontSize: 12, height: 1.6, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  /// 应用限制里的只读提示：只统计已上锁的规则。
  Widget _appLockNotice(DateTime until) {
    final String hh = until.hour.toString().padLeft(2, '0');
    final String mm = until.minute.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: sheetAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_clock_rounded, size: 15, color: Colors.white60),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '有加锁的应用正在限制中，它的规则已锁定，最晚 $hh:$mm 后可以调整。',
              style: const TextStyle(
                  fontSize: 11.5, height: 1.5, color: Colors.white70),
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
            onChanged:
                _masterLocked ? null : (bool v) => _settings.setLockEnabled(v),
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
  ///
  /// 右侧的锁是**这一条自己的**：上锁且正在生效时，这一行点不开、也删不掉。
  Widget _periodRow(int index, LockPeriod p, {required bool skipped}) {
    final bool active =
        LockSchedule(<LockPeriod>[p]).activeEnd(DateTime.now()) != null;
    final bool sealed = p.locked && active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: active
            ? sheetAccent.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: sealed ? null : () => _editPeriod(index),
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
                _rowSkipButton(
                  allow: p.allowSkip,
                  onTap: () => _togglePeriodSkip(index),
                  onLongPress: () => _emergencyAllowSkip(index),
                ),
                _rowLockButton(
                  locked: p.locked,
                  sealed: sealed,
                  onTap: () => _togglePeriodLock(index),
                  onLongPress: () => _emergencyUnlockPeriod(index),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 行尾的「放行」开关：钥匙 = 这一段还留着提前解锁，划掉钥匙 = 到点只能等。
  Widget _rowSkipButton({
    required bool allow,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return InkResponse(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Icon(
          allow ? Icons.key_rounded : Icons.key_off_rounded,
          size: 17,
          color: allow ? Colors.white54 : sheetAccent,
        ),
      ),
    );
  }

  /// 行尾的锁：点一下上锁 / 解锁，长按是紧急解除。
  ///
  /// 生效期间点它只会得到一句「X 点后才能解除」——这正是要的效果：
  /// 想改规则的那一下被挡住。长按能强解，但要多按一次并确认，
  /// 留着是为了「全天时段上锁后把自己关死」这种情况有个出口。
  Widget _rowLockButton({
    required bool locked,
    required bool sealed,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return InkResponse(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Icon(
          locked ? Icons.lock_rounded : Icons.lock_open_rounded,
          size: 17,
          color: locked
              ? (sealed ? sheetAccent : Colors.white60)
              : Colors.white24,
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

  // ── 锁屏上那句话 ──────────────────────────────────────────────────

  /// 锁屏上那句话：可以自己写，也可以直接挑一句现成的。
  Widget _mottoSection() {
    final String motto = _settings.lockMotto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle('锁屏上那句话', motto.isEmpty ? '未设置' : '已设置'),
        const SizedBox(height: 8),
        const Text(
          '锁屏时显示在倒计时下面。与其盯着一串数字，不如让它提醒你为什么要坐在这儿。',
          style: TextStyle(fontSize: 11.5, height: 1.5, color: Colors.white30),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _editMotto,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      motto.isEmpty ? '写一句，或从模板里挑' : motto,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: motto.isEmpty ? Colors.white38 : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined,
                      size: 16, color: Colors.white30),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editMotto() async {
    final TextEditingController controller =
        TextEditingController(text: _settings.lockMotto);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151A21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '锁屏上那句话',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 40,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  hintText: '例如：现在这一小时，只做一件事',
                  hintStyle: const TextStyle(color: Colors.white24),
                  counterStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '模板',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String t in Settings.mottoTemplates)
                    InkWell(
                      onTap: () => controller.text = t,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white60),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () {
                      controller.text = '';
                      _settings.setLockMotto('');
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('清空',
                        style: TextStyle(color: Colors.white38)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消',
                        style: TextStyle(color: Colors.white38)),
                  ),
                  TextButton(
                    onPressed: () {
                      _settings.setLockMotto(controller.text);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text(
                      '保存',
                      style: TextStyle(
                          color: sheetAccent, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
  }

  // ── 应用限制 ──────────────────────────────────────────────────────

  /// 应用限制区块：单独管「某几个应用在某个时段能不能打开」。
  Widget _appLimitSection() {
    final List<AppLimit> limits = _settings.appLimits;
    final DateTime now = DateTime.now();
    // 「锁定时段内也拦」用的是整机时段本身，不传 skip：
    // 提前解锁只放行整机屏幕，不该让被限制的应用跟着放行。
    final DateTime? lockEnd = _settings.lockEnabled
        ? LockSchedule(_settings.lockPeriods).activeEnd(now)
        : null;
    final Map<String, DateTime> active =
        activeLimits(limits, now, lockEnd: lockEnd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(
          '应用限制',
          limits.isEmpty ? '未设置' : '${limits.length} 个应用',
        ),
        const SizedBox(height: 8),
        const Text(
          '到点后无法打开，直到时段结束。点右侧锁图标可锁住这一条：'
          '它生效期间改不了、也删不掉。',
          style: TextStyle(fontSize: 11.5, height: 1.5, color: Colors.white30),
        ),
        const SizedBox(height: 10),
        _guardStatusRow(),
        if (_appLockEnd != null) _appLockNotice(_appLockEnd!),
        for (final AppLimit l in limits)
          _appLimitRow(l, activeEnd: active[l.package]),
        _addAppButton(),
        const SizedBox(height: 4),
        _restoreButton(),
      ],
    );
  }

  /// 应用限制生效的前置条件。
  ///
  /// 有 Shizuku（拿到 shell 身份）就到点直接 `pm disable-user`：图标从桌面
  /// 消失、点图标系统直接拒启，不存在「打开再踢回去」。没有它时降级成
  /// 「点开再弹回桌面」，靠无障碍兜住，但做不到图标消失。
  Widget _guardStatusRow() {
    final bool ready = _shizuku == 'ready';

    String text;
    String action = '';
    VoidCallback? onTap;

    if (_shizuku == 'ready') {
      text = '已就绪：到点直接禁用受限应用，图标消失、点不开';
    } else if (_shizuku == 'not_installed') {
      text = '未安装 Shizuku：只能做到点了再弹回，图标不会消失';
      action = '去安装';
      onTap = () => Kiosk.openShizuku();
    } else if (_shizuku == 'not_running') {
      text = 'Shizuku 未运行（重启后要重新启动它）：暂时只能点了再弹回';
      action = '去启动';
      onTap = () => Kiosk.openShizuku();
    } else if (_shizuku == 'denied') {
      text = 'Shizuku 未授权：授权后才能到点真正禁用应用';
      action = '去授权';
      onTap = () async {
        await Kiosk.requestShizuku();
        await Future<void>.delayed(const Duration(seconds: 2));
        await _reloadGuard();
      };
    } else {
      text = '正在检查 Shizuku 状态…';
    }

    final Color tint =
        ready ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);
    final Color iconColor =
        ready ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  ready ? Icons.verified_rounded : Icons.warning_amber_rounded,
                  size: 16,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: Colors.white70,
                    ),
                  ),
                ),
                if (action.isNotEmpty)
                  Text(
                    action,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF60A5FA),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 兜底出口：万一规则配错、把应用卡在禁用状态，一键全恢复。
  Widget _restoreButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: TextButton.icon(
        onPressed: _restoreAll,
        icon: const Icon(Icons.restore_rounded, size: 15),
        label: const Text('恢复所有被禁用的应用', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white38,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _appLimitRow(AppLimit limit, {DateTime? activeEnd}) {
    final bool on = activeEnd != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: on
            ? sheetAccent.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: on && limit.locked
              ? null
              : () => showAppLimitSheet(
                    context,
                    settings: _settings,
                    limit: limit,
                  ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              limit.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (on) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: sheetAccent.withValues(alpha: 0.30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '限制中',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        limit.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _rowLockButton(
                  locked: limit.locked,
                  sealed: limit.locked && on,
                  onTap: () => _toggleAppLock(limit, activeEnd: activeEnd),
                  onLongPress: () => _emergencyUnlockApp(limit),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addAppButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton.icon(
        onPressed: _addApp,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('添加应用', style: TextStyle(fontSize: 14)),
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

  /// 选一个应用加进列表，并直接打开规则编辑。
  Future<void> _addApp() async {
    final InstalledApp? app = await showAppPickerSheet(
      context,
      exclude: _settings.appLimits.map((AppLimit l) => l.package).toSet(),
    );
    if (app == null || !mounted) return;
    final AppLimit limit = AppLimit(package: app.package, label: app.label);
    await _settings.addAppLimit(limit);
    if (!mounted) return;
    await showAppLimitSheet(context, settings: _settings, limit: limit);
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
                          onChanged: _masterLocked
                              ? null
                              : (bool v) => _settings.setLockAutoStart(v),
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

  // ── 逐条上锁 ────────────────────────────────────────────────────────

  /// 所有「已上锁」的段里，此刻正在生效的最晚结束时刻；没有则 null。
  static DateTime? _lockedEnd(List<LockPeriod> periods, DateTime now) {
    DateTime? best;
    for (final LockPeriod p in periods) {
      if (!p.locked) continue;
      final DateTime? e = LockSchedule(<LockPeriod>[p]).activeEnd(now);
      if (e == null) continue;
      if (best == null || e.isAfter(best)) best = e;
    }
    return best;
  }

  /// 点钥匙：允许 ↔ 禁止提前解锁。
  ///
  /// 只许在生效期间往「更严」的方向改；想放宽得等这一段结束。
  /// 否则「关掉放行」这条设置会在最需要它的那一刻被随手撤掉。
  /// 自动锁定关着时不受这条限制——那时根本没有锁，改它不会放过任何东西。
  Future<void> _togglePeriodSkip(int index) async {
    final List<LockPeriod> list = _settings.lockPeriods;
    if (index < 0 || index >= list.length) return;
    final LockPeriod p = list[index];
    final DateTime? end =
        LockSchedule(<LockPeriod>[p]).activeEnd(DateTime.now());
    if (!p.allowSkip && end != null && _settings.lockEnabled) {
      _toast('这一段正在生效，${_hhmm(end)} 后才能改回来');
      return;
    }
    await _settings.setLockPeriodAllowSkip(index, !p.allowSkip);
    if (!mounted) return;
    _toast(p.allowSkip ? '已关闭提前解锁：到点只能等' : '已允许提前解锁');
  }

  /// 长按钥匙的出口：误把某段设成「不许放行」后，还能有条路退回来。
  Future<void> _emergencyAllowSkip(int index) async {
    final List<LockPeriod> list = _settings.lockPeriods;
    if (index < 0 || index >= list.length) return;
    if (list[index].allowSkip) return;
    final bool? ok = await _confirm(
      title: '紧急恢复放行',
      body: '恢复后这一段重新显示「提前解锁本次」。自己设的限制，确定现在放开吗？',
      confirm: '恢复',
    );
    if (ok != true) return;
    await _settings.setLockPeriodAllowSkip(index, true);
    if (!mounted) return;
    _toast('已恢复提前解锁');
  }

  /// 点锁：没锁 → 上锁；锁着但没生效 → 解锁；锁着且生效中 → 只给一句提示。
  Future<void> _togglePeriodLock(int index) async {
    final List<LockPeriod> list = _settings.lockPeriods;
    if (index < 0 || index >= list.length) return;
    final LockPeriod p = list[index];
    final DateTime? end =
        LockSchedule(<LockPeriod>[p]).activeEnd(DateTime.now());

    if (p.locked && end != null && _settings.lockEnabled) {
      _toast('这一段正在生效，${_hhmm(end)} 后才能解除');
      return;
    }
    if (!p.locked && p.isAllDay) {
      final bool? ok = await _confirm(
        title: '给全天时段上锁',
        body: '全天时段一直在生效，上锁后在应用里就解不开了。'
            '长按锁图标可以紧急解除 —— 那是留给你自己破例用的。',
        confirm: '仍然上锁',
      );
      if (ok != true) return;
    }
    await _settings.setLockPeriodLocked(index, !p.locked);
    if (!mounted) return;
    _toast(p.locked ? '已解除保护' : '已上锁，生效期间改不了');
  }

  /// 长按锁图标的出口：给「上锁后永远解不开」的那类情况留一条路。
  Future<void> _emergencyUnlockPeriod(int index) async {
    final List<LockPeriod> list = _settings.lockPeriods;
    if (index < 0 || index >= list.length) return;
    final LockPeriod p = list[index];
    if (!p.locked) return;
    final bool? ok = await _confirm(
      title: '紧急解除',
      body: '解除后这一段在生效期间也能修改了。自己设的限制，确定现在拆掉吗？',
      confirm: '解除',
    );
    if (ok != true) return;
    await _settings.setLockPeriodLocked(index, false);
    if (!mounted) return;
    _toast('已解除保护');
  }

  Future<void> _toggleAppLock(AppLimit limit, {DateTime? activeEnd}) async {
    if (limit.locked && activeEnd != null) {
      _toast('这个应用正在限制中，${_hhmm(activeEnd)} 后才能解除');
      return;
    }
    await _settings.setAppLimitLocked(limit.package, !limit.locked);
    if (!mounted) return;
    _toast(limit.locked ? '已解除保护' : '已上锁，限制期间改不了');
  }

  Future<void> _emergencyUnlockApp(AppLimit limit) async {
    if (!limit.locked) return;
    final bool? ok = await _confirm(
      title: '紧急解除',
      body: '解除后这个应用在限制期间也能改规则了。自己设的限制，确定现在拆掉吗？',
      confirm: '解除',
    );
    if (ok != true) return;
    await _settings.setAppLimitLocked(limit.package, false);
    if (!mounted) return;
    _toast('已解除保护');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12.5)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    String confirm = '确定',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2028),
        title: Text(title,
            style: const TextStyle(fontSize: 16, color: Colors.white)),
        content: Text(
          body,
          style: const TextStyle(
              fontSize: 13, height: 1.6, color: Colors.white70),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirm,
                style: const TextStyle(fontSize: 13, color: sheetAccent)),
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
