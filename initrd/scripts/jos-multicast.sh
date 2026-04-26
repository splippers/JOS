#!/bin/sh
# JOS multicast queue placeholder
# Runs inside BusyBox initramfs

SERIAL="$1"

log() {
    echo "JOS-MULTICAST: $1"
}

if [ -z "$SERIAL" ]; then
    log "ERROR: No serial passed to multicast script."
    exit 1
fi

log "Waiting for multicast task for serial: $SERIAL"

# Placeholder loop — will later poll FOG API
# using /tools/curl once registration logic is implemented
i=0
while [ $i -lt 5 ]; do
    log "Polling for multicast assignment... ($i)"
    sleep 1
    i=$((i + 1))
done

log "No multicast logic implemented yet."
exit 0