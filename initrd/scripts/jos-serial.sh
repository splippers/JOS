#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Extract BIOS serial number

. /scripts/jos-common.sh

SERIAL="$(cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null || true)"
SERIAL="${SERIAL//$'\r'/}"
SERIAL="${SERIAL//$'\n'/}"

if [[ -z "$SERIAL" || "$SERIAL" == "None" || "$SERIAL" == "To be filled by O.E.M." ]]; then
  local_dmi="/tools/dmidecode"
  [[ -x "$local_dmi" ]] || local_dmi="dmidecode"
  SERIAL="$("$local_dmi" -s system-serial-number 2>/dev/null || true)"
  SERIAL="${SERIAL//$'\r'/}"
  SERIAL="${SERIAL//$'\n'/}"
fi

echo "$SERIAL"
