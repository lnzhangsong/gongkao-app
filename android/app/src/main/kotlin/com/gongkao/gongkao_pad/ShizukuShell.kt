package com.gongkao.gongkao_pad

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku

/**
 * Shizuku 通道：借 shell 权限真正 force-stop 受限应用。
 *
 * 普通应用能做的只有 [android.app.ActivityManager.killBackgroundProcesses]——它只杀
 * 「后台」进程，有前台服务（VpnService、音乐播放、下载）的应用杀不掉，
 * 而且杀完系统还会把它拉起来。force-stop 会把包标记成 stopped，
 * 所有进程连同常驻服务一起停掉，也不会自启，直到用户下次手动打开。
 *
 * Shizuku 未安装 / 未运行 / 未授权时，调用方一律回退到 killBackgroundProcesses。
 */
object ShizukuShell {

    private const val TAG = "ShizukuShell"

    /** 权限请求码，和 MainActivity 里保持一致。 */
    const val PERMISSION_REQUEST_CODE = 7821

    private const val SHIZUKU_PKG = "moe.shizuku.privileged.api"

    fun isInstalled(context: Context): Boolean = try {
        context.packageManager.getPackageInfo(SHIZUKU_PKG, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /** Shizuku 服务是否正在运行（进程活着、binder 可 ping）。 */
    fun isRunning(): Boolean = try {
        Shizuku.pingBinder()
    } catch (t: Throwable) {
        false
    }

    fun isGranted(): Boolean = try {
        isRunning() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (t: Throwable) {
        false
    }

    /** 给 Dart 侧看的状态：not_installed / not_running / denied / ready。 */
    fun status(context: Context): String = when {
        !isInstalled(context) -> "not_installed"
        !isRunning() -> "not_running"
        isGranted() -> "ready"
        else -> "denied"
    }

    /** 请求授权；必须在有 Activity 时调用，结果走 Shizuku 的监听回调。 */
    fun requestPermission() {
        try {
            if (isRunning() && !isGranted()) {
                Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "requestPermission 失败", t)
        }
    }

    /** 真正停掉应用；成功返回 true，失败/无权限返回 false。 */
    fun forceStop(pkg: String): Boolean {
        if (!isGranted()) return false
        return try {
            val process = Shizuku.newProcess(arrayOf("am", "force-stop", pkg), null, null)
            process.waitFor()
            val code = process.exitValue()
            if (code == 0) {
                Log.i(TAG, "已 force-stop $pkg")
                true
            } else {
                Log.w(TAG, "force-stop $pkg 退出码 $code")
                false
            }
        } catch (t: Throwable) {
            Log.w(TAG, "force-stop $pkg 失败", t)
            false
        }
    }
}
