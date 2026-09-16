#!/bin/bash
# build_zero_copy.sh — 板端原生编译零拷贝压测（文档 §8.4 的板端版本）
# 本板已装 librknnrt + 头文件 + OpenCV4，不需要交叉工具链、不需要 -I/-L 指路。
set -e
cd "$(dirname "$0")"
echo "== g++ 版本 =="; g++ --version | head -1
FLAGS="$(pkg-config --cflags --libs opencv4)"
echo "== opencv4 flags: $FLAGS =="
# 头文件在 /usr/local/include/rknn/（不是 /usr/local/include/），必须显式 -I
g++ -O2 -std=c++17 zero_copy_bench.cc -o zero_copy_bench \
    -I/usr/local/include/rknn -lrknnrt -lpthread $FLAGS
echo "== 编译完成 =="
ls -l zero_copy_bench
