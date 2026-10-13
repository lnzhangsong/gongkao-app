import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'bing_image.dart';

/// 每日壁纸：Bing 图片搜索（免 Key）按关键词取图，当日一张并缓存。
/// 图片走 Bing CDN（ts*.mm.bing.net），稳定且在国内可达。
/// 任一环节失败则回落到 Bing 每日图；再失败返回 null，界面回落纯色。
class WallpaperImage {
  const WallpaperImage({this.bing = const BingImage()});

  final BingImage bing;

  static const Map<String, String> _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,image/*',
    'Referer': 'https://www.bing.com/',
  };

  Future<File?> todayImage() async {
    final File? remote = await _searchImage();
    if (remote != null) return remote;
    return bing.todayImage();
  }

  Future<File?> _searchImage() async {
    final Directory dir = await getApplicationSupportDirectory();
    final File cache = File('${dir.path}/wall_${_dateKey(DateTime.now())}.jpg');
    if (await cache.exists() && await cache.length() > 0) return cache;

    try {
      final String? url = await _pickImageUrl();
      if (url == null) return null;
      final http.Response resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      await cache.writeAsBytes(resp.bodyBytes, flush: true);
      return cache;
    } catch (e) {
      debugPrint('WallpaperImage: 取图失败，回落 Bing 每日图: $e');
      return null;
    }
  }

  /// 搜索关键词，取当日稳定的一张 CDN 缩略图（按日期取模，同一天同一张）。
  Future<String?> _pickImageUrl() async {
    final Uri uri = Uri.parse(bingImageSearchUrl).replace(
      queryParameters: <String, String>{
        'q': wallpaperQuery,
        'first': '1',
        'count': '20',
        'qft': '+filterui:imagesize-wallpaper',
        'mmasync': '1',
      },
    );
    final http.Response resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;

    // 结果内嵌 JSON：turl 为 Bing CDN 缩略图地址，最稳定。
    // 注意 HTML 里 & 被转义为 &amp;，需还原。
    final List<String> turls = <String>[];
    final RegExp re = RegExp(r'turl&quot;:&quot;(.*?)&quot;');
    for (final RegExpMatch m in re.allMatches(resp.body)) {
      final String u = (m.group(1) ?? '').replaceAll('&amp;', '&');
      if (u.startsWith('http')) turls.add(u);
    }
    if (turls.isEmpty) return null;

    final int idx = _dayOfYear(DateTime.now()) % turls.length;
    // 把 ts*.mm.bing.net 的缩略图地址改写到可达的 www.bing.com/th，
    // 并强制壁纸尺寸，保证铺满且清晰度一致。
    final String? id = _extractId(turls[idx]);
    if (id == null) return null;
    return '$bingImageHost?id=$id&pid=Api&w=$wallpaperWidth&h=1080&rs=1&c=4';
  }

  /// 从 turl（.../th?id=OIP.xxx&...）中取出 id 值。
  String? _extractId(String turl) {
    final RegExpMatch? m = RegExp(r'[?&]id=([^&]+)').firstMatch(turl);
    return m?.group(1);
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  int _dayOfYear(DateTime d) => d.difference(DateTime(d.year, 1, 1)).inDays;
}
