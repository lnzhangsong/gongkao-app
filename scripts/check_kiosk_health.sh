#!/usr/bin/env bash
# 锁定可靠性体检：一条命令看清「到点 / 开机还能不能自动锁」的每个环节。
#
# 用法：
#   bash scripts/check_kiosk_health.sh
#
# 建议在每次重启、每次装包之后跑一遍。任何一项 ⚠️ 都会让自动锁定失效或失灵。

set -uo pipefail

PKG="com.gongkao.gongkao_pad"

ADB="$(command -v adb || true)"
if [ -z "$ADB" ] && [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
fi
if [ -z "$ADB" ]; then
  echo "❌ 找不到 adb"
  exit 1
fi

if ! "$ADB" devices | awk 'NR>1 && $2=="device" {found=1} END{exit !found}'; then
  echo "❌ 没有已连接且已授权的设备"
  exit 1
fi

BAD=0
ok()   { echo "  ✅ $1"; }
warn() { echo "  ⚠️  $1"; BAD=1; }
info() { echo "  ·  $1"; }

echo "── 设备 ──"
info "$("$ADB" shell getprop ro.product.model | tr -d '\r') / Android $("$ADB" shell getprop ro.build.version.release | tr -d '\r')"
info "已开机 $("$ADB" shell uptime | sed 's/.*up //; s/, *[0-9]* users.*//; s/, *load.*//' | tr -d '\r')"

echo "── 应用 ──"
if "$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx "package:$PKG"; then
  ok "已安装（$("$ADB" shell dumpsys package "$PKG" | grep lastUpdateTime | head -1 | tr -d '\r' | sed 's/.*=//')）"
else
  warn "未安装"
fi

echo "── 小米专属权限（每次装包都可能被重置）──"
OPS="$("$ADB" shell appops get "$PKG" 2>/dev/null | tr -d '\r')"
echo "$OPS" | grep -q "MIUIOP(10008): allow" \
  && ok "10008 自启动 allow（开机广播送得到）" \
  || warn "10008 自启动 不是 allow → 重启后不会自动拉起（adb shell appops set $PKG 10008 allow）"
# 10021 才是「后台弹出界面」。10020 名字看着像，实测改它没用，
# 真正让界面能从后台顶到前台的是 10021（2026-10-22 逐项二分验证）。
echo "$OPS" | grep -q "MIUIOP(10021): allow" \
  && ok "10021 后台弹出界面 allow（到点能把锁定界面顶到前台）" \
  || warn "10021 后台弹出界面 不是 allow → 到点进程起来了但界面出不来（adb shell appops set $PKG 10021 allow）"
echo "$OPS" | grep -A1 "USE_FULL_SCREEN_INTENT" | grep -q "allow" \
  && ok "全屏通知 allow（10021 之外的第二条通道）" \
  || info "全屏通知被拒（有 10021 时不致命，屏幕熄灭时会少一条兜底）"

echo "── 系统权限 ──"
echo "$OPS" | grep -q "^ *SYSTEM_ALERT_WINDOW: allow" \
  && ok "悬浮窗（后台启动 Activity 的豁免条件）" \
  || warn "悬浮窗未授予 → Android 10+ 会拦下后台拉起界面"
"$ADB" shell dumpsys deviceidle whitelist 2>/dev/null | grep -q "$PKG" \
  && ok "已在 Doze 白名单（深度休眠也唤醒）" \
  || warn "不在 Doze 白名单 → 深度休眠时可能被压掉（adb shell dumpsys deviceidle whitelist +$PKG）"

echo "── 下一段闹钟 ──"
ALARM="$("$ADB" shell dumpsys alarm 2>/dev/null | grep -A2 "LockAlarmReceiver" | grep origWhen | head -1 | tr -d '\r')"
if [ -n "$ALARM" ]; then
  ok "已排：$(echo "$ALARM" | sed 's/.*origWhen=//; s/ window.*//')"
  echo "$ALARM" | grep -q "exactAllowReason" \
    && ok "精确闹钟权限已拿到" \
    || info "非精确闹钟（退化成 setAlarmClock，仍会送达）"
else
  warn "系统里没有闹钟 → 到点不会唤醒（打开一次应用即可重排）"
fi

echo "── 当前运行态 ──"
PID="$("$ADB" shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
[ -n "$PID" ] && ok "进程在跑（pid ${PID}）" || info "进程未运行（不影响闹钟到点拉起）"
info "lockTask：$("$ADB" shell dumpsys activity activities 2>/dev/null | grep -m1 mLockTaskModeState | sed 's/.*=//' | tr -d '\r')"

echo
if [ "${1:-}" = "--test" ]; then
  echo "── 端到端自测（约 90 秒，不碰你的时段配置）──"
  info "排一个约 30 秒后的测试闹钟，再把应用切到后台"
  "$ADB" shell am start -n "$PKG/.KioskTestActivity" --ei after 30 --ei minutes 3 >/dev/null 2>&1
  sleep 4
  "$ADB" shell am start -n com.android.settings/.Settings >/dev/null 2>&1
  HIT=0
  for _ in $(seq 1 20); do
    sleep 5
    if "$ADB" shell dumpsys activity activities 2>/dev/null | grep -m1 topResumedActivity | grep -q "$PKG"; then
      HIT=1
      break
    fi
  done
  if [ "$HIT" -eq 1 ]; then
    ok "到点后界面被自动顶回前台（后台启动已放行）"
  else
    warn "到点后界面没能自己回到前台 → 重点看 10021"
  fi
  echo
fi

if [ "$BAD" -eq 0 ]; then
  echo "结论：全链路正常，重启 / 划掉都不影响自动锁定。"
else
  echo "结论：有环节异常（见上面 ⚠️），自动锁定可能失效。"
  exit 2
fi
