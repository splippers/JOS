#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Collect hardware inventory and upload to FOG

SERIAL="$1"

. /scripts/jos-common.sh

[[ -n "$SERIAL" ]] || die "INVENTORY: No serial provided."
jos_load_fog_config

log "INVENTORY: Collecting hardware inventory for $SERIAL..."

ACTIVE_IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"

# Keep inventory lightweight: use proc/sysfs only (no external binaries required).
CPU="$(grep -m1 -E '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || true)"

# Collect RAM (from /proc)
RAM_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}' || true)"

# Collect a small amount of disk info from /sys/block
DISK_INFO="$(ls /sys/block 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || true)"

# DMI basics from sysfs (Dell Service Tag comes from product_serial already)
DMI_VENDOR="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | sed 's/"/\\"/g' || true)"
DMI_PRODUCT="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | sed 's/"/\\"/g' || true)"
DMI_VERSION="$(cat /sys/devices/virtual/dmi/id/product_version 2>/dev/null | sed 's/"/\\"/g' || true)"
DMI_BIOS_VER="$(cat /sys/devices/virtual/dmi/id/bios_version 2>/dev/null | sed 's/"/\\"/g' || true)"

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "serial": "$SERIAL",
  "active_iface": "${ACTIVE_IFACE}",
  "cpu": "$CPU",
  "ram_kb": "$RAM_KB",
  "disk": "$DISK_INFO",
  "dmi_vendor": "$DMI_VENDOR",
  "dmi_product": "$DMI_PRODUCT",
  "dmi_version": "$DMI_VERSION",
  "bios_version": "$DMI_BIOS_VER"
}
EOF
)

FOG_API="http://${FOG_SERVER}/fog/host/${SERIAL}"

log "INVENTORY: Uploading inventory to FOG..."

jos_curl_json PUT "$FOG_API" "$JSON_PAYLOAD" >/dev/null || die "INVENTORY: Inventory upload failed."

log "INVENTORY: Inventory upload complete."

exit 0