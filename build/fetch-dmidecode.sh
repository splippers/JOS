#!/bin/bash
set -euo pipefail

TOOLS_DIR="initrd/tools"
mkdir -p "$TOOLS_DIR"

# Static dmidecode build (musl, no external deps)
# Source: https://github.com/mirror/dmidecode-static/releases
DMIDECODE_VERSION="3.5"
ARCH="x86_64"

DMIDECODE_URL="https://github.com/mirror/dmidecode-static/releases/download/v${DMIDECODE_VERSION}/dmidecode-${DMIDECODE_VERSION}-${ARCH}-linux-musl"

echo "[JOS] Fetching static dmidecode ${DMIDECODE_VERSION} (${ARCH})..."
curl -L -o "${TOOLS_DIR}/dmidecode" "$DMIDECODE_URL"
chmod +x "${TOOLS_DIR}/dmidecode"

echo "[JOS] dmidecode installed at ${TOOLS_DIR}/dmidecode"