# RK3588 NPU 部署与性能优化

在 RK3588 工控板上打通 AI 模型从 ONNX 到板端推理的完整链路，并对三核 NPU 做系统性的基准测试与算力压榨。

配套测量报告（已提交至上游）：**[hannahrepo/rk3588-npu#2](https://github.com/hannahrepo/rk3588-npu/issues/2)**

---

## 硬件与环境

| 项 | 值 |
|---|---|
| 板卡 | 众云世纪 ZYSJ-2288A v2.0（RK3588 OEM 工控板，二手购入）|
| SoC | RK3588：4×Cortex-A76 + 4×Cortex-A55，aarch64 |
| NPU | 三核，合计 6 TOPS (INT8) |
| 内存 / 存储 | 8 GB LPDDR4 / 64 GB eMMC |
| 系统 | Ubuntu 22.04.5 LTS，内核 5.10.226（无头模式）|
| NPU 驱动 | RKNPU v0.9.8 |
| NPU 运行时 | librknnrt 2.3.2 |
| 工具链 | rknn-toolkit2 2.3.2（PC / WSL2）、rknn_toolkit_lite2 2.3.2（板端）|
| 散热 | 外接独立风道；满载峰值 28.7–39 ℃，无降频 |

**所有测试均在锁频条件下进行**（A55 1.8 G / A76 2.304 G / NPU 1.0 G / GPU 1.0 G / DDR 1.848 G），
否则数据不可比。锁频脚本见 `scripts/npu-bench/fix_freq_rk3588.sh`。

---

## 一、端到端部署链路

```
ONNX ──[WSL2 x86_64 + rknn-toolkit2 2.3.2]──> .rknn (INT8)
                                                │ scp
                                                ▼
                              RK3588 板端 librknnrt 2.3.2 推理
```

- `.rknn` 转换**只能在 x86_64 Linux 上完成**（无 Windows 轮子；aarch64 轮子链接 x86_64 专用模拟器，板上跑不了）
- 因此走 WSL2。官方 `wsl --install` 走 Canonical 海外源且不可换源，改为**自下 rootfs + `wsl --import`**
- 实测 `yolov5s_relu.onnx`（27.6 MB）→ `yolov5s_relu.rknn`（**8.39 MB INT8**），整条 **4.3 秒**

**三个版本坑**（根因均为官方 requirements 只写下界不写上界）：

| 现象 | 根因 | 解法 |
|---|---|---|
| `module 'onnx' has no attribute 'mapping'` | 装到 1.22，该版删除了 `mapping` | `onnx==1.16.1` |
| `No module named 'pkg_resources'` | setuptools 升到 84，81+ 已移除 | `setuptools<81` |
| torch 下载 2 GB+ | 默认 PyPI 的 torch 是 CUDA 版 | 加 CPU 索引，装 `torch==2.4.0+cpu` |

> 板端另需解决：Ubuntu 22.04 源里**没有 adbd 包**，已从 Debian 源码自编 adbd 34.0.5 并由 systemd 常驻。
> 见 `scripts/adbd/`。

---

## 二、性能演进链复现（YOLOv5s 640×640）

以一套公开的 RK3588 NPU 优化方案为参照，用**自写程序**把「锁竞争拖垮 → 多进程三核 → C++ 零拷贝」三段式路径完整复现：

| # | 方案 | 程序 | 实测 | 参照值 |
|---|------|------|------|--------|
| 1 | Python 单进程 | `board_stress_test_6p.py` | 38.0 fps | — |
| 2 | Python 16 线程单核（**反例**） | `board_stress_test_16t.py` | **28.2 fps** | 36 fps |
| 3 | Python 三核绑定 ×3 进程 | `board_stress_test_6p.py` | 107.1 fps | — |
| 4 | Python 三核绑定 ×6 进程 | `board_stress_test_6p.py` | **118.7 fps** | 119 fps |
| 5 | Python 三核绑定 ×9 进程 | `board_stress_test_6p.py` | 121.4 fps | — |
| 6 | C++ 单核单上下文 | `rknn_benchmark 1` | 15.98 ms / 62.6 fps | 18.8 ms / 53 fps |
| 7 | C++ 三核协同单上下文 | `rknn_benchmark 7` | 8.79 ms / 113.8 fps | — |
| 8 | C++ 零拷贝 3 线程 | `zero_copy_bench` | 173.6 fps | — |
| 9 | **C++ 零拷贝 8 线程** | `zero_copy_bench` | **177.6 fps** | 181+ fps |

关键数字复现到参照值的 **97%–100%**。

**反例确认**：16 线程共享一把锁时，线程分布 `[43,13,25,18,19,13,14,27,22,15,12,20,14,15,18,10]` 极不均匀，
吞吐 38.0 → 28.2 fps。本板 8 核的切换开销更大，掉幅比参照值更显著。

---

## 三、线程数饱和点（核心实验）

**问题**：C++ 零拷贝路径下，NPU 在「1 线程/核」时是否已经饱和？上游 `main.cc` 的 `NUM_THREADS 8` 是否必要？
（该行注释为 `// Adjusted to 8 threads as requested`，说明未经推导。）

**方法**：交错执行 5 轮（A B C D E × 5，避免温度/状态漂移的时间偏倚），每组预热 5 s / 计时 30 s / 冷却 10 s，
同时以 200 ms 间隔采样 `/sys/kernel/debug/rknpu/load` 与各域频率。另设独立确认实验。

### 吞吐（5 轮均值 ± 样本标准差）

| 每核线程 | 总线程 | 吞吐 | 相对平台 |
|---|---|---|---|
| **1** | **3** | **173.57 ± 0.09 fps** | **98.0%** |
| **2** | **6** | **177.10 ± 0.32 fps** | **100%（起点）** |
| 2.67 | 8（上游配置） | 177.32 ± 0.05 fps | +0.12% |
| 3 | 9 | 177.12 ± 0.14 fps | +0.01% |
| 4 | 12 | 176.86 ± 0.07 fps | −0.14% |

### 逐核 NPU 占用（稳态）

| 总线程 | Core0 | Core1 | Core2 |
|---|---|---|---|
| 3 | 96% | 96% | 96% |
| 6 及以上 | 98% | 98% | 98% |

### 结论

1. **1 线程/核 已达峰值吞吐的 98.0%**，NPU 占用稳定 96%（未满）
2. **饱和点在 2 线程/核**：占用升到 98% 后，再加线程零收益
3. **6 线程与 8 线程等价**（差 0.12%）：`NUM_THREADS 8` 无害，但并非必需；取 6（整数 2/核）负载天然均分
4. 3→6 的 +2.04% **真实且可复现**（n = 15，两轮独立实验的 3 线程均值完全一致；t = 26.7，df = 13，p < 0.0001）

**线程数只在 1→2 线程/核 这一段是杠杆，之后完全不是。**

### 换模型交叉验证

| 模型 | 单帧纯 NPU 时间 | 3 线程 | 6 线程 | 3 线程占峰值 | 3 线程逐核占用 |
|---|---|---|---|---|---|
| YOLOv5s 640 | 16.00 ms | 173.6 fps | 177.1 fps | 98.0% | 96 / 96 / 96 |
| ResNet18 224 | 3.82 ms | 743.6 fps | 761.1 fps | 97.7% | 96 / 96 / 97 |

单帧时间差 4.2 倍，饱和行为几乎重合 → **在单帧 ≳ 4 ms 区间内，饱和点固定在 2 线程/核，与模型大小无关**
（本板现有模型都在此区间，更小的未覆盖）。

另：探路扫描到 24 线程，超过 6 线程后**单调下降**：760.9 → 759.3 → 757.8 → 754.7 → 753.4 fps。

### 并发正确性

线程数 3→24、并发 1→4/核，全部 33 组输出校验和**逐字节一致**。
另验证零拷贝的两条输入路径（`pass_through=1` 自量化 INT8 vs `pass_through=0` 交 NPU 量化的 UINT8）输出完全相同。

> 完整报告：**[上游 issue #2](https://github.com/hannahrepo/rk3588-npu/issues/2)**
> 原始数据：`data/bench-raw-20260915/`

---

## 目录结构

```
.
├── README.md                  本文件
├── NPU/
│   ├── 本板实操.md             部署与性能压榨全过程记录（含逐节可行性核验）
│   ├── 线程数饱和点.md          饱和点实验的方案、原始结论与判读
│   └── 上游issue-存档.md        提交至上游的测量报告存档
├── scripts/
│   ├── npu-bench/             基准测试与压测（含自写 C++ 零拷贝）
│   ├── rknn-convert/          ONNX → RKNN 转换与校验
│   ├── adbd/                  自编 adbd 与 USB gadget
│   └── board-survey/          板级硬件体检
├── WSL/README.md              WSL2 转换环境搭建记录
├── data/bench-raw-20260915/   原始实测数据（128 个文件）
└── .gitignore
```

## 主要脚本

| 脚本 | 位置 | 作用 |
|---|---|---|
| `zero_copy_bench.cc` | 板端 | **自写**：`rknn_create_mem` + `pass_through` + 三核多上下文线程模型 |
| `build_zero_copy.sh` | 板端 | 原生编译（OpenCV4 走 pkg-config）|
| `fix_freq_rk3588.sh` | 板端 | 全域锁频，`restore` 子命令可还原 |
| `npu_sampler.sh` | 板端 | 200 ms 间隔采样 NPU 逐核占用/温度/频率 |
| `run_thread_saturation.sh` | 板端 | 主实验：交错 5 轮线程扫描 |
| `run_thread_sweep.sh` | 板端 | 通用「线程数 × 模型」扫描 |
| `analyze_thread_saturation.py` | 本机 | 汇总统计 |
| `convert_yolov5.py` | WSL2 | ONNX → RKNN INT8 转换 |
| `probe_board_npu.sh` | 板端 | NPU/RKNN/编译链/外网 八项只读体检 |

## 原始数据

`data/bench-raw-20260915/` 共 128 个文件：

- `*.log`（66 个）—— 每轮的 fps、帧数、输出校验和、频率
- `*.samples`（62 个）—— 每 200 ms 的 NPU 逐核占用 / 温度 / 频率

**采样格式**：

```
时间戳|NPU load: Core0: N%, Core1: N%, Core2: N%,|温度(m℃)|NPU频率(Hz)|DDR频率(Hz)|/proc/stat cpu 行
```

> ⚠️ **分析时先丢弃开头约 5 s（≈25 个采样）**。采样器先于压测启动，前几秒是负载爬坡
> （取值走 `0 → 3 → 87 → 稳态` 的台阶），算均值时包含它会显著偏低。

> ⚠️ `r1-t1-n3.samples`（1.15 MB，是其他文件的约 50 倍）**不具参考价值**：
> 启动前一次中止操作使用了 `pkill -f`，模式串匹配到 SSH 命令行本身，
> 导致残留压测进程与第 1 轮抢占 NPU（该轮 142.67 fps，其余 4 轮 173.4–173.7），
> 同时采样器未被终止，实际采集约 29 分钟。确认实验已加入开跑前显式清理。

## 复现

```bash
# ① 锁频（必须先做，否则数据不可比）
sudo ./scripts/npu-bench/fix_freq_rk3588.sh

# ② 主实验：交错 5 轮（约 19 分钟）
sudo bash ./scripts/npu-bench/run_thread_saturation.sh

# ③ 确认实验：3/6 线程干净对照
sudo bash ./scripts/npu-bench/confirm_3v6.sh 3 30

# ④ 汇总
python3 ./scripts/npu-bench/analyze_thread_saturation.py
```

脚本中的路径默认基于 `$HOME`，板端用户与 SSH 别名需按自己环境调整。

---

## 说明

- 本仓库的测试方法参照了公开的 RK3588 NPU 优化方案（见上游 issue 中的引用），
  但**所有代码为本仓库自写、所有数据为本人实测**，未转载第三方材料。
- 参照方案本身的文档与视频文稿不在本仓库中。
