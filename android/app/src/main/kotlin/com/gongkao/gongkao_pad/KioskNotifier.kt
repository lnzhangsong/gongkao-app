package com.gongkao.gongkao_pad

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 锁定到点时把界面「顶」到前台。
 *
 * 为什么不再依赖 startActivity：Android 15/16 收紧了后台启动 Activity，
 * 从广播 / 服务里 startActivity 会被系统直接中止（2026-10-22 真机实测）：
 *
 *   I ActivityManager: Start proc ... for broadcast {LockAlarmReceiver}      闹钟送达、进程拉起
 *   I ActivityManager: Background started FGS: Allowed ... SYSTEM_ALLOW_LISTED  前台服务启动
 *   E ActivityTaskManager: Abort background activity starts from 10439       界面被拦
 *   I ActivityTaskManager: START u0 {...MainActivity} (BAL_ALLOW_SAW_PERMISSION) result code=102
 *
 * 注意最后一行：系统承认「有悬浮窗权限」这个豁免（BAL_ALLOW_SAW_PERMISSION），
 * 但仍然中止了启动——targetSdk 35+ 上这条路已经不通。
 *
 * fullScreenIntent + CATEGORY_ALARM 是系统留给闹钟 / 来电类应用的正规通道：
 * 高优先级通知投递时，系统会点亮屏幕并直接展示对应 Activity，不受后台启动限制。
 */
object KioskNotifier {

    private const val CHANNEL_ID = "lock_alarm"
    private const val NOTIFICATION_ID = 7301

    /** 发出「锁定开始」全屏通知。界面已在栈里时由系统直接切到前台。 */
    fun show(context: Context, end: Long?) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return
        ensureChannel(nm)
        try {
            nm.notify(NOTIFICATION_ID, build(context, end))
            android.util.Log.i(
                "KioskNotifier",
                "show end=$end fullScreenAllowed=${canUseFullScreen(context)}"
            )
        } catch (e: Exception) {
            android.util.Log.w("KioskNotifier", "notify failed: $e")
        }
    }

    /** 界面已经到前台，撤掉这条兜底通知。 */
    fun cancel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return
        try {
            nm.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            // 忽略
        }
    }

    /** Android 14+ 用户可以单独关掉「全屏通知」，关掉后只剩普通横幅。 */
    fun canUseFullScreen(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return false
        return try {
            nm.canUseFullScreenIntent()
        } catch (e: Exception) {
            false
        }
    }

    /** 跳到系统的「全屏通知」开关页（Android 14+）。 */
    fun openFullScreenSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        try {
            context.startActivity(
                Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(android.net.Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            // 个别 ROM 没有这个页面，忽略。
        }
    }

    private fun build(context: Context, end: Long?): Notification {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(BootReceiver.EXTRA_FROM_BOOT, true)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val text = if (end == null) {
            "锁定时段生效中"
        } else {
            val fmt = SimpleDateFormat("HH:mm", Locale.getDefault())
            "锁定开始 · ${fmt.format(Date(end))} 解锁"
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        return builder
            .setContentTitle("锁定开始")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            // 关键：由系统在后台把界面直接展示出来。
            .setFullScreenIntent(open, true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(false)
            .build()
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "锁定开始提醒", NotificationManager.IMPORTANCE_HIGH)
                .apply {
                    description = "锁定时段开始时点亮屏幕并展示锁定界面"
                    setShowBadge(false)
                    enableVibration(false)
                    // 静音：不半夜吓人，但不影响全屏展示（重要性仍是 HIGH）。
                    setSound(null, null)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
        )
    }
}
