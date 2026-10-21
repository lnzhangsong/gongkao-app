package com.gongkao.gongkao_pad

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 锁定期守护服务。
 *
 * 作用：锁定期间每隔 2 秒核对一次状态——一旦发现应用被切到后台（例如用户把
 * 「屏幕固定」强行解除、或从后台切走），立刻把锁定界面拉回前台并重新进入
 * lock task，让「下拉通知栏 → 控制中心 → 切走」这条路走不通。
 *
 * 前台服务只是为了保活，通知在锁定态下本身也被系统隐藏。
 */
class LockGuardService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var ticking = false

    /** 上次发「全屏通知」的时刻：界面被切走时靠它把界面顶回前台，但不至于每 2 秒刷一次。 */
    private var lastNotifyAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground(null)
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
            val now = System.currentTimeMillis()
            val end = KioskSchedule.lockedEnd(KioskPrefs(this@LockGuardService), now)
            if (end == null) {
                // 已过锁定段：先把「下一段」交给系统闹钟，再收工，避免常驻通知打扰。
                // 少了这一步，段一结束就再没人记得下一段几点开始（放行后尤其明显）。
                KioskAlarms.schedule(this@LockGuardService)
                stopSelf()
                return
            }
            startAsForeground(end)
            if (!AppForeground.alive) {
                launchApp()
                // 后台 startActivity 在 Android 15/16 上会被系统中止，
                // 全屏通知才是能真正把界面顶到前台的那条路。节流避免每 2 秒重复弹。
                val nowMs = System.currentTimeMillis()
                if (nowMs - lastNotifyAt > NOTIFY_INTERVAL_MS) {
                    lastNotifyAt = nowMs
                    KioskNotifier.show(this@LockGuardService, end)
                }
            }
            handler.postDelayed(this, TICK_MS)
        }
    }

    /** 把锁定界面拉回前台；有悬浮窗权限时后台也能启动 Activity。 */
    private fun launchApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // 没有悬浮窗权限时系统会拦下后台启动，只能靠通知兜底。
        }
    }

    private fun startAsForeground(end: Long?) {
        val notification = buildNotification(end)
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

    private fun buildNotification(end: Long?): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val text = if (end == null) {
            "锁定时段生效中"
        } else {
            val fmt = SimpleDateFormat("HH:mm", Locale.getDefault())
            "锁定时段生效中 · ${fmt.format(Date(end))} 解锁"
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("锁定中")
            .setContentText(text)
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
            NotificationChannel(CHANNEL_ID, "锁定守护", NotificationManager.IMPORTANCE_LOW)
                .apply {
                    description = "锁定时段内保持锁定界面在前台"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
        )
    }

    companion object {
        private const val CHANNEL_ID = "lock_guard"
        private const val NOTIFICATION_ID = 7201
        private const val TICK_MS = 2000L
        private const val NOTIFY_INTERVAL_MS = 15_000L

        fun start(context: Context) {
            val intent = Intent(context, LockGuardService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LockGuardService::class.java))
        }
    }
}

/** 应用是否在前台。MainActivity 的 onResume/onPause 维护。 */
object AppForeground {
    @Volatile
    var alive: Boolean = false
}
