package com.gongkao.gongkao_pad

/**
 * 锁定时段的原生实现，与 Dart 侧 lib/lock_schedule.dart 保持同一套语义：
 * - `start == end` → 全天锁定；
 * - `end < start` → 跨午夜（如 22:00 → 次日 06:00）；
 * - 多段重叠时取最晚结束的那一段；
 * - `skipAt` 之前已经开始、且仍在 `skipUntil` 之前的段视为已放行；之后开始的新段照常锁。
 */
object KioskSchedule {

    /** 此刻若锁定，返回解锁时刻（epoch ms）；否则返回 null。 */
    fun lockedEnd(prefs: KioskPrefs, now: Long): Long? {
        if (!prefs.enabled) return null
        val periods = prefs.periods
        if (periods.isEmpty()) return null
        val skipAt = prefs.skipAt
        val skipUntil = prefs.skipUntil
        val skipping = skipAt > 0L && skipUntil > 0L && now < skipUntil

        var best: Long? = null
        val cal = java.util.Calendar.getInstance()
        for (period in periods) {
            // 跨午夜 / 全天会跨日，前后各看一天即可覆盖。
            for (offset in -1..1) {
                val dayStart = dayStart(cal, now, offset)
                val start = dayStart + period[0] * 60_000L
                val end = start + durationMinutes(period[0], period[1]) * 60_000L
                if (now < start || now >= end) continue
                // 放行只作用于按下那一刻已经在跑的段；之后才开始的下一段照常锁。
                if (skipping && start <= skipAt) continue
                if (best == null || end > best) best = end
            }
        }
        return best
    }

    /**
     * 下一次开始锁定的时刻（epoch ms），没有则 null。[KioskAlarms] 用它排闹钟。
     *
     * 不按放行窗口做过滤：放行只作用于某一段实例，与它重叠的另一段该在
     * 自己的开始时刻照常叫醒（旧版按窗口过滤会把这段整段跳过）。
     */
    fun nextStart(prefs: KioskPrefs, now: Long): Long? {
        if (!prefs.enabled) return null
        val periods = prefs.periods
        if (periods.isEmpty()) return null

        var best: Long? = null
        val cal = java.util.Calendar.getInstance()
        for (period in periods) {
            for (offset in -1..2) {
                val start = dayStart(cal, now, offset) + period[0] * 60_000L
                if (start <= now) continue
                if (best == null || start < best) best = start
            }
        }
        return best
    }

    private fun dayStart(cal: java.util.Calendar, now: Long, offset: Int): Long {
        cal.timeInMillis = now
        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
        cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        cal.add(java.util.Calendar.DAY_OF_YEAR, offset)
        return cal.timeInMillis
    }

    /** 环形时长：全天 1440；跨午夜按 +1440 计算。 */
    fun durationMinutes(start: Int, end: Int): Int {
        if (start == end) return KioskPrefs.DAY_MINUTES
        val d = ((end - start) % KioskPrefs.DAY_MINUTES + KioskPrefs.DAY_MINUTES) %
            KioskPrefs.DAY_MINUTES
        return if (d == 0) KioskPrefs.DAY_MINUTES else d
    }
}
