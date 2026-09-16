#!/usr/bin/env python3
# board_stress_test_6p.py — 文档 §7.2 的正确方案
# 多进程 + core mask 绑定，每核 2 个进程构成任务流水线。
# 对照档：NUMPROC=3（每核 1 进程）看流水线加成。
import os, sys, time, multiprocessing as mp
import numpy as np, cv2
from rknnlite.api import RKNNLite

MODEL        = os.path.expanduser("~/rknn/models/yolov5s_relu.rknn")
IMG          = os.path.expanduser("~/rknn/models/bus.jpg")
TEST_SECONDS = float(os.environ.get("TEST_SECONDS", 10))
CORES        = [1, 2, 4]                     # core0 / core1 / core2 位掩码
PER_CORE     = int(os.environ.get("PER_CORE", 2))

_img = cv2.cvtColor(cv2.imread(IMG), cv2.COLOR_BGR2RGB)
img  = np.expand_dims(cv2.resize(_img, (640, 640)), 0)

def worker(core_mask, seconds, q, idx):
    r = RKNNLite(verbose=False)
    r.load_rknn(MODEL)
    if core_mask is None:
        r.init_runtime()                 # 不传 mask：交给驱动默认（实测就是 core0）
    else:
        r.init_runtime(core_mask=core_mask)
    n, t0, local = 0, time.perf_counter(), 0
    while time.perf_counter() - t0 < seconds:
        r.inference(inputs=[img], data_format=["nhwc"])
        n += 1
    q.put((idx, core_mask, n))
    r.release()

def bench(plan, label, seconds=TEST_SECONDS):
    q = mp.Queue()
    ps = []
    for idx, mask in enumerate(plan):
        ps.append(mp.Process(target=worker, args=(mask, seconds, q, idx)))
    t0 = time.perf_counter()
    for p in ps: p.start()
    for p in ps: p.join()
    elapsed = time.perf_counter() - t0
    try:
        res = [q.get(timeout=2) for _ in ps]
    except Exception:
        res = []
    total = sum(r[2] for r in res)
    per = {}
    for _, mask, n in res:
        per[mask] = per.get(mask, 0) + n
    print(">>> %-26s 进程=%d  总帧=%d  吞吐 = %.1f fps   %s"
          % (label, len(plan), total, total / elapsed,
             " ".join("core%s:%d" % ({1:"0",2:"1",4:"2"}.get(m, m), v) for m, v in sorted(per.items()))))
    return total / elapsed

if __name__ == "__main__":
    print("模型: %s" % MODEL)
    print("时长: %.0fs/档\n" % TEST_SECONDS)
    plan6 = [m for m in CORES for _ in range(PER_CORE)]   # [1,1,2,2,4,4]
    bench([None],        "默认(不传mask) ×1")
    bench(CORES,         "三核绑定 ×3 (每核1进程)")
    bench(plan6,         "三核绑定 ×6 (每核2进程)")
    bench(CORES * 3,     "三核绑定 ×9 (每核3进程)")
