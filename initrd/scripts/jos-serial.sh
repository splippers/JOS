#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log
# Primary ID: dmidecode -s system-serial-number when available; sysfs DMI fallback.

. /scripts/jos-common.sh

SERIAL=""
local_dmi="/tools/dmidecode"
[ -x "$local_dmi" ] || local_dmi=""
if [ -z "$local_dmi" ] && command -v dmidecode >/dev/null 2>&1; then
  local_dmi="dmidecode"
fi

if [ -n "$local_dmi" ]; then
  SERIAL="$("$local_dmi" -s system-serial-number 2>/dev/null | tr -d '\r\n' || true)"
fi

jos_serial_is_bogus() {
  case "$1" in
    ""|"None"|"To be filled by O.E.M."|"Default string"|"Not Specified"|"N/A"|"0") return 0 ;;
  esac
  return 1
}

if jos_serial_is_bogus "$SERIAL"; then
  SERIAL="$(cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null | tr -d '\r\n' || true)"
fi

if jos_serial_is_bogus "$SERIAL"; then
  _iface="$(cat /tmp/jos-active-iface 2>/dev/null || true)"
  [ -z "$_iface" ] && _iface="$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -n1 || true)"
  if [ -n "$_iface" ]; then
    _mac="$(cat "/sys/class/net/${_iface}/address" 2>/dev/null | tr -d ':' | tr -d '\r\n' | tr '[:lower:]' '[:upper:]' || true)"
    [ -n "$_mac" ] && SERIAL="MAC-${_mac}"
  fi
fi

echo "$SERIAL"
