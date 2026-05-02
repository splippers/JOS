#!/bin/bash
set -euo pipefail

# Copy sfdisk (partition layout restore) + libs from the build host.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT}/initrd/usr/bin"
mkdir -p "$BIN_DIR"

SFDISK=""
for cand in "${JOS_SFDISK_BIN:-}" /usr/bin/sfdisk /sbin/sfdisk; do
  [[ -n "$cand" && -x "$cand" ]] && SFDISK="$cand" && break
done
if [[ -z "$SFDISK" ]]; then
  echo "[JOS] WARNING: sfdisk not found (/usr/bin/sfdisk or /sbin/sfdisk) — partition-table restore will not work."
  exit 0
fi

install -m 0755 "$SFDISK" "${BIN_DIR}/sfdisk"

echo "[JOS] Collecting runtime libs for sfdisk (ldd-based)..."
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

  dest="${ROOT}/initrd${path}"
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$path" "$dest"
done < <(ldd "${BIN_DIR}/sfdisk" 2>/dev/null || true)

if [[ -f "${ROOT}/initrd/lib64/ld-linux-x86-64.so.2" ]]; then
  chmod 0755 "${ROOT}/initrd/lib64/ld-linux-x86-64.so.2"
fi

echo "[JOS] sfdisk installed at ${BIN_DIR}/sfdisk"
