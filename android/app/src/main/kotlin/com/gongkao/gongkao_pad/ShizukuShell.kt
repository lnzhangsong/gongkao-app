package com.gongkao.gongkao_pad

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku

/**
 * 借 Shizuku 的 shell 身份执行命令。
 *
 * Shizuku 本身不提供任何特权，它做的是：引导用户用一次 ADB 配对，把
 * 一个以 shell 身份运行的守护进程拉起来，再把 binder 交给普通应用。
 * 有了这个身份，才能执行 `pm disable-user` —— 那是「到点真正禁用应用」
 * 唯一的口子，普通应用连改别人组件的 enabled 状态都没有权限。
 *
 * 重启后 ADB 连接必然断开，Shizuku 需要重新激活一次。这是系统设计，
 * 非 root 无法绕过；没激活时各调用点会自动降级（退化为只弹回桌面）。
 */
object ShizukuShell {

    private const val TAG = "ShizukuShell"

    /** 权限申请的 requestCode，与 MainActivity 保持一致。 */
    const val PERM_REQUEST = 4210

    /** Shizuku 应用包名。 */
    private const val PKG = "moe.shizuku.privileged.api"

    fun installed(context: Context): Boolean = try {
        context.packageManager.getPackageInfo(PKG, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * `not_installed` 没装 / `not_running` 装了但守护进程没起来 /
     * `denied` 起来了但没授权 / `ready` 可用。
     */
    fun status(context: Context): String {
        if (!installed(context)) return "not_installed"
        return try {
            if (!Shizuku.pingBinder()) return "not_running"
            val granted = Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            if (granted) "ready" else "denied"
        } catch (e: Throwable) {
            Log.w(TAG, "status failed", e)
            "not_running"
        }
    }

    /** 直接申请授权；用户点了弹窗后要稍等再查状态。 */
    fun requestPermission() {
        try {
            Shizuku.requestPermission(PERM_REQUEST)
        } catch (e: Throwable) {
            Log.w(TAG, "requestPermission failed", e)
        }
    }

    /** 执行一条 shell 命令，返回 (退出码, 输出)。 */
    fun exec(vararg cmd: String): Pair<Int, String> {
        return try {
            val p = Shizuku.newProcess(cmd, null, null)
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            val code = p.waitFor()
            code to (out + err).trim()
        } catch (e: Throwable) {
            Log.w(TAG, "exec failed: ${cmd.joinToString(" ")}", e)
            -1 to (e.message ?: "")
        }
    }

    /**
     * 启用 / 禁用应用。
     *
     * 禁用用 `disable-user`：把它从桌面上摘掉、点图标系统直接拒启，
     * 效果等于卸载但可逆，重启也保持。`pm disable` 不行——那个要求
     * 调用者是系统签名，shell 用 disable-user 才合法。
     */
    fun setEnabled(pkg: String, enabled: Boolean): Boolean {
        val cmd = if (enabled) "pm enable $pkg" else "pm disable-user --user 0 $pkg"
        val (code, out) = exec("sh", "-c", cmd)
        val ok = code == 0 && !out.contains("Error", ignoreCase = true) &&
            !out.contains("Exception", ignoreCase = true)
        Log.i(TAG, "$cmd → ok=$ok code=$code out=$out")
        return ok
    }

    /** 当前被禁用的包名列表；拿不到时返回 null。 */
    fun disabledPackages(): Set<String>? {
        val (code, out) = exec("sh", "-c", "pm list packages -d")
        if (code != 0) return null
        return out.lineSequence()
            .map { it.trim() }
            .filter { it.startsWith("package:") }
            .map { it.removePrefix("package:") }
            .toSet()
    }
}
