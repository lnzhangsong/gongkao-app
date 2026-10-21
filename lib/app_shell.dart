import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'config.dart';
import 'lock_schedule.dart';
import 'settings.dart';
import 'widgets/footprint_page.dart';
import 'widgets/pad_home.dart';
import 'widgets/phone_lock_page.dart';
import 'widgets/pomodoro_page.dart';
import 'widgets/settings_page.dart';
import 'widgets/tools_page.dart';

enum _Screen { calendar, pomodoro, tools, settings, footprint }

/// 按设备类型（窗口最短边）分流：
/// - 平板：台历 ⇄ 番茄钟 ⇄ 计时工具 ⇄ 今日足迹 ⇄ 设置，功能全部保留（默认台历），
///   横竖屏都不受影响；
/// - 手机：隐藏台历的全部功能，只保留「按时锁定手机」。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings});

  final Settings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Screen _screen = _Screen.calendar;

  /// 台历页「再按一次退出」的时间戳。
  DateTime? _lastBackAt;

  /// 返回键：手机端在锁定中拦截；子页先回台历；台历页两秒内连按两次才退出。
  Future<void> _onPop(bool didPop, Object? result) async {
    if (didPop) return;
    // 有压栈的页面（如锁定设置页）先退栈，别被首页的返回逻辑吞掉。
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    if (_isMobile) {
      final DateTime now = DateTime.now();
      final DateTime? lockedEnd = lockedEndNow(
        enabled: widget.settings.lockEnabled,
        periods: widget.settings.lockPeriods,
        now: now,
        skipAt: widget.settings.lockSkipAt,
        skipUntil: widget.settings.lockSkipUntil,
      );
      if (lockedEnd != null) {
        Fluttertoast.showToast(
          msg: '锁定中，${fmtHms(lockedEnd.difference(now))} 后解锁',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
        return;
      }
    } else if (_screen != _Screen.calendar) {
      setState(() => _screen = _Screen.calendar);
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    Fluttertoast.showToast(
      msg: '再按一次退出',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  bool get _isMobile =>
      MediaQuery.sizeOf(context).shortestSide < phoneMaxShortestSide;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        // 手机端整页自绘背景（壁纸铺到状态栏 / 挖孔区），由页面内部让位，
        // 不再套 SafeArea——否则顶部会露出 Scaffold 底色形成一条黑边。
        body: _isMobile
            ? PhoneLockPage(settings: widget.settings)
            : SafeArea(child: _tablet()),
      ),
    );
  }

  /// 平板 / 宽屏：台历 + 右上角功能入口，原样保留。
  Widget _tablet() {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _body()),
        if (_screen == _Screen.calendar)
          Positioned(
            top: 8,
            right: 12,
            child: Row(
              children: <Widget>[
                _iconBtn(Icons.settings_outlined, '设置',
                    () => setState(() => _screen = _Screen.settings)),
                const SizedBox(width: 4),
                _iconBtn(Icons.hourglass_bottom_outlined, '计时工具',
                    () => setState(() => _screen = _Screen.tools)),
                const SizedBox(width: 4),
                _iconBtn(Icons.timer_outlined, '番茄钟',
                    () => setState(() => _screen = _Screen.pomodoro)),
                const SizedBox(width: 4),
                _iconBtn(Icons.insights_outlined, '今日足迹',
                    () => setState(() => _screen = _Screen.footprint)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _body() {
    switch (_screen) {
      case _Screen.calendar:
        return PadHome(settings: widget.settings);
      case _Screen.pomodoro:
        return PomodoroPage(
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
      case _Screen.tools:
        return ToolsPage(
          settings: widget.settings,
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
      case _Screen.settings:
        return SettingsPage(
          settings: widget.settings,
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
      case _Screen.footprint:
        return FootprintPage(
          onBack: () => setState(() => _screen = _Screen.calendar),
        );
    }
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        tooltip: tip,
        icon: Icon(icon, size: 22),
        color: Colors.white.withValues(alpha: 0.55),
        splashRadius: 22,
      );
}
