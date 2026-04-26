#!/bin/sh
# Collect hardware inventory and upload to FOG

SERIAL="$1"

echo "JOS: Collecting inventory for $SERIAL..."

CPU=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ *//')
RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
DISK=$(lsblk -d -o NAME,SIZE | grep -v loop | tail -n +2)

INVENTORY="CPU: $CPU\nRAM: ${RAM}kB\nDisk:\n$DISK"

FOG="http://<fog-server-ip>/fog"

curl -X POST "$FOG/inventory/create" \
    -H "Content-Type: application/json" \
    -d "{
        \"serial\": \"$SERIAL\",
        \"inventory\": \"$INVENTORY\"
    }"
