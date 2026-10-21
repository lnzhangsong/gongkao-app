package com.gongkao.gongkao_pad

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val channel = "com.gongkao.gongkao_pad/usage"
    private val kioskChannel = "com.gongkao.gongkao_pad/kiosk"
    private val kioskAdmin: ComponentName by lazy {
        ComponentName(this, KioskAdminReceiver::class.java)
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kioskChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(kioskStatus())
                    "start" -> {
                        requestNotificationPermissionIfNeeded()
                        result.success(enterKiosk())
                    }
                    "stop" -> {
                        exitKiosk()
                        result.success(true)
                    }
                    "isActive" -> result.success(isLockTaskActive())
                    "sync" -> {
                        syncConfig(call.argument<Boolean>("enabled") ?: false,
                            call.argument<Boolean>("autoStart") ?: true,
                            call.argument<List<String>>("periods") ?: emptyList(),
                            call.argument<Long>("skipAt") ?: 0L,
                            call.argument<Long>("skipUntil") ?: 0L)
                        result.success(kioskStatus())
                    }
                    "openOverlaySettings" -> {
                        openOverlaySettings()
                        result.success(null)
                    }
                    "openBatterySettings" -> {
                        openBatterySettings()
                        result.success(null)
                    }
                    "openSecuritySettings" -> {
                        openSecuritySettings()
                        result.success(null)
                    }
                    "openFullScreenSettings" -> {
                        KioskNotifier.openFullScreenSettings(this)
                        result.success(null)
                    }
                    "deviceOwnerCommand" -> result.success(DEVICE_OWNER_COMMAND)
                    else -> result.notImplemented()
                }
            }
    }

    // ── 系统级锁定（lock task / 屏幕固定） ──────────────────────────────

    private fun isDeviceOwner(): Boolean = try {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        dpm.isDeviceOwnerApp(packageName)
    } catch (e: Exception) {
        false
    }

    private fun isLockTaskActive(): Boolean = try {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            am.isInLockTaskMode
        }
    } catch (e: Exception) {
        false
    }

    /** 进入系统锁定：锁定期间通知栏 / 控制中心 / 返回桌面全部被系统拦下。 */
    private fun enterKiosk(): Boolean {
        return try {
            if (isLockTaskActive()) return true
            if (isDeviceOwner()) {
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                dpm.setLockTaskPackages(kioskAdmin, arrayOf(packageName))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    dpm.setLockTaskFeatures(kioskAdmin, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
                }
            }
            startLockTask()
            KioskSchedule.lockedEnd(KioskPrefs(this), System.currentTimeMillis())
                ?.let { LockGuardService.start(this) }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun exitKiosk() {
        try {
            if (isLockTaskActive()) stopLockTask()
        } catch (e: Exception) {
            // 忽略：已被系统解除固定时 stopLockTask 会抛异常。
        }
        LockGuardService.stop(this)
    }

    /** Dart 侧把最新配置同步给原生，供开机广播与守护服务判断。 */
    private fun syncConfig(
        enabled: Boolean,
        autoStart: Boolean,
        periods: List<String>,
        skipAt: Long,
        skipUntil: Long
    ) {
        val prefs = KioskPrefs(this)
        prefs.enabled = enabled
        prefs.autoStart = autoStart
        prefs.skipAt = skipAt
        prefs.skipUntil = skipUntil
        prefs.periods = periods.mapNotNull { raw ->
            val parts = raw.split('-')
            if (parts.size != 2) return@mapNotNull null
            val a = parts[0].toIntOrNull() ?: return@mapNotNull null
            val b = parts[1].toIntOrNull() ?: return@mapNotNull null
            intArrayOf(a, b)
        }
        // 非锁定期不要把守护服务留在后台。
        if (!enabled) LockGuardService.stop(this)
        // 配置一变就重排「下一段开始」的闹钟（含放行 skipUntil 的变化）。
        KioskAlarms.schedule(this)
    }

    private fun kioskStatus(): Map<String, Any> = mapOf(
        "supported" to true,
        "deviceOwner" to isDeviceOwner(),
        "active" to isLockTaskActive(),
        "pinningEnabled" to isPinningEnabled(),
        "overlay" to Settings.canDrawOverlays(this),
        "batteryOk" to isIgnoringBattery(),
        "notifications" to hasNotificationPermission(),
        // Android 14+ 可被单独关掉；关掉后到点只能弹横幅，拉不起全屏界面。
        "fullScreenIntent" to KioskNotifier.canUseFullScreen(this)
    )

    private fun isPinningEnabled(): Boolean = try {
        Settings.Secure.getInt(contentResolver, "lock_to_app_enabled", 0) == 1
    } catch (e: Exception) {
        false
    }

    private fun isIgnoringBattery(): Boolean = try {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.isIgnoringBatteryOptimizations(packageName)
    } catch (e: Exception) {
        false
    }

    private fun hasNotificationPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasNotificationPermission()) return
        try {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 7101)
        } catch (e: Exception) {
            // 拒绝也不影响锁定本身，只是看不到守护通知。
        }
    }

    private fun openOverlaySettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName")
        )
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
        }
    }

    private fun openBatterySettings() {
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName")
        )
        try {
            startActivity(direct)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (e2: Exception) {
                // 忽略
            }
        }
    }

    private fun openSecuritySettings() {
        try {
            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        } catch (e: Exception) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e2: Exception) {
                // 忽略
            }
        }
    }

    override fun onResume() {
        super.onResume()
        AppForeground.alive = true
        // 界面已经到前台了，撤掉「锁定开始」那条全屏通知，避免常驻。
        KioskNotifier.cancel(this)
    }

    override fun onPause() {
        AppForeground.alive = false
        super.onPause()
    }

    override fun onDestroy() {
        AppForeground.alive = false
        super.onDestroy()
    }

    companion object {
        const val DEVICE_OWNER_COMMAND =
            "adb shell dpm set-device-owner com.gongkao.gongkao_pad/.KioskAdminReceiver"
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
