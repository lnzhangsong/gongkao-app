import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';

import '../config.dart';

/// 日期区：杂志式强排版。
/// 横屏（twoColumn）：左栏，整体左对齐，倒计时行撑满宽度。
/// 竖屏（!twoColumn）：作为居中 hero，日期组水平居中，倒计时做成一排居中的小格。
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

    if (!twoColumn) {
      return _portraitHero(now, lunarDay, ganzhi, toExam, elapsed);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _caps('${now.year} · ${_monthEn(now.month)}'),
        const SizedBox(height: 10),
        Text(
          '${now.day}',
          style: const TextStyle(
            fontSize: 190,
            height: 0.82,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$lunarDay · ${_weekday(now.weekday)}',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        _caps(ganzhi, color: Colors.white60),
        const SizedBox(height: 26),
        _hairline(),
        const SizedBox(height: 16),
        _countdownRow('距 $examName', toExam),
        const SizedBox(height: 12),
        _countdownRow('今年已过', elapsed),
      ],
    );
  }

  /// 竖屏 hero：顶部小标签 + 超大日期 + 农历/干支，整体居中；
  /// 倒计时做成居中的两个小格（主流倒计时 App 的排布）。
  Widget _portraitHero(DateTime now, String lunarDay, String ganzhi,
      int toExam, int elapsed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _caps('${now.year} · ${_monthEn(now.month)}'),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${now.day}',
            style: const TextStyle(
              fontSize: 150,
              height: 0.86,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -6,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$lunarDay · ${_weekday(now.weekday)}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        _caps(ganzhi, color: Colors.white60),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(child: _countdownCell('距 $examName', toExam)),
            const SizedBox(width: 14),
            Expanded(child: _countdownCell('今年已过', elapsed)),
          ],
        ),
      ],
    );
  }

  /// 竖屏倒计时小格：半透明底 + 居中大数字 + 标签。
  Widget _countdownCell(String label, int days) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: _caps(label, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '$days',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 3, bottom: 5),
                  child: Text('天',
                      style: TextStyle(fontSize: 14, color: Colors.white60)),
                ),
              ],
            ),
          ),
        ],
      ),
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

  /// 倒计时列表行：左标题、右对齐天数。行宽撑满，与内容卡左右对齐。
  Widget _countdownRow(String label, int days) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontSize: twoColumn ? 19 : 18,
                color: Colors.white,
                height: 1.2),
          ),
        ),
        Text(
          '$days',
          style: TextStyle(
            fontSize: twoColumn ? 38 : 34,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 3, bottom: 4),
          child:
              Text('天', style: TextStyle(fontSize: 14, color: Colors.white60)),
        ),
      ],
    );
  }

  Widget _hairline() => Container(
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
