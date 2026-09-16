#!/bin/bash
# build_adbd.sh — 在板子上从 Debian 源码编译 adbd（AOSP 34.0.5），产物 /usr/local/sbin/adbd
#
# 背景：Ubuntu 22.04 源里没有 adbd；Debian 的现成二进制要 glibc>=2.38 装不上。
# 所以用 Debian 的源码 + 板子自己的 clang/gcc 编译。
# 依赖（一次性）：sudo apt install -y clang libcap-dev libssl-dev protobuf-compiler \
#                 libprotobuf-dev libbrotli-dev liblz4-dev libzstd-dev libsystemd-dev \
#                 android-libboringssl-dev
set -e
WORK=${WORK:-/tmp/adbsrc2}
SRC=${SRC:-$HOME/Transmission/adbd-build}

mkdir -p "$WORK/compat" && cd "$WORK"

# 1) 取源码（原始下载物放 ~/Transmission/adbd-build/）
for f in android-platform-tools_34.0.5.orig.tar.xz android-platform-tools_34.0.5-13.debian.tar.xz; do
    [ -f "$f" ] || cp "$SRC/$f" .
done
tar xf android-platform-tools_34.0.5.orig.tar.xz
tar xf android-platform-tools_34.0.5-13.debian.tar.xz

# 2) 打补丁：跳过 4 个 arm64 用不上的 MIPS 补丁，其余全部应用
ok=0; fail=0
for p in $(sed 's/#.*//' debian/patches/series); do
    case "$p" in *mips*|*Mips*|*MIPS*) continue;; esac
    if patch -p1 --forward --no-backup-if-mismatch < debian/patches/$p >/dev/null 2>&1; then
        ok=$((ok+1)); else fail=$((fail+1)); echo "FAIL $p"; fi
done
echo "补丁 ok=$ok fail=$fail"

# 3) 生成 protobuf 代码
(cd packages/modules/adb && protoc --cpp_out=. proto/*.proto)

# 4) 兼容垫片：补板载 AOSP10 老库缺失的符号
[ -f compat/compat.cpp ] || cp "$SRC/compat.cpp" compat/
[ -f compat/compat.h ]   || cp "$SRC/compat.h"   compat/

export DEB_HOST_MULTIARCH=aarch64-linux-gnu PLATFORM_TOOLS_VERSION=34.0.5 DEB_VERSION=34.0.5-13
export CC=clang CXX=clang++
INC='-I'"$WORK"'/compat -I/usr/include/android -Isystem/libbase/include -Isystem/logging/liblog/include -Isystem/core/include'
F="-O2 -fPIC -std=gnu++2a -fno-exceptions -fno-strict-aliasing -DNDEBUG -UDEBUG -Wno-narrowing $INC -include $WORK/compat/compat.h"
mkdir -p debian/out/system

# 5) 编静态库 + adbd 对象
make -f debian/system/libadb.mk           CXXFLAGS="$F" -j6
make -f debian/system/libcrypto_utils.mk  CXXFLAGS="$F" -j6
make -f debian/system/adbd.mk             CXXFLAGS="$F" -j6 || true   # 只到链接会失败，正常
clang++ -c -o compat/compat.o compat/compat.cpp $F

# 6) 手工链接（把垫片排在库前面）
OBJS=$(ls packages/modules/adb/*.adbd.o packages/modules/adb/daemon/*.adbd.o \
         packages/modules/adb/libs/adbconnection/*.adbd.o packages/modules/adb/libs/libadbd_fs/*.adbd.o \
         system/core/diagnose_usb/*.adbd.o system/core/libasyncio/*.adbd.o \
         frameworks/native/libs/adbd_auth/*.adbd.o | tr '\n' ' ')
clang++ -o debian/out/system/adbd $OBJS compat/compat.o \
    debian/out/system/libadb.a debian/out/system/libcrypto_utils.a \
    -Ldebian/out/system -L/usr/lib/aarch64-linux-gnu/android -Wl,-rpath=/usr/lib/aarch64-linux-gnu/android \
    -lbase -lbrotlidec -lbrotlienc -lcrypto -lcutils -llog -llz4 -lprotobuf -lresolv -lssl -lsystemd -lzstd -pie

# 7) 装
sudo install -m755 debian/out/system/adbd /usr/local/sbin/adbd
echo ">>> 完成：/usr/local/sbin/adbd"
/usr/local/sbin/adbd --version
