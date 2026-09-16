#!/bin/bash
# probe_board_hw2.sh — 第二轮：决定「能不能玩」的关键能力
echo "########## A. GStreamer 硬解插件（决定视频玩法是否开箱可用）##########"
gst-inspect-1.0 2>/dev/null | grep -iE "rockchip|rkmpp|mpp|v4l2|wayland|kmssink" | head -20
echo "-- 插件总数 --"; gst-inspect-1.0 2>/dev/null | tail -3

echo
echo "########## B. 硬件编解码器节点（V4L2 M2M）##########"
for d in /sys/class/video4linux/video*; do
  n=$(basename $d); nm=$(cat $d/name 2>/dev/null)
  case "$nm" in *rkvenc*|*rkvdec*|*rkisp*|*rkcif*|*hdmirx*|*rgb*|*scale*)
    printf '%-10s %s\n' "$n" "$nm";; esac
done | head -30

echo
echo "########## C. HDMI 输入（fdee0000.hdmirx）—— 能当采集卡？##########"
ls /sys/class/video4linux/ | wc -l
dmesg 2>/dev/null | grep -i hdmirx | tail -3

echo
echo "########## D. RGA 2D 加速 / MPP 库 ##########"
ls -l /dev/rga /dev/mpp_service
ldconfig -p 2>/dev/null | grep -iE "rga|mpp|mali|OpenCL" | head -12

echo
echo "########## E. GPU 通用计算 ##########"
ls /dev/dri/renderD*
ldconfig -p 2>/dev/null | grep -i mali
ls /usr/lib/aarch64-linux-gnu/libmali* 2>/dev/null
clinfo 2>/dev/null | head -8 || echo "(clinfo 未装)"

echo
echo "########## F. Docker 现状 ##########"
sudo docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Docker Root|Registry Mirrors" -A2 | head -12
sudo docker images 2>/dev/null | head -8

echo
echo "########## G. USB 3.0 端口 / 存储扩展 ##########"
for h in /sys/bus/usb/devices/usb*; do
  [ -f "$h/speed" ] && echo "$(basename $h): speed=$(cat $h/speed) ports=$(cat $h/maxchild 2>/dev/null)"
done
ls /sys/class/ata_port 2>/dev/null && echo "有 SATA" || echo "无 SATA 控制器"
ls /dev/nvme* 2>/dev/null || echo "无 NVMe"

echo
echo "########## H. 软件包现状（决定缺什么要装）##########"
for c in ffmpeg v4l2-ctl gst-launch-1.0 i2cdetect gpiodetect clinfo docker python3 uv; do
  printf '%-18s ' "$c"; command -v $c || echo "-"
done

echo
echo "########## I. 内核里编进去的 Rockchip 驱动 ##########"
zcat /proc/config.gz 2>/dev/null | grep -iE "CONFIG_VIDEO_ROCKCHIP|RK_VPU|RKNPU|MALI|CONFIG_DRM_ROCKCHIP|RGA" | head -15 || echo "(无 /proc/config.gz)"
echo "########## 结束 ##########"
