#!/bin/bash
# Build JOS initramfs

set -euo pipefail

# Allow running from any working directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/build/fetch-busybox.sh"
bash "$ROOT/build/fetch-curl.sh"
bash "$ROOT/build/fetch-dmidecode.sh"
bash "$ROOT/build/fetch-jq.sh"
# udpcast tools (udp-receiver/udp-sender) for multicast imaging
bash "$ROOT/build/fetch-udpcast.sh"
# Unicast imaging stack (FOG-style NFS + partclone helpers + partition tools)
bash "$ROOT/build/fetch-partclone.sh"
bash "$ROOT/build/fetch-mount-nfs.sh"
bash "$ROOT/build/fetch-sfdisk.sh"

echo "Building JOS initramfs..."

mkdir -p build/out

# Ensure required mountpoint directories exist in the initrd tree.
for _d in proc sys dev tmp mnt run etc/fog; do
  mkdir -p "$ROOT/initrd/$_d"
done

# Ensure the initramfs entrypoint is executable.
chmod +x "$ROOT/initrd/init"
chmod +x "$ROOT/initrd/scripts/"*.sh 2>/dev/null || true

cd "$ROOT/initrd"
find . \
  -not -path './.git/*' \
  -not -name '.gitkeep' \
  | cpio -H newc -o \
  | gzip -9 \
  > ../build/out/initrd.img
cd ..

echo "Initramfs built: build/out/initrd.img ($(du -sh ../jos/build/out/initrd.img 2>/dev/null | cut -f1 || echo '?'))"