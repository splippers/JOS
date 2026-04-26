#!/bin/sh
# Bring up networking in the JOS initramfs using BusyBox udhcpc

log() {
    echo "JOS-NET: $1"
}

log "Initialising network..."

# Wait for NICs to appear (important for USB-C docks, laptops, etc.)
for i in 1 2 3 4 5; do
    IFACES=$(ls /sys/class/net 2>/dev/null)
    [ -n "$IFACES" ] && break
    log "Waiting for network interfaces..."
    sleep 1
done

# Try DHCP on all real interfaces
for iface in $IFACES; do
    # Skip loopback and virtual interfaces
    case "$iface" in
        lo|docker*|veth*|virbr*|br*|tap*) continue ;;
    esac

    log "Attempting DHCP on $iface"

    # BusyBox udhcpc flags:
    # -i iface   → interface
    # -q         → quit after obtaining lease
    # -t 5       → try 5 times
    # -n         → exit if no lease
    # -s script  → udhcpc event handler (we use BusyBox default)
    udhcpc -i "$iface" -q -t 5 -n

    if [ $? -eq 0 ]; then
        log "DHCP successful on $iface"
        echo "$iface" > /tmp/jos-active-iface
        exit 0
    else
        log "DHCP failed on $iface"
    fi
done

log "ERROR: No network interfaces received a DHCP lease."
exit 1