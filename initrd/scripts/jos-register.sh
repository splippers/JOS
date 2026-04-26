#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Register host with FOG using the FOG REST API

SERIAL="$1"

. /scripts/jos-common.sh

[[ -n "$SERIAL" ]] || die "REGISTER: No serial provided."

jos_load_fog_config

log "REGISTER: Registering/updating host $SERIAL with FOG..."

# Base API endpoints
FOG_BASE="http://${FOG_SERVER}/fog"
HOST_EP="${FOG_BASE}/host"

# Determine a primary MAC address from the active interface (fallback: first non-lo).
ACTIVE_IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"
if [[ -z "$ACTIVE_IFACE" ]]; then
  ACTIVE_IFACE="$(ls /sys/class/net | grep -v '^lo$' | head -n1 || true)"
fi

MAC_RAW="$(cat "/sys/class/net/${ACTIVE_IFACE}/address" 2>/dev/null || true)"
MAC="${MAC_RAW^^}"
[[ -n "$MAC" ]] || die "REGISTER: Unable to determine MAC address (iface: ${ACTIVE_IFACE:-unknown})"

# Check if host already exists (FOG host endpoint is by host ID typically; serial lookup varies by version).
# We'll attempt GET /host/<serial> first; if that fails, we will just create and rely on FOG to de-dupe on MAC.
EXISTING=""
if EXISTING="$(jos_curl_json GET "${HOST_EP}/${SERIAL}" 2>/dev/null || true)"; then
  true
fi

if echo "$EXISTING" | grep -q '"id"[[:space:]]*:'; then
  log "REGISTER: Host already exists in FOG. Skipping creation."
  exit 0
fi

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${SERIAL}",
  "description": "Auto-registered by JOS",
  "serial": "${SERIAL}",
  "macs": ["${MAC}"]
}
EOF
)

# Create host
RESULT="$(jos_curl_json POST "${HOST_EP}" "${JSON_PAYLOAD}" || true)"

echo "$RESULT" | grep -q '"id"[[:space:]]*:' || die "REGISTER: Host registration failed. FOG response: ${RESULT}"

log "REGISTER: Host successfully registered."

exit 0