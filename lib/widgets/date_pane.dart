import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';

import '../config.dart';

/// 日期 / 星期 / 农历 / 倒计时。平板与手机两版式共用。
class DatePane extends StatelessWidget {
  const DatePane({super.key, required this.twoColumn});

  final bool twoColumn;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final TextTheme text = Theme.of(context).textTheme;
    final Lunar lunar = Lunar.fromDate(now);
    final String lunarText =
        '农历${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}';
    final today = DateTime(now.year, now.month, now.day);
    final target =
        DateTime(examDate.year, examDate.month, examDate.day);
    final int toExam = target.difference(today).inDays;
    final int elapsed = DateTime(now.year).difference(today).inDays.abs();

    final String dateLine =
        '${now.year}年${now.month}月${now.day}日';
    final String weekLine = _weekday(now.weekday);

    if (twoColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text('${now.month}月', style: text.headlineMedium),
          Text('${now.day}', style: text.displayLarge),
          const SizedBox(height: 4),
          Text(weekLine, style: text.titleLarge),
          const SizedBox(height: 28),
          Text('距 $examName', style: text.bodyMedium),
          Text('还有 $toExam 天', style: text.headlineMedium),
          const SizedBox(height: 16),
          Text('已过 $elapsed 天  ·  公元 ${now.year}  ·  $lunarText',
              style: text.bodyMedium),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text('$dateLine  $weekLine', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(lunarText, style: text.bodyMedium),
        const SizedBox(height: 20),
        Text('${now.day}', style: text.displayLarge),
        const SizedBox(height: 12),
        Text('距 $examName', style: text.bodyMedium),
        Text('还有 $toExam 天', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text('已过 $elapsed 天', style: text.bodyMedium),
      ],
    );
  }

  static String _weekday(int w) =>
      const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'][w - 1];
}
