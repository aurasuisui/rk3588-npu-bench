#!/bin/bash
# inspect_rknn_api.sh — 解包 rknn-toolkit2 whl，提取真实的量化相关 API 参数
# 用法（Windows 侧）：wsl -d Ubuntu-2204 bash /mnt/c/.../scripts/rknn-convert/inspect_rknn_api.sh
WHL=/mnt/c/Users/aurasui/Desktop/Anything/ZYSJ-2288A/Transmission/rknn-toolkit2/rknn_toolkit2-2.3.2-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
rm -rf /tmp/rknnwhl && mkdir -p /tmp/rknnwhl && cd /tmp/rknnwhl || exit 1
unzip -q "$WHL" || { echo "unzip 失败"; exit 1; }

echo "=== api 目录 ==="
ls rknn/api/*.py 2>/dev/null

echo
echo "=== config() 中与量化直接相关的参数 ==="
grep -n "quantized_dtype\|quantized_algorithm\|quantized_method\|quant_img_RGB2BGR\|optimization_level" rknn/api/rknn.py | head -40

echo
echo "=== 量化算法可选值 ==="
grep -n -A3 "quantized_algorithm" rknn/api/rknn.py | grep -i "normal\|mmse\|kl_divergence\|quantized_algorithm" | head -20

echo
echo "=== 精度/性能分析接口 ==="
grep -n "def accuracy_analysis\|def eval_perf\|def eval_memory\|def hybrid_quantization\|def export_rknn\|def build" rknn/api/rknn.py

echo
echo "=== acc_analysis 支持的 metric（逐层余弦相似度）==="
grep -rn "cosine\|euclidean\|sqnr\|akld" rknn/api/*.py 2>/dev/null | head -20
