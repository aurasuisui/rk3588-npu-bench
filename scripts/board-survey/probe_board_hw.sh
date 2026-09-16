#!/bin/bash
# probe_board_hw.sh — ZYSJ-2288A 硬件能力普查（只读）
# 目的是回答「这块板除 NPU 外还能干什么」，按子系统逐项探测真实可用的设备节点。
echo "########## 0. 板型 ##########"
cat /proc/device-tree/model 2>/dev/null; echo
tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null; echo

echo
echo "########## 1. CPU / GPU / NPU ##########"
lscpu | grep -E "Model name|Architecture|CPU\(s\)|BogoMIPS|L1d|L2|L3" | head -8
echo "-- devfreq 域 --"; ls /sys/class/devfreq/
echo "-- GPU 可用频点 --"; cat /sys/class/devfreq/fb000000.gpu/available_frequencies 2>/dev/null

echo
echo "########## 2. VPU 视频编解码（RK3588 的隐藏王牌）##########"
lsmod | grep -iE "rkvdec|rkvenc|mpp|vpu|hantro" || echo "(模块未以 lsmod 形式出现，见下设备节点)"
ls -l /dev/mpp_service /dev/rga /dev/dri/card* /dev/dri/renderD* 2>/dev/null
echo "-- video 设备 --"; ls /dev/video* 2>/dev/null | tr '\n' ' '; echo
echo "-- v4l2 能力（若装了 v4l-utils）--"; v4l2-ctl --list-devices 2>/dev/null | head -30 || echo "v4l-utils 未安装"

echo
echo "########## 3. 显示输出 ##########"
for c in /sys/class/drm/card*/status; do [ -f "$c" ] && echo "$(dirname $c | xargs basename): $(cat $c)"; done
echo "-- 连接器 --"; ls /sys/class/drm/ | tr '\n' ' '; echo

echo
echo "########## 4. 音频 ##########"
aplay -l 2>/dev/null | head -20 || echo "alsa-utils 未安装"

echo
echo "########## 5. 网络 ##########"
ip -br link
echo "-- 无线 --"; ls /sys/class/net/ | tr '\n' ' '; echo

echo
echo "########## 6. USB / PCIe / SATA ##########"
lsusb 2>/dev/null | head -15 || echo "usbutils 未安装"
lspci 2>/dev/null | head -10 || echo "pciutils 未安装"
ls /sys/bus/pci/devices/ 2>/dev/null | head

echo
echo "########## 7. GPIO / I2C / SPI / UART / PWM ##########"
ls /dev/gpiochip* /dev/i2c-* /dev/spidev* /dev/pwm* 2>/dev/null | tr '\n' ' '; echo
echo "-- 串口 --"; ls /dev/ttyS* /dev/ttyFIQ* 2>/dev/null | tr '\n' ' '; echo
echo "-- gpiodetect --"; gpiodetect 2>/dev/null || echo "libgpiod 工具未安装"
echo "-- i2c 总线上有什么 --"; for b in /dev/i2c-*; do [ -e "$b" ] && echo "  $b:" && (i2cdetect -y -r ${b#/dev/i2c-} 2>/dev/null | tail -8 | head -8); done 2>/dev/null | head -40

echo
echo "########## 8. 存储 ##########"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null

echo
echo "########## 9. 容器 / 虚拟化 ##########"
for c in docker podman lxc qemu-system-aarch64; do printf '%-22s ' "$c"; command -v $c || echo "-"; done
docker --version 2>/dev/null

echo
echo "########## 10. 温控 / 电源 ##########"
for z in /sys/class/thermal/thermal_zone*; do printf '%s=%sC ' "$(cat $z/type 2>/dev/null)" "$(( $(cat $z/temp 2>/dev/null || echo 0) / 1000 ))"; done; echo
ls /sys/class/power_supply/ 2>/dev/null

echo
echo "########## 11. 已装的开发相关能力 ##########"
for c in gcc g++ cmake python3 node npm ffmpeg gst-launch-1.0 qmake; do printf '%-18s ' "$c"; command -v $c || echo "-"; done
echo "-- 视频/图形库 --"
for p in librockchip_mpp rockchip_mpp rga opencv4 gstreamer-1.0; do printf '%-22s ' "$p"; pkg-config --modversion $p 2>/dev/null || echo "-"; done
echo "########## 普查结束 ##########"
