#!/bin/bash
# bw_contention.sh — 带宽竞争测试：NPU 压测 vs 叠加 DDR 带宽压力
# 若叠加后 fps 明显下降 → 说明 NPU 的瓶颈是内存带宽（共享资源），
# 那么再加 GPU 推理（同样吃带宽）只会更慢，不会更快。
MB=${2:-256}
SECS=${1:-10}
BENCH=$HOME/scripts/npu-bench/zero_copy_bench
MODEL=$HOME/rknn/models/yolov5s_relu.rknn
IMG=$HOME/rknn/models/bus.jpg

run_case () {
  local n=$1 label=$2
  local pids=()
  for i in $(seq 1 $n); do
    python3 $HOME/scripts/npu-bench/bw_hog.py $((SECS+2)) $MB > /tmp/hog_$i.log 2>&1 &
    pids+=($!)
  done
  sleep 1
  local out
  out=$("$BENCH" "$MODEL" "$IMG" "$SECS" 1 8 2>/dev/null | grep -E "吞吐|线程分布")
  for p in "${pids[@]}"; do wait $p 2>/dev/null; done
  echo "--- $label ---"
  echo "$out" | sed 's/^/  /'
  cat /tmp/hog_1.log 2>/dev/null | head -1
  echo
}

echo "=== 基线：无额外负载 ==="
run_case 0 "基线（仅 NPU 压测）"
echo "=== 叠加 2 个带宽压力器 ==="
run_case 2 "NPU + 2×DDR hog"
echo "=== 叠加 4 个带宽压力器 ==="
run_case 4 "NPU + 4×DDR hog"
