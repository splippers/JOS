#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Primary ID: dmidecode -s system-serial-number when available; sysfs DMI fallback.

. /scripts/jos-common.sh

SERIAL=""
local_dmi="/tools/dmidecode"
[[ -x "$local_dmi" ]] || local_dmi=""
if [[ -z "$local_dmi" ]] && command -v dmidecode >/dev/null 2>&1; then
  local_dmi="dmidecode"
fi

if [[ -n "$local_dmi" ]]; then
  SERIAL="$("$local_dmi" -s system-serial-number 2>/dev/null || true)"
  SERIAL="${SERIAL//$'\r'/}"
  SERIAL="${SERIAL//$'\n'/}"
fi

if [[ -z "$SERIAL" || "$SERIAL" == "None" || "$SERIAL" == "To be filled by O.E.M." ]]; then
  SERIAL="$(cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null || true)"
  SERIAL="${SERIAL//$'\r'/}"
  SERIAL="${SERIAL//$'\n'/}"
fi

echo "$SERIAL"
