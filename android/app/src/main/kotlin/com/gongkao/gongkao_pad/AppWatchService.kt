package com.gongkao.gongkao_pad

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 应用限用的前台轮询服务。
 *
 * 做法：每 1.2 秒查一次「最近这段时间内最后一个被切到前台的应用」，
 * 一旦是受限应用且此刻处于它的限用时段，就立刻把它顶回桌面。
 *
 * 这是**兜底**：[AppGuardService]（无障碍）在线时更准更快，由它处理，
 * 这里只记录不重复动作。无障碍被系统关掉时靠这条兜底，代价是约 1 秒延迟。
 * 之所以留着轮询：无障碍在 MIUI 上容易被回收，没有兜底就等于功能时灵时不灵。
 *
 * 每个轮询周期都判定一次，而不是只在「前台应用发生变化」时判定：
 * 应用一直开着、到点进入限用时段时包名并没有变化，按变化判定会整段漏掉。
 * 自己的界面停在前台时（包名等于自己）不判定，所以不会反复自弹。
 */
class AppWatchService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var ticking = false

    /** 上一次拦的是谁、什么时候拦的，用来抑制拉起过程中的重复触发。 */
    private var lastBlockPkg: String? = null
    private var lastBlockAt = 0L

    /** 上一次看到的前台包名，只用于切换时打一行日志。 */
    private var lastFg: String? = null

    /** 上一次做「禁用 / 恢复」同步的时刻，限流用。 */
    private var lastSyncAt = 0L

    /** 记录自己禁用过哪些包，负责到点恢复。 */
    private val guardPrefs by lazy {
        getSharedPreferences("app_limit_guard", Context.MODE_PRIVATE)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        if (!ticking) {
            ticking = true
            handler.post(tick)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        ticking = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private val tick = object : Runnable {
        override fun run() {
            if (!ticking) return
            val limits = AppLimitPrefs(this@AppWatchService)
            // 一条规则都没有就不必常驻，避免白占通知栏和电。
            if (!limits.hasRules()) {
                stopSelf()
                return
            }
            val now = System.currentTimeMillis()
            // 主线：有 shell 身份就直接禁用/恢复应用，到点它连图标都没有，
            // 根本不存在「点开再踢回去」这回事。
            syncDisabled(limits, now)

            val fg = foregroundPackage()
            if (fg != lastFg) {
                // 只在切换时记一条，便于排查「配了没反应」到底是没读到前台还是没命中时段。
                Log.d(TAG, "前台切到 $fg（规则 ${limits.raw.size} 条）")
                lastFg = fg
            }
            if (fg != null && fg != packageName) {
                val hit = AppLimitSchedule.hit(
                    limits, KioskPrefs(this@AppWatchService), fg, now
                )
                // 每个周期都判定，不看「是不是刚切过来」：
                // 应用一直开着、到点进入限用时段时包名并没有变化，
                // 按变化判定就会永远漏掉这一种情况（这正是「到点没关」的原因）。
                if (hit != null) {
                    when {
                        // 正在替用户点「强行停止」，别去打断那个流程。
                        AppGuardService.busy -> Unit
                        // 无障碍刚处理过：短暂让位，免得两边同时推桌面。
                        AppGuardService.connected &&
                            now - AppGuardService.lastBlockAt < GUARD_GRACE_MS -> {
                            Log.d(TAG, "无障碍刚处理过 $fg，轮询让位")
                        }
                        fg != lastBlockPkg || now - lastBlockAt > BLOCK_DEBOUNCE_MS -> {
                            lastBlockPkg = fg
                            lastBlockAt = now
                            Log.i(TAG, "拦截 $fg，解除于 ${hit.end}（轮询兜底）")
                            kickOut(fg, hit.end)
                        }
                    }
                }
            } else {
                // 回到桌面或本应用时复位，下次再打开同一应用还能立刻拦。
                lastBlockPkg = null
            }
            handler.postDelayed(this, TICK_MS)
        }
    }

    /**
     * 按规则禁用 / 恢复应用。
     *
     * `pm disable-user` 会把应用从桌面摘掉，点图标系统直接拒绝启动——
     * 这才是「到点打不开」，而不是「打开之后被踢回去」。
     *
     * 只负责自己禁用的那些：记在 [K_MANAGED] 里，规则删掉或时段结束就恢复。
     * 用户自己去系统设置里手动禁用的应用不在这个集合里，绝不会被误启用。
     */
    private fun syncDisabled(limits: AppLimitPrefs, now: Long) {
        if (now - lastSyncAt < SYNC_MS) return
        lastSyncAt = now
        if (ShizukuShell.status(this) != "ready") return

        val kiosk = KioskPrefs(this)
        val want = limits.rules()
            .map { it.pkg }
            .filter { it != packageName }
            .filter { isThirdParty(it) }
            .filter { AppLimitSchedule.hit(limits, kiosk, it, now) != null }
            .toSet()

        val managed = loadManaged()
        // 以系统真实状态为准：用户可能自己在设置里把我们禁用的应用又启用了。
        val disabled = ShizukuShell.disabledPackages() ?: return

        var changed = false
        for (pkg in want) {
            if (pkg in disabled) {
                if (managed.add(pkg)) changed = true
                continue
            }
            if (ShizukuShell.setEnabled(pkg, enabled = false)) {
                managed.add(pkg)
                changed = true
                Log.i(TAG, "到点禁用 $pkg")
            }
        }
        for (pkg in managed.toList()) {
            if (pkg in want) continue
            if (pkg !in disabled) {
                // 已经不是我禁用的状态了（被手动启用），只把账销掉。
                managed.remove(pkg)
                changed = true
                continue
            }
            if (ShizukuShell.setEnabled(pkg, enabled = true)) {
                managed.remove(pkg)
                changed = true
                Log.i(TAG, "解除禁用 $pkg")
            }
        }
        if (changed) saveManaged(managed)
    }

    /**
     * 只处理第三方应用。
     *
     * `pm disable-user` 的名字不阻止我们禁用系统应用——真把桌面、输入法、
     * 电话这类禁掉，手机就废了。系统应用一律不碰，宁可少拦。
     */
    private fun isThirdParty(pkg: String): Boolean = try {
        val info = packageManager.getApplicationInfo(pkg, 0)
        (info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) == 0
    } catch (e: Exception) {
        false
    }

    private fun loadManaged(): MutableSet<String> =
        (guardPrefs.getStringSet(K_MANAGED, emptySet()) ?: emptySet()).toMutableSet()

    private fun saveManaged(set: Set<String>) {
        guardPrefs.edit().putStringSet(K_MANAGED, set).apply()
    }

    /**
     * 最近一段时间内最后一个切到前台的应用。
     *
     * 用 events 而不是 queryUsageStats：后者按天聚合，取不到「当前是谁」。
     */
    private fun foregroundPackage(): String? {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val events = usm.queryEvents(now - LOOKBACK_MS, now) ?: return null
            val ev = UsageEvents.Event()
            var last: String? = null
            while (events.hasNextEvent()) {
                events.getNextEvent(ev)
                // ACTIVITY_RESUMED 与旧的 MOVE_TO_FOREGROUND 同值（1），
                // 在 API 29 以下也能正确匹配。
                if (ev.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                    last = ev.packageName
                }
            }
            last
        } catch (e: Exception) {
            Log.w(TAG, "foregroundPackage failed", e)
            null
        }
    }

    /**
     * 把受限应用顶回桌面。
     *
     * 刻意不弹全屏拦截页：用户要的是「打不开」，不是「打开之后盖一层」。
     * 原因用 Toast 说一句就够，不占屏幕、也不用再点一次。
     */
    private fun kickOut(pkg: String, end: Long) {
        try {
            val home = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(home)
        } catch (e: Exception) {
            // 没有「后台弹出界面」权限时系统会拦下，只能等下一轮再试。
            Log.w(TAG, "回桌面失败 for $pkg", e)
        }
        try {
            Toast.makeText(
                this, "「${labelOf(pkg)}」在限制时段内，${fmt(end)} 之后可用",
                Toast.LENGTH_SHORT
            ).show()
        } catch (e: Exception) {
            Log.w(TAG, "toast failed", e)
        }
        // 顶到后台之后再补一刀：普通应用没有 force-stop 权限，
        // killBackgroundProcesses 只能清掉「已经不在前台」的进程，
        // 但足以让受限应用停止发声/停止后台工作，重新打开就是冷启动。
        handler.postDelayed({ killTarget(pkg) }, KILL_DELAY_MS)
    }

    private fun fmt(epochMs: Long): String =
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))

    private fun killTarget(pkg: String) {
        // 无障碍没开时只能尽力清后台：有前台服务的应用（VPN/音乐）杀不掉，
        // 要彻底停得开无障碍、并把该应用标记成「彻底停止」。
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            am.killBackgroundProcesses(pkg)
        } catch (e: Exception) {
            Log.w(TAG, "killBackgroundProcesses failed for $pkg", e)
        }
    }

    private fun labelOf(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("应用限制生效中")
            .setContentText("受限应用在设定时段内无法打开")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "应用限制", NotificationManager.IMPORTANCE_LOW)
                .apply {
                    description = "受限应用在设定时段内无法打开"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
        )
    }

    companion object {
        private const val TAG = "AppWatch"
        private const val CHANNEL_ID = "app_watch"
        private const val NOTIFICATION_ID = 7202
        private const val TICK_MS = 1200L

        /** 拉起拦截页后等多久再清目标进程：给它留出真正退到后台的时间。 */
        private const val KILL_DELAY_MS = 600L

        /** 同一个应用重复拉起拦截页的最小间隔，避免和 startActivity 的时序打架。 */
        private const val BLOCK_DEBOUNCE_MS = 2500L

        /**
         * 无障碍刚拦过之后的让位时长。
         *
         * 只是「别抢它的活」，不是「放手不管」：无障碍在 MIUI 上偶尔会漏事件
         * （用户隔一两秒再点一次就是典型），超过这个时长轮询照常兜底，
         * 否则漏一次就等于那个应用整段限制期都进得去。
         */
        private const val GUARD_GRACE_MS = 3000L

        /** 回看的窗口：够覆盖一次前后台切换，又不至于每次扫太久。 */
        private const val LOOKBACK_MS = 8000L

        /** 「禁用 / 恢复」的同步间隔：每次要过一遍 shell，没必要太密。 */
        private const val SYNC_MS = 3000L

        /** 自己禁用过的包，到点由自己负责恢复。 */
        private const val K_MANAGED = "managed_packages"

        /**
         * 恢复所有被本应用禁用的包。
         *
         * 用户要一个「万一出问题」的出口：规则配错、Shizuku 被关、
         * 应用卡在禁用状态时，点一下就能全部启回来。
         */
        fun restoreAll(context: Context): Int {
            if (ShizukuShell.status(context) != "ready") return -1
            val sp = context.getSharedPreferences("app_limit_guard", Context.MODE_PRIVATE)
            val managed = (sp.getStringSet(K_MANAGED, emptySet()) ?: emptySet()).toMutableSet()
            var restored = 0
            for (pkg in managed.toList()) {
                if (ShizukuShell.setEnabled(pkg, enabled = true)) restored++
            }
            sp.edit().putStringSet(K_MANAGED, emptySet()).apply()
            return restored
        }

        fun start(context: Context) {
            val intent = Intent(context, AppWatchService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AppWatchService::class.java))
        }

        /** 按当前规则决定启动还是停止：没规则就不留常驻服务。 */
        fun sync(context: Context) {
            if (AppLimitPrefs(context).hasRules()) start(context) else stop(context)
        }
    }
}
