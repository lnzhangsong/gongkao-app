package com.gongkao.gongkao_pad

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import java.util.Calendar

/**
 * 现场诊断入口，只给 adb 用（activity 受 `android.permission.DUMP` 保护，
 * 普通应用调不起来）。
 *
 *   adb shell am start -n com.gongkao.gongkao_pad/.KioskTestActivity \
 *       --ei after 20 --ei minutes 3
 *
 * 作用：排一个**独立于用户配置**的闹钟，约 after 秒后触发一次完整的
 * 「起守护服务 → 发全屏通知 → 拉起锁定界面」，然后退出。
 *
 * 为什么不改配置再等：Dart 侧每秒级同步会立刻把原生配置覆盖回真实值，
 * 测试段活不过 1 秒（实测 0.07 秒就被盖掉）。所以走 [KioskAlarms.scheduleTest]
 * 的独立 PendingIntent，Dart 的 cancel 取消不到它，也不影响用户已设的时段。
 */
class KioskTestActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val after = intent.getIntExtra("after", 20)
        val minutes = intent.getIntExtra("minutes", 3)

        // 分钟粒度：向上取整到下一分钟，保证触发时刻确实在未来。
        val cal = Calendar.getInstance().apply {
            timeInMillis = System.currentTimeMillis() + after * 1000L
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.MINUTE, 1)
        }
        val at = cal.timeInMillis
        val end = at + minutes.coerceAtLeast(1) * 60_000L

        KioskAlarms.scheduleTest(this, at, end)
        Log.i("KioskTest", "test alarm at=$at end=$end (after=${after}s minutes=$minutes)")
        Toast.makeText(this, "测试：约 $after 秒后触发一次锁定", Toast.LENGTH_SHORT).show()
        finish()
    }
}
