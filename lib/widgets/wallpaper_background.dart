import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/wallpaper_image.dart';

/// 全屏背景：每日壁纸（高斯模糊）+ 半透明深色蒙版。
/// 未就位时透明，回落 Scaffold 的纯色背景。各页面共用。
class WallpaperBackground extends StatefulWidget {
  const WallpaperBackground({super.key});

  @override
  State<WallpaperBackground> createState() => _WallpaperBackgroundState();
}

class _WallpaperBackgroundState extends State<WallpaperBackground> {
  File? _bg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final File? f = await const WallpaperImage().todayImage();
    if (!mounted || f == null) return;
    setState(() => _bg = f);
  }

  @override
  Widget build(BuildContext context) {
    final File? f = _bg;
    if (f == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: wallpaperBlur,
            sigmaY: wallpaperBlur,
          ),
          child: Image.file(f, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: wallpaperScrim)),
      ],
    );
  }
}
