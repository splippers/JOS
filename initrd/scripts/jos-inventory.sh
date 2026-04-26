#!/bin/sh
# Collect hardware inventory and upload to FOG

SERIAL="$1"

log() {
    echo "JOS-INVENTORY: $1"
}

if [ -z "$SERIAL" ]; then
    log "ERROR: No serial provided."
    exit 1
fi

log "Collecting hardware inventory for $SERIAL..."

# Paths to static tools
DMIDECODE="/tools/dmidecode"
LSHW="/tools/lshw"
HWINFO="/tools/hwinfo"
CURL="/tools/curl"

# Collect CPU info (dmidecode is reliable in initramfs)
CPU="$($DMIDECODE -t processor | grep 'Version:' | head -n1 | cut -d: -f2 | sed 's/^ *//')"

# Collect RAM (from /proc)
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Collect disk info (BusyBox lsblk is limited, so use hwinfo)
DISK_INFO="$($HWINFO --disk --short | sed 's/"/\\"/g')"

# Collect full DMI table (escaped for JSON)
DMI_INFO="$($DMIDECODE | sed 's/"/\\"/g')"

# Collect full hardware tree (escaped)
LSHW_INFO="$($LSHW -json 2>/dev/null | sed 's/"/\\"/g')"

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "serial": "$SERIAL",
  "cpu": "$CPU",
  "ram_kb": "$RAM_KB",
  "disk": "$DISK_INFO",
  "dmi": "$DMI_INFO",
  "lshw": "$LSHW_INFO"
}
EOF
)

# FOG API endpoint (you will replace <fog-server-ip>)
FOG_API="http://<fog-server-ip>/fog/host/${SERIAL}"

log "Uploading inventory to FOG..."

$CURL -s -X PUT "$FOG_API" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD"

if [ $? -eq 0 ]; then
    log "Inventory upload complete."
else
    log "ERROR: Inventory upload failed."
fi

exit 0