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
if [[ -z "${ENABLE_SUSFS}" ]]; then
    read -p "Enable SUSFS support? (y/n): " ENABLE_SUSFS
fi
if [[ -z "${ENABLE_DROIDSPACES}" ]]; then
    read -p "Enable Droidspaces support? (y/n): " ENABLE_DROIDSPACES
fi
echo "Building with: SUSFS=${ENABLE_SUSFS}, Droidspaces=${ENABLE_DROIDSPACES}"

# Setup KernelSU-Next dynamically (proper method)
echo "Setting up KernelSU-Next..."
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s dev
cd KernelSU-Next
# Reset any previous patches to ensure a clean state before patching
git reset --hard HEAD
# Apply our hand-stitched SUSFS hooks
patch -p1 < ../patches/susfs-ksun-hooks.patch
cd ..

# Generate the base configuration
make O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" $KERNEL_DEFCONFIG || exit 1

# Toggle SUSFS features
if [[ "$ENABLE_SUSFS" == "y" ]]; then
    echo "Enabling SUSFS..."
    ./scripts/config --file "$OUT_DIR/.config" -e CONFIG_KSU -e CONFIG_KSU_SUSFS -e CONFIG_KSU_SUSFS_SUS_PATH
else
    echo "Disabling SUSFS..."
    ./scripts/config --file "$OUT_DIR/.config" -d CONFIG_KSU -d CONFIG_KSU_SUSFS -d CONFIG_KSU_SUSFS_SUS_PATH
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
ZIP_NAME="Capybara-CLO-$TIME.zip"
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
