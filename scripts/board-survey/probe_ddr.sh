#!/bin/bash
# probe_ddr.sh — DDR 带宽相关旋钮普查
echo "########## 1. DMC debugfs（找带宽监控器）##########"
sudo ls -R /sys/kernel/debug/dmc/ 2>/dev/null | head -40 || echo "(无 /sys/kernel/debug/dmc)"

echo
echo "########## 2. devfreq/dmc 全部属性 ##########"
ls /sys/class/devfreq/dmc/ 2>/dev/null | tr '\n' ' '; echo
for f in governor available_governors cur_freq available_frequencies min_freq max_freq; do
  printf '  %-24s %s\n' "$f" "$(cat /sys/class/devfreq/dmc/$f 2>/dev/null)"
done
echo "  -- 是否有 freq_table / stats --"
ls /sys/class/devfreq/dmc/ | grep -iE "stat|load|trans|table" || echo "  无"

echo
echo "########## 3. DDR QoS / 优先级节点 ##########"
sudo find /sys/kernel/debug -maxdepth 2 -iname "*qos*" -o -maxdepth 2 -iname "*ddr*" -o -maxdepth 2 -iname "*bandwidth*" 2>/dev/null | head -20
sudo ls /sys/kernel/debug/ 2>/dev/null | tr '\n' ' '; echo

echo
echo "########## 4. 显示控制器是否在扫描输出（白吃带宽？）##########"
for c in /sys/class/drm/card0-DSI-1 /sys/class/drm/card0-DSI-2 /sys/class/drm/card0-HDMI-A-1; do
  [ -d "$c" ] || continue
  echo "  $(basename $c): status=$(cat $c/status 2>/dev/null) enabled=$(cat $c/enabled 2>/dev/null) modes=[$(cat $c/modes 2>/dev/null | tr '\n' ' ')]"
done
echo "  -- framebuffer 占用 --"
sudo cat /sys/kernel/debug/dri/0/framebuffer 2>/dev/null | head -8 || echo "  (无)"
echo "  -- 是否有进程持有 /dev/dri/card* --"
sudo fuser -v /dev/dri/card0 2>&1 | head -5

echo
echo "########## 5. 当前谁在跑（load / 中断）##########"
uptime
echo "  -- 中断统计 TOP --"
grep -E "dwc3|eth|mali|rknpu|rga|mpp|vdec|venc|dsi|vop" /proc/interrupts 2>/dev/null | awk '{n=$2+$3+$4+$5+$6+$7+$8+$9; if(n>0) printf "  %-30s %d\n", $1, n}' | head -12

echo
echo "########## 6. 内存布局 / CMA ##########"
grep -E "CmaTotal|CmaFree|MemTotal|MemAvailable" /proc/meminfo
echo "  -- zram --"; cat /sys/block/zram0/disksize 2>/dev/null; swapon --show 2>/dev/null || echo "  无 swap"

echo
echo "########## 7. DDR 相关内核参数 ##########"
sudo cat /proc/cmdline
echo "  -- 内核里 DDR/DMC 配置 --"
zcat /proc/config.gz 2>/dev/null | grep -iE "CONFIG_ROCKCHIP_DMC|DDR|DEVFREQ_GOV" | head -10
