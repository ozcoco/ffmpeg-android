#!/bin/bash
#
# Copyright 2016 Eng Chong Meng
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Uncomment the line below to see all script echo to terminal
# set -x
if [ "$ANDROID_NDK" = "" ]; then
	echo "You need to set ANDROID_NDK environment variable, exiting"
	echo "Use: export ANDROID_NDK=/your/path/to/android-ndk"
	echo "e.g.: export ANDROID_NDK=/opt/android/android-ndk-r17c"
	exit 1
fi
set -u

# Never mix two api level to build static library for use on the same apk.
# Set to API:15 for aTalk minimun support for platform API-15
# Does not build 64-bit arch if ANDROID_API is less than 21 - the minimum supported API level for 64-bit.
ANDROID_API=21
NDK_ABI_VERSION=4.9

# Built with command i.e. ./ffmpeg-android_build.sh or following with parameter [ABIS(x)]
# Create custom ABIS or uncomment to build all supported abi for ffmpeg.
# Do not change naming convention of the ABIS; see:
# https://developer.android.com/ndk/guides/abis.html#Native code in app packages
# ABIS=("armeabi" "armeabi-v7a" "arm64-v8a" "x86" "x86_64" "mips" "mips64")

# Android recommended architecture support; others are deprecated
ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")

BASEDIR=`pwd`
TOOLCHAIN_PREFIX=${BASEDIR}/toolchain-android

#===========================================
# Do not proceed on first call without the required 2 parameters
[[ $# -lt 2 ]] && return

NDK=${ANDROID_NDK}
HOST_NUM_CORES=$(nproc)

# https://gcc.gnu.org/onlinedocs/gcc-4.9.1/gcc/Optimize-Options.html
# Note: vpx with ABIs x86 and x86_64 build has error with option -fstack-protector-all
CFLAGS="-fpic -fpie -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -fno-strict-overflow -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2"
LDFLAGS=""

# Do not modify any of the NDK_ARCH, CPU and -march unless you are very sure.
# The settings are used by <ARCH>-linux-android-gcc and submodule configure
# https://en.wikipedia.org/wiki/List_of_ARM_microarchitectures
# $NDK/toolchains/llvm/prebuilt/...../includellvm/ARMTargetParser.def etc
# ARCH - should be one from $ANDROID_NDK/platforms/android-$API/arch-* [arm / arm64 / mips / mips64 / x86 / x86_64]"
# https://gcc.gnu.org/onlinedocs/gcc/AArch64-Options.html

case $1 in
  # Deprecated in r16. Will be removed in r17
  armeabi)
    CPU='armv5'
    HOST='arm-linux'
    NDK_ARCH="arm"
    NDK_ABIARCH='arm-linux-androideabi'
    CFLAGS="$CFLAGS -march=$CPU -mthumb"
    ASFLAGS=""
  ;;
  # https://gcc.gnu.org/onlinedocs/gcc-4.9.4/gcc/ARM-Options.html#ARM-Options
  armeabi-v7a)
    CPU='armv7-a'
    HOST='arm-linux'
    NDK_ARCH='arm'
    NDK_ABIARCH='arm-linux-androideabi'
    # clang70: warning: -Wl,--fix-cortex-a8: 'linker' input unused [-Wunused-command-line-argument]
    # CFLAGS="$CFLAGS -Wl,--fix-cortex-a8 -march=$CPU -mfloat-abi=softfp -mfpu=neon -mtune=cortex-a8 -mthumb -D__thumb__"
    CFLAGS="$CFLAGS -march=$CPU -mfloat-abi=softfp -mfpu=neon -mtune=cortex-a8 -mthumb -D__thumb__"
    ASFLAGS=""

    # 1. -march=$CPU flag targets the armv7 architecture.
    # 2. -mfloat-abi=softfp enables hardware-FPU instructions while ensuring that the system passes floating-point
    #     parameters in core registers, which is critical for ABI compatibility
    # 3. -mfpu=neon setting forces the use of VFPv3-D32, per the ARM specification
    # 4. -mthumb forces the generation of 16-bit Thumb-2 instructions (Thumb-1 for armeabi).
    #    If omitted, the toolchain will emit 32-bit ARM instructions.
    # 5. -Wl,--fix-cortex-a8 is required as a workaround for a CPU bug in some Cortex-A8 implementation (x264 flags as warning)
    #    Standalone toolchains does not accept this option. SDK toolchains (gcc/cg++) is ok.
    #    /home/cmeng/workspace/ndk/ffmpeg-android/toolchain-android/bin/arm-linux-androideabi-ld: -Wl,--fix-cortex-a8: unknown option
    # LDFLAGS="-Wl,--fix-cortex-a8"

    # arm v7vfpv3
    # CFLAGS="$CFLAGS -march=$CPU -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb"

    # arm v7 + neon (neon also include vfpv3-32)
    # CFLAGS="$CFLAGS -march=$CPU -mfloat-abi=softfp -mfpu=neon -mtune=cortex-a8 -mthumb -D__thumb__" 
  ;;
  arm64-v8a)
    # Valid cpu = armv8-a cortex-a35, cortex-a53, cortec-a57 etc. but -march=armv8-a is required
    # x264 build has own undefined references e.g. x264_8_pixel_sad_16x16_neon - show up when build with ffmpeg
    # -march valid only for ‘armv8-a’, ‘armv8.1-a’, ‘armv8.2-a’, ‘armv8.3-a’ or ‘armv8.4-a’ or native (only armv8-a is valid for lame build).
    CPU='cortex-a57'
    HOST='aarch64-linux'
    NDK_ARCH='arm64'
    NDK_ABIARCH='aarch64-linux-android'
    CFLAGS="$CFLAGS -march=armv8-a"
    ASFLAGS=""
  ;;
  x86)
    CPU='i686'
    HOST='i686-linux'
    NDK_ARCH='x86'
    NDK_ABIARCH='i686-linux-android'
    CFLAGS="$CFLAGS -O2 -march=$CPU -mtune=intel -msse3 -mfpmath=sse -m32"
    ASFLAGS="-D__ANDROID__"
  ;;
  x86_64)
    CPU='x86-64' 
    HOST='x86_64-linux'
    NDK_ARCH='x86_64'
    NDK_ABIARCH='x86_64-linux-android'
    CFLAGS="$CFLAGS -O2 -march=$CPU -mtune=intel -msse4.2 -mpopcnt -m64"
    ASFLAGS="-D__ANDROID__"
  ;;

  # MIPS is deprecated in NDK r16 and will be removed in r17.
  # https://gcc.gnu.org/onlinedocs/gcc/MIPS-Options.html#MIPS-Options
  # https://en.wikipedia.org/wiki/List_of_MIPS_architecture_processors
  mips)
    # unknown cpu - optimization disable
    CPU='p5600'
    HOST='mips-linux'
    NDK_ARCH='mips'
    NDK_ABIARCH="mipsel-linux-android"
    CFLAGS="$CFLAGS -EL -march=$CPU -mhard-float"
    ASFLAGS=""
  ;;
  mips64)
    # -march=mips64r6 works for clangs but complain by ffmpeg (use -march=$CPU), reverse effect when -march=i6400 - so omit it in CFLAG works for both
    CPU='i6400'
    HOST='mips64-linux'
    NDK_ARCH='mips64'
    NDK_ABIARCH='mips64el-linux-android'
    CFLAGS="$CFLAGS -EL -mfp64 -mhard-float"
    ASFLAGS=""
  ;;
esac

# old .sh script has been replaced with .py below
# Version r19b => Instead use:
#    $ $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang++ src.cpp

# cmeng: must ensure AS JNI uses the same STL library or "system" if specified
# Create standalone toolchains for the specified architecture - use .py instead of the old .sh
  [ -d ${TOOLCHAIN_PREFIX} ] || python $NDK/build/tools/make_standalone_toolchain.py \
    --arch ${NDK_ARCH} \
    --api ${ANDROID_API} \
    --stl libc++ \
    --install-dir=${TOOLCHAIN_PREFIX}

NDK_SYSROOT=${TOOLCHAIN_PREFIX}/sysroot

# Define the install directory of the libs and include files etc
# lame needs absolute path
PREFIX=${BASEDIR}/jni/$2/android/$1
# PREFIX=../jni/$2/android/$1

# Add the standalone toolchain to the search path.
export PATH=${TOOLCHAIN_PREFIX}/bin:$PATH
export CROSS_PREFIX=${TOOLCHAIN_PREFIX}/bin/${NDK_ABIARCH}-
export CFLAGS="${CFLAGS}"
export CPPFLAGS="${CFLAGS}"
export CXXFLAGS="${CFLAGS} -std=c++11"
export ASFLAGS="${ASFLAGS}"
export LDFLAGS="${LDFLAGS} -L${NDK_SYSROOT}"

export AR="${CROSS_PREFIX}ar"
export AS="${CROSS_PREFIX}clang"
export CC="${CROSS_PREFIX}clang"
export CXX="${CROSS_PREFIX}clang++"
export LD="${CROSS_PREFIX}ld"
export STRIP="${CROSS_PREFIX}strip"
export RANLIB="${CROSS_PREFIX}ranlib"
export OBJDUMP="${CROSS_PREFIX}objdump"
export CPP="${CROSS_PREFIX}cpp"
export GCONV="${CROSS_PREFIX}gconv"
export NM="${CROSS_PREFIX}nm"
export SIZE="${CROSS_PREFIX}size"
export PKG_CONFIG="${CROSS_PREFIX}pkg-config"
export PKG_CONFIG_LIBDIR=${PREFIX}/lib/pkgconfig
export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig

echo "use NDK=${NDK}"
echo "use ANDROID_API=${ANDROID_API}"
echo "PREFIX=${PREFIX}"

