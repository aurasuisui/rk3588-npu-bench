#!/bin/bash
# push_npu_scripts.sh — 把本机 scripts/ 里的板端脚本推到板子 ~/scripts/（保持子目录结构）
# 用法：./push_npu_scripts.sh [board-lan]
# 约定（见项目 README「目录约定」）：本机 scripts/ 负责"打包和推送"，板上 ~/scripts/ 负责"实际执行"
HOST=${1:-board-lan}
DIR="$(cd "$(dirname "$0")" && pwd)"
ADBD="$DIR/../adbd"

echo ">> 建远端子目录"
ssh -o ConnectTimeout=8 "$HOST" 'mkdir -p ~/scripts/adbd ~/scripts/npu-bench'

echo ">> 推送 adbd/"
scp -o ConnectTimeout=8 \
    "$ADBD/build_adbd.sh" \
    "$ADBD/adbd-usb-gadget.sh" \
    "$HOST:~/scripts/adbd/"

echo ">> 推送 npu-bench/"
scp -o ConnectTimeout=8 \
    "$DIR/probe_board_npu.sh" \
    "$DIR/npu_test_resnet18.py" \
    "$DIR/mask_latency.py" \
    "$DIR/core_mask_bench.py" \
    "$HOST:~/scripts/npu-bench/"

echo ">> 校验"
ssh -o ConnectTimeout=8 "$HOST" 'chmod +x ~/scripts/*/*.sh; find ~/scripts -type f | sort'
echo ">> 完成。板上执行示例：ssh $HOST 'cd ~/scripts/npu-bench && ./probe_board_npu.sh'"
