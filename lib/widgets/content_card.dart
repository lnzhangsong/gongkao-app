import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';

/// 单张轮播卡：kind 标签着色、题名加粗、正文常规、辨析与例证弱化。
/// 无卡片底（与左栏的日视图统一），纯文字浮于壁纸之上，靠阴影保证可读。
class ContentCard extends StatelessWidget {
  const ContentCard({super.key, required this.item});

  final CardItem item;

  @override
  Widget build(BuildContext context) {
    final Color tint = kindColor(item.kind);
    final String label =
        item.group == null ? item.kind : '${item.kind} · ${item.group}';

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _shadow(
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _shadow(Text(
                item.title,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.25,
                ),
              )),
              const SizedBox(height: 12),
              _shadow(Text(
                item.body,
                style: const TextStyle(
                    fontSize: 21, height: 1.6, color: Colors.white),
              )),
              if (item.extra != null) ...<Widget>[
                const SizedBox(height: 18),
                _hairline(),
                const SizedBox(height: 18),
                _shadow(Text(
                  item.extra!,
                  style: const TextStyle(
                      fontSize: 17, height: 1.6, color: Colors.white70),
                )),
              ],
              if (item.example != null) ...<Widget>[
                const SizedBox(height: 12),
                _shadow(Text(
                  item.example!,
                  style: const TextStyle(
                      fontSize: 15, height: 1.5, color: Colors.white54),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hairline() => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.20),
      );

  /// 文字阴影：背景已高斯模糊，无需再叠阴影，直接返回。
  Widget _shadow(Widget child) => child;
}
