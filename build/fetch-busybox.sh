#!/bin/bash
set -euo pipefail

BUSYBOX_VERSION="1.36.1"
ARCH="x86_64"
DEST="initrd/bin"

echo "[JOS] Preparing BusyBox directory..."
mkdir -p "$DEST"

BB_URL="https://busybox.net/downloads/binaries/${BUSYBOX_VERSION}-musl/busybox-${ARCH}"

echo "[JOS] Downloading BusyBox ${BUSYBOX_VERSION} (${ARCH})..."
curl -L -o "${DEST}/busybox" "$BB_URL"
chmod +x "${DEST}/busybox"

echo "[JOS] Creating BusyBox symlinks..."
APPLET_LIST="$("${DEST}/busybox" --list)"

for applet in $APPLET_LIST; do
    ln -sf busybox "${DEST}/${applet}"
done

echo "[JOS] BusyBox installed with $(echo "$APPLET_LIST" | wc -w) applets."