#!/usr/bin/env bash
# 一条命令走完：出 release 包 → 装到已连接手机 → 启动 → 清理构建守护进程。
#
# 用法：
#   bash scripts/build_and_install.sh          # 构建 + 安装 + 启动 + 清理
#   bash scripts/build_and_install.sh --build-only   # 只构建（仍会清理）
#
# 之所以把清理放在最后：flutter build 会留下 Gradle / Kotlin 守护进程和 adb server，
# 手动关容易忘，脚本收尾统一关掉。

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
PKG="com.gongkao.gongkao_pad"

ADB="$(command -v adb || true)"
if [ -z "$ADB" ] && [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
fi

BUILD_ONLY=0
[ "${1:-}" = "--build-only" ] && BUILD_ONLY=1

# 设置一个 appops 并回读校验。
#
# 装包后 MIUI 会把部分权限重写成 ignore，而且这个重写可能**晚于**我们的设置动作
# （实测：安装刚结束时 set 10021 allow，回读仍是 ignore，重设一次就稳了）。
# 所以不能"设完就算"，必须回读确认，必要时重试。
ensure_op() {
  local op="$1" by_uid="${2:-0}" i got=""
  for i in 1 2 3; do
    if [ "$by_uid" -eq 1 ]; then
      "$ADB" shell appops set --uid "$PKG" "$op" allow >/dev/null 2>&1
    else
      "$ADB" shell appops set "$PKG" "$op" allow >/dev/null 2>&1
    fi
    sleep 1
    got="$("$ADB" shell appops get "$PKG" "$op" 2>/dev/null | tr -d '\r')"
    case "$got" in
      *allow*) return 0 ;;
    esac
  done
  echo "⚠️  $op 未能设为 allow（当前：${got:-未知}），请手动在系统设置里授权"
  return 1
}

cd "$ROOT" || exit 1

echo "▶ flutter build apk --release"
flutter build apk --release || { echo "❌ 构建失败"; exit 1; }

if [ "$BUILD_ONLY" -eq 0 ] && [ -n "$ADB" ]; then
  if "$ADB" devices | awk 'NR>1 && $2=="device" {found=1} END{exit !found}'; then
    # 装之前先停掉：锁定态（PINNED）下 adb install 会被拒
    # （INSTALL_FAILED_USER_RESTRICTED: Install canceled by user）。
    "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1

    echo "▶ adb install -r"
    "$ADB" install -r "$APK" || echo "⚠️  安装失败（签名不一致时先 adb uninstall $PKG 再装）"

    # 小米 HyperOS 装包会把 MIUI 专属权限重置回 ignore。真正决定「到点能不能
    # 把锁定界面从后台顶到前台」的是 10021（不是名字更像的 10020——2026-10-22
    # 逐项二分实测：只开 10021 时 startActivity 返回 code=2 成功置前）。
    echo "▶ 补 MIUI 自启 / 后台弹出界面 / 全屏通知"
    ensure_op 10008
    ensure_op 10021
    # Android 14+ 只把 USE_FULL_SCREEN_INTENT 自动授予通话/闹钟类应用，其余默认为
    # ignore。它是 10021 之外的第二条通道（屏幕熄灭时由系统直接亮屏展示）。
    ensure_op USE_FULL_SCREEN_INTENT 1
    "$ADB" shell appops get "$PKG" 2>/dev/null \
      | grep -E "10008|10021|USE_FULL_SCREEN_INTENT" || true

    # Doze 白名单：避免深度休眠时把闹钟和服务压掉。
    "$ADB" shell dumpsys deviceidle whitelist +"$PKG" >/dev/null 2>&1 || true

    "$ADB" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1 \
      && echo "▶ 已启动 $PKG"
  else
    echo "⚠️  没有已连接且已授权的安卓设备，跳过安装"
  fi
fi

echo "▶ 清理构建守护进程"
bash "$ROOT/scripts/clean_daemons.sh"
