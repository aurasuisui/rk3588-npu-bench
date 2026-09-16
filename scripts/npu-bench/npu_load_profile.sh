#!/bin/bash
# npu_load_profile.sh — 压测期间逐秒采样 NPU 三核负载，判断 NPU 是否真的跑满
# 用法：sudo ./npu_load_profile.sh [秒数]
SECS=${1:-15}
MODEL=$HOME/rknn/models/yolov5s_relu.rknn
IMG=$HOME/rknn/models/bus.jpg
BENCH=$HOME/scripts/npu-bench/zero_copy_bench

echo "=== 锁频（CPU / NPU / GPU）==="
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo userspace > "$p/scaling_governor" 2>/dev/null
  echo "$(cat $p/cpuinfo_max_freq)" > "$p/scaling_setspeed" 2>/dev/null
done
echo userspace > /sys/class/devfreq/fdab0000.npu/governor 2>/dev/null
echo 1000000000 > /sys/class/devfreq/fdab0000.npu/userspace/set_freq 2>/dev/null
echo userspace > /sys/class/devfreq/fb000000.gpu/governor 2>/dev/null
echo 1000000000 > /sys/class/devfreq/fb000000.gpu/userspace/set_freq 2>/dev/null
for x in npu gpu dmc; do
  d=$(ls -d /sys/class/devfreq/*$x* 2>/dev/null | head -1)
  [ -n "$d" ] && printf '  %-18s gov=%s cur=%s\n' "$(basename $d)" "$(cat $d/governor)" "$(cat $d/cur_freq)"
done

echo
echo "=== 启动零拷贝压测（8 线程三核，${SECS}s）并逐秒采样 ==="
"$BENCH" "$MODEL" "$IMG" "$SECS" 1 8 > /tmp/bench_out.txt 2>/dev/null &
BPID=$!
sum0=0; sum1=0; sum2=0; n=0
for i in $(seq 1 $SECS); do
  L=$(cat /sys/kernel/debug/rknpu/load 2>/dev/null)
  c0=$(echo "$L" | grep -oP 'Core0:\s*\K[0-9]+')
  c1=$(echo "$L" | grep -oP 'Core1:\s*\K[0-9]+')
  c2=$(echo "$L" | grep -oP 'Core2:\s*\K[0-9]+')
  printf 't=%2ds  Core0=%3s%%  Core1=%3s%%  Core2=%3s%%\n' "$i" "$c0" "$c1" "$c2"
  sum0=$((sum0+c0)); sum1=$((sum1+c1)); sum2=$((sum2+c2)); n=$((n+1))
  sleep 1
done
wait $BPID
echo
echo "=== 平均负载 ==="
awk -v a="$sum0" -v b="$sum1" -v c="$sum2" -v n="$n" 'BEGIN{printf "  Core0=%.1f%%  Core1=%.1f%%  Core2=%.1f%%  三核均值=%.1f%%\n", a/n, b/n, c/n, (a+b+c)/(3*n)}'
echo
echo "=== 压测结果 ==="
grep -E "吞吐|平均单核延迟|线程分布|NPU 频率|DDR 频率" /tmp/bench_out.txt
