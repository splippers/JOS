#!/bin/bash
set -euo pipefail

BUSYBOX_VERSION="1.35.0"
ARCH="x86_64"
DEST="initrd/bin"

echo "[JOS] Preparing BusyBox directory..."
mkdir -p "$DEST"

BB_URL="https://busybox.net/downloads/binaries/${BUSYBOX_VERSION}-${ARCH}-linux-musl/busybox"

echo "[JOS] Downloading BusyBox ${BUSYBOX_VERSION} (${ARCH})..."
curl -fL -o "${DEST}/busybox" "$BB_URL"
chmod +x "${DEST}/busybox"

echo "[JOS] Creating BusyBox symlinks..."
APPLET_LIST="$("${DEST}/busybox" --list)"

for applet in $APPLET_LIST; do
    ln -sf busybox "${DEST}/${applet}"
done

# Provide /bin/bash in initramfs (symlink to BusyBox shell).
# Many JOS scripts are bash for consistency with fleet tooling.
ln -sf busybox "${DEST}/bash"

echo "[JOS] BusyBox installed with $(echo "$APPLET_LIST" | wc -w) applets."