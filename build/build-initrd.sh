#!/bin/bash
# Build JOS initramfs

set -e

# Allow running from any working directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/build/fetch-busybox.sh"
bash "$ROOT/build/fetch-curl.sh"
# udpcast tools (udp-receiver/udp-sender) for multicast imaging
bash "$ROOT/build/fetch-udpcast.sh"
# dmidecode/lshw/hwinfo static assets are not reliably available upstream.
# JOS scripts primarily use sysfs/procfs to keep the initrd small and robust.

echo "Building JOS initramfs..."

mkdir -p build/out

# Ensure the initramfs entrypoint is executable.
chmod +x "$ROOT/initrd/init"
chmod +x "$ROOT/initrd/scripts/"*.sh 2>/dev/null || true

cd "$ROOT/initrd"
find . | cpio -H newc -o > ../build/out/initrd.img
cd ..

echo "Initramfs built: build/out/initrd.img"