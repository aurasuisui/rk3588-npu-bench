#!/bin/bash
# npu_sampler.sh <输出文件> —— 每 200ms 记录 NPU 逐核负载 / 温度 / 频率 / CPU 累计计数
# 需 root：/sys/kernel/debug/rknpu/load 仅 root 可读，普通用户会静默读到空值（方案 §五.2）
OUT="${1:?usage: $0 <outfile>}"
: > "$OUT"
while true; do
  TS=$(date +%s.%N)
  LOAD=$(tr -d '\n' < /sys/kernel/debug/rknpu/load 2>/dev/null | tr -s ' ')
  T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  NPUF=$(cat /sys/class/devfreq/fdab0000.npu/cur_freq 2>/dev/null)
  DDRF=$(cat /sys/class/devfreq/dmc/cur_freq 2>/dev/null)
  CPU=$(grep '^cpu ' /proc/stat 2>/dev/null | tr -s ' ')
  echo "$TS|$LOAD|$T|$NPUF|$DDRF|$CPU" >> "$OUT"
  sleep 0.2
done
