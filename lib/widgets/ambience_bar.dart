import 'package:flutter/material.dart';

import '../audio/ambience.dart';

/// 背景音控件：选源 + 音量。素材未就位时整体禁用。
class AmbienceBar extends StatelessWidget {
  const AmbienceBar({super.key, required this.ambience});

  final Ambience ambience;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: ambience,
      builder: (BuildContext context, _) {
        if (!ambience.available) {
          return Text('背景音素材未就位', style: text.labelSmall);
        }
        return Row(
          children: <Widget>[
            IconButton(
              onPressed: ambience.toggle,
              icon: Icon(ambience.playing
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline),
              tooltip: '播放/暂停',
            ),
            DropdownButton<int>(
              value: ambience.index < 0 ? 0 : ambience.index,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<int>>[
                for (int i = 0; i < ambience.tracks.length; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Text(ambience.tracks[i].label),
                  ),
              ],
              onChanged: (int? v) {
                if (v != null) ambience.select(v);
              },
            ),
            const SizedBox(width: 12),
            Icon(Icons.volume_up, size: 20, color: text.bodyMedium?.color),
            Expanded(
              child: Slider(
                value: ambience.volume,
                onChanged: ambience.setVolume,
              ),
            ),
          ],
        );
      },
    );
  }
}
