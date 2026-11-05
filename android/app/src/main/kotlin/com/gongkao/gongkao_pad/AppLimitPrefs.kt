package com.gongkao.gongkao_pad

import android.content.Context

/**
 * 应用限用规则的原生镜像。
 *
 * 拦截发生在原生（前台轮询 + 拦截页），Flutter 引擎可能没起来，
 * 所以不能依赖 Dart 侧的 shared_preferences，单独存一份。
 *
 * 每条规则的持久化格式与 Dart 的 `AppLimit.encode()` 一致：
 * `包名|名称|是否叠加锁机时段|480-720,900-1080`。名称这里用不上，直接跳过。
 */
class AppLimitPrefs(context: Context) {
    private val sp = context.applicationContext
        .getSharedPreferences("app_limit", Context.MODE_PRIVATE)

    /** 一条规则：包名 + 是否在锁机时段内也拦 + 独立时段。 */
    data class Rule(
        val pkg: String,
        val duringLock: Boolean,
        val periods: List<IntArray>,
    )

    /** 原始规则串，每条一行。 */
    var raw: List<String>
        get() = (sp.getString("rules", "") ?: "")
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        set(value) {
            sp.edit().putString("rules", value.joinToString("\n")).apply()
        }

    /** 解析成结构化规则；脏行直接丢弃。 */
    fun rules(): List<Rule> = raw.mapNotNull { parse(it) }

    /** 是否有任何规则——没有就不必常驻轮询。 */
    fun hasRules(): Boolean = raw.isNotEmpty()

    private fun parse(line: String): Rule? {
        val parts = line.split('|')
        if (parts.size < 3) return null
        val pkg = parts[0].trim()
        if (pkg.isEmpty()) return null
        val periods = if (parts.size > 3 && parts[3].isNotEmpty()) {
            parts[3].split(',').mapNotNull { parsePeriod(it.trim()) }
        } else {
            emptyList()
        }
        // 旧版本在末尾多存了一段「彻底停止」，这里直接忽略（parts[4] 不读）。
        return Rule(pkg, parts[2] == "1", periods)
    }

    private fun parsePeriod(raw: String): IntArray? {
        val parts = raw.split('-')
        if (parts.size != 2) return null
        val a = parts[0].toIntOrNull() ?: return null
        val b = parts[1].toIntOrNull() ?: return null
        if (a !in 0 until KioskPrefs.DAY_MINUTES) return null
        if (b !in 0 until KioskPrefs.DAY_MINUTES) return null
        return intArrayOf(a, b)
    }
}
