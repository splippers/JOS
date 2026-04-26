#!/bin/sh
# Register host with FOG using FOG API

SERIAL="$1"

echo "JOS: Registering host $SERIAL with FOG..."

FOG="http://<fog-server-ip>/fog"

curl -X POST "$FOG/host/create" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$SERIAL\",
        \"description\": \"Auto-registered by JOS\",
        \"serial\": \"$SERIAL\"
    }"