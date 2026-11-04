package com.gongkao.gongkao_pad

import android.accessibilityservice.AccessibilityService
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 应用限制的无障碍守护。
 *
 * 两件事：
 * 1. 窗口一露头就 [GLOBAL_ACTION_HOME] 退回桌面——比轮询快一个数量级，
 *    用户看到的是「点了没反应」，而不是「先打开再被顶掉」。
 * 2. 标记了「彻底停止」的应用，替用户去系统设置点一次「强行停止」。
 *    普通应用拿不到 force-stop 的权限（那是系统签名级），但无障碍可以
 *    操作系统自己的界面，等于替人点按钮。效果是真的把包停掉，
 *    连 VPN / 音乐这类常驻服务一起停，且不会自启。
 *
 * 代价是这一步要跳到应用详情页，屏幕上会闪一下设置页（约 1~2 秒），
 * 所以只对勾了「彻底停止」的应用做——只弹回桌面的应用不受影响。
 *
 * 被系统回收或用户手动关闭时不做兜底——[AppWatchService] 的轮询还在跑，
 * 只是慢一点、且退化成「只弹回桌面」。
 */
class AppGuardService : AccessibilityService() {

    /** 上一次执行「回桌面」的时刻，只用来节流动作，不用来决定是否拦截。 */
    private var lastHomeAt = 0L

    /** 上一次弹提示的对象与时刻，避免同一秒里重复 toast。 */
    private var lastToastPkg: String? = null
    private var lastToastAt = 0L

    /** 正在执行「彻底停止」的目标；非 null 时说明流程进行中。 */
    private var stopPkg: String? = null

    /** 整个流程的截止时间，超时就当失败回退。 */
    private var stopDeadline = 0L

    /** 是否已经点过「强行停止」，接下来该找确认框了。 */
    private var clicked = false

    /** 确认框的等待截止时间：有的系统没有二次确认，超时就当成功。 */
    private var confirmDeadline = 0L

    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
        Log.i(TAG, "无障碍守护已连接")
    }

    override fun onDestroy() {
        connected = false
        busy = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> onWindowChanged(event)
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> maybeClickStop()
        }
    }

    override fun onInterrupt() = Unit

    // ── 第一部分：把受限应用顶回桌面 ────────────────────────────────

    private fun onWindowChanged(event: AccessibilityEvent) {
        // 「彻底停止」流程进行中时，屏幕上是设置页，不要再走拦截逻辑，
        // 否则会被自己的界面反复打断。
        if (stopPkg != null) {
            maybeClickStop()
            return
        }
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
        // 改成一概判定，只对「动作」做节流——回桌面重复执行无害，卡顿才要避免。
        markBlocked(now)
        Log.i(TAG, "拦截 $pkg，解除于 ${hit.end}，彻底停止=${hit.deep}")
        if (hit.deep) {
            // 直接跳到应用详情页：让设置页盖住受限应用，比「先回桌面再跳」少闪一次。
            beginDeepStop(pkg, hit.end)
        } else {
            kickHome(pkg, hit.end)
        }
    }

    /** 退回桌面，附带一次节流的提示。 */
    private fun kickHome(pkg: String, end: Long) {
        val now = System.currentTimeMillis()
        if (now - lastHomeAt >= HOME_THROTTLE_MS) {
            lastHomeAt = now
            performGlobalAction(GLOBAL_ACTION_HOME)
            // 顶回桌面后补一刀：普通应用没有 force-stop 权限，
            // killBackgroundProcesses 只能清掉「已不在前台」的进程，
            // 但足以让它停止发声/停止后台工作，重新打开就是冷启动。
            // 延后一点，等它真的退到后台再杀，否则会被系统判定为前台而无效。
            handler.postDelayed({ killBackground(pkg) }, KILL_DELAY_MS)
        }
        if (pkg != lastToastPkg || now - lastToastAt >= TOAST_THROTTLE_MS) {
            lastToastPkg = pkg
            lastToastAt = now
            toast("「${labelOf(pkg)}」在限制时段内，${fmt(end)} 之后可用")
        }
    }

    // ── 第二部分：替用户点「强行停止」 ──────────────────────────────

    private fun beginDeepStop(pkg: String, end: Long) {
        stopPkg = pkg
        busy = true
        clicked = false
        markBlocked(System.currentTimeMillis())
        stopDeadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
        toast("「${labelOf(pkg)}」在限制时段内，${fmt(end)} 之后可用")

        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", pkg, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // 后台起 Activity 被拦时只能退化成「只弹回桌面」。
            Log.w(TAG, "打开应用详情页失败 for $pkg", e)
            finishStop(pkg, success = false)
            return
        }
        handler.postDelayed(retryClick, CLICK_RETRY_MS)
    }

    /** 设置页加载有先后，靠定时重试兜住「事件没来」的情况。 */
    private val retryClick = object : Runnable {
        override fun run() {
            if (stopPkg == null) return
            maybeClickStop()
            if (stopPkg != null) handler.postDelayed(this, CLICK_RETRY_MS)
        }
    }

    private fun maybeClickStop() {
        val pkg = stopPkg ?: return
        val now = System.currentTimeMillis()
        if (now > stopDeadline) {
            Log.w(TAG, "彻底停止 $pkg 超时")
            finishStop(pkg, success = false)
            return
        }
        val root = rootInActiveWindow ?: return

        if (!clicked) {
            val btn = findClickable(root, STOP_TEXTS)
            if (btn != null) {
                Log.i(TAG, "点「强行停止」：$pkg")
                btn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                clicked = true
                confirmDeadline = now + CONFIRM_WAIT_MS
            }
            return
        }

        // 点完之后可能弹确认框，也可能直接生效。
        if (now > confirmDeadline) {
            Log.i(TAG, "没有确认框，视为已停止：$pkg")
            finishStop(pkg, success = true)
            return
        }
        val ok = findClickable(root, CONFIRM_TEXTS)
        if (ok != null) {
            Log.i(TAG, "点确认：$pkg")
            ok.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            finishStop(pkg, success = true)
        }
    }

    private fun finishStop(pkg: String, success: Boolean) {
        stopPkg = null
        busy = false
        handler.removeCallbacks(retryClick)
        if (success) {
            Log.i(TAG, "已彻底停止 $pkg")
        } else {
            Log.w(TAG, "彻底停止失败，回退到清后台：$pkg")
            killBackground(pkg)
        }
        // 停完把设置页关掉，回到桌面，用户看到的就是「点了没反应」。
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /**
     * 在节点树里找文案匹配、且可点的控件。
     *
     * 文本节点本身通常不可点，所以命中文本后往上找可点的祖先（最多 4 层）。
     */
    private fun findClickable(root: AccessibilityNodeInfo, texts: List<String>): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited++ < MAX_NODES) {
            val node = queue.removeFirst()
            val label = node.text?.toString()?.trim().orEmpty()
            if (label.isNotEmpty() && texts.any { label == it }) {
                var cur: AccessibilityNodeInfo? = node
                var depth = 0
                while (cur != null && depth++ < 4) {
                    if (cur.isClickable) return cur
                    cur = cur.parent
                }
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                queue.add(child)
            }
        }
        return null
    }

    // ── 工具 ──────────────────────────────────────────────────────

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

        /** 「回桌面」的动作间隔：连续窗口事件只执行一次，避免闪烁和卡顿。 */
        private const val HOME_THROTTLE_MS = 300L

        /** 同一条提示的最小间隔。 */
        private const val TOAST_THROTTLE_MS = 2000L

        /** 退回桌面后等多久再清后台：要等它真的不在前台，杀了才有效。 */
        private const val KILL_DELAY_MS = 600L

        /** 整个「点强行停止」流程的上限，超过就回退。 */
        private const val STOP_TIMEOUT_MS = 8000L

        /** 点完「强行停止」等确认框的时间；没有确认框就当直接生效。 */
        private const val CONFIRM_WAIT_MS = 2500L

        /** 定时重试间隔：设置页是异步加载的，事件不一定能及时到。 */
        private const val CLICK_RETRY_MS = 400L

        /** 遍历上限，防止异常界面导致卡死。 */
        private const val MAX_NODES = 400

        /** 「强行停止」在不同 ROM 上的文案。 */
        private val STOP_TEXTS = listOf("强行停止", "强制停止", "结束运行")

        /** 二次确认框的按钮文案。 */
        private val CONFIRM_TEXTS = listOf("确定", "确认", "强制停止")

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

        /**
         * 是否正在执行「彻底停止」流程。
         *
         * 流程会在系统设置页停留 1~2 秒，期间前台包名是「设置」，
         * 轮询要是不知情会把这个过程打断，点击就永远点不到。
         */
        @Volatile
        var busy: Boolean = false
            private set

        private fun fmt(epochMs: Long): String =
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))
    }
}
