#!/bin/bash
set -e
rm -rf /tmp/susfs4ksu
git clone --depth 1 -b gki-android15-6.6-dev https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs4ksu

cp /tmp/susfs4ksu/kernel_patches/fs/susfs.c fs/susfs.c
cp /tmp/susfs4ksu/kernel_patches/include/linux/susfs.h include/linux/susfs.h
cp /tmp/susfs4ksu/kernel_patches/include/linux/susfs_def.h include/linux/susfs_def.h

SUSFS_DEF_H="include/linux/susfs_def.h"
if [ -f "$SUSFS_DEF_H" ] && ! grep -q "linux/sched.h" "$SUSFS_DEF_H" 2>/dev/null; then
  sed -i '/#include <linux\/bits.h>/a\
#include <linux\/sched.h>\
#include <linux\/thread_info.h>\
#include <linux\/cred.h>\
#include <asm\/current.h>' "$SUSFS_DEF_H"
fi
if [ ! -d "KernelSU/kernel/uapi" ] && [ -d "KernelSU/uapi" ]; then
  ln -sfn ../uapi KernelSU/kernel/uapi
fi

cd KernelSU
if grep -q "KSU_SUSFS" kernel/Kconfig 2>/dev/null; then
  echo "[+] KernelSU already has native SUSFS integration. Skipping patch..."
else
  echo "[+] Patching KernelSU for SUSFS..."
  patch -p1 --forward -f --reject-file=- < /tmp/susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch || true
fi
cd ..
patch -p1 < /tmp/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch

bash scripts/ksu_susfs_fixup.sh KernelSU/kernel ${1:-kowsu}
echo "CONFIG_KSU_SUSFS=y" >> arch/arm64/configs/hydrochoerus_defconfig
