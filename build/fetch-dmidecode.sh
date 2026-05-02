#!/bin/bash
set -euo pipefail

# Bundle dmidecode + libraries from Ubuntu's package (matches udpcast fetch pattern).
# Pinned Ubuntu archive revision for reproducibility; bump when validating on new Ubuntu LTS.

TOOLS_DIR="initrd/tools"
TMP_DIR="build/tmp/dmidecode"
DEB_NAME="dmidecode_3.6-2_amd64.deb"
DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/d/dmidecode/${DEB_NAME}"
DEB_PATH="${TMP_DIR}/${DEB_NAME}"

mkdir -p "$TOOLS_DIR" "$TMP_DIR"

echo "[JOS] Fetching ${DEB_NAME}..."
curl -fL -o "$DEB_PATH" "$DEB_URL"

echo "[JOS] Extracting dmidecode..."
rm -rf "${TMP_DIR}/root"
mkdir -p "${TMP_DIR}/root"
dpkg-deb -x "$DEB_PATH" "${TMP_DIR}/root"

install -m 0755 "${TMP_DIR}/root/usr/sbin/dmidecode" "${TOOLS_DIR}/dmidecode"

if command -v file >/dev/null 2>&1; then
  file "${TOOLS_DIR}/dmidecode" | grep -q "ELF" || {
    echo "[JOS] ERROR: dmidecode is not an ELF binary"
    exit 1
  }
fi

echo "[JOS] Collecting runtime libs for dmidecode (ldd-based)..."
if ! command -v ldd >/dev/null 2>&1; then
  echo "[JOS] ERROR: ldd not found on build host"
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

  dest="initrd${path}"
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$path" "$dest"
done < <(ldd "${TOOLS_DIR}/dmidecode" 2>/dev/null || true)

if [[ -f initrd/lib64/ld-linux-x86-64.so.2 ]]; then
  chmod 0755 initrd/lib64/ld-linux-x86-64.so.2
fi

echo "[JOS] dmidecode installed at ${TOOLS_DIR}/dmidecode"
