package com.gongkao.gongkao_pad

/**
 * 应用限用规则的判定，与 Dart 侧 `lib/app_limit.dart` 保持同一套语义：
 * - 独立时段：与整机锁定时段无关，整机没锁也照拦；
 * - 叠加规则（duringLock）：用的是**整机锁定时段本身**，不看「提前解锁」放行。
 *   提前解锁只放行整机屏幕，不该让被限制的应用跟着放行。
 */
object AppLimitSchedule {

    /** 某一段独立时段此刻是否生效；生效则返回结束时刻（epoch ms）。 */
    fun periodEnd(period: IntArray, now: Long): Long? {
        var best: Long? = null
        val cal = java.util.Calendar.getInstance()
        // 跨午夜 / 全天会跨日，前后各看一天即可覆盖。
        for (offset in -1..1) {
            val dayStart = KioskSchedule.dayStart(cal, now, offset)
            val start = dayStart + period[0] * 60_000L
            val end = start +
                KioskSchedule.durationMinutes(period[0], period[1]) * 60_000L
            if (now < start || now >= end) continue
            if (best == null || end > best) best = end
        }
        return best
    }

    /** 命中的结果：什么时候解除 + 是否要连常驻服务一起停。 */
    data class Hit(val end: Long, val deep: Boolean)

    /**
     * 此刻 [pkg] 是否受限；受限返回解除时刻（取最晚的一条）与拦截强度，否则 null。
     */
    fun hit(
        limits: AppLimitPrefs,
        kiosk: KioskPrefs,
        pkg: String,
        now: Long
    ): Hit? {
        val rule = limits.rules().firstOrNull { it.pkg == pkg } ?: return null
        var best: Long? = null
        if (rule.duringLock) {
            best = KioskSchedule.lockedEndIgnoringSkip(kiosk, now)
        }
        for (period in rule.periods) {
            val end = periodEnd(period, now) ?: continue
            if (best == null || end > best) best = end
        }
        val end = best ?: return null
        return Hit(end, rule.deep)
    }
}
