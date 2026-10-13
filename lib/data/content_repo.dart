import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// 读 assets/data/*.json → CardItem[]，按主题分组。
/// 缺文件或某类为空时不抛异常，交由界面兜底。
class ContentRepo {
  static const List<String> _files = <String>[
    'assets/data/common-sense.json',
    'assets/data/idioms.json',
    'assets/data/politics-hot.json',
  ];

  /// 按主题分组的全部内容：{ '常识': [...], '成语': [...], '时政': [...] }。
  Future<Map<String, List<CardItem>>> loadByKind() async {
    final Map<String, List<CardItem>> byKind = <String, List<CardItem>>{};
    for (final String path in _files) {
      try {
        final String raw = await rootBundle.loadString(path);
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        for (final dynamic e in list) {
          final CardItem c = CardItem.fromJson(e as Map<String, dynamic>);
          byKind.putIfAbsent(c.kind, () => <CardItem>[]).add(c);
        }
      } catch (_) {
        // 文件缺失或解析失败：跳过该类，其余照常。
      }
    }
    return byKind;
  }

  /// 混排后的完整序列（保留给需要全量的场景）。
  Future<List<CardItem>> load() async {
    final Map<String, List<CardItem>> byKind = await loadByKind();
    final List<CardItem> all = <CardItem>[];
    for (final List<CardItem> q in byKind.values) {
      all.addAll(q);
    }
    return interleave(all);
  }

  /// 按 kind 轮转取样，避免连续同类型。
  static List<CardItem> interleave(List<CardItem> items) {
    final Map<String, List<CardItem>> byKind = <String, List<CardItem>>{};
    for (final CardItem c in items) {
      byKind.putIfAbsent(c.kind, () => <CardItem>[]).add(c);
    }
    final List<List<CardItem>> queues = byKind.values.toList();
    final int maxLen = queues.fold<int>(
      0,
      (int m, List<CardItem> q) => q.length > m ? q.length : m,
    );
    final List<CardItem> out = <CardItem>[];
    for (int idx = 0; idx < maxLen; idx++) {
      for (final List<CardItem> q in queues) {
        if (idx < q.length) out.add(q[idx]);
      }
    }
    return out;
  }
}
