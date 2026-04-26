#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Bring up networking in the JOS initramfs using BusyBox udhcpc

. /scripts/jos-common.sh

log "NET: Initialising network..."

# Wait for NICs to appear (important for USB-C docks, laptops, etc.)
for _ in 1 2 3 4 5; do
  IFACES="$(ls /sys/class/net 2>/dev/null || true)"
  [[ -n "$IFACES" ]] && break
  log "NET: Waiting for network interfaces..."
  sleep 1
done

# Try DHCP on all real interfaces
for iface in $IFACES; do
    # Skip loopback and virtual interfaces
    case "$iface" in
        lo|docker*|veth*|virbr*|br*|tap*) continue ;;
    esac

    log "NET: Attempting DHCP on $iface"

    # BusyBox udhcpc flags:
    # -i iface   → interface
    # -q         → quit after obtaining lease
    # -t 5       → try 5 times
    # -n         → exit if no lease
    # -s script  → udhcpc event handler (captures NEXT SERVER / siaddr)
    if udhcpc -i "$iface" -q -t 5 -n -s /scripts/udhcpc-jos.sh; then
      log "NET: DHCP successful on $iface"
      # /scripts/udhcpc-jos.sh already writes /tmp/jos-active-iface and /tmp/jos-next-server
      exit 0
    fi

    log "NET: DHCP failed on $iface"
done

err "NET: No network interfaces received a DHCP lease."
exit 1