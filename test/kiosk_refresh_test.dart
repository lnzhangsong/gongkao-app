import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gongkao_pad/settings.dart';
import 'package:gongkao_pad/widgets/lock_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 模拟系统里的「显示在其他应用上层」授权状态。
  bool overlay = false;

  setUp(() {
    overlay = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
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
            'overlay': overlay,
            'batteryOk': true,
            'notifications': true,
          };
        }
        return null;
      },
    );
  });

  testWidgets('权限授予后从系统设置返回，锁定强度立刻刷新', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final Settings settings = Settings();
    await settings.load();
    await tester.pumpWidget(MaterialApp(
      home: LockSettingsPage(settings: settings, onBack: () {}),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // 初始：没授权。
    expect(find.text('有未处理的项'), findsOneWidget);
    expect(find.text('未授权 · 切走后无法拉回'), findsOneWidget);

    // 用户去系统设置里授予权限，然后返回 App（生命周期 paused → resumed）。
    overlay = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));

    // 不退出页面就应该变成已就绪。
    expect(find.text('已就绪'), findsOneWidget);
    expect(find.text('被切走会自动拉回锁定界面'), findsOneWidget);
    expect(find.text('未授权 · 切走后无法拉回'), findsNothing);
  });
}
