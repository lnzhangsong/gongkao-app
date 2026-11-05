package com.gongkao.gongkao_pad

import android.accessibilityservice.AccessibilityService
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 应用限制的无障碍守护——**降级兜底**。
 *
 * 只做一件事：受限应用的窗口一露头就 [GLOBAL_ACTION_HOME] 退回桌面，
 * 比轮询快一个数量级，用户看到的是「点了没反应」，而不是「先打开再被顶掉」。
 *
 * 主线不是它：有 Shizuku（shell 身份）时，[AppWatchService] 会直接
 * `pm disable-user` 把应用禁掉——图标从桌面消失、点图标系统直接拒启，
 * 根本轮不到这里。只有 Shizuku 没启动 / 没授权时，才靠这层兜住。
 *
 * 早期版本这里还替用户跳系统应用详情页点「强行停止」，那是没有 shell 身份时
 * 唯一能停掉常驻服务的办法，代价是每次闪一下设置页。走 ADB 真正禁用之后
 * 它既没必要也不可靠，已整体移除。
 *
 * 被系统回收或用户手动关闭时不做兜底——[AppWatchService] 的轮询还在跑，
 * 只是慢一点。
 */
class AppGuardService : AccessibilityService() {

    /** 上一次弹提示的对象与时刻，避免同一秒里重复 toast。 */
    private var lastToastPkg: String? = null
    private var lastToastAt = 0L

    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
        Log.i(TAG, "无障碍守护已连接")
    }

    override fun onDestroy() {
        connected = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        onWindowChanged(event)
    }

    override fun onInterrupt() = Unit

    private fun onWindowChanged(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return
        // 系统弹层（权限对话框、状态栏）不是用户主动打开的应用。
        if (pkg == "android" || pkg == "com.android.systemui") return

        val limits = AppLimitPrefs(this)
        if (!limits.hasRules()) return
        val now = System.currentTimeMillis()
        val hit = AppLimitSchedule.hit(limits, KioskPrefs(this), pkg, now) ?: return

        // 不按「包名 + 时间窗」跳过判定：那样用户隔一两秒再点一次就会整段放行，
        // 而应用一旦真的站稳前台，就不会再有窗口事件把它踢出来了。
        // 也不对「回桌面」节流：用户连点时窗口事件可能只隔几十毫秒，
        // 一旦被节流吞掉就等于这一下没拦。
        markBlocked(now)
        Log.i(TAG, "拦截 $pkg，解除于 ${hit.end}")
        kickHome(pkg, hit.end)
    }

    /**
     * 退回桌面并提示。
     *
     * 先 HOME 才能保证「应用确实被打不开」；提示晚一步弹，避免被 HOME 顶掉。
     */
    private fun kickHome(pkg: String, end: Long) {
        val now = System.currentTimeMillis()
        performGlobalAction(GLOBAL_ACTION_HOME)
        // 顶回桌面后补一刀：普通应用没有 force-stop 权限，
        // killBackgroundProcesses 只能清掉「已不在前台」的进程，
        // 但足以让它停止发声/停止后台工作，重新打开就是冷启动。
        // 延后一点，等它真的退到后台再杀，否则会被系统判定为前台而无效。
        handler.postDelayed({ killBackground(pkg) }, KILL_DELAY_MS)

        if (pkg != lastToastPkg || now - lastToastAt >= TOAST_THROTTLE_MS) {
            lastToastPkg = pkg
            lastToastAt = now
            toast("「${labelOf(pkg)}」在限制时段内，${fmt(end)} 之后可用")
        }
    }

    private fun killBackground(pkg: String) {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.killBackgroundProcesses(pkg)
        } catch (e: Exception) {
            Log.w(TAG, "killBackgroundProcesses failed for $pkg", e)
        }
    }

    private fun toast(msg: String) {
        try {
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.w(TAG, "toast failed", e)
        }
    }

    private fun labelOf(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    companion object {
        private const val TAG = "AppGuard"

        /** 同一条提示的最小间隔。 */
        private const val TOAST_THROTTLE_MS = 2000L

        /** 退回桌面后等多久再清后台：要等它真的不在前台，杀了才有效。 */
        private const val KILL_DELAY_MS = 600L

        /** 无障碍守护是否在运行；轮询服务据此调整兜底策略。 */
        @Volatile
        var connected: Boolean = false
            private set

        /**
         * 最近一次拦截的时刻。
         *
         * [AppWatchService] 用它判断「无障碍刚刚处理过」，只是短暂让位；
         * 超过宽限期仍然由轮询兜底，避免无障碍漏一次事件就被彻底放行。
         */
        @Volatile
        var lastBlockAt: Long = 0L
            private set

        /** 记录一次拦截，供轮询服务判断是否需要兜底。 */
        fun markBlocked(at: Long) {
            lastBlockAt = at
        }

        private fun fmt(epochMs: Long): String =
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))
    }
}
