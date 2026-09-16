#!/usr/bin/env python3
# core_mask_bench.py — 验证文档 §7.2：单核默认 vs 三核绑定（多进程 + core_mask）
import multiprocessing as mp, time, numpy as np
from PIL import Image
from rknnlite.api import RKNNLite

MODEL = "/tmp/nputest/resnet18_for_rk3588.rknn"
IMG   = "/tmp/nputest/space_shuttle_224.jpg"
img = np.asarray(Image.open(IMG).convert("RGB").resize((224, 224), Image.BILINEAR),
                 dtype=np.uint8)[None, ...]

def worker(mask, seconds, q):
    r = RKNNLite(verbose=False)
    r.load_rknn(MODEL)
    r.init_runtime(core_mask=mask)
    n, t0 = 0, time.perf_counter()
    while time.perf_counter() - t0 < seconds:
        r.inference(inputs=[img], data_format=["nhwc"]); n += 1
    q.put(n)
    r.release()

def bench(mask, nproc, seconds=5.0):
    q = mp.Queue()
    ps = [mp.Process(target=worker, args=(mask, seconds, q)) for _ in range(nproc)]
    t0 = time.perf_counter()
    [p.start() for p in ps]; [p.join() for p in ps]
    # 每个 worker 各自计满 seconds，故总吞吐 = 各自帧率之和
    total = sum(q.get() for _ in ps)
    return total / (time.perf_counter() - t0)

if __name__ == "__main__":
    print("%-18s %-8s %s" % ("配置", "进程数", "总吞吐 fps"))
    print("%-18s %-8s %.1f" % ("默认(单核 core0)", 1, bench(None, 1)))
    print("%-18s %-8s %.1f" % ("默认(单核 core0)", 3, bench(None, 3)))
    print("%-18s %-8s %.1f" % ("三核绑定 mask=1|2|4", 3, bench(1 | 2 | 4, 3)))
    print("%-18s %-8s %.1f" % ("三核绑定 mask=1|2|4", 6, bench(1 | 2 | 4, 6)))
