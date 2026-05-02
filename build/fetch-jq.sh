#!/bin/bash
set -euo pipefail

# Bundles a static jq binary for JSON parsing in initramfs scripts (FOG API bodies).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT}/initrd/tools"
TMP_DIR="${ROOT}/build/tmp/jq"
mkdir -p "$TOOLS_DIR" "$TMP_DIR"

JQ_VER="${JOS_JQ_VERSION:-1.7.1}"
URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VER}/jq-linux-amd64"
OUT="${TMP_DIR}/jq-linux-amd64"

echo "[JOS] Fetching jq ${JQ_VER} (amd64)..."
curl -fL -o "$OUT" "$URL"
chmod +x "$OUT"

if command -v file >/dev/null 2>&1; then
  file "$OUT" | grep -q "ELF" || {
    echo "[JOS] ERROR: jq download is not an ELF binary"
    exit 1
  }
fi

install -m 0755 "$OUT" "${TOOLS_DIR}/jq"
echo "[JOS] jq installed at ${TOOLS_DIR}/jq"
