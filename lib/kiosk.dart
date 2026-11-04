import 'package:flutter/services.dart';

/// 系统级锁定的状态快照（来自 Android 原生侧）。
class KioskStatus {
  const KioskStatus({
    this.supported = false,
    this.deviceOwner = false,
    this.active = false,
    this.pinningEnabled = false,
    this.overlay = false,
    this.batteryOk = false,
    this.notifications = true,
  });

  /// 是否支持系统级锁定（非 Android 平台为 false，页面会退回纯应用内锁定）。
  final bool supported;

  /// 是否已被设为设备所有者（严格模式：锁定期间完全无法退出）。
  final bool deviceOwner;

  /// 当前是否处于系统锁定（lock task）状态。
  final bool active;

  /// 系统设置里是否开启了「屏幕固定」。
  final bool pinningEnabled;

  /// 是否已授予「显示在其他应用上层」——后台把锁定界面拉回前台需要它。
  final bool overlay;

  /// 是否已忽略电池优化，避免后台被系统冻结。
  final bool batteryOk;

  /// 通知权限（守护通知是否可见）。
  final bool notifications;

  /// 严格模式：锁定期间连长按返回也退不出去。
  bool get strict => deviceOwner;

  /// 是否能做到「切走自动拉回」。
  bool get canGuard => overlay;

  factory KioskStatus.fromMap(Object? raw) {
    if (raw is! Map) return const KioskStatus();
    return KioskStatus(
      supported: raw['supported'] == true,
      deviceOwner: raw['deviceOwner'] == true,
      active: raw['active'] == true,
      pinningEnabled: raw['pinningEnabled'] == true,
      overlay: raw['overlay'] == true,
      batteryOk: raw['batteryOk'] == true,
      notifications: raw['notifications'] != false,
    );
  }
}

/// 一个可被限制的已安装应用（来自原生 PackageManager）。
class InstalledApp {
  const InstalledApp({required this.package, required this.label});

  final String package;
  final String label;

  factory InstalledApp.fromMap(Object? raw) {
    final Map<Object?, Object?> m = raw as Map<Object?, Object?>;
    return InstalledApp(
      package: (m['package'] as String?) ?? '',
      label: (m['label'] as String?) ?? '',
    );
  }
}

/// 与原生 Kiosk 通道的封装。
///
/// 锁定期内调用 [start] 进入 Android lock task（屏幕固定）：
/// 通知栏、控制中心、返回桌面都会被系统拦下；配合 [LockGuard] 的前台服务，
/// 应用被切走后会被拉回前台。没有任何原生实现时（测试 / 桌面端）全部安全降级。
class Kiosk {
  Kiosk._();

  static const MethodChannel _channel =
      MethodChannel('com.gongkao.gongkao_pad/kiosk');

  /// 严格模式需要用户手动执行的一次性 adb 命令。
  static const String deviceOwnerCommand =
      'adb shell dpm set-device-owner com.gongkao.gongkao_pad/.KioskAdminReceiver';

  /// 统一收口：任何原生异常 / 无实现 / 卡住都退化成 null，不影响界面。
  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel
          .invokeMethod<T>(method, args)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  static Future<KioskStatus> status() async =>
      KioskStatus.fromMap(await _invoke<Object?>('status'));

  /// 进入系统锁定，返回是否处于锁定态。
  static Future<bool> start() async => await _invoke<bool>('start') ?? false;

  static Future<void> stop() async {
    await _invoke<void>('stop');
  }

  static Future<bool> isActive() async => await _invoke<bool>('isActive') ?? false;

  /// 把锁定配置同步给原生，供开机广播 / 守护服务在 Flutter 起来之前判断。
  ///
  /// [skipAt] 是按下「提前解锁」的时刻，[skipUntil] 是放行到哪一刻：
  /// 原生只放过按下时已经开始的段，之后开始的新段照常锁。
  ///
  /// [appLimits] 是应用限用规则的持久化串（见 `AppLimit.encode`）：
  /// 每个串是 `包名|名称|是否叠加|时段列表`，原生只需包名和时段。
  static Future<void> sync({
    required bool enabled,
    required bool autoStart,
    required List<String> periods,
    required DateTime? skipAt,
    required DateTime? skipUntil,
    List<String> appLimits = const <String>[],
  }) async {
    await _invoke<void>('sync', <String, Object?>{
      'enabled': enabled,
      'autoStart': autoStart,
      'periods': periods,
      'skipAt': skipAt?.millisecondsSinceEpoch ?? 0,
      'skipUntil': skipUntil?.millisecondsSinceEpoch ?? 0,
      'appLimits': appLimits,
    });
  }

  /// 只同步应用限用规则。
  ///
  /// 拦截在原生侧做（前台轮询 + 拦截页），规则一变就要立刻生效，
  /// 不必等整机配置整体同步一次。
  static Future<void> syncAppLimits(List<String> rules) async {
    await _invoke<void>('syncAppLimits', <String, Object?>{'rules': rules});
  }

  /// 可用于限制的已安装应用（有启动图标、非系统框架类），按名称排序。
  static Future<List<InstalledApp>> listApps() async {
    final List<Object?>? raw = await _invoke<List<Object?>>('listApps');
    if (raw == null) return const <InstalledApp>[];
    final List<InstalledApp> out = <InstalledApp>[];
    for (final Object? item in raw) {
      if (item is Map) {
        final InstalledApp app = InstalledApp.fromMap(item);
        if (app.package.isNotEmpty) out.add(app);
      }
    }
    out.sort((InstalledApp a, InstalledApp b) => a.label.compareTo(b.label));
    return out;
  }

  /// 无障碍守护是否已开启。关着时拦截要等轮询，慢约 1 秒。
  static Future<bool> accessibilityEnabled() async =>
      await _invoke<bool>('accessibilityStatus') ?? false;

  static Future<void> openAccessibility() async {
    await _invoke<void>('openAccessibility');
  }

  static Future<void> openOverlaySettings() async {
    await _invoke<void>('openOverlaySettings');
  }

  static Future<void> openBatterySettings() async {
    await _invoke<void>('openBatterySettings');
  }

  static Future<void> openSecuritySettings() async {
    await _invoke<void>('openSecuritySettings');
  }
}
