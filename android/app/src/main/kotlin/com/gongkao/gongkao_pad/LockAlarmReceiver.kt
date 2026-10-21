package com.gongkao.gongkao_pad

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 闹钟到点：该锁就锁，然后把下一段重新排上。
 *
 * 由 [KioskAlarms] 排程，系统在指定时刻唤醒应用进程并投递本广播——
 * 即使应用早被划掉、手机在深度休眠也一样。
 */
class LockAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val prefs = KioskPrefs(context)
        val now = System.currentTimeMillis()

        // 诊断入口排的测试闹钟：直接按 extra 里的结束时刻走完整条链路，
        // 不读用户配置（Dart 会不断把原生配置覆盖回真实值）。
        val testEnd = intent.getLongExtra(EXTRA_TEST_END, 0L)
        if (testEnd > 0L) {
            KioskAlarms.cancelTest(context)
            android.util.Log.i("LockAlarm", "test fire end=$testEnd -> dispatch")
            dispatch(context, testEnd)
            return
        }

        // 到点那一刻是否真该锁：可能这段刚被「提前解锁」放行了，或时段已被改掉。
        val end = KioskSchedule.lockedEnd(prefs, now)
        android.util.Log.i(
            "LockAlarm",
            "fire now=${now} enabled=${prefs.enabled} " +
                "periods=${prefs.periods.joinToString("|") { "${it[0]}-${it[1]}" }} " +
                "skipAt=${prefs.skipAt} skipUntil=${prefs.skipUntil} -> end=${end}"
        )
        if (end != null) dispatch(context, end)

        // 无论这段起没起，都把再下一段排上：放行 / 改配置都会让本次落空。
        KioskAlarms.schedule(context)
    }

    /** 到点执行：起守护服务 + 发全屏通知 + 尝试直接拉起界面。 */
    private fun dispatch(context: Context, end: Long) {
        try {
            LockGuardService.start(context)
        } catch (e: Exception) {
            // 后台启动前台服务受限时忽略，界面起来后 Dart 会再启动一次。
        }
        // 主通道：全屏通知。Android 15/16 已禁止从广播后台 startActivity
        // （实测 Abort background activity starts / result code=102），
        // fullScreenIntent 是系统给闹钟类应用留的正规入口。
        KioskNotifier.show(context, end)
        // 旧通道：部分机型（含部分 MIUI 版本）仍放行，两条一起走。
        launch(context)
    }

    private fun launch(context: Context) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(BootReceiver.EXTRA_FROM_BOOT, true)
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            // 没有悬浮窗权限时系统会拦下后台启动，靠守护服务与通知兜底。
        }
    }

    companion object {
        /** 诊断用：带着它来的闹钟按这个时刻当作「解锁时间」，不读用户配置。 */
        const val EXTRA_TEST_END = "test_end"
    }
}
