import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gongkao_pad/app_shell.dart';
import 'package:gongkao_pad/settings.dart';
import 'package:gongkao_pad/widgets/phone_lock_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 断点分流：平板保留全部功能，手机只留锁机页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
    // 原生锁定通道桩：避免测试里真的去调 startLockTask。
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

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final Settings settings = Settings();
    await settings.load();
    await tester.pumpWidget(MaterialApp(home: AppShell(settings: settings)));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('平板宽度：台历与四个功能入口都在', (WidgetTester tester) async {
    await pumpShell(tester, const Size(1280, 800));
    expect(find.byType(PhoneLockPage), findsNothing);
    for (final String tip in <String>['设置', '计时工具', '番茄钟', '今日足迹']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: '缺少入口：$tip');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // 释放轮播定时器
  });

  testWidgets('平板竖屏也保留全部功能', (WidgetTester tester) async {
    await pumpShell(tester, const Size(800, 1280));
    expect(find.byType(PhoneLockPage), findsNothing);
    expect(find.byTooltip('番茄钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手机横屏仍只显示锁机页', (WidgetTester tester) async {
    await pumpShell(tester, const Size(844, 390));
    expect(find.byType(PhoneLockPage), findsOneWidget);
    expect(find.byTooltip('番茄钟'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度：功能入口全部隐藏，只剩锁机页', (WidgetTester tester) async {
    await pumpShell(tester, const Size(390, 844));
    expect(find.byType(PhoneLockPage), findsOneWidget);
    for (final String tip in <String>['设置', '计时工具', '番茄钟', '今日足迹']) {
      expect(find.byTooltip(tip), findsNothing, reason: '不应出现入口：$tip');
    }
    expect(find.text('自动锁定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
