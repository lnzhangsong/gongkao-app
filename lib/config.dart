import 'package:flutter/material.dart';

/// 常改项集中在此：考试日期、轮播间隔、断点、番茄时长、音源清单。

/// 目标考试。日期依据官方公告/历年规律，可随时在此调整。
/// 国考：2027 年度公共科目笔试 2026-11-29（国家公务员局公告）。
/// 辽宁省考：参加春季联考，近年笔试均在 3 月中旬周六（2025-03-15、2026-03-14），
/// 2027 年预计 3 月中旬，此处按 2027-03-13（周六）预填，公告发布后请核对。
class ExamTarget {
  const ExamTarget({required this.label, required this.date});

  final String label;
  final DateTime date;
}

final List<ExamTarget> examTargets = <ExamTarget>[
  ExamTarget(label: '2027 国考', date: DateTime(2026, 11, 29)),
  ExamTarget(label: '2027 辽宁省考', date: DateTime(2027, 3, 13)),
];

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

/// 全部主题（顺序即界面展示顺序）。
const List<String> allKinds = <String>['常识', '成语', '时政'];


/// 壁纸来源：Bing 图片搜索（免 Key，每日一换），失败时回落 Bing 每日图。
const String bingImageSearchUrl = 'https://www.bing.com/images/async';

/// Bing 图片 CDN 代理（同 www.bing.com，稳定可达），按 id 取指定尺寸。
const String bingImageHost = 'https://www.bing.com/th';

/// 壁纸搜索关键词（中式古建）。
const String wallpaperQuery = 'chinese ancient architecture';

/// 期望的壁纸图宽（px）。Bing CDN 会按此缩放。
const int wallpaperWidth = 1920;

/// Bing 每日图背景（台历界面）。取 UHD，当日缓存到本地，离线回落纯色。
const bool useBingWallpaper = true;
const String bingArchiveUrl =
    'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN';

/// 图片上的半透明深色蒙版不透明度（0..1），保证文字可读。
const double wallpaperScrim = 0.35;

/// 背景图高斯模糊半径（sigma）。越大越虚化，前景文字越清晰。
const double wallpaperBlur = 18;

