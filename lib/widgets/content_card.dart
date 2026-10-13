import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';

/// 单张轮播卡：kind 标签着色、题名加粗、正文常规、辨析与例证弱化。
class ContentCard extends StatelessWidget {
  const ContentCard({super.key, required this.item});

  final CardItem item;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = kindColor(item.kind);
    final String label =
        item.group == null ? item.kind : '${item.kind} · ${item.group}';

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: text.labelLarge?.copyWith(color: tint)),
            ),
            const SizedBox(height: 14),
            Text(item.title, style: text.titleLarge),
            const SizedBox(height: 10),
            Text(item.body, style: text.bodyLarge),
            if (item.extra != null) ...<Widget>[
              const Divider(height: 28),
              Text(item.extra!, style: text.bodyMedium),
            ],
            if (item.example != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(item.example!, style: text.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}
