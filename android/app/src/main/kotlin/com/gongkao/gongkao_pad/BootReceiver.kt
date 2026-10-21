package com.gongkao.gongkao_pad

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * 开机广播：解决「重启一次就把锁定绕过去」的问题。
 *
 * - 处于锁定时段：无条件拉起锁定界面并启动守护服务（重启不能成为逃生门）；
 * - 不在锁定时段：按「开机自启」开关决定是否拉起应用。
 *
 * Android 10+ 限制后台启动 Activity，已授予「显示在其他应用上层」的应用属于豁免，
 * 因此这里优先依赖该权限；未授权时会退化成提示通知，由界面引导授权。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val boot = action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        if (!boot && action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        val prefs = KioskPrefs(context)
        if (!prefs.enabled && !prefs.autoStart) return

        // 重启会清空所有闹钟，先按最新配置把「下一段」重新排上。
        KioskAlarms.schedule(context)

        val end = if (prefs.enabled) {
            KioskSchedule.lockedEnd(prefs, System.currentTimeMillis())
        } else {
            null
        }
        if (end != null) {
            // 锁定期：拉服务 + 全屏通知 + 拉界面，哪个先成功都能兜住。
            // 开机时同样受后台启动 Activity 限制，全屏通知是可靠的那条路。
            safeStartService(context)
            KioskNotifier.show(context, end)
            launch(context)
        } else if (prefs.autoStart) {
            launch(context)
        }
    }

    private fun safeStartService(context: Context) {
        try {
            LockGuardService.start(context)
        } catch (e: Exception) {
            // 后台启动前台服务受限时忽略，界面起来后 Dart 会再启动一次。
        }
    }

    private fun launch(context: Context) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_FROM_BOOT, true)
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            // 未授予悬浮窗权限时系统会拦下后台启动。
        }
        if (!Settings.canDrawOverlays(context)) {
            // 只提示，不弹窗打扰：真正的引导在应用内的「锁定强度」里。
            LockGuardService.start(context)
        }
    }

    companion object {
        const val EXTRA_FROM_BOOT = "from_boot"
    }
}
