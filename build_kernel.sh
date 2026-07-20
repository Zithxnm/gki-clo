#!/bin/bash
set -e

# Configuration
DIR=$(readlink -f .)
MAIN=$(readlink -f ${DIR}/..)
KERNEL_DEFCONFIG=capybara_defconfig
CLANG_DIR="$MAIN/toolchains/clang"
KERNEL_DIR=$(pwd)
OUT_DIR="$KERNEL_DIR/out"
ZIMAGE_DIR="$OUT_DIR/arch/arm64/boot"
DTB_DTBO_DIR="$ZIMAGE_DIR/dts/vendor/qcom"
BUILD_START=$(date +"%s")

# Use system clang
export PATH="/usr/bin:$PATH"

# Set up toolchain
export ARCH=arm64
export SUBARCH=arm64

# Allow environment variables to override interactive prompts.
# Set ENABLE_SUSFS=y or ENABLE_DROIDSPACES=y before calling this script
# to skip the interactive prompts (useful for scripted/CI invocations).
if [[ -z "${ROOT_MANAGER}" ]]; then
    echo "Select Root Manager:"
    echo "1) KernelSU-Next (KSUN)"
    echo "2) ReSukiSU"
    echo "3) None"
    read -p "Enter choice (1-3) [default: 1]: " root_choice
    case $root_choice in
        2) ROOT_MANAGER="RESUKISU" ;;
        3) ROOT_MANAGER="NONE" ;;
        *) ROOT_MANAGER="KSUN" ;;
    esac
fi
if [[ -z "${ENABLE_SUSFS}" ]]; then
    read -p "Enable SUSFS support? (y/n) [default: y]: " ENABLE_SUSFS
    ENABLE_SUSFS=${ENABLE_SUSFS:-y}
fi
if [[ -z "${ENABLE_DROIDSPACES}" ]]; then
    read -p "Enable Droidspaces support? (y/n) [default: y]: " ENABLE_DROIDSPACES
    ENABLE_DROIDSPACES=${ENABLE_DROIDSPACES:-y}
fi
echo "Building with: ROOT_MANAGER=${ROOT_MANAGER}, SUSFS=${ENABLE_SUSFS}, Droidspaces=${ENABLE_DROIDSPACES}"

# Setup Root Manager dynamically
echo "Setting up root manager: ${ROOT_MANAGER}..."
rm -rf KernelSU KernelSU-Next common/drivers/kernelsu drivers/kernelsu

if [[ "$ROOT_MANAGER" == "KSUN" ]]; then
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s dev
    cd KernelSU-Next
    git reset --hard HEAD
    patch -p1 < ../patches/susfs-ksun-hooks.patch
    cd ..
elif [[ "$ROOT_MANAGER" == "RESUKISU" ]]; then
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
fi

# Generate the base configuration
make O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" $KERNEL_DEFCONFIG || exit 1

# Toggle Root Manager
if [[ "$ROOT_MANAGER" != "NONE" ]]; then
    ./scripts/config --file "$OUT_DIR/.config" -e CONFIG_KSU
else
    ./scripts/config --file "$OUT_DIR/.config" -d CONFIG_KSU
fi

# Toggle SUSFS features
if [[ "$ENABLE_SUSFS" == "y" ]]; then
    echo "Enabling SUSFS..."
    ./scripts/config --file "$OUT_DIR/.config" \
        -e CONFIG_KSU_SUSFS \
        -e CONFIG_KSU_SUSFS_SUS_PATH \
        -e CONFIG_KSU_SUSFS_SUS_MOUNT \
        -e CONFIG_KSU_SUSFS_SUS_KSTAT \
        -e CONFIG_KSU_SUSFS_SPOOF_UNAME \
        -e CONFIG_KSU_SUSFS_ENABLE_LOG \
        -e CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
        -e CONFIG_KSU_SUSFS_OPEN_REDIRECT \
        -e CONFIG_KSU_SUSFS_SUS_MAP
else
    echo "Disabling SUSFS..."
    ./scripts/config --file "$OUT_DIR/.config" \
        -d CONFIG_KSU_SUSFS \
        -d CONFIG_KSU_SUSFS_SUS_PATH \
        -d CONFIG_KSU_SUSFS_SUS_MOUNT \
        -d CONFIG_KSU_SUSFS_SUS_KSTAT \
        -d CONFIG_KSU_SUSFS_SPOOF_UNAME \
        -d CONFIG_KSU_SUSFS_ENABLE_LOG \
        -d CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
        -d CONFIG_KSU_SUSFS_OPEN_REDIRECT \
        -d CONFIG_KSU_SUSFS_SUS_MAP
fi

# Toggle Droidspaces features
if [[ "$ENABLE_DROIDSPACES" == "y" ]]; then
    echo "Enabling Droidspaces..."
    ./scripts/config --file "$OUT_DIR/.config" \
        -e CONFIG_SYSVIPC -e CONFIG_POSIX_MQUEUE -e CONFIG_USER_NS \
        -e CONFIG_PID_NS -e CONFIG_IPC_NS -e CONFIG_DEVTMPFS \
        -e CONFIG_NETFILTER_XT_MATCH_ADDRTYPE -e CONFIG_NETFILTER_XT_TARGET_REJECT \
        -e CONFIG_NETFILTER_XT_TARGET_LOG -e CONFIG_NETFILTER_XT_MATCH_RECENT \
        -e CONFIG_IP_SET -e CONFIG_IP_SET_HASH_IP -e CONFIG_IP_SET_HASH_NET \
        -e CONFIG_NETFILTER_XT_SET -e CONFIG_TMPFS_POSIX_ACL -e CONFIG_TMPFS_XATTR
else
    echo "Disabling Droidspaces..."
    ./scripts/config --file "$OUT_DIR/.config" \
        -d CONFIG_SYSVIPC -d CONFIG_POSIX_MQUEUE -d CONFIG_USER_NS \
        -d CONFIG_PID_NS -d CONFIG_IPC_NS
fi

# Re-evaluate the new .config dependencies
make O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" olddefconfig

# Build kernel
make -j6 O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" || exit 1

# Clean up old kernel zip files
echo "Cleaning up old kernel zip files..."
find "$KERNEL_DIR" -maxdepth 1 -type f -name "Capybara-CLO-*.zip" -exec rm -v {} \;

# Create temporary anykernel directory
TIME=$(date "+%Y%m%d-%H%M%S")
TEMP_ANY_KERNEL_DIR="$KERNEL_DIR/anykernel_temp"
rm -rf "$TEMP_ANY_KERNEL_DIR"

# Clone entire anykernel directory
echo "Cloning anykernel directory..."
if [ -d "$KERNEL_DIR/anykernel" ]; then
    cp -r "$KERNEL_DIR/anykernel" "$TEMP_ANY_KERNEL_DIR"
else
    echo "Error: anykernel directory not found!"
    exit 1
fi

# Copy kernel image
if [ -f "$ZIMAGE_DIR/Image.gz-dtb" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz-dtb" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image.gz" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image" ]; then
    cp -v "$ZIMAGE_DIR/Image" "$TEMP_ANY_KERNEL_DIR/"
fi

# Create zip file in kernel root directory
echo "Creating zip package..."
SUFFIX=""
[[ "$ROOT_MANAGER" != "NONE" ]] && SUFFIX="${SUFFIX}-${ROOT_MANAGER}"
[[ "$ENABLE_SUSFS" == "y" ]] && SUFFIX="${SUFFIX}-SUSFS"
[[ "$ENABLE_DROIDSPACES" == "y" ]] && SUFFIX="${SUFFIX}-Droidspaces"
[[ -z "${SUFFIX}" ]] && SUFFIX="-Vanilla"
ZIP_NAME="Capybara-CLO-$TIME$SUFFIX.zip"
cd "$TEMP_ANY_KERNEL_DIR"
zip -r9 "$KERNEL_DIR/$ZIP_NAME" ./*
cd ..

# Clean up temporary directory
rm -rf "$TEMP_ANY_KERNEL_DIR"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo -e "\n=========================================="
echo "Build completed in $((DIFF / 60))m $((DIFF % 60))s"
echo "Final zip: $KERNEL_DIR/$ZIP_NAME"
echo "Zip size: $(du -h "$KERNEL_DIR/$ZIP_NAME" | cut -f1)"
echo "=========================================="
