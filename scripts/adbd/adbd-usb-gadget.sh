#!/bin/bash
# /usr/local/sbin/adbd-usb-gadget — 用 configfs + FunctionFS 把板子做成 ADB USB 设备
# Google VID 0x18D1，Windows/Linux 的 adb 都能直接识别
set -e
G=/sys/kernel/config/usb_gadget/g1

setup() {
    UDC="$(ls /sys/class/udc 2>/dev/null | head -1)"
    if [ -z "$UDC" ]; then
        echo "没有 UDC（USB 控制器未处于设备模式），跳过 USB gadget 配置"
        exit 0
    fi
    modprobe libcomposite 2>/dev/null || true
    [ -d $G ] && reset
    mkdir -p $G
    cd $G
    echo 0x18D1 > idVendor
    echo 0x4EE7 > idProduct
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB
    mkdir -p strings/0x409
    echo "ZYSJ-2288A" > strings/0x409/manufacturer
    echo "RK3588 ADB device" > strings/0x409/product
    echo "$(cat /etc/machine-id)" > strings/0x409/serialnumber
    mkdir -p configs/c.1/strings/0x409
    echo "ADB" > configs/c.1/strings/0x409/configuration
    echo 500 > configs/c.1/MaxPower
    mkdir -p functions/ffs.adb
    ln -sf functions/ffs.adb configs/c.1/
    mkdir -p /dev/usb-ffs/adb
    mountpoint -q /dev/usb-ffs/adb || mount -t functionfs adb /dev/usb-ffs/adb
    echo "$UDC" > $G/UDC
    echo "USB gadget 已绑定到 $UDC"
}

reset() {
    [ -d $G ] || return 0
    echo '' > $G/UDC 2>/dev/null || true
    rm -f $G/configs/c.1/ffs.adb 2>/dev/null || true
    rmdir $G/configs/c.1/strings/0x409 $G/configs/c.1 $G/functions/ffs.adb \
          $G/strings/0x409 $G 2>/dev/null || true
    umount /dev/usb-ffs/adb 2>/dev/null || true
}

status() {
    echo "UDC          : $(ls /sys/class/udc 2>/dev/null | tr '\n' ' ')"
    echo "gadget g1    : $([ -d $G ] && echo 存在 || echo 无)"
    echo "已绑定 UDC   : $(cat $G/UDC 2>/dev/null)"
    echo "functionfs   : $(ls /dev/usb-ffs/adb/ 2>/dev/null | tr '\n' ' ')"
    echo "adbd 进程    : $(pgrep -a adbd || echo 未运行)"
    echo "TCP 5555     : $(ss -ltn 2>/dev/null | grep -q 5555 && echo 监听中 || echo 未监听)"
}

case "$1" in
    setup) setup ;;
    reset) reset ;;
    status) status ;;
    *) echo "用法: $0 {setup|reset|status}"; exit 1 ;;
esac

