#!/bin/bash
# Build JOS initramfs

set -e

bash build/fetch-busybox.sh
bash build/fetch-curl.sh
# udpcast tools (udp-receiver/udp-sender) for multicast imaging
bash build/fetch-udpcast.sh
# dmidecode/lshw/hwinfo static assets are not reliably available upstream.
# JOS scripts primarily use sysfs/procfs to keep the initrd small and robust.

echo "Building JOS initramfs..."

mkdir -p build/out

cd initrd
find . | cpio -H newc -o > ../build/out/initrd.img
cd ..

echo "Initramfs built: build/out/initrd.img"