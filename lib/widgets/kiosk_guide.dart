import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../kiosk.dart';
import 'lock_sheets.dart' show sheetAccent;

/// 「锁定强度」说明与授权引导弹层。
///
/// 三层防线：
/// 1. 屏幕固定（系统 lock task）——锁定期禁止下拉通知栏 / 控制中心 / 返回桌面；
/// 2. 后台守护 + 开机自启——被切走会拉回，重启还在锁定期会直接锁上；
/// 3. 严格模式（可选）——设为设备所有者，连长按返回也退不出去。
Future<void> showKioskGuideSheet(
  BuildContext context, {
  required KioskStatus status,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (BuildContext ctx) => _KioskGuideSheet(initial: status),
  );
}

class _KioskGuideSheet extends StatefulWidget {
  const _KioskGuideSheet({required this.initial});

  final KioskStatus initial;

  @override
  State<_KioskGuideSheet> createState() => _KioskGuideSheetState();
}

class _KioskGuideSheetState extends State<_KioskGuideSheet>
    with WidgetsBindingObserver {
  late KioskStatus status = widget.initial;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回时重新读一次权限，否则弹层里会一直显示「待处理」。
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final int seq = ++_seq;
    final KioskStatus st = await Kiosk.status();
    if (!mounted || seq != _seq) return;
    setState(() => status = st);
  }

  /// 跳系统设置：回来时由 resumed 回调刷新，弹层里的状态随之变化。
  Future<void> _open(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141821),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '锁定强度',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '只靠应用内全屏挡不住系统手势，下面三项才是真正锁住的关键。',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white38),
          ),
          const SizedBox(height: 20),
          _item(
            icon: Icons.pin_outlined,
            title: '屏幕固定',
            body: status.deviceOwner
                ? '已由设备所有者接管：锁定期无法退出、无法下拉通知栏。'
                : '系统级固定已可用：锁定期通知栏、控制中心、返回桌面都会被拦下。',
            ok: status.supported || status.deviceOwner,
            action: status.supported || status.deviceOwner
                ? null
                : '去开启',
            onTap: () => _open(Kiosk.openSecuritySettings),
          ),
          const SizedBox(height: 12),
          _item(
            icon: Icons.shield_moon_outlined,
            title: '后台守护',
            body: status.overlay
                ? '已授权悬浮窗：被切走或强行解除固定时会自动拉回锁定界面。'
                : '需要「显示在其他应用上层」权限，才能在应用被切走时立刻拉回来。',
            ok: status.overlay,
            action: status.overlay ? null : '去授权',
            onTap: () => _open(Kiosk.openOverlaySettings),
          ),
          const SizedBox(height: 12),
          _item(
            icon: Icons.restart_alt,
            title: '开机自启',
            body: status.batteryOk
                ? '已关闭电池优化：重启后若仍在锁定期，会直接拉起并锁定。'
                : '关闭电池优化可避免后台被系统冻结，重启后拉起更可靠。',
            ok: status.batteryOk,
            action: status.batteryOk ? null : '去设置',
            onTap: () => _open(Kiosk.openBatterySettings),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      status.deviceOwner
                          ? Icons.verified_user_outlined
                          : Icons.lock_outline,
                      size: 16,
                      color: status.deviceOwner
                          ? const Color(0xFF34D399)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      status.deviceOwner ? '严格模式已开启' : '严格模式（可选）',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status.deviceOwner
                      ? '锁定期间连长按返回也无法解除，只能等解锁时刻。'
                      : '用电脑执行一次下面的命令，把本应用设为设备所有者，'
                          '之后锁定期间完全无法退出。',
                  style: const TextStyle(
                      fontSize: 12, height: 1.6, color: Colors.white38),
                ),
                if (!status.deviceOwner) ...<Widget>[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(
                          const ClipboardData(text: Kiosk.deviceOwnerCommand));
                      Fluttertoast.showToast(
                        msg: '命令已复制',
                        toastLength: Toast.LENGTH_SHORT,
                        gravity: ToastGravity.BOTTOM,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        Kiosk.deviceOwnerCommand,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: Colors.white54,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '注意：设为设备所有者后，卸载前需先执行 '
                    'adb shell dpm remove-active-admin '
                    'com.gongkao.gongkao_pad/.KioskAdminReceiver，'
                    '否则可能只能恢复出厂设置。',
                    style: TextStyle(
                        fontSize: 11, height: 1.5, color: Color(0xFFB4794A)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                foregroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('知道了', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String title,
    required String body,
    required bool ok,
    String? action,
    VoidCallback? onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: ok ? sheetAccent : Colors.white30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ok ? '已就绪' : '待处理',
                    style: TextStyle(
                      fontSize: 11,
                      color: ok ? sheetAccent : const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                    fontSize: 12, height: 1.55, color: Colors.white38),
              ),
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: sheetAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(action, style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }
}
