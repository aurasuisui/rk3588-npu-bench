#!/bin/bash
# run_thread_saturation.sh —— 线程数饱和点实测（方案 §四.4 的交错 5 轮）
# 用 sudo 跑（采样器需要 root 读 NPU 负载）。
# 环境变量可覆盖：MEASURE=30 WARMUP=5 COOLDOWN=10 ROUNDS=5
set -u
HOMEDIR="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$HOMEDIR/scripts/npu-bench/zero_copy_bench"
SAMPLER="$HOMEDIR/scripts/npu-bench/npu_sampler.sh"
MODEL="$HOMEDIR/rknn/models/yolov5s_relu.rknn"
IMG="$HOMEDIR/rknn/models/bus.jpg"
OUT="$HOMEDIR/bench-results"

MEASURE=${MEASURE:-30}
WARMUP=${WARMUP:-5}
COOLDOWN=${COOLDOWN:-10}
ROUNDS=${ROUNDS:-5}

[ -x "$BENCH" ] || { echo "先编译：$HOMEDIR/scripts/npu-bench/build_zero_copy.sh"; exit 1; }
mkdir -p "$OUT"
LOG="$OUT/run.log"

echo "开始: $(date -Is)" | tee "$LOG"
echo "预热 ${WARMUP}s / 计时 ${MEASURE}s / 冷却 ${COOLDOWN}s / ${ROUNDS} 轮交错" | tee -a "$LOG"
echo "配置: A=3(1/核) B=6(2/核) C=9(3/核) D=12(4/核) E=8(复刻上游)" | tee -a "$LOG"

for round in $(seq 1 "$ROUNDS"); do
  for cfg in 3:t1 6:t2 9:t3 12:t4 8:tup; do
    N=${cfg%%:*}; TAG=${cfg##*:}
    L="$OUT/r${round}-${TAG}-n${N}.log"
    S="$OUT/r${round}-${TAG}-n${N}.samples"

    "$SAMPLER" "$S" &
    SAMPLER_PID=$!
    sleep 1
    echo "=== round $round  threads=$N ($TAG)  $(date +%H:%M:%S) ===" | tee -a "$LOG"
    "$BENCH" "$MODEL" "$IMG" "$MEASURE" 1 "$N" "$WARMUP" > "$L" 2>/dev/null
    kill "$SAMPLER_PID" 2>/dev/null; wait "$SAMPLER_PID" 2>/dev/null

    grep -E 'RESULT|CHECKSUM' "$L" | tee -a "$LOG"
    echo "    温度: $(cat /sys/class/thermal/thermal_zone0/temp)  NPU: $(cat /sys/class/devfreq/fdab0000.npu/cur_freq)" | tee -a "$LOG"
    sleep "$COOLDOWN"
  done
done
echo "结束: $(date -Is)" | tee -a "$LOG"
