import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';

import '../config.dart';

/// 日期区（左栏）：杂志式强排版。
/// 超小号大写标签 + 超大日期数字 + 小号拉开字距的元信息 + 列表式倒计时。
class DatePane extends StatelessWidget {
  const DatePane({super.key, required this.twoColumn});

  final bool twoColumn;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final Lunar lunar = Lunar.fromDate(now);
    final String lunarDay =
        '${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}';
    final String ganzhi =
        '${lunar.getYearInGanZhi()}${lunar.getYearShengXiao()}年 · '
        '${lunar.getMonthInGanZhi()}月 · ${lunar.getDayInGanZhi()}日';
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime target =
        DateTime(examDate.year, examDate.month, examDate.day);
    final int toExam = target.difference(today).inDays;
    final int elapsed = today.difference(DateTime(now.year)).inDays + 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _caps('${now.year} · ${_monthEn(now.month)}'),
        const SizedBox(height: 10),
        Text(
          '${now.day}',
          style: TextStyle(
            fontSize: twoColumn ? 190 : 120,
            height: 0.82,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$lunarDay · ${_weekday(now.weekday)}',
          style: TextStyle(
            fontSize: twoColumn ? 24 : 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        _caps(ganzhi, color: Colors.white60),
        SizedBox(height: twoColumn ? 26 : 18),
        _hairline(),
        SizedBox(height: twoColumn ? 16 : 12),
        _countdownRow('距 $examName', toExam),
        const SizedBox(height: 12),
        _countdownRow('今年已过', elapsed),
      ],
    );
  }

  /// 大写小标签：小号 + 拉开字距，杂志式点缀。
  Widget _caps(String s, {Color color = Colors.white70}) => Text(
        s,
        style: TextStyle(
          fontSize: 13,
          color: color,
          letterSpacing: 3,
          fontWeight: FontWeight.w600,
        ),
      );

  /// 倒计时列表行：左标题、右对齐天数。
  Widget _countdownRow(String label, int days) {
    return SizedBox(
      width: twoColumn ? 320 : 320,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: twoColumn ? 19 : 17,
                  color: Colors.white,
                  height: 1.2),
            ),
          ),
          Text(
            '$days',
            style: TextStyle(
              fontSize: twoColumn ? 38 : 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 3, bottom: 4),
            child: Text('天',
                style: TextStyle(fontSize: 14, color: Colors.white60)),
          ),
        ],
      ),
    );
  }

  Widget _hairline() => Container(
        width: twoColumn ? 320 : 320,
        height: 1,
        color: Colors.white.withValues(alpha: 0.22),
      );

  static String _monthEn(int m) => const <String>[
        'JANUARY',
        'FEBRUARY',
        'MARCH',
        'APRIL',
        'MAY',
        'JUNE',
        'JULY',
        'AUGUST',
        'SEPTEMBER',
        'OCTOBER',
        'NOVEMBER',
        'DECEMBER'
      ][m - 1];

  static String _weekday(int w) => const <String>[
        '星期一',
        '星期二',
        '星期三',
        '星期四',
        '星期五',
        '星期六',
        '星期日'
      ][w - 1];
}
