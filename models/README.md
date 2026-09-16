# 模型文件

本次 NPU 压榨用到的模型与测试素材。

| 文件 | 大小 | 说明 | 来源 |
|---|---|---|---|
| `yolov5s_relu.rknn` | 8.39 MB | **本次的主测试模型**（INT8）。由下方 ONNX 经 rknn-toolkit2 2.3.2 转换而来，耗时 4.3 秒 | 本仓库自产（`scripts/rknn-convert/convert_yolov5.py`）|
| `yolov5s_relu.onnx` | 27.6 MB | 转换的输入源（含 ReLU 融合的 YOLOv5s）| [rknn_model_zoo/examples/yolov5](https://github.com/airockchip/rknn_model_zoo/tree/main/examples/yolov5) |
| `resnet18_for_rk3588.rknn` | 11.4 MB | 交叉验证用的轻量模型（纯 NPU 单帧 3.82 ms）| rknn-toolkit2 `examples/resnet18/` |
| `bus.jpg` | 177 KB | YOLOv5s 的测试输入（640×640）| rknn_model_zoo yolov5 示例 |
| `space_shuttle_224.jpg` | 23 KB | ResNet18 的测试输入（224×224）| rknn-toolkit2 resnet18 示例 |
| `dataset.txt` | <1 KB | INT8 量化校准集清单 | 转换时生成 |

## 复现转换

```bash
# 在 WSL2 中执行（环境搭建见 ../WSL/README.md）
~/rknn-env/bin/python ../scripts/rknn-convert/convert_yolov5.py
```

转换产物应得到 8.39 MB 的 INT8 `.rknn`。若体积明显偏大，说明量化没生效
（通常是没提供校准集 `dataset`）。

## 许可与署名

- `yolov5s_relu.onnx` / `bus.jpg` 来自瑞芯微 [rknn_model_zoo](https://github.com/airockchip/rknn_model_zoo)（Apache-2.0）。
  YOLOv5 原始模型由 [Ultralytics](https://github.com/ultralytics/yolov5) 发布（AGPL-3.0），
  此处为瑞芯微为 NPU 部署适配的 ReLU 融合版本。
- `resnet18_for_rk3588.rknn` / `space_shuttle_224.jpg` 来自瑞芯微 rknn-toolkit2（Apache-2.0）。
- 以上文件**仅用于本仓库的基准复现**，版权归原作者。如需商用请自行确认许可。
