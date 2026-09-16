#!/usr/bin/env python3
"""bw_hog.py — DDR 带宽压力器：反复在大数组间拷贝，吃满内存带宽
用法：python3 bw_hog.py 秒数 [MB]
"""
import sys, time
import numpy as np

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 10
mb   = int(sys.argv[2]) if len(sys.argv) > 2 else 256
n = mb * 1024 * 1024
a = np.ones(n, dtype=np.uint8)
b = np.empty_like(a)
t0 = time.perf_counter()
it = 0
while time.perf_counter() - t0 < secs:
    np.copyto(b, a)
    it += 1
el = time.perf_counter() - t0
# 每轮读写各 mb MB → 有效带宽
print("  [hog] %.1fs  %d 轮  ≈ %.1f GB/s (读+写)" % (el, it, 2.0 * it * mb / 1024 / el))
