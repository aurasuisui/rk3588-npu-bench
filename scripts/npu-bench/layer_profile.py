#!/usr/bin/env python3
"""layer_profile.py — 逐层耗时剖析：找是否有算子掉到 CPU / 异常慢的层"""
import numpy as np, cv2, os
from rknnlite.api import RKNNLite

MODEL = os.path.expanduser("~/rknn/models/yolov5s_relu.rknn")
IMG   = os.path.expanduser("~/rknn/models/bus.jpg")
img = np.expand_dims(cv2.resize(cv2.cvtColor(cv2.imread(IMG), cv2.COLOR_BGR2RGB), (640, 640)), 0)

r = RKNNLite(verbose=False)
print("load_rknn   :", r.load_rknn(MODEL))
print("init_runtime:", r.init_runtime(core_mask=7))
for _ in range(5):
    r.inference(inputs=[img], data_format=["nhwc"])
print("--- 逐层/逐算子耗时 ---")
try:
    r.eval_perf(is_print=True)
except Exception as e:
    print("eval_perf 失败:", type(e).__name__, e)
try:
    print("--- 内存 ---")
    r.eval_memory()
except Exception as e:
    print("eval_memory 失败:", type(e).__name__, e)
r.release()
