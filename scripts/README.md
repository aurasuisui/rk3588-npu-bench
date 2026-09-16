# scripts —— 本机侧脚本

> 约定见项目 `README.md` 第四节：**本机 `scripts/` 负责打包和推送，板上 `~/scripts/` 负责实际执行。**

## 约定：一个项目一个子文件夹

**不要往本目录根下丢脚本**，新项目新建一个子目录：

```
scripts/
├── adbd/            ADB 调试
├── npu-bench/       板端 NPU 体检 / 压测 / 推理自检
└── rknn-convert/    模型转换 + 板端验证
```

判断归哪组：**按「这件事属于哪个项目」分，不按文件类型分。**

---

## adbd/

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `build_adbd.sh` | 板端 | 从 Debian 源码编译 adbd（AOSP 34.0.5）→ `/usr/local/sbin/adbd` |
| `adbd-usb-gadget.sh` | 板端（root）| configfs + FunctionFS 建 ADB USB gadget；已装到 `/usr/local/sbin/adbd-usb-gadget` |

原料与产物在 `../Transmission/adbd/`。

## npu-bench/

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `run_probe_npu.ps1` | 本机（Windows）| 一键：scp 推 `probe_board_npu.sh` → 板端执行 |
| `push_npu_scripts.sh` | 本机 | 把本组脚本 + `adbd/` 的板端脚本一次性推到 `board-lan:~/scripts/` |
| `probe_board_npu.sh` | 板端 | NPU / RKNN / 编译链 / 外网 / ADB / RKLLM 八项只读体检 |
| `npu_test_resnet18.py` | 板端 | NPU 推理自检（ResNet18，约 214 fps）|
| `mask_latency.py` | 板端 | core_mask 单进程延迟对照（三核 ≈1.7×）|
| `core_mask_bench.py` | 板端 | 多进程吞吐对照（暴露宿主开销瓶颈）|
| `fix_freq_rk3588.sh` | 板端（root）| **§11 锁频**：各域自动取最高可用频点；`restore` 子命令还原 |
| `board_stress_test_16t.py` | 板端 | **§7.1 反面案例**：16 线程抢一把锁（YOLOv5s，实测 28.2 fps）|
| `board_stress_test_6p.py` | 板端 | **§7.2 正确方案**：多进程 + core_mask，含 3/6/9 进程对照（实测 118.7 fps）|
| `zero_copy_bench.cc` | 板端编译 | **§8 零拷贝压测**：`rknn_create_mem` + `pass_through` + 多线程（实测 177.6 fps）|
| `build_zero_copy.sh` | 板端 | 编译 `zero_copy_bench.cc`（OpenCV4 走 pkg-config）|
| `npu_sampler.sh` | 板端（root）| 每 200 ms 采 NPU 逐核负载 / 温度 / 各域频率 / CPU 累计 |
| `run_thread_saturation.sh` | 板端（root）| **线程数饱和点主实验**：3/6/9/12/8 线程交错 5 轮（约 19 min）|
| `confirm_3v6.sh` | 板端（root）| 3 vs 6 线程干净对照（开跑前自动清理残留进程）|
| `analyze_thread_saturation.py` | 板端 / 本机 | 汇总 fps 均值±标准差、逐核 NPU 占用，按事先规则自动判读 |
| `run_thread_sweep.sh` | 板端（root）| **通用「线程数 × 模型」扫描**（参数化模型/轮数/线程列表），ResNet18 对照用它 |

两类素材路径：

- ResNet18 系列脚本读 `/tmp/nputest/` —— 把 `../RKNN-SDK/rknn-toolkit-lite2/examples/resnet18/`
  下的 `resnet18_for_rk3588.rknn` 与 `space_shuttle_224.jpg` 拷过去。
- YOLOv5s 系列脚本（`board_stress_test_*` / `zero_copy_bench`）读 **`~/rknn/models/`** ——
  把 `../Transmission/rknn-output/` 下的 `yolov5s_relu.rknn` 与 `bus.jpg` 拷过去。

> 跑压测前先 `sudo fix_freq_rk3588.sh` 锁频，否则数据不可比（见 `../../NPU/本板实操.md` 第四节）。

## rknn-convert/

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `convert_yolov5.py` | WSL（PC）| `.onnx` → `.rknn`（INT8 量化），说明见本目录 `README.md` |
| `verify_rknn_on_board.sh` | 本机 | 把转好的 `.rknn` 推板，跑单核 / 三核基准对照 |

WSL 环境见 `../../WSL/README.md`；产物在 `../Transmission/rknn-output/`。
