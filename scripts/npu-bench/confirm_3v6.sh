#!/bin/bash
# confirm_3v6.sh —— 确认实验：3 线程（1/核）vs 6 线程（2/核）干净对照
# 目的：判定主实验中 3 线程第 1 轮的 142.67 fps 是否为残留进程干扰造成的假象。
# 用法：sudo bash confirm_3v6.sh [轮数] [计时秒]
set -u
HOMEDIR="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$HOMEDIR/scripts/npu-bench/zero_copy_bench"
SAMPLER="$HOMEDIR/scripts/npu-bench/npu_sampler.sh"
MODEL="$HOMEDIR/rknn/models/yolov5s_relu.rknn"
IMG="$HOMEDIR/rknn/models/bus.jpg"
OUT="$HOMEDIR/bench-confirm"
ROUNDS=${1:-3}; MEASURE=${2:-30}; WARMUP=5; COOLDOWN=10

# 开跑前确认没有残留压测进程（避免重蹈主实验第 1 轮的覆辙）
LEFT=$(pgrep -c -f zero_copy_bench || true)
echo "残留 zero_copy_bench 进程数: ${LEFT:-0}"
pkill -f zero_copy_bench 2>/dev/null; sleep 2

mkdir -p "$OUT"
for r in $(seq 1 "$ROUNDS"); do
  for n in 3 6; do
    L="$OUT/c${r}-n${n}.log"; S="$OUT/c${r}-n${n}.samples"
    "$SAMPLER" "$S" & SP=$!
    sleep 1
    echo "=== confirm round $r threads=$n $(date +%H:%M:%S) ==="
    "$BENCH" "$MODEL" "$IMG" "$MEASURE" 1 "$n" "$WARMUP" > "$L" 2>/dev/null
    kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
    grep -o "fps=[0-9.]*" "$L"
    sleep "$COOLDOWN"
  done
done
echo "确认实验结束 $(date -Is)"
