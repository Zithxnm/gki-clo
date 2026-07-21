#!/bin/bash
set -e

echo "Setting up Droidspaces support..."

# Download and apply mandatory kABI patch for 6.6
wget -q https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/GKI/below-kernel-6.12/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
patch -p1 < 001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
rm 001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch

DEFCONFIG="arch/arm64/configs/capybara_defconfig"

# Append Droidspaces Configurations
cat <<EOF >> $DEFCONFIG

# Droidspaces Configuration
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_DEVTMPFS=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_USER_NS=y
CONFIG_NETFILTER_XT_TARGET_REJECT=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y
CONFIG_IP_SET=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y
EOF

echo "Droidspaces setup completed!"
