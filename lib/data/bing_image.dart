import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Bing 每日图：拉当日壁纸（UHD），缓存到本地，按日期命名。
/// 已缓存则直接用；无网/失败返回 null，界面回落纯色背景。
class BingImage {
  const BingImage();

  Future<File?> todayImage() async {
    if (!useBingWallpaper) return null;

    final Directory dir = await getApplicationSupportDirectory();
    final File cache = File('${dir.path}/bing_${_dateKey(DateTime.now())}.jpg');
    if (await cache.exists() && await cache.length() > 0) return cache;

    try {
      final String? url = await _fetchUhdUrl();
      if (url == null) return null;
      final http.Response resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      await cache.writeAsBytes(resp.bodyBytes, flush: true);
      return cache;
    } catch (e) {
      debugPrint('BingImage: 获取失败，回落纯色背景: $e');
      return null;
    }
  }

  Future<String?> _fetchUhdUrl() async {
    final http.Response resp = await http
        .get(Uri.parse(bingArchiveUrl))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    final List<dynamic> images = json['images'] as List<dynamic>;
    if (images.isEmpty) return null;
    final String urlbase =
        (images.first as Map<String, dynamic>)['urlbase'] as String;
    return 'https://www.bing.com$urlbase${_suffix()}';
  }

  /// UHD 图路径后缀：多数为 _UHD.jpg，个别老图为 _1920x1080.jpg。
  String _suffix() => '_UHD.jpg';

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}
