#!/bin/bash
set -euo pipefail

# Bundle partclone helpers from Debian package (same pattern as udpcast).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT}/initrd/tools"
TMP_DIR="${ROOT}/build/tmp/partclone"
mkdir -p "$TOOLS_DIR" "$TMP_DIR"

DEB_PKG="${JOS_PARTCLONE_DEB_PKG:-partclone_0.3.23%2Brepack-1_amd64.deb}"
DEB_URL="https://deb.debian.org/debian/pool/main/p/partclone/${DEB_PKG}"
DEB_PATH="${TMP_DIR}/partclone_amd64.deb"

echo "[JOS] Fetching partclone deb (${DEB_PKG})..."
curl -fL -o "$DEB_PATH" "$DEB_URL"

echo "[JOS] Extracting partclone binaries..."
rm -rf "${TMP_DIR}/root"
mkdir -p "${TMP_DIR}/root"
dpkg-deb -x "$DEB_PATH" "${TMP_DIR}/root"

while IFS= read -r -d '' src; do
  [[ -e "$src" ]] || continue
  base="$(basename "$src")"
  install -m 0755 "$src" "${TOOLS_DIR}/${base}"
done < <(find "${TMP_DIR}/root/usr/sbin" -maxdepth 1 -name 'partclone*' -print0 2>/dev/null || true)

if [[ ! -x "${TOOLS_DIR}/partclone.extfs" ]]; then
  echo "[JOS] ERROR: partclone.extfs missing after extract (unexpected Debian layout change)"
  exit 1
fi

echo "[JOS] Collecting runtime libs for partclone (ldd-based)..."
if ! command -v ldd >/dev/null 2>&1; then
  echo "[JOS] ERROR: ldd not found on build host; cannot bundle partclone dependencies"
  exit 1
fi

bundle_ldd() {
  local bin="$1"
  [[ -x "$bin" ]] || return 0
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
  done < <(ldd "$bin" 2>/dev/null || true)
}

for cand in partclone.extfs partclone.ntfs partclone.fat partclone.restore; do
  bundle_ldd "${TOOLS_DIR}/${cand}"
done

if [[ -f "${ROOT}/initrd/lib64/ld-linux-x86-64.so.2" ]]; then
  chmod 0755 "${ROOT}/initrd/lib64/ld-linux-x86-64.so.2"
fi

echo "[JOS] partclone installed under ${TOOLS_DIR}/"
