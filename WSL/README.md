# WSL —— 模型转换环境（ONNX → RKNN）

> 最后更新：2026-09-14
> ⚠️ **这是 PC 侧的 x86_64 Linux，只负责把模型转成 `.rknn`。** 推理和压测都在开发板上，别混淆两台机器。

## 为什么需要它

`.onnx` / `.pt` / `.tflite` → `.rknn` 这一步**只能在 x86_64 Linux 上做**：

- 板子是 aarch64，`rknn_toolkit_lite2` 只负责推理，不能转换
- rknn-toolkit2 **没有 Windows 轮子**

所以走 WSL2。当初没选双系统的原因：切系统会丢掉 DSH 会话上下文。

## 环境（已装好，开箱即用）

| 项目 | 值 |
|---|---|
| 发行版 | `Ubuntu-2204`（Ubuntu 22.04.5 / x86_64 / Python 3.10.12）|
| 默认用户 | `aura`（sudo 免密）|
| venv | `/home/aura/rknn-env` —— rknn-toolkit2 **2.3.2** + torch **2.4.0+cpu** |
| 源 | apt → 华为云；pip → 阿里云；torch → 官方 CPU 索引 |

## 怎么用

**从 Windows 一条命令**（推荐）：

```powershell
wsl -d Ubuntu-2204 /home/aura/rknn-env/bin/python /home/aura/convert_yolov5.py
```

或进 WSL 里跑：

```bash
wsl -d Ubuntu-2204                    # 进去就是 aura 用户
~/rknn-env/bin/python ~/convert_yolov5.py
```

转换脚本的说明与改法见 `../scripts/rknn-convert/README.md`。
产物落在 `Transmission/rknn-output/`，再用 `scripts/rknn-convert/verify_rknn_on_board.sh` 推板验证。

## ⚠️ 三个版本坑（重装环境必再遇到）

根因都是**官方 requirements 只写了下界、没写上界**：

| 现象 | 原因 | 解法 |
|---|---|---|
| `module 'onnx' has no attribute 'mapping'` | 装到了 1.22，而 1.22 删了 `mapping` | `pip install onnx==1.16.1` |
| `No module named 'pkg_resources'` | setuptools 被升到 84，81+ 移除了它 | `pip install "setuptools<81"` |
| torch 下载 2 GB+ | 默认 PyPI 的 torch 是 CUDA 版 | 加 `--extra-index-url https://download.pytorch.org/whl/cpu`，装 `torch==2.4.0+cpu` |

## 如果要重装

WSL 自带的 `wsl --install -d Ubuntu-22.04` 走 Canonical 海外源、**换不了源**且慢。当时用的是**自下 rootfs + 导入**：

```powershell
# ① 从华为云下 rootfs（实测 12.49 MB/s，325 MB / 26 秒）—— 兜底：上交 → 官方
# ② 导入
wsl --import Ubuntu-2204 C:\WSL\Ubuntu-2204 <rootfs.tar.gz>
```

装完记得换源（思路同板子）：apt → `mirrors.huaweicloud.com/ubuntu`、pip → 清华。
⚠️ x86_64 用 `ubuntu`，**不带 `-ports`** —— 板子是 arm64 才用 `ubuntu-ports`。

## 提醒

- **两台机器别混**：WSL 只做转换，推理/压测在板子（`board-lan`）
- 板子侧已全部就绪（librknnrt 2.3.2 + adbd + systemd 服务），转换产物拿到就能跑
- 退路：若 WSL 不可用，可上 Ubuntu 双系统，本文的工具链要点同样适用
