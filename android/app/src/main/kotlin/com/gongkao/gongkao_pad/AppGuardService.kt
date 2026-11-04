package com.gongkao.gongkao_pad

import android.accessibilityservice.AccessibilityService
import android.content.pm.PackageManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 应用限制的无障碍守护。
 *
 * 轮询只能做到秒级：受限应用会先完整显示出来、再被顶走，观感是「打开了又被关掉」。
 * 这里订阅 TYPE_WINDOW_STATE_CHANGED——窗口刚切过去就能收到事件，
 * 立刻 [GLOBAL_ACTION_HOME] 退回桌面，用户看到的是「点了没反应」，
 * 而不是「先打开一个遮罩再关掉」。
 *
 * 配置只订阅窗口切换、且 canRetrieveWindowContent=false，不读取屏幕内容。
 *
 * 被系统回收或用户手动关闭时不做任何兜底——[AppWatchService] 的轮询还在跑，
 * 只是慢一点，功能不会彻底失效。
 */
class AppGuardService : AccessibilityService() {

    /** 上一次踢的是谁、什么时候踢的，抑制应用反复重建窗口导致的连踢。 */
    private var lastPkg: String? = null
    private var lastAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "无障碍守护已连接")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return

        val limits = AppLimitPrefs(this)
        if (!limits.hasRules()) return
        val now = System.currentTimeMillis()
        val end = AppLimitSchedule.limitEnd(limits, KioskPrefs(this), pkg, now) ?: return

        if (pkg == lastPkg && now - lastAt < REPEAT_GUARD_MS) return
        lastPkg = pkg
        lastAt = now

        Log.i(TAG, "拦截 $pkg，解除于 $end")
        performGlobalAction(GLOBAL_ACTION_HOME)
        toast("「${labelOf(pkg)}」在限制时段内，${fmt(end)} 之后可用")
    }

    override fun onInterrupt() = Unit

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
        private const val REPEAT_GUARD_MS = 2000L

        private fun fmt(epochMs: Long): String =
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))
    }
}
