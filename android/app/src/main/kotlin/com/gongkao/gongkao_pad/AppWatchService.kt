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
 * 一旦是受限应用且此刻处于它的限用时段，就立刻把 [AppBlockActivity] 顶上去。
 *
 * 为什么用轮询而不是无障碍：开机就要能用，不想让用户去系统设置里翻「无障碍」
 * （MIUI 上入口很深、还容易被系统回收）；「使用情况访问」权限本项目本来就有
 * （今日足迹在用）。代价是 1 秒左右的延迟——打开后会闪一下再被顶走。
 *
 * 每个轮询周期都判定一次，而不是只在「前台应用发生变化」时判定：
 * 应用一直开着、到点进入限用时段时包名并没有变化，按变化判定会整段漏掉。
 * 拦截页本身停在前台时（包名等于自己）不判定，所以不会反复自弹。
 */
class AppWatchService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var ticking = false

    /** 上一次拦的是谁、什么时候拦的，用来抑制拉起过程中的重复触发。 */
    private var lastBlockPkg: String? = null
    private var lastBlockAt = 0L

    /** 上一次看到的前台包名，只用于切换时打一行日志。 */
    private var lastFg: String? = null

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
            val fg = foregroundPackage()
            if (fg != lastFg) {
                // 只在切换时记一条，便于排查「配了没反应」到底是没读到前台还是没命中时段。
                Log.d(TAG, "前台切到 $fg（规则 ${limits.raw.size} 条）")
                lastFg = fg
            }
            if (fg != null && fg != packageName) {
                val end = AppLimitSchedule.limitEnd(
                    limits, KioskPrefs(this@AppWatchService), fg, now
                )
                // 每个周期都判定，不看「是不是刚切过来」：
                // 应用一直开着、到点进入限用时段时包名并没有变化，
                // 按变化判定就会永远漏掉这一种情况（这正是「到点没关」的原因）。
                if (end != null && (fg != lastBlockPkg || now - lastBlockAt > BLOCK_DEBOUNCE_MS)) {
                    lastBlockPkg = fg
                    lastBlockAt = now
                    Log.i(TAG, "拦截 $fg，解除于 $end")
                    kickOut(fg, end)
                }
            } else {
                // 回到桌面或本应用时复位，下次再打开同一应用还能立刻拦。
                lastBlockPkg = null
            }
            handler.postDelayed(this, TICK_MS)
        }
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
        // 有 Shizuku 就 force-stop（连前台服务一起停、不会自启），否则尽力杀后台。
        if (ShizukuShell.forceStop(pkg)) return
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

        /** 回看的窗口：够覆盖一次前后台切换，又不至于每次扫太久。 */
        private const val LOOKBACK_MS = 8000L

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
