#!/bin/bash
set -euo pipefail

# Copy mount.nfs + dynamic libs from the build host into the initramfs.
# BusyBox mount often lacks NFS support; nfs-common provides /usr/sbin/mount.nfs on Ubuntu/Debian.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT}/initrd/sbin"
mkdir -p "$TOOLS_DIR"

MOUNT_NFS="${JOS_MOUNT_NFS_BIN:-/usr/sbin/mount.nfs}"

if [[ ! -x "$MOUNT_NFS" ]]; then
  echo "[JOS] WARNING: ${MOUNT_NFS} not executable — install nfs-common on the build host for NFS imaging."
  exit 0
fi

install -m 0755 "$MOUNT_NFS" "${TOOLS_DIR}/mount.nfs"

echo "[JOS] Collecting runtime libs for mount.nfs (ldd-based)..."
if ! command -v ldd >/dev/null 2>&1; then
  echo "[JOS] ERROR: ldd not found on build host; cannot bundle mount.nfs dependencies"
  exit 1
fi

while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  path=""
  if [[ "$line" == *"=>"*"/"* ]]; then
    path="$(echo "$line" | awk '{print $3}')"
  elif [[ "$line" == /*"/"* ]]; then
    path="$(echo "$line" | awk '{print $1}')"
  fi
  [[ -n "$path" && -e "$path" ]] || continue

  dest="${ROOT}/initrd${path}"
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$path" "$dest"
done < <(ldd "${TOOLS_DIR}/mount.nfs" 2>/dev/null || true)

if [[ -f "${ROOT}/initrd/lib64/ld-linux-x86-64.so.2" ]]; then
  chmod 0755 "${ROOT}/initrd/lib64/ld-linux-x86-64.so.2"
fi

echo "[JOS] mount.nfs installed at ${TOOLS_DIR}/mount.nfs"
