#!/bin/sh
# Extract BIOS serial number

SERIAL=$(cat /sys/devices/virtual/dmi/id/product_serial 2>/dev/null)

if [ -z "$SERIAL" ]; then
    SERIAL=$(dmidecode -s system-serial-number 2>/dev/null)
fi

echo "$SERIAL"
