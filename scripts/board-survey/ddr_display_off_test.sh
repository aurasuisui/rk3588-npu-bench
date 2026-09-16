#!/bin/bash
# ddr_display_off_test.sh — 验证「关掉无人看的显示器扫描输出」能否拿回带宽
BENCH=$HOME/scripts/npu-bench/zero_copy_bench
MODEL=$HOME/rknn/models/yolov5s_relu.rknn
IMG=$HOME/rknn/models/bus.jpg
SECS=${1:-15}

run_bench () {
  local label="$1"
  local out
  out=$("$BENCH" "$MODEL" "$IMG" "$SECS" 1 8 2>/dev/null | grep -oP '吞吐\s*:\s*\K[0-9.]+')
  echo "  $label : $out fps"
}

echo "=== 显示器状态（关闭前）==="
for c in /sys/class/drm/card0-DSI-1 /sys/class/drm/card0-DSI-2; do
  echo "  $(basename $c): status=$(cat $c/status) enabled=$(cat $c/enabled) mode=$(cat $c/modes|head -1)"
done
echo "  空载 DDR 频率: $(cat /sys/class/devfreq/dmc/cur_freq)"
echo

echo "=== A. 基线（显示器在扫描输出）==="
run_bench "第 1 次"
run_bench "第 2 次"
echo

echo "=== 关闭 DSI-1 / DSI-2 ==="
for c in /sys/class/drm/card0-DSI-1 /sys/class/drm/card0-DSI-2; do
  echo off > "$c/status" 2>/dev/null && echo "  $(basename $c) -> off" || echo "  $(basename $c) 不支持 status 写入"
done
sleep 3
for c in /sys/class/drm/card0-DSI-1 /sys/class/drm/card0-DSI-2; do
  echo "  $(basename $c): status=$(cat $c/status) enabled=$(cat $c/enabled 2>/dev/null)"
done
echo "  空载 DDR 频率: $(cat /sys/class/devfreq/dmc/cur_freq)"
echo

echo "=== B. 关闭显示器后 ==="
run_bench "第 1 次"
run_bench "第 2 次"
echo
echo "=== DDR devfreq 统计 ==="
cat /sys/class/devfreq/dmc/trans_stat 2>/dev/null | head -10
