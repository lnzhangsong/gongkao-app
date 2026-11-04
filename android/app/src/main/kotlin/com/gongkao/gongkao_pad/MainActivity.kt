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
import android.util.Log
import android.view.WindowManager
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
                            call.argument<Long>("skipUntil") ?: 0L,
                            call.argument<List<String>>("appLimits") ?: emptyList())
                        result.success(kioskStatus())
                    }
                    "syncAppLimits" -> {
                        syncAppLimits(
                            call.argument<List<String>>("rules") ?: emptyList()
                        )
                        result.success(null)
                    }
                    "listApps" -> result.success(listLaunchableApps())
                    "shizukuStatus" -> result.success(ShizukuShell.status(this))
                    "requestShizuku" -> {
                        ShizukuShell.requestPermission()
                        result.success(ShizukuShell.status(this))
                    }
                    "openShizuku" -> {
                        openShizuku()
                        result.success(null)
                    }
                    "accessibilityStatus" -> result.success(isAccessibilityEnabled())
                    "openAccessibility" -> {
                        openAccessibility()
                        result.success(null)
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
            // startLockTask 在「非设备所有者 + 屏幕固定未开启」时是**静默无效**的：
            // 不抛异常、也不进锁定态。以前这里直接 return true，上层以为锁上了，
            // 实际状态栏照常能拉、Home 照常能按——表现就是「起来了但没有全屏遮盖」。
            // 必须回读真实状态把结果如实上报。
            val ok = awaitLockTask(400)
            Log.i(
                "Kiosk",
                "enterKiosk pinning=${isPinningEnabled()} owner=${isDeviceOwner()} " +
                    "sdk=${Build.VERSION.SDK_INT} -> lockTask=$ok"
            )
            if (ok) {
                KioskSchedule.lockedEnd(KioskPrefs(this), System.currentTimeMillis())
                    ?.let { LockGuardService.start(this) }
            }
            // 能否盖住锁屏与 lock task 无关：只要处于锁定期就一律放行（即使固定失败）。
            syncLockScreenWindow()
            ok
        } catch (e: Exception) {
            Log.w("Kiosk", "enterKiosk failed", e)
            false
        }
    }

    /** 轮询等待锁定态生效：系统应用是异步的，直接回读常常还是 NONE。 */
    private fun awaitLockTask(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (isLockTaskActive()) return true
            try {
                Thread.sleep(40)
            } catch (e: InterruptedException) {
                break
            }
        }
        return isLockTaskActive()
    }

    private fun exitKiosk() {
        try {
            if (isLockTaskActive()) stopLockTask()
        } catch (e: Exception) {
            // 忽略：已被系统解除固定时 stopLockTask 会抛异常。
        }
        applyLockScreenWindow(false)
        LockGuardService.stop(this)
    }

    /** Dart 侧把最新配置同步给原生，供开机广播与守护服务判断。 */
    private fun syncConfig(
        enabled: Boolean,
        autoStart: Boolean,
        periods: List<String>,
        skipAt: Long,
        skipUntil: Long,
        appLimits: List<String>
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
        // 应用限用规则一并落地，并确保轮询服务跟着起停。
        syncAppLimits(appLimits)
        // 配置一变就重排「下一段开始」的闹钟（含放行 skipUntil 的变化）。
        KioskAlarms.schedule(this)
    }

    /**
     * 落盘应用限用规则，并按「有没有规则」起停前台轮询服务。
     *
     * 没有规则就不留常驻服务和通知——这条容易被忘，用户清空规则后
     * 通知栏还挂着一条「应用限制生效中」会很怪。
     */
    private fun syncAppLimits(rules: List<String>) {
        AppLimitPrefs(this).raw = rules
        AppWatchService.sync(this)
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

    /** 无障碍守护是否已开启（系统里的 enabled_accessibility_services 有没有我们）。 */
    private fun isAccessibilityEnabled(): Boolean {
        val expected = "$packageName/${AppGuardService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun openAccessibility() {
        try {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        } catch (e: Exception) {
            Log.w("MainActivity", "打开无障碍设置失败", e)
        }
    }

    /** 打开 Shizuku（没装就跳下载页）。 */
    private fun openShizuku() {
        val pkg = "moe.shizuku.privileged.api"
        val launch = packageManager.getLaunchIntentForPackage(pkg)
        try {
            if (launch != null) {
                startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } else {
                startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse("https://shizuku.rikka.app/"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "打开 Shizuku 失败", e)
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
        // 到点被拉起时设备可能正锁屏 / 熄屏：必须让界面盖在锁屏之上并点亮屏幕，
        // 否则界面在锁屏**下面**，用户什么都看不到（「能自启动，但屏幕没启动」）。
        syncLockScreenWindow()
        // 界面已经到前台了，撤掉「锁定开始」那条全屏通知，避免常驻。
        KioskNotifier.cancel(this)
    }

    /**
     * 锁定期：允许界面盖在锁屏之上，并在被拉起时点亮屏幕。
     *
     * 非锁定期必须关掉——否则平时打开应用也会盖住锁屏、还会自己亮屏。
     */
    private fun applyLockScreenWindow(locked: Boolean) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(locked)
                setTurnScreenOn(locked)
            } else {
                @Suppress("DEPRECATION")
                if (locked) {
                    window.addFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    )
                } else {
                    window.clearFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    )
                }
            }
            Log.i("Kiosk", "lockScreenWindow locked=$locked")
        } catch (e: Exception) {
            Log.w("Kiosk", "applyLockScreenWindow failed", e)
        }
    }

    /** 按「此刻是否处于锁定期」刷新窗口属性。 */
    private fun syncLockScreenWindow() {
        val prefs = KioskPrefs(this)
        val locked = prefs.enabled &&
            KioskSchedule.lockedEnd(prefs, System.currentTimeMillis()) != null
        applyLockScreenWindow(locked)
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

    /**
     * 可被限制的应用清单：桌面可见的、且不是本应用。
     *
     * 只取 CATEGORY_LAUNCHER：系统组件、纯后台服务没必要出现在选择列表里。
     */
    private fun listLaunchableApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        val infos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        return infos.asSequence()
            .mapNotNull { it.activityInfo?.applicationInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { info ->
                mapOf(
                    "package" to info.packageName,
                    "label" to pm.getApplicationLabel(info).toString()
                )
            }
            .toList()
    }
}
