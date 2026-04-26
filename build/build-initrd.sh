#!/bin/bash
# Build JOS initramfs
bash build/fetch-busybox.sh
set -e

echo "Building JOS initramfs..."

mkdir -p build/out

cd initrd
find . | cpio -H newc -o > ../build/out/initrd.img
cd ..

echo "Initramfs built: build/out/initrd.img"