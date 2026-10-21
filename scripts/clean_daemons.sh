#!/usr/bin/env bash
# 构建后清理：停掉 Gradle / Kotlin 守护进程与 adb server，避免它们常驻吃内存。
#
# 用法：bash scripts/clean_daemons.sh
# 时机：flutter build / flutter install / flutter run 结束之后跑一次。
#
# 只停「构建工具自己拉起来的后台常驻进程」，不碰 Android Studio、IDE 里的其它 Java 进程。

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── 1. 找 JDK：环境变量 → Android Studio 自带 → 系统 java_home ────────────────
JAVA_HOME="${JAVA_HOME:-}"
if [ ! -x "${JAVA_HOME}/bin/java" ]; then
  JAVA_HOME=""
  for candidate in \
    "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$(/usr/libexec/java_home 2>/dev/null || true)"; do
    if [ -x "$candidate/bin/java" ]; then
      JAVA_HOME="$candidate"
      break
    fi
  done
fi

# ── 2. Java 侧守护进程 ────────────────────────────────────────────────────
GRADLE_STOPPED=0
KOTLIN_STOPPED=0

if [ -n "$JAVA_HOME" ]; then
  # Gradle 自己认得 --stop，会优雅退出（先试 gradlew，再试全局 gradle）。
  if [ -x "$ROOT/android/gradlew" ]; then
    OUTPUT="$(cd "$ROOT/android" && JAVA_HOME="$JAVA_HOME" ./gradlew --stop 2>&1)"
    GRADLE_STOPPED="$(printf '%s' "$OUTPUT" | sed -n 's/^\([0-9]\+\) Daemon stopped/\1/p')"
    [ -z "$GRADLE_STOPPED" ] && GRADLE_STOPPED=0
  fi

  # 兜底：--stop 没清掉的 GradleDaemon，以及 gradlew 管不到的 Kotlin 编译守护进程。
  for name in GradleDaemon KotlinCompileDaemon; do
    for pid in $("$JAVA_HOME/bin/jps" -l 2>/dev/null | awk -v pat="$name" '$0 ~ pat {print $1}'); do
      if kill "$pid" 2>/dev/null; then
        [ "$name" = "KotlinCompileDaemon" ] && KOTLIN_STOPPED=$((KOTLIN_STOPPED + 1))
        [ "$name" = "GradleDaemon" ] && GRADLE_STOPPED=$((GRADLE_STOPPED + 1))
      fi
    done
  done
else
  echo "⚠️  没找到 JDK，跳过 Gradle / Kotlin 守护进程清理。" >&2
fi

# ── 3. adb server（端口 5037 的常驻桥接进程）───────────────────────────────
ADB="$(command -v adb || true)"
[ -z "$ADB" ] && [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ] \
  && ADB="$HOME/Library/Android/sdk/platform-tools/adb"
ADB_STOPPED=0
if [ -n "$ADB" ]; then
  "$ADB" kill-server >/dev/null 2>&1 && ADB_STOPPED=1
fi

# ── 4. 结果 ──────────────────────────────────────────────────────────────
left_java=0
if [ -n "$JAVA_HOME" ]; then
  left_java="$("$JAVA_HOME/bin/jps" -l 2>/dev/null \
    | grep -cE 'GradleDaemon|KotlinCompileDaemon' || true)"
fi
left_adb="$(pgrep -f 'adb -L tcp:' 2>/dev/null | wc -l | tr -d ' ')"

echo "已停止 —— Gradle: ${GRADLE_STOPPED:-0} · Kotlin: ${KOTLIN_STOPPED} · adb: ${ADB_STOPPED}"
echo "残留 —— Java 守护进程: ${left_java} · adb server: ${left_adb:-0}"
if [ "${left_java:-0}" -gt 0 ] || [ "${left_adb:-0}" -gt 0 ]; then
  echo "仍有残留，可再跑一次本脚本。"
  exit 1
fi
