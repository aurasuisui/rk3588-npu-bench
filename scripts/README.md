# scripts

本次 NPU 压榨用到的全部代码。板端脚本在开发板上执行，PC 侧脚本负责打包、推送与模型转换。

> ⚠️ 跑任何压测前先 `sudo fix_freq_rk3588.sh` 锁频，否则数据不可比。

---

## npu-bench/ —— 基准测试与压榨

### 环境与自检

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `run_probe_npu.ps1` | 本机（Windows）| 一键：scp 推 `probe_board_npu.sh` → 板端执行 |
| `push_npu_scripts.sh` | 本机 | 把本组脚本一次性推到板端 `~/scripts/` |
| `probe_board_npu.sh` | 板端 | NPU / RKNN / 编译链 / 外网 / 驱动 八项只读体检 |
| `npu_test_resnet18.py` | 板端 | NPU 推理自检（ResNet18，约 214 fps）|

### core_mask 标定

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `mask_latency.py` | 板端 | core_mask 单进程延迟对照（三核 ≈1.7×）|
| `core_mask_bench.py` | 板端 | 多进程吞吐对照（暴露宿主开销瓶颈）|

### 性能演进链（Python 侧对照）

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `board_stress_test_16t.py` | 板端 | **反面案例**：16 线程抢一把锁（YOLOv5s，实测 28.2 fps）|
| `board_stress_test_6p.py` | 板端 | **多进程 + core_mask**，含 3/6/9 进程对照（实测 118.7 fps）|

### C++ 零拷贝

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `zero_copy_bench.cc` | 板端编译 | **自写**：`rknn_create_mem` + `pass_through` + 三核多上下文线程模型（实测 177.6 fps）|
| `build_zero_copy.sh` | 板端 | 编译上面这个（OpenCV4 走 pkg-config）|

### 线程数饱和点实验

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `fix_freq_rk3588.sh` | 板端（root）| 全域锁频，自动取各域最高可用频点；`restore` 子命令还原 |
| `npu_sampler.sh` | 板端（root）| 每 200 ms 采 NPU 逐核负载 / 温度 / 各域频率 / CPU 累计 |
| `run_thread_saturation.sh` | 板端（root）| **主实验**：3/6/9/12/8 线程交错 5 轮（约 19 min）|
| `confirm_3v6.sh` | 板端（root）| 3 vs 6 线程干净对照（开跑前自动清理残留进程）|
| `run_thread_sweep.sh` | 板端（root）| **通用「线程数 × 模型」扫描**，ResNet18 对照用它 |
| `analyze_thread_saturation.py` | 板端 / 本机 | 汇总 fps 均值±标准差、逐核 NPU 占用，按事先规则自动判读 |

### 瓶颈分析（探索性）

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `npu_load_profile.sh` | 板端（root）| 压测期间逐秒采样三核负载，判断 NPU 是否真跑满 |
| `bw_contention.sh` | 板端（root）| 带宽竞争：NPU 压测叠加 DDR 压力，看 fps 是否下降 |
| `bw_hog.py` | 板端 | 上面的 DDR 带宽压力器 |
| `layer_profile.py` | 板端 | 逐层耗时剖析 |

### 素材路径

脚本默认读取：

| 模型 | 路径 |
|---|---|
| YOLOv5s 系列 | `~/rknn/models/yolov5s_relu.rknn` + `bus.jpg` |
| ResNet18 系列 | `/tmp/nputest/resnet18_for_rk3588.rknn` + `space_shuttle_224.jpg` |

对应文件都在本仓库 `../models/`，拷到上述路径即可。

---

## rknn-convert/ —— 模型转换与校验

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `convert_yolov5.py` | WSL2（PC）| `.onnx` → `.rknn`（INT8 量化），说明见本目录 `README.md` |
| `verify_rknn_on_board.sh` | 本机 | 把转好的 `.rknn` 推板，跑单核 / 三核基准对照 |
| `inspect_onnx_ops.py` | WSL2 | 统计 ONNX 的算子构成（判断 NPU 支持度）|
| `inspect_rknn_api.sh` | 板端 | 导出 RKNN Runtime 的 API 与版本信息 |
| `op_roofline.py` | 本机 | 按算子类型估算 roofline，找理论瓶颈 |
| `traffic_map.py` | 本机 | 估算逐层访存量 |
| `traffic_by_op.py` | 本机 | 按算子聚合访存量 |

WSL 环境搭建见 `../WSL/README.md`；转换产物见 `../models/`。
