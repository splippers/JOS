#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Upload inventory — FOG Inventory schema; create/update routes depend on server version probe.

SERIAL="$1"

. /scripts/jos-common.sh
# shellcheck disable=SC1091
. /scripts/jos-disk.sh

[[ -n "$SERIAL" ]] || die "INVENTORY: No serial provided."
jos_load_fog_config

FOG_BASE="$(jos_fog_base_url)"

log "INVENTORY: FOG≈${FOG_VERSION_RAW:-?} inv_paths=${JOS_FOG_INV_CREATE_PATHS}"

log "INVENTORY: Collecting hardware inventory for $SERIAL..."

HOST_ID="$(jos_fog_resolve_host_id "$SERIAL")"
[[ -n "$HOST_ID" ]] || die "INVENTORY: Could not resolve FOG host id for ${SERIAL} (register first?)."

ACTIVE_IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"

CPU="$(grep -m1 -E '^model name|^Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' | sed 's/"/\\"/g' || true)"
RAM_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}' || true)"

LSBLK_JSON="$(jos_lsblk_json_full)"
DISK_PAIR="$(jos_largest_fixed_disk_sysfs)"
PRIMARY_DISK="${DISK_PAIR%%:*}"
PRIMARY_DISK_BYTES="${DISK_PAIR##*:}"

DISK_MODEL=""
DISK_SERIAL=""
if [[ -n "$PRIMARY_DISK" ]]; then
  [[ -f "/sys/block/${PRIMARY_DISK}/device/model" ]] && \
    DISK_MODEL="$(sed 's/[[:space:]]*$//' "/sys/block/${PRIMARY_DISK}/device/model" 2>/dev/null | sed 's/"/\\"/g' || true)"
  [[ -f "/sys/block/${PRIMARY_DISK}/device/serial" ]] && \
    DISK_SERIAL="$(sed 's/[[:space:]]*$//' "/sys/block/${PRIMARY_DISK}/device/serial" 2>/dev/null | sed 's/"/\\"/g' || true)"
fi

DMI_VENDOR="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null | sed 's/"/\\"/g' || true)"
DMI_PRODUCT="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | sed 's/"/\\"/g' || true)"
DMI_VERSION="$(cat /sys/devices/virtual/dmi/id/product_version 2>/dev/null | sed 's/"/\\"/g' || true)"
DMI_BIOS_VER="$(cat /sys/devices/virtual/dmi/id/bios_version 2>/dev/null | sed 's/"/\\"/g' || true)"

MEM_FIELD="Total ${RAM_KB}"

HOST_JSON="$(jos_curl_json GET "${FOG_BASE}/host/${HOST_ID}" 2>/dev/null || true)"
INV_ID="$(jos_fog_extract_inventory_id_from_host_json "$HOST_JSON")"

OTHER_NOTE="JOS:$(date +%Y%m%d);disk=${PRIMARY_DISK};lsblk=${#LSBLK_JSON}b"
OTHER_NOTE="${OTHER_NOTE:0:240}"

JSON_PAYLOAD=$(cat <<EOF
{
  "hostID": ${HOST_ID},
  "sysserial": "${SERIAL}",
  "sysman": "${DMI_VENDOR}",
  "sysproduct": "${DMI_PRODUCT}",
  "sysversion": "${DMI_VERSION}",
  "biosversion": "${DMI_BIOS_VER}",
  "mem": "${MEM_FIELD}",
  "cpuman": "${CPU}",
  "cpuversion": "${CPU}",
  "hdmodel": "${DISK_MODEL}",
  "hdserial": "${DISK_SERIAL}",
  "other1": "${OTHER_NOTE}",
  "primaryUser": "iface:${ACTIVE_IFACE};diskB:${PRIMARY_DISK_BYTES};blk:${PRIMARY_DISK}"
}
EOF
)

log "INVENTORY: Uploading inventory to FOG (host id=${HOST_ID}, inventory id=${INV_ID:-new})..."

if [[ -n "$INV_ID" ]]; then
  jos_fog_api_put_inventory "$FOG_BASE" "$INV_ID" "${JSON_PAYLOAD}" >/dev/null || die "INVENTORY: Inventory update failed."
else
  jos_fog_api_post_first_ok "$FOG_BASE" "$JOS_FOG_INV_CREATE_PATHS" "${JSON_PAYLOAD}" || die "INVENTORY: Inventory create failed."
fi

log "INVENTORY: Inventory upload complete."

exit 0
