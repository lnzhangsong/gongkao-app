import 'package:flutter/material.dart';

/// 常改项集中在此：考试日期、轮播间隔、断点、番茄时长、音源清单。

/// 目标考试。日期为占位，待用户给定后替换。
const String examName = '2027 国考';
final DateTime examDate = DateTime(2027, 11, 28);

/// 内容卡轮播间隔。
const Duration cardInterval = Duration(seconds: 30);

/// 平板 / 手机版式分界（dp）。>= 此值走两栏，否则单栏。
const double wideBreakpoint = 720;

/// 番茄工作法时长（分钟）。
const int pomodoroMinutes = 25;
const int shortBreakMinutes = 5;
const int longBreakMinutes = 15;
const int roundsPerLongBreak = 4;

/// 段末提醒。material 音效需另找可商用素材，默认只振动。
const bool vibrateOnPhaseEnd = true;

/// 背景音音源清单。素材放进 assets/audio/ 后在此登记；
/// 列表为空时播放器静默禁用。
class AmbienceTrack {
  const AmbienceTrack({required this.label, required this.asset});

  final String label;
  final String asset;
}

const List<AmbienceTrack> ambienceTracks = <AmbienceTrack>[];

/// 卡片类型配色。
const Map<String, Color> kindColors = <String, Color>{
  '常识': Color(0xFF3B82F6),
  '成语': Color(0xFF10B981),
  '时政': Color(0xFFF59E0B),
};

Color kindColor(String kind) => kindColors[kind] ?? const Color(0xFF6B7280);
