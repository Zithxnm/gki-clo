#!/bin/bash

# Setup NoMount
echo "[+] Setting up NoMount..."
rm -rf /tmp/nomount
git clone --depth 1 https://github.com/maxsteeel/nomount.git /tmp/nomount

# Copy the core NoMount files
cp /tmp/nomount/kernel/src/nomount.c fs/
cp /tmp/nomount/kernel/src/nomount.h fs/

# Apply the NoMount patches for 6.6
patch -p1 --forward --reject-file=- < /tmp/nomount/kernel/patches/nomount_6.6_kernel_integration.patch || true

echo "[+] NoMount setup complete."
