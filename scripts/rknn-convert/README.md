# convert_yolov5.py —— ONNX → RKNN 模型转换（在 WSL 里跑）

环境已经装好，**开箱即用**：WSL 发行版 `Ubuntu-2204`（默认用户 `aura`）。
完整安装记录、源配置、踩过的版本坑见 `../../WSL/README.md`。

## 用法

```powershell
# 在 Windows 侧（PowerShell / cmd）直接调用 WSL
wsl -d Ubuntu-2204 /home/aura/rknn-env/bin/python /home/aura/convert_yolov5.py
```

或者进 WSL 里跑：

```bash
wsl -d Ubuntu-2204          # 进去就是 aura 用户，sudo 免密
~/rknn-env/bin/python ~/convert_yolov5.py
```

## 它做什么

| 步骤 | 说明 |
|---|---|
| 读 ONNX | `Transmission/rknn-toolkit2/yolov5s_relu.onnx`（27.6 MB，经 `/mnt/c/...` 直接读 Windows 盘）|
| 取校准图 | `bus.jpg`，缺失时自动从官方仓库下载 |
| config | `mean=[[0,0,0]] std=[[255,255,255]] target_platform=rk3588 quant_img_RGB2BGR=True` |
| build | INT8 量化（`do_quantization=True`，校准集 `dataset.txt`）|
| export | `/home/aura/yolov5s_relu.rknn`（8.39 MB）|

实测：整条 4.3 秒。产物要再拷出来给板子用：

```bash
cp /home/aura/yolov5s_relu.rknn /mnt/c/Users/aurasui/Desktop/Anything/ZYSJ-2288A/Transmission/rknn-output/
```

## 换成自己的模型

改脚本开头的 `ONNX` / `OUT` / `CAL` 三个常量即可。注意：

- `mean` / `std` 要跟训练时的预处理一致（YOLOv5 是 0~255 归一化）
- 量化必须有校准集，**否则精度会明显掉**（不给 `dataset` 就退化成非量化）
- 输入尺寸跟模型走，YOLOv5s 是 640×640

## ⚠️ 两个版本坑（已修好，重装环境时会再遇到）

| 现象 | 原因 | 解法 |
|---|---|---|
| `AttributeError: module 'onnx' has no attribute 'mapping'` | pip 按 `onnx>=1.16.1` 装到了 1.22，而 onnx 1.22 删了 `mapping` | `pip install "onnx==1.16.1"` |
| `ModuleNotFoundError: No module named 'pkg_resources'` | setuptools 被升到 84，81+ 移除了 `pkg_resources` | `pip install "setuptools<81"` |
| torch 下载 2 GB+ | 默认 PyPI 的 torch 是 CUDA 版 | 加 `--extra-index-url https://download.pytorch.org/whl/cpu`，装 `torch==2.4.0+cpu` |