import 'package:flutter_test/flutter_test.dart';
import 'package:gongkao_pad/lock_schedule.dart';

/// 「提前解锁」的作用域：只放过按下那一刻已经在跑的段，
/// 之后才开始的新段 / 首尾相接的下一段 / 次日同名段都不受影响。
void main() {
  DateTime at(int y, int m, int d, int h, [int min = 0]) =>
      DateTime(y, m, d, h, min);

  group('放行一段不影响下一段', () {
    test('首尾相接：放行 21:00-02:00 后，02:00 开始的下一段照常锁', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
        const LockPeriod(start: 2 * 60, end: 7 * 60),
      ]);
      final DateTime pressed = at(2026, 10, 22, 0, 25);
      final DateTime until = at(2026, 10, 22, 2); // 只放到本段结束

      // 放行窗口内：不锁
      expect(
        s.lockedEnd(at(2026, 10, 22, 1),
            enabled: true, skipAt: pressed, skipUntil: until),
        isNull,
      );
      // 下一段自己的时间：锁到 07:00
      expect(
        s.lockedEnd(at(2026, 10, 22, 3),
            enabled: true, skipAt: pressed, skipUntil: until),
        at(2026, 10, 22, 7),
      );
    });

    test('放行之后才开始的一段不受影响（哪怕按段放行到更晚）', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
        const LockPeriod(start: 2 * 60, end: 7 * 60),
      ]);
      expect(
        s.lockedEnd(
          at(2026, 10, 22, 2, 30),
          enabled: true,
          skipAt: at(2026, 10, 22, 0, 25),
          skipUntil: at(2026, 10, 22, 4), // 就算放到 04:00，02:00 这段也要锁
        ),
        at(2026, 10, 22, 7),
      );
    });

    test('重叠：按下时已经在跑的两段都放过（否则按了等于没按）', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
        const LockPeriod(start: 20, end: 7 * 60),
      ]);
      expect(
        s.lockedEnd(
          at(2026, 10, 22, 0, 30),
          enabled: true,
          skipAt: at(2026, 10, 22, 0, 25),
          skipUntil: at(2026, 10, 22, 7),
        ),
        isNull,
      );
    });

    test('放行到期后照常锁', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 7 * 60),
      ]);
      expect(
        s.lockedEnd(
          at(2026, 10, 22, 4),
          enabled: true,
          skipAt: at(2026, 10, 22, 0, 25),
          skipUntil: at(2026, 10, 22, 3),
        ),
        at(2026, 10, 22, 7),
      );
    });

    test('次日同名段不受昨天的放行影响', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
      ]);
      expect(
        s.lockedEnd(
          at(2026, 10, 22, 22),
          enabled: true,
          skipAt: at(2026, 10, 21, 21),
          skipUntil: at(2026, 10, 22, 2),
        ),
        at(2026, 10, 23, 2),
      );
    });

    test('没有放行记录时按最晚结束锁定', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
        const LockPeriod(start: 20, end: 7 * 60),
      ]);
      expect(
        s.lockedEnd(at(2026, 10, 22, 0, 30), enabled: true),
        at(2026, 10, 22, 7),
      );
    });

    test('activeWindow 给出段的真实起止（供放行时取本段结束）', () {
      final LockSchedule s = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
      ]);
      final ({DateTime start, DateTime end})? w =
          s.activeWindow(at(2026, 10, 22, 0, 30));
      expect(w?.start, at(2026, 10, 21, 21));
      expect(w?.end, at(2026, 10, 22, 2));
    });
  });

  // 用户路径：点「提前解锁」→ 进设置改时段 → 保存。放行是显式动作，
  // 不该被编辑动作撤销，否则一保存就被锁回去，设置根本改不了。
  group('改时段不撤销放行', () {
    final DateTime pressed = at(2026, 10, 22, 0, 25);
    final DateTime now = at(2026, 10, 22, 0, 30);

    test('延长当前段：放行截止跟着延到新结束，此刻仍不锁', () {
      final DateTime before = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
      ]).releasedEnd(now, skipAt: pressed)!;
      expect(before, at(2026, 10, 22, 2));

      final LockSchedule after = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 5 * 60), // 结束时间改晚
      ]);
      final DateTime until = after.releasedEnd(now, skipAt: pressed)!;
      expect(until, at(2026, 10, 22, 5));
      expect(
        after.lockedEnd(now, enabled: true, skipAt: pressed, skipUntil: until),
        isNull,
      );
    });

    test('把当前段挪到未来：放行没有对象，改完不锁，到点才锁', () {
      final LockSchedule after = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 9 * 60, end: 12 * 60),
      ]);
      expect(after.releasedEnd(now, skipAt: pressed), isNull);
      expect(
        after.lockedEnd(now,
            enabled: true, skipAt: pressed, skipUntil: at(2026, 10, 22, 2)),
        isNull,
      );
      expect(
        after.lockedEnd(at(2026, 10, 22, 10), enabled: true),
        at(2026, 10, 22, 12),
      );
    });

    test('改完仍只放过已开始的段：之后才开始的不在其内', () {
      final LockSchedule after = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60), // 在跑
        const LockPeriod(start: 3 * 60, end: 7 * 60), // 之后才开始
      ]);
      final DateTime until = after.releasedEnd(now, skipAt: pressed)!;
      expect(until, at(2026, 10, 22, 2));
      expect(
        after.lockedEnd(at(2026, 10, 22, 4),
            enabled: true, skipAt: pressed, skipUntil: until),
        at(2026, 10, 22, 7),
      );
    });

    test('重叠两段（真机配置）：截止取最晚，改完不锁', () {
      final LockSchedule after = LockSchedule(<LockPeriod>[
        const LockPeriod(start: 21 * 60, end: 2 * 60),
        const LockPeriod(start: 20, end: 7 * 60),
      ]);
      final DateTime until = after.releasedEnd(at(2026, 10, 22, 1, 16),
          skipAt: at(2026, 10, 22, 1, 10))!;
      expect(until, at(2026, 10, 22, 7));
      expect(
        after.lockedEnd(at(2026, 10, 22, 1, 20),
            enabled: true,
            skipAt: at(2026, 10, 22, 1, 10),
            skipUntil: until),
        isNull,
      );
    });
  });
}
