#!/bin/bash
set -euo pipefail

TOOLS_DIR="initrd/tools"
mkdir -p "$TOOLS_DIR"

# Static lshw build (musl, no external deps)
# Source: https://github.com/lyonel/lshw-static/releases
LSHW_VERSION="B.02.20"
ARCH="x86_64"

LSHW_URL="https://github.com/lyonel/lshw-static/releases/download/${LSHW_VERSION}/lshw-${LSHW_VERSION}-${ARCH}-linux-musl"

echo "[JOS] Fetching static lshw ${LSHW_VERSION} (${ARCH})..."
curl -L -o "${TOOLS_DIR}/lshw" "$LSHW_URL"
chmod +x "${TOOLS_DIR}/lshw"

echo "[JOS] lshw installed at ${TOOLS_DIR}/lshw"