package com.gongkao.gongkao_pad

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 受限应用的拦截页。
 *
 * 由 [AppWatchService] 在检测到受限应用被切到前台时拉起，把目标应用顶到后台。
 * 界面刻意做得极简：只有「什么应用、为什么、什么时候能再用、回桌面」，
 * 不留任何可以绕过去的入口。
 *
 * 用原生 Activity 而不是 Flutter 页面：此时 Flutter 引擎可能压根没起来，
 * 等引擎冷启动要好几秒，期间人已经在用受限应用了。
 */
class AppBlockActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())
    private var endAt = 0L
    private var titleView: TextView? = null
    private var countdownView: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyIntent(intent)
        setContentView(buildUi())

        // 从后台被拉起时屏幕可能刚亮，兜一下：让界面盖在锁屏之上。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        handler.post(ticker)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        // 连续拦截不同应用时复用同一个实例，只换文案与截止时刻。
        if (intent != null) {
            setIntent(intent)
            applyIntent(intent)
            titleView?.text = buildTitle()
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    /** 返回键一律回桌面：留在原地只会让用户反复试。 */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHome()
    }

    private fun applyIntent(intent: Intent?) {
        endAt = intent?.getLongExtra(EXTRA_END, 0L) ?: 0L
    }

    private val ticker = object : Runnable {
        override fun run() {
            val left = endAt - System.currentTimeMillis()
            if (left <= 0L) {
                // 时段已过：自动放行，不必让用户再点一次。
                finish()
                return
            }
            countdownView?.text = fmtLeft(left)
            handler.postDelayed(this, 1000L)
        }
    }

    private fun buildTitle(): String {
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "该应用"
        return "「$label」现在不能用"
    }

    private fun buildUi(): ViewGroup {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0E1116"))
            setPadding(dp(28), dp(40), dp(28), dp(40))
        }

        val lock = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_lock_lock)
            setColorFilter(Color.parseColor("#3B82F6"))
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
        }
        root.addView(lock)

        titleView = TextView(this).apply {
            text = buildTitle()
            setTextColor(Color.WHITE)
            textSize = 20f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(22), 0, 0)
        }
        root.addView(titleView)

        root.addView(TextView(this).apply {
            text = if (endAt > 0L) {
                "${fmtTime(endAt)} 之后可以继续使用"
            } else {
                "当前处于限制时段"
            }
            setTextColor(Color.parseColor("#99FFFFFF"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        })

        countdownView = TextView(this).apply {
            text = fmtLeft((endAt - System.currentTimeMillis()).coerceAtLeast(0L))
            setTextColor(Color.parseColor("#3B82F6"))
            textSize = 34f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(26), 0, 0)
            // 等宽数字，倒计时跳动时不会左右抖。
            fontFeatureSettings = "tnum"
        }
        root.addView(countdownView)

        root.addView(TextView(this).apply {
            text = "这个时段是你在「锁定设置 → 应用限制」里定的。"
            setTextColor(Color.parseColor("#4DFFFFFF"))
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(0, dp(28), 0, 0)
        })

        root.addView(pillButton("回到桌面") { goHome() }.apply {
            (layoutParams as LinearLayout.LayoutParams).topMargin = dp(36)
        })

        return root
    }

    private fun pillButton(text: String, onClick: () -> Unit): TextView {
        val params = LinearLayout.LayoutParams(dp(200), dp(48))
        return TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(Color.parseColor("#3B82F6"))
            }
            isClickable = true
            isFocusable = true
            layoutParams = params
            setOnClickListener { onClick() }
        }
    }

    private fun goHome() {
        val home = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(home)
        } catch (e: Exception) {
            // 找不到桌面（极少见）时至少要退出本页，别把人困在拦截页里。
        }
        finish()
    }

    private fun dp(v: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics
    ).toInt()

    companion object {
        const val EXTRA_PACKAGE = "extra_package"
        const val EXTRA_LABEL = "extra_label"
        const val EXTRA_END = "extra_end"

        private fun fmtTime(epochMs: Long): String =
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))

        /** 剩余时长：不到 1 分钟给秒，不到 1 小时给分秒，再长给时分。 */
        private fun fmtLeft(ms: Long): String {
            val total = ms / 1000L
            val h = total / 3600L
            val m = total % 3600L / 60L
            val s = total % 60L
            return when {
                h > 0L -> "${h} 小时 ${m} 分"
                m > 0L -> "${m} 分 ${s} 秒"
                else -> "${s} 秒"
            }
        }
    }
}
