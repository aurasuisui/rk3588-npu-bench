#!/usr/bin/env python3
# mask_latency.py — 单进程、逐个 core_mask 测纯延迟；确认 core_mask 是否真的改变执行核心
import time, numpy as np
from PIL import Image
from rknnlite.api import RKNNLite

MODEL = "/tmp/nputest/resnet18_for_rk3588.rknn"
IMG   = "/tmp/nputest/space_shuttle_224.jpg"
img = np.asarray(Image.open(IMG).convert("RGB").resize((224, 224), Image.BILINEAR),
                 dtype=np.uint8)[None, ...]

def measure(mask, warm=20, n=200):
    r = RKNNLite(verbose=False)
    r.load_rknn(MODEL)
    r.init_runtime(core_mask=mask)
    for _ in range(warm):
        r.inference(inputs=[img], data_format=["nhwc"])
    t = time.perf_counter()
    for _ in range(n):
        r.inference(inputs=[img], data_format=["nhwc"])
    ms = (time.perf_counter() - t) * 1000.0 / n
    # 打开 perf 剖析，看各核心 workload（文档 §5.3 的 workload 列）
    if mask == (1 | 2 | 4):
        try:
            r.eval_perf(is_print=False)
        except Exception as e:
            print("   eval_perf:", e)
    r.release()
    return ms

print("%-22s %-12s %s" % ("init_runtime(core_mask)", "单帧延迟", "等效 fps"))
for name, mask in [("1  (CORE_0)", 1), ("2  (CORE_1)", 2), ("4  (CORE_2)", 4),
                   ("1|2|4 (三核)", 1 | 2 | 4), ("1|2 (双核)", 1 | 2)]:
    try:
        ms = measure(mask)
        print("%-22s %-12s %.1f" % (name, "%.3f ms" % ms, 1000.0 / ms))
    except Exception as e:
        print("%-22s ERROR: %s" % (name, e))
