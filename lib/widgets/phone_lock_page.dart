import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:lunar/lunar.dart';

import '../config.dart';
import '../kiosk.dart';
import '../lock_schedule.dart';
import '../settings.dart';
import 'lock_settings_page.dart';
import 'lock_sheets.dart' show sheetAccent;
import 'wallpaper_background.dart';

/// 手机（窄屏）首页：隐藏台历的全部功能，只留「按时锁定手机」。
///
/// 三种形态：
/// - 未锁定 → 时钟 + 锁定状态卡 + 设置入口；
/// - 锁定中 → 全屏锁屏，倒计时到解锁时刻，只留「提前解锁本次」；
/// - 设置 → 独立的 LockSettingsPage（与平板设置页共用同一份设置）。
///
/// 平板端（宽屏）不进入本页，原有台历 / 番茄钟 / 计时工具 / 足迹全部保留。
class PhoneLockPage extends StatefulWidget {
  const PhoneLockPage({super.key, required this.settings});

  final Settings settings;

  @override
  State<PhoneLockPage> createState() => _PhoneLockPageState();
}

class _PhoneLockPageState extends State<PhoneLockPage>
    with WidgetsBindingObserver {
  late final Timer _ticker;
  DateTime _now = DateTime.now();

  /// 系统级锁定状态（屏幕固定 / 悬浮窗 / 设备所有者）。
  KioskStatus _kiosk = const KioskStatus();

  /// 正在调用原生进入锁定，避免每秒重复触发。
  bool _pinBusy = false;
  bool _stopBusy = false;
  DateTime? _lastPinTry;

  Settings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    // 秒级心跳：既刷新时钟，也会在到点时自动切成锁屏 / 解锁。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _watchLock();
    });
    // 改完时段立刻反映到界面，不必等下一次心跳。
    _settings.addListener(_onSettingsChanged);
    // 开机 / 从后台回来时，原生可能已经拉起过锁定界面，这里补一次同步。
    _syncKioskConfig();
    _reloadKiosk();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _now = DateTime.now();
      _reloadKiosk();
      _watchLock();
      setState(() {});
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _syncKioskConfig();
  }

  @override
  void dispose() {
    _ticker.cancel();
    _settings.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 此刻是否锁定；锁定则返回解锁时刻。
  DateTime? get _lockedEnd => lockedEndNow(
        enabled: _settings.lockEnabled,
        periods: _settings.lockPeriods,
        now: _now,
        skipAt: _settings.lockSkipAt,
        skipUntil: _settings.lockSkipUntil,
      );

  /// 把最新的锁定配置同步给原生（开机广播与守护服务要用）。
  Future<void> _syncKioskConfig() async {
    await Kiosk.sync(
      enabled: _settings.lockEnabled,
      autoStart: _settings.lockAutoStart,
      periods:
          _settings.lockPeriods.map((LockPeriod p) => p.encode()).toList(),
      skipAt: _settings.lockSkipAt,
      skipUntil: _settings.lockSkipUntil,
    );
  }

  Future<void> _reloadKiosk() async {
    final KioskStatus st = await Kiosk.status();
    if (!mounted) return;
    if (st.active != _kiosk.active ||
        st.deviceOwner != _kiosk.deviceOwner ||
        st.overlay != _kiosk.overlay ||
        st.pinningEnabled != _kiosk.pinningEnabled ||
        st.batteryOk != _kiosk.batteryOk) {
      setState(() => _kiosk = st);
    }
  }

  /// 锁定期间确保处于系统锁定态：被解除固定 / 被切走时会重新进入。
  Future<void> _watchLock() async {
    final bool locked = _lockedEnd != null;
    if (!locked) {
      if (_kiosk.active && !_stopBusy) {
        _stopBusy = true;
        try {
          await Kiosk.stop();
          await _reloadKiosk();
        } finally {
          _stopBusy = false;
        }
      }
      return;
    }
    if (_pinBusy) return;
    final DateTime now = DateTime.now();
    if (_lastPinTry != null &&
        now.difference(_lastPinTry!) < const Duration(seconds: 3)) {
      return;
    }
    _pinBusy = true;
    _lastPinTry = now;
    try {
      if (!_kiosk.active) await Kiosk.start();
      await _reloadKiosk();
    } finally {
      _pinBusy = false;
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => LockSettingsPage(
          settings: _settings,
          onBack: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (!mounted) return;
    _syncKioskConfig();
    await _reloadKiosk();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? end = _lockedEnd;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: end == null
          ? KeyedSubtree(key: const ValueKey<String>('editor'), child: _editor())
          : KeyedSubtree(
              key: const ValueKey<String>('locked'), child: _locked(end)),
    );
  }

  // ── 未锁定：时钟 + 状态 + 设置入口 ────────────────────────────────

  Widget _editor() {
    final List<LockPeriod> periods = _settings.lockPeriods;
    final (DateTime, bool)? next = LockSchedule(periods).nextSwitch(_now);
    // 页面自己让位：壁纸铺满整屏（含状态栏 / 挖孔区），内容避开刘海拔高与手势条。
    final EdgeInsets insets = MediaQuery.paddingOf(context);

    return Stack(
      children: <Widget>[
        // 深色底：壁纸未就位（离线首启）时也不会白底白字。
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0E1116))),
        const Positioned.fill(child: WallpaperBackground(boost: 0.30)),
        Positioned.fill(
          child: ListView(
            padding:
                EdgeInsets.fromLTRB(20, 26 + insets.top, 20, 30 + insets.bottom),
            children: <Widget>[
              _clockBlock(),
              const SizedBox(height: 30),
              _statusCard(next),
              const SizedBox(height: 14),
              _settingsEntry(periods),
              const SizedBox(height: 24),
              const Text(
                '到点自动全屏锁定：通知栏、控制中心与返回桌面都会被拦下；'
                '重启后仍在锁定期会直接锁定。',
                style:
                    TextStyle(fontSize: 12, height: 1.7, color: Colors.white38),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶部时钟：大号时分 + 日期 / 农历 / 距考试。
  Widget _clockBlock() {
    final Lunar lunar = Lunar.fromDate(_now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '${_two(_now.hour)}:${_two(_now.minute)}',
                style: const TextStyle(
                  fontSize: 66,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _two(_now.second),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: Colors.white24,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_weekday(_now.weekday)} · ${_now.month} 月 ${_now.day} 日 · '
          '${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}',
          style: const TextStyle(fontSize: 13, color: Colors.white54),
        ),
        const SizedBox(height: 4),
        Text(
          '距 ${_exam.label} $_examDays 天',
          style: const TextStyle(fontSize: 12, color: Colors.white24),
        ),
      ],
    );
  }

  ExamTarget get _exam => examTargets.first;

  int get _examDays {
    final DateTime today = DateTime(_now.year, _now.month, _now.day);
    return DateTime(_exam.date.year, _exam.date.month, _exam.date.day)
        .difference(today)
        .inDays;
  }

  /// 状态卡：只显示状态与倒计时，操作都收进设置页。
  Widget _statusCard((DateTime, bool)? next) {
    final bool on = _settings.lockEnabled;
    final bool configured = _settings.lockPeriods.isNotEmpty;

    String state;
    String big;
    String sub;
    Color dot;
    // 是否处于「本次已放行」——只有这种状态才谈得上「再次锁定」。
    bool skipped = false;

    if (!on) {
      dot = Colors.white24;
      state = '未开启';
      big = '未开启';
      sub = '去「锁定设置」里打开自动锁定';
    } else if (!configured) {
      dot = const Color(0xFFF59E0B);
      state = '无时段';
      big = '无时段';
      sub = '去「锁定设置」里添加一个大时段';
    } else if (next == null) {
      dot = const Color(0xFFF59E0B);
      state = '时段异常';
      big = '时段异常';
      sub = '请检查时段设置';
    } else {
      final (DateTime at, bool starts) = next;
      dot = starts ? const Color(0xFF34D399) : const Color(0xFFF59E0B);
      state = starts ? '未锁定' : '已放行本次';
      big = fmtHms(at.difference(_now));
      sub = starts
          ? '${_dayLabel(at)} ${_two(at.hour)}:${_two(at.minute)} 开始锁定'
          : '本段已放行 · ${_dayLabel(at)} ${_two(at.hour)}:${_two(at.minute)} 结束';
      skipped = !starts;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                '自动锁定',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              big,
              style: const TextStyle(
                fontSize: 40,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            style: const TextStyle(fontSize: 12.5, color: Colors.white54),
          ),
          if (skipped) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.icon(
                onPressed: _relockNow,
                icon: const Icon(Icons.lock_clock, size: 16),
                label: const Text(
                  '再次锁定',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: sheetAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 设置入口：一行摘要 + 箭头，点进去是独立的锁定设置页。
  Widget _settingsEntry(List<LockPeriod> periods) {
    final int totalMin = periods.fold<int>(
        0, (int sum, LockPeriod p) => sum + p.durationMinutes);
    final String summary = periods.isEmpty
        ? '未设置时段'
        : '${periods.length} 段 · 每天 ${_hoursText(totalMin)}';
    final bool ready = _kiosk.supported || _kiosk.deviceOwner;

    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openSettings,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.tune, size: 18, color: Colors.white54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '锁定设置',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              if (!ready && _settings.lockEnabled)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.error_outline,
                      size: 16, color: Color(0xFFF59E0B)),
                ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  // ── 锁定中：全屏锁屏 ─────────────────────────────────────────────

  Widget _locked(DateTime end) {
    final Duration left = end.difference(_now);
    return Container(
      color: const Color(0xFF07080A),
      child: Stack(
        children: <Widget>[
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.lock_outline, size: 44, color: Colors.white24),
                const SizedBox(height: 22),
                const Text(
                  '锁 定 中',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white54,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 26),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    fmtHms(left),
                    style: const TextStyle(
                      fontSize: 68,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -2,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '距解锁 · ${_dayLabel(end)} '
                  '${_two(end.hour)}:${_two(end.minute)}',
                  style: const TextStyle(fontSize: 14, color: Colors.white38),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _kiosk.active ? Icons.shield_outlined : Icons.sync,
                      size: 13,
                      color: _kiosk.active
                          ? const Color(0xFF34D399)
                          : Colors.white24,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _kiosk.active ? '系统锁定已开启 · 通知栏已禁用' : '正在启用系统锁定…',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _kiosk.active
                            ? const Color(0xFF34D399)
                            : Colors.white24,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28 + MediaQuery.paddingOf(context).bottom,
            child: Center(
              child: TextButton(
                onPressed: () => _skipCurrent(end),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white38,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                child: const Text('提前解锁本次', style: TextStyle(fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 提前解锁：只放行当前这一段，与它重叠的下一段照常生效。
  Future<void> _skipCurrent(DateTime end) async {
    // 记下「按下时刻」：放行只作用于此刻已经开始的段，之后才开始的新段照常锁。
    await _settings.setLockSkip(at: DateTime.now(), until: end);
    // 必须先把放行同步给原生再退锁定：原生据此重排下一段的系统闹钟，
    // 否则段一结束就没人记得下一段几点开始。
    await _syncKioskConfig();
    unawaited(Kiosk.stop());
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: '已放行到 ${_two(end.hour)}:${_two(end.minute)}',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  /// 再次锁定：撤销本次放行，若仍在时段内会立刻锁回去。
  Future<void> _relockNow() async {
    await _settings.clearLockSkip();
    if (!mounted) return;
    _now = DateTime.now();
    setState(() {});
    await _syncKioskConfig();
    // 直接进系统锁定，不等心跳；_watchLock 之后继续负责守卫。
    await Kiosk.start();
    await _reloadKiosk();
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: _lockedEnd == null ? '当前不在锁定时段内' : '已重新锁定',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  // ── 小工具 ──────────────────────────────────────────────────────

  String _dayLabel(DateTime at) {
    final DateTime today = DateTime(_now.year, _now.month, _now.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    final int diff = day.difference(today).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '明天';
    return '${at.month}/${at.day}';
  }

  static String _hoursText(int minutes) {
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    final int h = minutes ~/ 60;
    return h == 0 ? '$minutes 分钟' : '$h 小时 ${minutes % 60} 分';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _weekday(int w) => const <String>[
        '星期一',
        '星期二',
        '星期三',
        '星期四',
        '星期五',
        '星期六',
        '星期日'
      ][w - 1];
}
