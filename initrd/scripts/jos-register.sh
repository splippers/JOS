#!/bin/sh
# Register host with FOG using the FOG REST API

SERIAL="$1"

log() {
    echo "JOS-REGISTER: $1"
}

if [ -z "$SERIAL" ]; then
    log "ERROR: No serial provided."
    exit 1
fi

log "Registering host $SERIAL with FOG..."

# Static curl path
CURL="/tools/curl"

# Replace these with your real tokens
FOG_SERVER="<fog-server-ip>"
FOG_API="http://${FOG_SERVER}/fog/host"
FOG_API_TOKEN="<fog-api-token>"
FOG_USER_TOKEN="<fog-user-token>"

# Check if host already exists
EXISTING=$($CURL -s \
    -H "fog-api-token: ${FOG_API_TOKEN}" \
    -H "fog-user-token: ${FOG_USER_TOKEN}" \
    "${FOG_API}/${SERIAL}")

echo "$EXISTING" | grep -q "\"id\":"
if [ $? -eq 0 ]; then
    log "Host already exists in FOG. Skipping creation."
    exit 0
fi

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${SERIAL}",
  "description": "Auto-registered by JOS",
  "serial": "${SERIAL}"
}
EOF
)

# Create host
RESULT=$($CURL -s -X POST \
    -H "Content-Type: application/json" \
    -H "fog-api-token: ${FOG_API_TOKEN}" \
    -H "fog-user-token: ${FOG_USER_TOKEN}" \
    -d "${JSON_PAYLOAD}" \
    "${FOG_API}")

echo "$RESULT" | grep -q "\"id\":"
if [ $? -eq 0 ]; then
    log "Host successfully registered."
else
    log "ERROR: Host registration failed."
    log "FOG response: $RESULT"
    exit 1
fi

exit 0