#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# JOS multicast queue logic (FOG API driven).
# Goal: ensure a newly-booted host is queued into a multicast session with minimal admin touch.

SERIAL="$1"

. /scripts/jos-common.sh

[[ -n "$SERIAL" ]] || die "MULTICAST: No serial passed to multicast script."
jos_load_fog_config

log "MULTICAST: Preparing multicast queue for serial: $SERIAL"

# NOTE: FOG API structures vary by version; we implement a pragmatic flow:
# - Create a multicast session (if configured) and associate this host task to it.
# Required config variables in $FOG_CONFIG_FILE:
#   JOS_IMAGE_ID: numeric image id in FOG
#   JOS_MC_NAME: session name prefix (default "JOS-AUTO")
#   JOS_MC_IFACE: interface name the server should use (default "eth0")
#   JOS_MC_PORT: port base (default 57364)
#   JOS_MC_SESSCLIENTS: how many clients to wait for (default 20)
#   JOS_TASK_TYPE_ID: FOG taskTypeID for deploy (default 1; adjust to your environment)

: "${JOS_IMAGE_ID:=}"
: "${JOS_MC_NAME:=JOS-AUTO}"
: "${JOS_MC_IFACE:=eth0}"
: "${JOS_MC_PORT:=57364}"
: "${JOS_MC_SESSCLIENTS:=20}"
: "${JOS_TASK_TYPE_ID:=1}"

if [[ -z "$JOS_IMAGE_ID" ]]; then
  log "MULTICAST: JOS_IMAGE_ID not set; skipping multicast queue."
  exit 0
fi

FOG_BASE="http://${FOG_SERVER}/fog"

# 1) Find host id (best effort). Try GET /host/<serial> first.
HOST_JSON="$(jos_curl_json GET "${FOG_BASE}/host/${SERIAL}" 2>/dev/null || true)"
HOST_ID="$(echo "$HOST_JSON" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1)"

if [[ -z "$HOST_ID" ]]; then
  # As a fallback, we don't block the whole boot.
  log "MULTICAST: Could not resolve host id for ${SERIAL}; skipping multicast queue."
  exit 0
fi

log "MULTICAST: Resolved host id: ${HOST_ID}"

# 2) Create a task for this host (deploy task).
TASK_PAYLOAD="$(cat <<EOF
{"taskTypeID": ${JOS_TASK_TYPE_ID}, "shutdown": true}
EOF
)"

TASK_JSON="$(jos_curl_json POST "${FOG_BASE}/host/${HOST_ID}/task" "${TASK_PAYLOAD}" 2>/dev/null || true)"
TASK_ID="$(echo "$TASK_JSON" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1)"
if [[ -z "$TASK_ID" ]]; then
  log "MULTICAST: Could not create host task; response: ${TASK_JSON}"
  exit 0
fi

log "MULTICAST: Created host task id: ${TASK_ID}"

# 3) Create a multicast session.
MC_NAME="${JOS_MC_NAME}-${JOS_IMAGE_ID}"
MC_PAYLOAD="$(cat <<EOF
{
  "name": "${MC_NAME}",
  "port": "${JOS_MC_PORT}",
  "clients": "-2",
  "sessclients": "${JOS_MC_SESSCLIENTS}",
  "interface": "${JOS_MC_IFACE}",
  "isDD": "1",
  "state": "3",
  "image": "${JOS_IMAGE_ID}"
}
EOF
)"

MC_JSON="$(jos_curl_json POST "${FOG_BASE}/multicastsession" "${MC_PAYLOAD}" 2>/dev/null || true)"
MC_ID="$(echo "$MC_JSON" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1)"
if [[ -z "$MC_ID" ]]; then
  log "MULTICAST: Could not create multicast session; response: ${MC_JSON}"
  exit 0
fi

log "MULTICAST: Created multicast session id: ${MC_ID}"

# 4) Associate the host task to the multicast session.
ASSOC_PAYLOAD="$(cat <<EOF
{"msID": ${MC_ID}, "taskID": ${TASK_ID}}
EOF
)"

ASSOC_JSON="$(jos_curl_json POST "${FOG_BASE}/multicastsessionassociation" "${ASSOC_PAYLOAD}" 2>/dev/null || true)"
if echo "$ASSOC_JSON" | grep -q '"id"[[:space:]]*:'; then
  log "MULTICAST: Associated host task to multicast session."
else
  log "MULTICAST: Could not associate task to multicast session; response: ${ASSOC_JSON}"
fi

# 5) Start receiving (client-side) using udp-receiver with the required watchdog.
# This keeps the technician experience "PXE and walk away". The server side (JOG/FOG)
# is responsible for starting udp-sender for the same portbase/session.
ACTIVE_IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"
[[ -n "$ACTIVE_IFACE" ]] || ACTIVE_IFACE="eth0"

# Rendezvous defaults to DHCP NEXT SERVER (FOG_SERVER).
RDV_ADDR="${JOS_MC_RDV_ADDR:-$FOG_SERVER}"

# Provide escape hatch for custom args (advanced troubleshooting / special networks).
# Example:
#   JOS_UDP_RECEIVER_EXTRA_ARGS="--mcast-data-address 239.0.0.1 --ttl 32"
: "${JOS_UDP_RECEIVER_EXTRA_ARGS:=}"

log "MULTICAST: Starting udp-receiver (iface=${ACTIVE_IFACE} rdv=${RDV_ADDR} portbase=${JOS_MC_PORT})"

exec /scripts/jos-udpcast-receiver.sh \
  --interface "${ACTIVE_IFACE}" \
  --portbase "${JOS_MC_PORT}" \
  --mcast-rdv-address "${RDV_ADDR}" \
  --nokbd \
  --nopointopoint \
  ${JOS_UDP_RECEIVER_EXTRA_ARGS}

exit 0