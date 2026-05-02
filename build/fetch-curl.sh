#!/bin/bash
set -euo pipefail

TOOLS_DIR="initrd/tools"
mkdir -p "$TOOLS_DIR"

CURL_VERSION="8.7.1"
ARCH="x86_64"

# Static curl builds published as arch-named assets (amd64, aarch64, etc.)
CURL_URL="https://github.com/moparisthebest/static-curl/releases/download/v${CURL_VERSION}/curl-amd64"

echo "[JOS] Fetching static curl ${CURL_VERSION} (${ARCH})..."
curl -fL -o "${TOOLS_DIR}/curl" "$CURL_URL"
chmod +x "${TOOLS_DIR}/curl"

echo "[JOS] curl installed at ${TOOLS_DIR}/curl"