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

    /** 上一次弹提示的对象与时刻，避免同一秒里重复 toast。 */
    private var lastToastPkg: String? = null
    private var lastToastAt = 0L

    /** 「彻底停止」的进度存储，重启后仍然有效（按限制段区分）。 */
    private val deepPrefs by lazy {
        getSharedPreferences("app_guard", Context.MODE_PRIVATE)
    }

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
        // 也不对「回桌面」节流：用户连点时窗口事件可能只隔几十毫秒，
        // 一旦被节流吞掉就等于这一下没拦。
        markBlocked(now)
        Log.i(TAG, "拦截 $pkg，解除于 ${hit.end}，彻底停止=${hit.deep}")
        if (hit.deep && !deepDoneFor(pkg, hit.end)) {
            // 同一个限制段只来这一次。
            //
            // 「彻底停止」要借系统应用信息页点按钮，屏幕必然闪一下；每点一次
            // 都跳一次会很脏。而停过一次之后包已经是 stopped 状态，用户再点
            // 只是冷启动，立刻弹回桌面就够，没有理由再把他拽到设置页。
            markDeepStart(pkg, hit.end)
            beginDeepStop(pkg, hit.end)
        } else {
            kickHome(pkg, hit.end)
        }
    }

    /** 退回桌面。不节流：用户点多快都得被踢回来，重复执行 HOME 本身无害。 */
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

    // ── 第二部分：替用户点「强行停止」 ──────────────────────────────

    /**
     * 本限制段是否已经处理过「彻底停止」。
     *
     * 用「包名 + 解除时刻」标识这一段：同一段的 end 是固定的，
     * 下一段（或明天同一段）会算出不同的 end，自然重新允许停一次。
     * 成功过、或者已经试满次数，都算处理过。
     */
    private fun deepDoneFor(pkg: String, end: Long): Boolean {
        if (deepPrefs.getString(K_DEEP_PKG, null) != pkg) return false
        if (deepPrefs.getLong(K_DEEP_END, 0L) != end) return false
        if (deepPrefs.getBoolean(K_DEEP_OK, false)) return true
        return deepPrefs.getInt(K_DEEP_ATTEMPTS, 0) >= MAX_DEEP_ATTEMPTS
    }

    /** 记一次尝试，顺带复位上一段的状态。 */
    private fun markDeepStart(pkg: String, end: Long) {
        val same = deepPrefs.getString(K_DEEP_PKG, null) == pkg &&
            deepPrefs.getLong(K_DEEP_END, 0L) == end
        val attempts = if (same) deepPrefs.getInt(K_DEEP_ATTEMPTS, 0) + 1 else 1
        deepPrefs.edit()
            .putString(K_DEEP_PKG, pkg)
            .putLong(K_DEEP_END, end)
            .putBoolean(K_DEEP_OK, false)
            .putInt(K_DEEP_ATTEMPTS, attempts)
            .apply()
    }

    private fun markDeepOk() {
        deepPrefs.edit().putBoolean(K_DEEP_OK, true).apply()
    }

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
            markDeepOk()
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

        /** 同一条提示的最小间隔。 */
        private const val TOAST_THROTTLE_MS = 2000L

        /** 退回桌面后等多久再清后台：要等它真的不在前台，杀了才有效。 */
        private const val KILL_DELAY_MS = 600L

        /** 同一限制段里最多尝试几次「彻底停止」：失败就退化成只弹回桌面。 */
        private const val MAX_DEEP_ATTEMPTS = 2

        private const val K_DEEP_PKG = "deep_pkg"
        private const val K_DEEP_END = "deep_end"
        private const val K_DEEP_OK = "deep_ok"
        private const val K_DEEP_ATTEMPTS = "deep_attempts"

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
