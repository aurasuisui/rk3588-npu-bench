#!/bin/bash
# verify_rknn_on_board.sh — 把 PC 上转好的 .rknn 推到板子并跑 NPU 基准
# 用法（PC 侧 Git Bash / WSL）：bash scripts/rknn-convert/verify_rknn_on_board.sh [board-lan]
set -e
BOARD=${1:-board-lan}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODEL="$ROOT/Transmission/rknn-output/yolov5s_relu.rknn"
IMG="$ROOT/Transmission/rknn-output/bus.jpg"

[ -f "$MODEL" ] || { echo "找不到 $MODEL（先在 WSL 里跑 scripts/rknn-convert/convert_yolov5.py）"; exit 1; }

echo ">> 推到板子"
scp -o ConnectTimeout=8 "$MODEL" "$IMG" "$BOARD:~/"

echo ">> 板端 NPU 基准（单核 / 三核）"
ssh -o ConnectTimeout=8 "$BOARD" 'bash -s' <<'EOF'
cd ~/rknn/examples/rknn_benchmark/install/*/ 2>/dev/null || { echo "找不到 rknn_benchmark，先按 README.md 第六节编译"; exit 1; }
export LD_LIBRARY_PATH=.
echo "--- 单核 (core_mask=1) ---"
./rknn_benchmark ~/yolov5s_relu.rknn ~/bus.jpg 50 1 2>&1 | grep -iE "fps|ms|total|average" | head -6
echo "--- 三核 (core_mask=7) ---"
./rknn_benchmark ~/yolov5s_relu.rknn ~/bus.jpg 50 7 2>&1 | grep -iE "fps|ms|total|average" | head -6
EOF

echo ">> 完成"
