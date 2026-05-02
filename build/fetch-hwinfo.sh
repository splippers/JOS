#!/bin/bash
set -euo pipefail

TOOLS_DIR="initrd/tools"
mkdir -p "$TOOLS_DIR"

# Static hwinfo build (musl, no external deps)
# Source: https://github.com/andrew-d/static-binaries
HWINFO_VERSION="2024.01"
ARCH="x86_64"

HWINFO_URL="https://github.com/andrew-d/static-binaries/releases/download/${HWINFO_VERSION}/hwinfo-${ARCH}"

echo "[JOS] Fetching static hwinfo (${ARCH})..."
curl -L -o "${TOOLS_DIR}/hwinfo" "$HWINFO_URL"
chmod +x "${TOOLS_DIR}/hwinfo"

echo "[JOS] hwinfo installed at ${TOOLS_DIR}/hwinfo"