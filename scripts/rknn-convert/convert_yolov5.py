#!/usr/bin/env python3
"""convert_yolov5.py — yolov5s_relu.onnx -> yolov5s_relu.rknn (RK3588, INT8)
参考 rknn_model_zoo/examples/yolov5/python/convert.py 的配置。
"""
import os, sys, urllib.request
from rknn.api import RKNN

ONNX = "/mnt/c/Users/aurasui/Desktop/Anything/ZYSJ-2288A/Transmission/rknn-toolkit2/yolov5s_relu.onnx"
OUT  = "/home/aura/yolov5s_relu.rknn"
DATA = "/home/aura/dataset.txt"
CAL  = "/home/aura/bus.jpg"          # 量化校准图（官方示例图）
CAL_URL = "https://raw.githubusercontent.com/airockchip/rknn_model_zoo/main/examples/yolov5/model/bus.jpg"

def ensure_cal():
    if os.path.exists(CAL) and os.path.getsize(CAL) > 10000:
        return True
    try:
        urllib.request.urlretrieve(CAL_URL, CAL)
        return os.path.getsize(CAL) > 10000
    except Exception as e:
        print("!! 校准图下载失败:", e)
        return False

def main():
    print("onnx:", ONNX, os.path.getsize(ONNX), "bytes")
    if not ensure_cal():
        print("!! 没有校准图，退化为不做量化（精度会差但能验证链路）")
        quant = False
    else:
        print("校准图:", CAL, os.path.getsize(CAL), "bytes")
        quant = True
    with open(DATA, "w") as f:
        if quant:
            f.write(CAL + "\n")

    rknn = RKNN(verbose=False)
    print("--- config ---")
    ret = rknn.config(
        mean_values=[[0, 0, 0]],
        std_values=[[255, 255, 255]],
        target_platform="rk3588",
        quant_img_RGB2BGR=True,
    )
    print("config ret:", ret)

    print("--- load_onnx ---")
    ret = rknn.load_onnx(model=ONNX)
    print("load_onnx ret:", ret)
    if ret != 0:
        sys.exit(1)

    print("--- build ---")
    ret = rknn.build(do_quantization=quant, dataset=DATA if quant else None)
    print("build ret:", ret)
    if ret != 0:
        sys.exit(1)

    print("--- export ---")
    ret = rknn.export_rknn(OUT)
    print("export ret:", ret)
    rknn.release()
    if ret == 0 and os.path.exists(OUT):
        print("OK ->", OUT, os.path.getsize(OUT), "bytes")
    else:
        sys.exit(1)

main()
