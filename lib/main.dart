import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const GongkaoApp());
  _keepAwake();
}

/// 常亮：不阻塞启动。个别机型上 WakelockPlus 调用可能挂起，
/// 若在 runApp 前 await 会把整个启动拖死导致 ANR，故启动后异步启用。
Future<void> _keepAwake() async {
  try {
    await WakelockPlus.enable();
  } catch (_) {
    // 常亮失败不影响显示，忽略。
  }
}

class GongkaoApp extends StatelessWidget {
  const GongkaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '考公台历',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}
