import 'package:flutter/material.dart';

/// 深/浅两套配色，跟随系统（ThemeMode.system）。

ThemeData _base(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B82F6),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0E1116) : const Color(0xFFF7F8FA),
    textTheme: _textTheme(brightness),
  );
}

/// 台历以大字号为主，故标题档整体放大；深色下压低亮度、降低对比，夜间不刺眼。
TextTheme _textTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final Color primary = dark ? const Color(0xFFE6E8EB) : const Color(0xFF1A1D21);
  final Color secondary =
      dark ? const Color(0xFF9BA1A9) : const Color(0xFF6B7280);

  return TextTheme(
    displayLarge: TextStyle(
      fontSize: 140,
      fontWeight: FontWeight.w700,
      height: 1,
      color: primary,
    ),
    headlineMedium: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    titleLarge: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: primary,
    ),
    bodyLarge: TextStyle(fontSize: 20, height: 1.5, color: primary),
    bodyMedium: TextStyle(fontSize: 17, height: 1.5, color: secondary),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: secondary,
    ),
    labelSmall: TextStyle(fontSize: 13, color: secondary),
  );
}

final ThemeData lightTheme = _base(Brightness.light);
final ThemeData darkTheme = _base(Brightness.dark);
