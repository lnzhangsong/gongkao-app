package com.gongkao.gongkao_pad

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 把「下一段锁定开始」排进系统闹钟。
 *
 * 为什么需要：守护服务只在锁定期内运行，段一结束就 stopSelf 收工（避免常驻通知），
 * 放行（提前解锁）时也会被停掉。之后没有任何东西记得「下一段几点开始」——
 * 只靠 Flutter 的秒级心跳，一旦应用被切到后台、进程被冻结或杀掉，下一段就静默失效。
 *
 * 把唤醒交给系统闹钟后，应用不在也能准时起来：闹钟到点 → [LockAlarmReceiver]
 * → 拉起守护服务与界面 → 界面里再进 lock task。
 *
 * 每次配置变化 / 服务收工 / 开机 / 闹钟触发都会重排一次，形成闭环。
 */
object KioskAlarms {

    private const val REQUEST_CODE = 7311

    /** 排下一段；没有下一段（未开启 / 无时段）则取消。 */
    fun schedule(context: Context) {
        val app = context.applicationContext
        val am = app.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = System.currentTimeMillis()
        val prefs = KioskPrefs(app)
        val at = KioskSchedule.nextStart(prefs, now)
        android.util.Log.i(
            "KioskAlarms",
            "schedule now=${fmt(now)} skipAt=${if (prefs.skipAt > 0) fmt(prefs.skipAt) else "none"} " +
                "skipUntil=${fmt(prefs.skipUntil)} " +
                "periods=${prefs.periods.joinToString("|") { "${it[0]}-${it[1]}" }} " +
                "-> at=${at?.let { fmt(it) }}"
        )
        if (at == null) {
            cancel(app)
            return
        }
        val pi = pending(app)
        try {
            // 用 setAlarmClock 而不是 setExactAndAllowWhileIdle：
            // 1. 语义上这就是个闹钟，系统保证精确送达，Doze / 省电策略都压不掉；
            // 2. 在系统「下次闹钟」里有登记，部分机型会把本应用当闹钟类应用对待。
            //    注意：实测（HyperOS / Android 16）**不会**因此自动授予
            //    USE_FULL_SCREEN_INTENT，那只只能由用户或 appops 显式授予。
            am.setAlarmClock(AlarmManager.AlarmClockInfo(at, pi), pi)
        } catch (e: Exception) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                } else {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                }
            } catch (e2: Exception) {
                // 忽略：仍有应用内心跳兜底。
            }
        }
    }

    /**
     * 排一个**独立于用户配置**的测试闹钟，只给 [KioskTestActivity] 用。
     *
     * 为什么不复用 [schedule]：Dart 侧每秒级同步会立刻把原生配置覆盖回真实值，
     * 测试段活不过 1 秒。这里用另一个 PendingIntent（不同 requestCode）+
     * `test_end` extra，Dart 的 cancel 取消不到它，到点 [LockAlarmReceiver]
     * 直接用 extra 里的结束时刻，走完「拉起服务 + 发全屏通知 + 拉界面」全程。
     */
    fun scheduleTest(context: Context, at: Long, end: Long) {
        val app = context.applicationContext
        val am = app.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(app, LockAlarmReceiver::class.java)
            .putExtra(LockAlarmReceiver.EXTRA_TEST_END, end)
        val pi = PendingIntent.getBroadcast(
            app,
            REQUEST_CODE + 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(at, pi), pi)
        } catch (e: Exception) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
        android.util.Log.i("KioskAlarms", "scheduleTest at=${fmt(at)} end=${fmt(end)}")
    }

    /** 撤掉测试闹钟（触发一次后就没用了）。 */
    fun cancelTest(context: Context) {
        val app = context.applicationContext
        val am = app.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        try {
            am.cancel(
                PendingIntent.getBroadcast(
                    app,
                    REQUEST_CODE + 1,
                    Intent(app, LockAlarmReceiver::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        } catch (e: Exception) {
            // 忽略
        }
    }

    fun cancel(context: Context) {        val am = context.applicationContext
            .getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        try {
            am.cancel(pending(context.applicationContext))
        } catch (e: Exception) {
            // 忽略
        }
    }

    private fun fmt(ms: Long): String =
        java.text.SimpleDateFormat("MM-dd HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date(ms))

    private fun pending(context: Context): PendingIntent {
        val intent = Intent(context, LockAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
