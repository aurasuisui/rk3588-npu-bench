#!/bin/bash
# probe_board_npu.sh — 板端 NPU/RKNN 就绪体检（只读，sudo 已免密）
# 用法：板上 cd ~/scripts && ./probe_board_npu.sh
# 对照 NPU/RK3588-NPU-技术文档.md 判断每一节能否在 ZYSJ-2288A 上实操
echo "===== 0. 身份 ====="
hostname; uname -a; grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
echo
echo "===== 1. NPU 驱动（文档 §3.3 要求 > 0.9.2）====="
sudo cat /sys/kernel/debug/rknpu/version 2>&1 | head -5
sudo ls /sys/kernel/debug/rknpu/ 2>&1 | tr '\n' ' '; echo
echo "-- devfreq 节点（文档 §8.3/§11.2 用到的路径）--"
for d in /sys/class/devfreq/fdab0000.npu /sys/class/devfreq/dmc /sys/class/devfreq/fb000000.gpu; do
  printf '%-38s ' "$d"
  if [ -d "$d" ]; then printf 'cur=%s gov=%s\n' "$(cat $d/cur_freq 2>/dev/null)" "$(cat $d/governor 2>/dev/null)"; else echo MISSING; fi
done
echo "-- NPU 可用频点（核对 1000000000 在不在列表里）--"
cat /sys/class/devfreq/fdab0000.npu/available_frequencies 2>&1
echo
echo "===== 2. NPU 运行时（板端推理必需）====="
ls -l /usr/lib/librknnrt.so /usr/lib/librknn_api.so /usr/lib/librknnmrt.so 2>&1
find / -xdev -maxdepth 5 -name 'librknn*.so*' 2>/dev/null | head
find / -xdev -maxdepth 6 -name 'rknn_api.h' 2>/dev/null | head
echo
echo "===== 3. Python 侧（文档 §4.2 / §7.2 用 RKNNLite）====="
python3 -V; python3 -c 'import sys;print(sys.executable)'
python3 -c 'import rknnlite;print("rknnlite IMPORT OK")' 2>&1 | tail -2
python3 -c 'import numpy;print("numpy", numpy.__version__)' 2>&1 | tail -1
python3 -c 'import cv2;print("cv2", cv2.__version__)' 2>&1 | tail -1
pip3 -V 2>&1 | head -1
echo "-- 若需重装：whl 在 PC 的 RKNN-SDK/rknn-toolkit-lite2/packages/ --"
ls ~/*.whl ~/deps/*.whl /tmp/*.whl 2>/dev/null
echo
echo "===== 4. 编译能力（文档 §8 C++ 零拷贝要 g++/cmake）====="
for c in gcc g++ make cmake pkg-config clang; do printf '%-12s ' "$c"; command -v $c || echo MISSING; done
ls /usr/include/opencv4/opencv2/core.hpp 2>&1 | head -1
echo
echo "===== 5. 外网 ====="
timeout 6 getent hosts pypi.org >/dev/null 2>&1 && echo "DNS ok" || echo "DNS FAIL"
timeout 5 ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 && echo "ping 223.5.5.5 ok" || echo "ping 外网 FAIL"
if command -v curl >/dev/null 2>&1; then
  timeout 8 curl -sI -o /dev/null -w 'pypi.org http=%{http_code}\n' https://pypi.org || echo "curl 取 pypi 失败"
elif command -v wget >/dev/null 2>&1; then
  timeout 8 wget -q -O /dev/null --spider https://pypi.org && echo "wget https pypi ok" || echo "wget 取 pypi 失败"
else
  echo "curl / wget 都没有"
fi
timeout 10 apt-get -o Acquire::http::Timeout=5 -s install --no-download cmake >/dev/null 2>&1 && echo "apt 索引可用" || echo "apt 索引不可用"
echo
echo "===== 6. 资源 ====="
free -m | head -2; echo; df -h / | tail -1
for p in policy0 policy4 policy6; do printf '%-8s gov=%s cur=%s\n' "$p" "$(cat /sys/devices/system/cpu/cpufreq/$p/scaling_governor 2>/dev/null)" "$(cat /sys/devices/system/cpu/cpufreq/$p/scaling_cur_freq 2>/dev/null)"; done
printf 'thermal_zone0=%s（散热已改造：外接风道，可长时间满载；但跑高能耗前需机主调风道）\n' "$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
echo
echo "===== 7. ADB（文档 §3.3 远程调试前提）====="
printf 'adb 客户端   : '; command -v adb || echo MISSING
printf 'adbd 进程    : '; pgrep -a adbd || echo 未运行
printf 'TCP 5555     : '; ss -ltn 2>/dev/null | grep -q 5555 && echo 监听中 || echo 未监听
printf 'UDC（USB设备模式）: '; ls /sys/class/udc/ 2>/dev/null | tr '\n' ' '; [ -n "$(ls /sys/class/udc/ 2>/dev/null)" ] || echo '空（未插数据线/未进设备模式）'
sudo /usr/local/sbin/adbd-usb-gadget status 2>/dev/null | head -4
echo
echo "===== 8. RKLLM 运行时（文档 §10 大模型部署需要）====="
ls -l /usr/lib/librkllmrt.so /usr/lib/librkllm_api.so 2>&1
find / -xdev -maxdepth 5 -iname 'librkllm*' 2>/dev/null | head
echo
echo "===== 体检结束 ====="
