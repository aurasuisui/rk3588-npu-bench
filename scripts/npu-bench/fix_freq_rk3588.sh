#!/bin/bash
# fix_freq_rk3588.sh — 锁定 RK3588 各部件频率（文档 §11 的前置动作）
# 用法：板端 sudo ./fix_freq_rk3588.sh [lock|restore]
# 本板适配说明见 NPU/本板实操.md 第一节 —— 自动取各域最高可用频点，
# 因此文档 §11.2 表格里的 A76 2352MHz / DDR 2112MHz 与本板不符时会自动用本板实际值。
set -u
MODE="${1:-lock}"

lock_cpufreq() {   # $1=policy路径 $2=目标governor
  local p="$1" gov="$2"
  [ -d "$p" ] || return
  local avail max
  avail=$(cat "$p/scaling_available_governors" 2>/dev/null)
  echo "$avail" | grep -qw "$gov" || gov=performance
  echo "$gov" > "$p/scaling_governor" 2>/dev/null
  if [ "$gov" = userspace ]; then
    max=$(cat "$p/cpuinfo_max_freq" 2>/dev/null || cat "$p/scaling_max_freq")
    echo "$max" > "$p/scaling_setspeed" 2>/dev/null
  fi
}

lock_devfreq() {   # $1=devfreq路径 $2=目标governor
  local d="$1" gov="$2"
  [ -d "$d" ] || return
  local avail
  avail=$(cat "$d/available_governors" 2>/dev/null)
  echo "$avail" | grep -qw "$gov" || gov=performance
  echo "$gov" > "$d/governor" 2>/dev/null
  if [ "$gov" = userspace ]; then
    local max
    max=$(cat "$d/available_frequencies" 2>/dev/null | tr ' ' '\n' | sort -n | tail -1)
    echo "$max" > "$d/userspace/set_freq" 2>/dev/null
  fi
}

if [ "$MODE" = restore ]; then
  echo "== 恢复动态调频 =="
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo schedutil > "$p/scaling_governor" 2>/dev/null
  done
  echo rknpu_ondemand > /sys/class/devfreq/fdab0000.npu/governor 2>/dev/null
  echo simple_ondemand > /sys/class/devfreq/fb000000.gpu/governor 2>/dev/null
  echo dmc_ondemand > /sys/class/devfreq/dmc/governor 2>/dev/null
  for i in 0 1 2 3 4 5 6 7; do
    echo 0 > "/sys/devices/system/cpu/cpu$i/cpuidle/state1/disable" 2>/dev/null
  done
  echo "已恢复（或直接 reboot，本脚本的锁定不持久化）"
  exit 0
fi

echo "== 1. 锁定 CPU =="
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  lock_cpufreq "$p" userspace
done

echo "== 2. 锁定 NPU / GPU / DDR =="
lock_devfreq /sys/class/devfreq/fdab0000.npu userspace
lock_devfreq /sys/class/devfreq/fb000000.gpu userspace
lock_devfreq /sys/class/devfreq/dmc            userspace

echo "== 3. 关闭 CPU idle 深度状态（state1），降低唤醒延迟 =="
for i in 0 1 2 3 4 5 6 7; do
  echo 1 > "/sys/devices/system/cpu/cpu$i/cpuidle/state1/disable" 2>/dev/null
done

echo
echo "================= 锁定结果核对 ================="
printf '%-22s %-14s %-14s %s\n' 部件 governor cur_freq 文档值
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  printf '%-22s %-14s %-14s %s\n' "$(basename "$p")" \
    "$(cat "$p/scaling_governor")" "$(cat "$p/scaling_cur_freq")" "1800000 / 2352000"
done
for d in /sys/class/devfreq/fdab0000.npu /sys/class/devfreq/fb000000.gpu /sys/class/devfreq/dmc; do
  printf '%-22s %-14s %-14s %s\n' "$(basename "$d")" \
    "$(cat "$d/governor" 2>/dev/null)" "$(cat "$d/cur_freq" 2>/dev/null)" \
    "$([ "$(basename "$d")" = dmc ] && echo '2112000000' || echo '1000000000')"
done
echo "================================================"
echo "注：锁定不持久化，reboot 即恢复。还原：sudo $0 restore"
