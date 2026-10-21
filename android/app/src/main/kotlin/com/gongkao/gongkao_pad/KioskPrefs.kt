package com.gongkao.gongkao_pad

import android.content.Context

/**
 * 原生侧的锁定配置镜像。
 *
 * 开机自启 / 后台守护服务在 Flutter 引擎起来之前就要判断「现在该不该锁」，
 * 所以不能依赖 Dart 的 shared_preferences，单独存一份精简配置。
 */
class KioskPrefs(context: Context) {
    private val sp = context.applicationContext
        .getSharedPreferences("kiosk", Context.MODE_PRIVATE)

    /** 自动锁定总开关。 */
    var enabled: Boolean
        get() = sp.getBoolean("enabled", false)
        set(value) = sp.edit().putBoolean("enabled", value).apply()

    /** 开机自启动总开关（非锁定期也拉起应用）。 */
    var autoStart: Boolean
        get() = sp.getBoolean("auto_start", true)
        set(value) = sp.edit().putBoolean("auto_start", value).apply()

    /** 本次提前解锁的有效期（epoch ms）。 */
    var skipUntil: Long
        get() = sp.getLong("skip_until", 0L)
        set(value) = sp.edit().putLong("skip_until", value).apply()

    /**
     * 按下「提前解锁」的时刻（epoch ms），0 表示没有放行。
     *
     * 放行只作用于这一刻**已经开始**的段：之后才开始的下一段照常锁，
     * 否则上一段的放行会把下一段一起吞掉。
     */
    var skipAt: Long
        get() = sp.getLong("skip_at", 0L)
        set(value) = sp.edit().putLong("skip_at", value).apply()

    /** 时段列表，每项为 [开始分钟, 结束分钟]。 */
    var periods: List<IntArray>
        get() = (sp.getString("periods", "") ?: "")
            .split(',')
            .mapNotNull { parse(it) }
        set(value) {
            sp.edit()
                .putString("periods", value.joinToString(",") { "${it[0]}-${it[1]}" })
                .apply()
        }

    private fun parse(raw: String): IntArray? {
        val parts = raw.trim().split('-')
        if (parts.size != 2) return null
        val a = parts[0].toIntOrNull() ?: return null
        val b = parts[1].toIntOrNull() ?: return null
        if (a !in 0 until DAY_MINUTES || b !in 0 until DAY_MINUTES) return null
        return intArrayOf(a, b)
    }

    companion object {
        const val DAY_MINUTES = 24 * 60
    }
}
