#!/bin/bash
set -euo pipefail

# Option A: "copy known-good binaries" into initrd
# We fetch the upstream Debian package and extract only udp-receiver/udp-sender.

TOOLS_DIR="initrd/tools"
TMP_DIR="build/tmp/udpcast"
mkdir -p "$TOOLS_DIR" "$TMP_DIR"

UDPCAST_VER="20250223"
DEB_URL="https://www.udpcast.linux.lu/download/udpcast_${UDPCAST_VER}_amd64.deb"
DEB_PATH="${TMP_DIR}/udpcast_${UDPCAST_VER}_amd64.deb"

echo "[JOS] Fetching udpcast deb (${UDPCAST_VER})..."
curl -fL -o "$DEB_PATH" "$DEB_URL"

echo "[JOS] Extracting udpcast binaries..."
rm -rf "${TMP_DIR}/root"
mkdir -p "${TMP_DIR}/root"
dpkg-deb -x "$DEB_PATH" "${TMP_DIR}/root"

install -m 0755 "${TMP_DIR}/root/sbin/udp-receiver" "${TOOLS_DIR}/udp-receiver"
install -m 0755 "${TMP_DIR}/root/sbin/udp-sender" "${TOOLS_DIR}/udp-sender"

# Sanity check: ensure we didn't download HTML or a stub
if command -v file >/dev/null 2>&1; then
  file "${TOOLS_DIR}/udp-receiver" | grep -q "ELF" || {
    echo "[JOS] ERROR: udp-receiver is not an ELF binary"
    exit 1
  }
fi

echo "[JOS] Collecting runtime libs for udpcast (ldd-based)..."
if ! command -v ldd >/dev/null 2>&1; then
  echo "[JOS] ERROR: ldd not found on build host; cannot bundle udpcast dependencies"
  exit 1
fi

# Copy the dynamic loader + all libraries reported by ldd into the initrd
# preserving their absolute paths.
while IFS= read -r line; do
  # ldd output is often indented; normalize.
  line="${line#"${line%%[![:space:]]*}"}"
  # patterns:
  #   linux-vdso.so.1 (0x00007ffd...)
  #   libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007f...)
  #   /lib64/ld-linux-x86-64.so.2 (0x00007f...)
  path=""
  if [[ "$line" == *"=>"*"/"* ]]; then
    path="$(echo "$line" | awk '{print $3}')"
  elif [[ "$line" == /*"/"* ]]; then
    path="$(echo "$line" | awk '{print $1}')"
  fi
  [[ -n "$path" && -e "$path" ]] || continue

  dest="initrd${path}"
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$path" "$dest"
done < <(ldd "${TOOLS_DIR}/udp-receiver" 2>/dev/null || true)

# Ensure loader is executable if present
if [[ -f initrd/lib64/ld-linux-x86-64.so.2 ]]; then
  chmod 0755 initrd/lib64/ld-linux-x86-64.so.2
fi

echo "[JOS] udpcast installed at ${TOOLS_DIR}/udp-receiver"

