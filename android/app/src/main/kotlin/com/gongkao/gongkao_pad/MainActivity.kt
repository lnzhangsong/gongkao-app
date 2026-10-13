package com.gongkao.gongkao_pad

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val channel = "com.gongkao.gongkao_pad/usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasUsagePermission())
                    "openSettings" -> {
                        openUsageSettings()
                        result.success(null)
                    }
                    "todayUsage" -> result.success(todayUsage())
                    "todayTimeline" -> result.success(todayTimeline())
                    else -> result.notImplemented()
                }
            }
    }

    /** 是否已授予「使用情况访问」特殊权限。 */
    private fun hasUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** 跳到系统的「使用情况访问」设置页，供用户手动授权。 */
    private fun openUsageSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    /**
     * 今日各应用使用时长（毫秒），按时长降序。
     * 返回 [{package, label, millis}]。
     */
    private fun todayUsage(): List<Map<String, Any>> {
        if (!hasUsagePermission()) return emptyList()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val start = cal.timeInMillis
        val end = System.currentTimeMillis()
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            ?: return emptyList()

        val pm = packageManager
        // 按包名合并（queryUsageStats 可能返回同一包的多个区间）。
        val byPkg = HashMap<String, Long>()
        for (s in stats) {
            val t = s.totalTimeInForeground
            if (t <= 0) continue
            byPkg[s.packageName] = (byPkg[s.packageName] ?: 0L) + t
        }
        return byPkg.entries
            .filter { it.key != packageName }
            .sortedByDescending { it.value }
            .map { e ->
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(e.key, 0)).toString()
                } catch (ex: PackageManager.NameNotFoundException) {
                    e.key
                }
                mapOf(
                    "package" to e.key,
                    "label" to label,
                    "millis" to e.value
                )
            }
    }

    /**
     * 今日前台切换时间线：把 UsageEvents 里的 resumed/paused 配对成前台区间。
     * 返回 [{package,label,start,end,millis}]，按开始时间升序。
     */
    private fun todayTimeline(): List<Map<String, Any>> {
        if (!hasUsagePermission()) return emptyList()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val start = cal.timeInMillis
        val end = System.currentTimeMillis()
        val events = usm.queryEvents(start, end)

        val out = ArrayList<Map<String, Any>>()
        // 每个包当前处于前台的开始时刻（null 表示不在前台）。
        val openAt = HashMap<String, Long>()
        val ev = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            val pkg = ev.packageName ?: continue
            if (pkg == packageName) continue
            when (ev.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    // 打开某 App 时，先把上一条未闭合的区间补上（粗略处理）。
                    openAt[pkg] = ev.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val s = openAt.remove(pkg) ?: continue
                    val e = ev.timeStamp
                    if (e <= s) continue
                    out.add(
                        mapOf(
                            "package" to pkg,
                            "label" to labelOf(pkg),
                            "start" to s,
                            "end" to e,
                            "millis" to (e - s)
                        )
                    )
                }
            }
        }
        // 仍在前后台的，用当前时刻收尾，避免丢掉正在使用的一段。
        for ((pkg, s) in openAt) {
            val e = end
            if (e <= s) continue
            out.add(
                mapOf(
                    "package" to pkg,
                    "label" to labelOf(pkg),
                    "start" to s,
                    "end" to e,
                    "millis" to (e - s)
                )
            )
        }
        // 过滤过短片段（<3s），并按开始时间升序。
        return out
            .filter { (it["millis"] as Long) >= 3000 }
            .sortedBy { it["start"] as Long }
    }

    private fun labelOf(pkg: String): String {
        val pm = packageManager
        return try {
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (ex: PackageManager.NameNotFoundException) {
            pkg
        }
    }
}
