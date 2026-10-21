package com.gongkao.gongkao_pad

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

/**
 * 设备管理员组件。
 *
 * 只有在用户主动执行 `adb shell dpm set-device-owner ...` 之后才会生效，
 * 用于「严格模式」：由设备所有者身份开启 lock task，锁定期间无法退出、无法下拉通知栏。
 * 不开严格模式时本组件完全闲置。
 */
class KioskAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        Toast.makeText(context, "本应用已成为设备管理者（严格模式）", Toast.LENGTH_LONG).show()
    }
}
