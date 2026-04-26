#!/bin/bash
set -euo pipefail

TOOLS_DIR="initrd/tools"
mkdir -p "$TOOLS_DIR"

CURL_VERSION="8.7.1"
ARCH="x86_64"

# A reliable static curl build (musl, no external deps)
CURL_URL="https://github.com/moparisthebest/static-curl/releases/download/v${CURL_VERSION}/curl-${CURL_VERSION}-${ARCH}-linux-musl"

echo "[JOS] Fetching static curl ${CURL_VERSION} (${ARCH})..."
curl -L -o "${TOOLS_DIR}/curl" "$CURL_URL"
chmod +x "${TOOLS_DIR}/curl"

echo "[JOS] curl installed at ${TOOLS_DIR}/curl"