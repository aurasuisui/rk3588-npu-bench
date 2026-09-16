#!/usr/bin/env python3
# npu_test_resnet18.py — 用官方 resnet18 rknn 模型在板端跑通 NPU 推理（避免引入 opencv 依赖）
import time, numpy as np
from PIL import Image
from rknnlite.api import RKNNLite

MODEL = "/tmp/nputest/resnet18_for_rk3588.rknn"
IMG   = "/tmp/nputest/space_shuttle_224.jpg"

def load(path, size):
    im = Image.open(path).convert("RGB").resize(size, Image.BILINEAR)
    return np.asarray(im, dtype=np.uint8)[None, ...]     # NHWC

def main():
    img = load(IMG, (224, 224))
    print("input:", img.shape, img.dtype, "sum:", int(img.sum()))

    rknn = RKNNLite(verbose=False)
    print("load_rknn   :", rknn.load_rknn(MODEL))
    print("init_runtime:", rknn.init_runtime())          # 不传 core_mask = 文档 §5.3 的默认单核
    out = rknn.inference(inputs=[img], data_format=["nhwc"])
    print("output0:", out[0].shape, "argmax:", int(np.argmax(out[0].flatten())))

    t = time.perf_counter(); n = 50
    for _ in range(n):
        rknn.inference(inputs=[img], data_format=["nhwc"])
    fps = n / (time.perf_counter() - t)
    print("RESULT: %.2f fps (%.2f ms/frame, 单核默认, 224x224 resnet18)" % (fps, 1000.0/fps))
    rknn.release()

main()
