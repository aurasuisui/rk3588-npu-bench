#!/bin/bash
# run_thread_sweep.sh —— 通用「线程数 × 模型」扫描（交错多轮，带 NPU 逐核采样）
#
# 用法：
#   sudo bash run_thread_sweep.sh <模型.rknn> <图片> <pass_through> <轮数> <计时秒> <线程列表> <输出子目录名>
# 例：
#   sudo bash run_thread_sweep.sh ~/rknn/models/resnet18/resnet18_for_rk3588.rknn \
#        ~/rknn/models/resnet18/space_shuttle_224.jpg 0 5 30 3,6,9,12,8 resnet18
#
# 产出：~/bench-results-<子目录名>/r<轮>-t<线程>-n<线程>.{log,samples}
#       fps 解析用 analyze_thread_saturation.py（识别 -n<N>.log）
set -u
HOMEDIR="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$HOMEDIR/scripts/npu-bench/zero_copy_bench"
SAMPLER="$HOMEDIR/scripts/npu-bench/npu_sampler.sh"

MODEL="${1:?模型路径}"; IMG="${2:?图片路径}"; PT="${3:-0}"
ROUNDS="${4:-5}"; MEASURE="${5:-30}"; THREADS="${6:?线程列表，如 3,6,9,12,8}"
NAME="${7:-sweep}"
WARMUP=5; COOLDOWN=10
OUT="$HOMEDIR/bench-results-$NAME"

[ -x "$BENCH" ] || { echo "先编译：$HOMEDIR/scripts/npu-bench/build_zero_copy.sh"; exit 1; }
[ -f "$MODEL" ] || { echo "找不到模型：$MODEL"; exit 1; }
[ -f "$IMG" ]   || { echo "找不到图片：$IMG"; exit 1; }

# 开跑前清残留（主实验踩过的坑：残留进程会污染第一组）
LEFT=$(pgrep -c -f zero_copy_bench || true)
[ "${LEFT:-0}" != "0" ] && { echo "清理 $LEFT 个残留 zero_copy_bench"; pkill -f zero_copy_bench; sleep 2; }

# 每次都从干净目录开始，避免上一轮的结果混进来
rm -rf "$OUT"; mkdir -p "$OUT"
LOG="$OUT/run.log"
IFS=',' read -ra TLIST <<< "$THREADS"

echo "开始: $(date -Is)" | tee "$LOG"
echo "模型: $MODEL" | tee -a "$LOG"
echo "图片: $IMG   pass_through=$PT" | tee -a "$LOG"
echo "预热 ${WARMUP}s / 计时 ${MEASURE}s / 冷却 ${COOLDOWN}s / ${ROUNDS} 轮交错 / 线程 $THREADS" | tee -a "$LOG"

for round in $(seq 1 "$ROUNDS"); do
  for N in "${TLIST[@]}"; do
    L="$OUT/r${round}-t${N}-n${N}.log"; S="$OUT/r${round}-t${N}-n${N}.samples"
    "$SAMPLER" "$S" & SP=$!
    sleep 1
    echo "=== round $round  threads=$N  $(date +%H:%M:%S) ===" | tee -a "$LOG"
    "$BENCH" "$MODEL" "$IMG" "$MEASURE" "$PT" "$N" "$WARMUP" > "$L" 2>/dev/null
    kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
    grep -E 'RESULT|CHECKSUM' "$L" | tee -a "$LOG"
    echo "    温度: $(cat /sys/class/thermal/thermal_zone0/temp)" | tee -a "$LOG"
    sleep "$COOLDOWN"
  done
done
echo "结束: $(date -Is)" | tee -a "$LOG"
