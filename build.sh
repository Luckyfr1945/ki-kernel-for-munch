#!/bin/bash
# Universal Ki-Kernel Build Script for SM8250 (munch / alioth / etc.)
# Supports: AOSP / Custom ROM & MIUI / HyperOS
# Usage: bash build.sh <target_device> [variant] [target_os]
#   variant   : ksu (default) | nosusfs | noksu
#   target_os : aosp (default) | miui | both

set -e

TARGET_DEVICE=$1
KERNEL_NAME="Ki-kernel"
KERNEL_VERSION="v1.4"
BUILD_DATETIME=$(date +'%Y%m%d_%H%M')

if [ -z "$1" ]; then
    echo "=========================================================="
    echo "  Ki-Kernel Build Script ($KERNEL_VERSION)"
    echo "=========================================================="
    echo "Usage: bash build.sh <target_device> [variant] [target_os]"
    echo ""
    echo "Arguments:"
    echo "  target_device : munch, alioth, apollo, lmi, umi, etc."
    echo "  variant       : ksu (default) | nosusfs | noksu"
    echo "  target_os     : aosp (default) | miui | both"
    echo ""
    echo "Examples:"
    echo "  bash build.sh munch ksu aosp   # Build AOSP with ReSukiSU + SuSFS"
    echo "  bash build.sh munch ksu miui   # Build MIUI/HyperOS with ReSukiSU + SuSFS"
    echo "  bash build.sh munch ksu both   # Build Universal Dual-OS zip"
    echo "=========================================================="
    exit 1
fi

# Detect Toolchain (ZyCromerZ Clang 16 > Neutron > Proton)
ZYC_PATH=$HOME/zyc-clang/bin
NEUTRON_PATH=$HOME/neutron-clang/bin
PROTON_PATH=$HOME/proton-clang/proton-clang-20210522/bin

if [ -d "$ZYC_PATH" ]; then
    export PATH="$ZYC_PATH:$PATH"
    echo "Using Toolchain: ZyCromerZ Clang 16 ($ZYC_PATH)"
elif [ -d "$NEUTRON_PATH" ]; then
    export PATH="$NEUTRON_PATH:$PATH"
    echo "Using Toolchain: Neutron Clang ($NEUTRON_PATH)"
elif [ -d "$PROTON_PATH" ]; then
    export PATH="$PROTON_PATH:$PATH"
    echo "Using Toolchain: Proton Clang ($PROTON_PATH)"
else
    echo "Error: No suitable Clang toolchain found."
    exit 1
fi

if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
    echo "[aarch64-linux-gnu-ld] not found in environment."
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    echo "[clang] not found in environment."
    exit 1
fi

# Prioritize ZyC Clang 16 if available
if [ -d "$HOME/zyc-clang/bin" ]; then
    export PATH="$HOME/zyc-clang/bin:$PATH"
    echo "Using ZyC Clang: [$HOME/zyc-clang/bin]"
fi

# Enable ccache for fast compiling
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
export CC="ccache gcc"
export CXX="ccache g++"
export PATH="/usr/lib/ccache/bin:/usr/lib/ccache:$PATH"
echo "CCACHE_DIR: [$CCACHE_DIR]"

export KBUILD_BUILD_USER="build-user"
export KBUILD_BUILD_HOST="build-host 4.19.404R"

MAKE_ARGS="ARCH=arm64 SUBARCH=arm64 O=out CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip HOSTCC=$PWD/tools/hostcc HOSTLD=/usr/bin/ld.bfd CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- CLANG_TRIPLE=aarch64-linux-gnu-"

if [ ! -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    echo "Error: arch/arm64/configs/${TARGET_DEVICE}_defconfig not found."
    exit 1
fi

echo "[clang --version]:"
clang --version

# Parse Variant (Root / SuSFS)
KSU_ENABLE=1
SUSFS_ENABLE=1
VARIANT_TAG="ReSukiSU+SUSFS"

case "$2" in
    ksu|ksu-susfs|susfs|"")
        KSU_ENABLE=1
        SUSFS_ENABLE=1
        VARIANT_TAG="ReSukiSU+SUSFS"
        ;;
    ksu-nosusfs|nosusfs|plain)
        KSU_ENABLE=1
        SUSFS_ENABLE=0
        VARIANT_TAG="ReSukiSU"
        ;;
    noksu|vanilla|none)
        KSU_ENABLE=0
        SUSFS_ENABLE=0
        VARIANT_TAG="NoKSU"
        ;;
    *)
        echo "Unknown variant: $2. Defaulting to ReSukiSU+SUSFS."
        KSU_ENABLE=1
        SUSFS_ENABLE=1
        VARIANT_TAG="ReSukiSU+SUSFS"
        ;;
esac

# Parse Target OS (aosp, miui, both)
TARGET_OS="${3:-aosp}"
case "$TARGET_OS" in
    aosp|miui|both|all) ;;
    *) TARGET_OS="aosp" ;;
esac

echo "=========================================================="
echo "Target Device : $TARGET_DEVICE"
echo "Kernel        : $KERNEL_NAME $KERNEL_VERSION"
echo "Variant       : $VARIANT_TAG"
echo "Target OS     : $TARGET_OS"
echo "=========================================================="

apply_ksu_config() {
    if [ $KSU_ENABLE -eq 1 ]; then
        scripts/config --file out/.config \
            -e KSU \
            -e THREAD_INFO_IN_TASK \
            -d KSU_KPROBES_HOOK \
            -d KSU_DEBUG \
            -d KSU_TRACEPOINT_HOOK \
            -e KSU_THRONE_TRACKER_ALWAYS_THREADED \
            -d KSU_ALLOWLIST_WORKAROUND \
            -e KSU_LSM_SECURITY_HOOKS \
            -d KSU_MANUAL_HOOK \
            -e KSU_SUSFS

        if [ $SUSFS_ENABLE -eq 1 ]; then
            scripts/config --file out/.config \
                -e KSU_SUSFS_SUS_PATH \
                -e KSU_SUSFS_SUS_MAP \
                -e KSU_SUSFS_SUS_NETLINK \
                -e KSU_SUSFS_AUTO_ADD_SUS_KSURULES \
                -e KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
                -e KSU_SUSFS_SUS_SU \
                -e KSU_SUSFS_SUS_MOUNT \
                -e KSU_SUSFS_SUS_KSTAT \
                -e KSU_SUSFS_SPOOF_UNAME \
                -e KSU_SUSFS_ENABLE_LOG \
                -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
                -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
                -e KSU_SUSFS_OPEN_REDIRECT \
                -e KSU_SUSFS_SUS_OVERLAYFS
        else
            scripts/config --file out/.config \
                -d KSU_SUSFS_SUS_PATH \
                -d KSU_SUSFS_SUS_MAP \
                -d KSU_SUSFS_SUS_NETLINK \
                -d KSU_SUSFS_AUTO_ADD_SUS_KSURULES \
                -d KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
                -d KSU_SUSFS_SUS_SU \
                -d KSU_SUSFS_SUS_MOUNT \
                -d KSU_SUSFS_SUS_KSTAT \
                -d KSU_SUSFS_SPOOF_UNAME \
                -d KSU_SUSFS_ENABLE_LOG \
                -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
                -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
                -d KSU_SUSFS_OPEN_REDIRECT \
                -d KSU_SUSFS_SUS_OVERLAYFS
        fi
    else
        scripts/config --file out/.config \
            -d KSU \
            -d KSU_MANUAL_HOOK \
            -d KSU_TRACEPOINT_HOOK \
            -d KSU_SUSFS
    fi
}

echo "Cleaning build directories..."
rm -rf out/ anykernel/
rm -rf build_artifacts 2>/dev/null || true
mkdir -p build_artifacts/aosp build_artifacts/miui

echo "Cloning AnyKernel3..."
git clone https://github.com/AstideLabs/AnyKernel3 -b kona --single-branch --depth=1 anykernel

local_version_date_str="-${BUILD_DATETIME}-${KERNEL_NAME}-${KERNEL_VERSION}"
sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"${local_version_date_str}\"/" arch/arm64/configs/${TARGET_DEVICE}_defconfig

# Pre-generate SELinux headers so KernelSU never races with parallel make
if [ ! -f "security/selinux/flask.h" ]; then
    echo "Pre-generating SELinux flask.h..."
    gcc -Iinclude/uapi -Iinclude -Isecurity/selinux/include scripts/selinux/genheaders/genheaders.c -o /tmp/genheaders
    /tmp/genheaders security/selinux/flask.h security/selinux/av_permissions.h
fi

# ------------------------------------------------------------
# BUILD AOSP
# ------------------------------------------------------------
if [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ] || [ "$TARGET_OS" == "all" ]; then
    echo ""
    echo ">>> Compiling Kernel for AOSP / Custom ROM <<<"
    rm -rf out/
    make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
    apply_ksu_config
    make $MAKE_ARGS olddefconfig
    make $MAKE_ARGS KCFLAGS="-O2" -j$(nproc)

    if [ ! -f "out/arch/arm64/boot/Image" ]; then
        echo "Error: AOSP Image compilation failed."
        exit 1
    fi

    echo "Compiling DTBs (Extreme UV + OC 683 MHz)..."
    cp -f arch/arm64/boot/dts/gpu_profiles/kona-v2-gpu-extreme.dtsi arch/arm64/boot/dts/vendor/qcom/kona-v2-gpu.dtsi
    rm -rf out/arch/arm64/boot/dts
    make $MAKE_ARGS dtbs -j$(nproc)
    if [ -f "out/arch/arm64/boot/dts/vendor/qcom/kona-v2.1.dtb" ]; then
        cp out/arch/arm64/boot/dts/vendor/qcom/kona-v2.1.dtb out/arch/arm64/boot/dtb
    else
        find out/arch/arm64/boot/dts -name '*.dtb' | sort | head -n 1 | xargs cat > out/arch/arm64/boot/dtb
    fi

    cp out/arch/arm64/boot/Image build_artifacts/aosp/Image
    cp out/arch/arm64/boot/dtb build_artifacts/aosp/dtb
    echo ">>> AOSP Build Done! <<<"
fi

# ------------------------------------------------------------
# BUILD MIUI / HyperOS
# ------------------------------------------------------------
if [ "$TARGET_OS" == "miui" ] || [ "$TARGET_OS" == "both" ] || [ "$TARGET_OS" == "all" ]; then
    echo ""
    echo ">>> Compiling Kernel for MIUI / HyperOS <<<"
    rm -rf out/
    make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
    apply_ksu_config

    # Enable MIUI hardware drivers, disable obsolete/hanging daemons
    scripts/config --file out/.config \
        --set-str STATIC_USERMODEHELPER_PATH "" \
        -d SF_BINDER \
        -d MILLET \
        -d MIGT \
        -d MIGT_ENERGY_MODEL \
        -d BOOTUP_RECLAIM \
        -d MI_RECLAIM \
        -d RTMM \
        -e XIAOMI_MIUI \
        -e TECHPACK_CAMERA_XIAOMI \
        -e OVERLAY_FS \
        -d DEBUG_FS \
        -e LTO_NONE \
        -d LTO_CLANG \
        -d LOCALVERSION_AUTO \
        -d MODULE_SIG_SHA512 \
        -d MODULE_SIG_HASH \
        -d CORESIGHT \
        -d IPC_LOGGING \
        -d SCHEDSTATS \
        -d DEBUG_INFO

    make $MAKE_ARGS olddefconfig
    make $MAKE_ARGS KCFLAGS="-O2" -j$(nproc)

    if [ ! -f "out/arch/arm64/boot/Image" ]; then
        echo "Error: MIUI Image compilation failed."
        exit 1
    fi

    echo "Compiling DTBs (Extreme UV + OC 683 MHz)..."
    cp -f arch/arm64/boot/dts/gpu_profiles/kona-v2-gpu-extreme.dtsi arch/arm64/boot/dts/vendor/qcom/kona-v2-gpu.dtsi
    rm -rf out/arch/arm64/boot/dts
    make $MAKE_ARGS dtbs -j$(nproc)
    if [ -f "out/arch/arm64/boot/dts/vendor/qcom/kona-v2.1.dtb" ]; then
        cp out/arch/arm64/boot/dts/vendor/qcom/kona-v2.1.dtb out/arch/arm64/boot/dtb
    else
        find out/arch/arm64/boot/dts -name '*.dtb' | sort | head -n 1 | xargs cat > out/arch/arm64/boot/dtb
    fi

    cp out/arch/arm64/boot/Image build_artifacts/miui/Image
    cp out/arch/arm64/boot/dtb build_artifacts/miui/dtb
    echo ">>> MIUI / HyperOS Build Done! <<<"
fi

# ------------------------------------------------------------
# PACKAGING ANYKERNEL3
# ------------------------------------------------------------
echo ""
echo ">>> Packaging AnyKernel3 Flashable Zip <<<"
rm -rf anykernel/kernels/ anykernel/dtbs/ anykernel/Image anykernel/dtb anykernel/dtbo.img 2>/dev/null

if [ "$TARGET_OS" == "aosp" ]; then
    mkdir -p anykernel/kernels/aosp/
    cp build_artifacts/aosp/Image anykernel/kernels/aosp/Image
    cp build_artifacts/aosp/dtb anykernel/kernels/aosp/dtb
elif [ "$TARGET_OS" == "miui" ]; then
    mkdir -p anykernel/kernels/miui/
    cp build_artifacts/miui/Image anykernel/kernels/miui/Image
    cp build_artifacts/miui/dtb anykernel/kernels/miui/dtb
else
    mkdir -p anykernel/kernels/aosp/ anykernel/kernels/miui/
    cp build_artifacts/aosp/Image anykernel/kernels/aosp/Image
    cp build_artifacts/aosp/dtb anykernel/kernels/aosp/dtb
    cp build_artifacts/miui/Image anykernel/kernels/miui/Image
    cp build_artifacts/miui/dtb anykernel/kernels/miui/dtb
fi

# DO NOT include dtbo (preserve panel/touch drivers from ROM)
rm -f anykernel/dtbo.img anykernel/kernels/dtbo.img anykernel/kernels/*/*.img 2>/dev/null
cp -f anykernel_template/anykernel.sh anykernel/anykernel.sh

cd anykernel

if [ "$TARGET_OS" == "aosp" ]; then
    ZIP_FILENAME="${VARIANT_TAG}_Ki-kernel-AOSP-${KERNEL_VERSION}_$(date +'%Y%m%d_%H%M%S').zip"
elif [ "$TARGET_OS" == "miui" ]; then
    ZIP_FILENAME="${VARIANT_TAG}_Ki-kernel-MIUI-${KERNEL_VERSION}_$(date +'%Y%m%d_%H%M%S').zip"
else
    ZIP_FILENAME="${VARIANT_TAG}_Ki-kernel-Universal-${KERNEL_VERSION}_$(date +'%Y%m%d_%H%M%S').zip"
fi

zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore out/ ./*.zip
mv "$ZIP_FILENAME" ../
cd ..

rm -rf build_artifacts 2>/dev/null || true

echo "=========================================================="
echo "Build Finished Successfully!"
echo "Flashable Zip: [./$ZIP_FILENAME]"
echo "=========================================================="
