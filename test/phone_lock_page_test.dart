import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gongkao_pad/lock_schedule.dart';
import 'package:gongkao_pad/settings.dart';
import 'package:gongkao_pad/widgets/phone_lock_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手机端锁机页的布局与状态切换（不依赖相机 / 网络）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 测试环境无 path_provider 插件，桩一个临时目录给壁纸缓存用。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
    // 原生锁定通道：给出一个「屏幕固定已开、其余就绪」的桩，避免测试触发真实跳转。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.gongkao.gongkao_pad/kiosk'),
      (MethodCall call) async {
        if (call.method == 'status') {
          return <String, Object?>{
            'supported': true,
            'deviceOwner': false,
            'active': false,
            'pinningEnabled': true,
            'overlay': true,
            'batteryOk': true,
            'notifications': true,
          };
        }
        if (call.method == 'start' || call.method == 'isActive') return false;
        return null;
      },
    );
  });

  Future<Settings> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final Settings settings = Settings();
    await settings.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PhoneLockPage(settings: settings)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return settings;
  }

  /// 首页只显示，操作都在独立的锁定设置页。
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('锁定设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('未锁定：首页只显示状态与设置入口', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('自动锁定'), findsOneWidget);
    expect(find.text('锁定设置'), findsOneWidget);
    // 设置项不再堆在首页。
    expect(find.text('添加时段'), findsNothing);
    expect(find.text('08:00'), findsNothing);
  });

  testWidgets('设置页：开关、时段、强度都在独立页面里', (WidgetTester tester) async {
    await pumpPage(tester);
    await openSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('添加时段'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('系统锁定'), findsOneWidget);
    expect(find.text('开机自启'), findsOneWidget);
  });

  testWidgets('到点进入锁屏，提前解锁后回到编辑态', (WidgetTester tester) async {
    final Settings settings = await pumpPage(tester);
    final int now = DateTime.now().hour * 60 + DateTime.now().minute;
    await settings.setLockEnabled(true);
    await settings.setLockPeriod(
      0,
      LockPeriod(
        start: (now - 30 + kDayMinutes) % kDayMinutes,
        end: (now + 30) % kDayMinutes,
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('锁 定 中'), findsOneWidget);
    expect(find.text('提前解锁本次'), findsOneWidget);

    await tester.tap(find.text('提前解锁本次'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('自动锁定'), findsOneWidget);

    // 放行期间给出「再次锁定」出口，点了立刻锁回去。
    expect(find.text('再次锁定'), findsOneWidget);
    await tester.tap(find.text('再次锁定'));
    await tester.pump(const Duration(seconds: 1));
    // AnimatedSwitcher 退场动画结束后旧内容才会真正移除。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('锁 定 中'), findsOneWidget);
    expect(find.text('再次锁定'), findsNothing);
  });

  testWidgets('提前解锁后修改时段，不会被立刻锁回去', (WidgetTester tester) async {
    final Settings settings = await pumpPage(tester);
    final int now = DateTime.now().hour * 60 + DateTime.now().minute;
    await settings.setLockEnabled(true);
    await settings.setLockPeriod(
      0,
      LockPeriod(
        start: (now - 30 + kDayMinutes) % kDayMinutes,
        end: (now + 30) % kDayMinutes,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('锁 定 中'), findsOneWidget);

    await tester.tap(find.text('提前解锁本次'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('自动锁定'), findsOneWidget);
    expect(settings.lockSkipAt, isNotNull);

    // 用户的真实动作：解锁之后顺手改一下时段。放行是显式动作，
    // 不该被编辑动作撤销——否则一保存就锁回去，设置根本改不了。
    final LockPeriod cur = settings.lockPeriods.first;
    await settings.setLockPeriod(
      0,
      LockPeriod(start: cur.start, end: (cur.end + 30) % kDayMinutes),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(settings.lockSkipAt, isNotNull);
    expect(find.text('锁 定 中'), findsNothing);
    expect(find.text('自动锁定'), findsOneWidget);
  });

  testWidgets('跨午夜时段不算错，设置页正常渲染', (WidgetTester tester) async {
    final Settings settings = await pumpPage(tester);
    await settings.setLockPeriod(0, const LockPeriod(start: 22 * 60, end: 6 * 60));
    await settings.addLockPeriod();
    await tester.pump(const Duration(seconds: 1));
    await openSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('次日'), findsOneWidget);
  });
}
