#!/usr/bin/env python3
# board_stress_test_16t.py — 文档 §7.1 的「反面案例」复现
# 16 线程共享同一个 RKNNLite 实例 + 一把互斥锁，全部绑在 core0。
# 预期结果：吞吐反而低于单进程单核（锁竞争 + GIL + 上下文切换）。
import os, sys, time, threading
import numpy as np, cv2
from rknnlite.api import RKNNLite

MODEL        = os.path.expanduser("~/rknn/models/yolov5s_relu.rknn")
IMG          = os.path.expanduser("~/rknn/models/bus.jpg")
NUM_THREADS  = 16
TEST_SECONDS = float(os.environ.get("TEST_SECONDS", 10))
CORE_MASK    = RKNNLite.NPU_CORE_0          # 只绑 core0（Mask = 1）

_img = cv2.cvtColor(cv2.imread(IMG), cv2.COLOR_BGR2RGB)
img  = np.expand_dims(cv2.resize(_img, (640, 640)), 0)   # (1,640,640,3) NHWC

if __name__ == "__main__":
    rknn = RKNNLite(verbose=False)
    rknn.load_rknn(MODEL)
    rknn.init_runtime(core_mask=CORE_MASK)

    lock    = threading.Lock()
    stop    = threading.Event()
    counts  = [0] * NUM_THREADS

    def worker(tid):
        n = 0
        while not stop.is_set():
            with lock:                                   # ← 16 个线程抢同一把锁
                rknn.inference(inputs=[img], data_format=["nhwc"])
            n += 1
        counts[tid] = n

    print("线程数=%d  core_mask=%d  时长=%.0fs  —— 预热中" % (NUM_THREADS, CORE_MASK, TEST_SECONDS))
    ts = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(NUM_THREADS)]
    t0 = time.perf_counter()
    for t in ts: t.start()
    time.sleep(TEST_SECONDS)
    stop.set()
    for t in ts: t.join()
    elapsed = time.perf_counter() - t0

    total = sum(counts)
    print("总帧数=%d  墙钟=%.2fs" % (total, elapsed))
    print(">>> 16 线程单核吞吐 = %.1f fps" % (total / elapsed))
    print("    线程分布:", counts)
    rknn.release()
