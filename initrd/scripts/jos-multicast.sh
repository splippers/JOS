#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# JOS multicast queue logic (FOG REST: POST host/id/task, POST multicastsession/create).

SERIAL="$1"

. /scripts/jos-common.sh

[[ -n "$SERIAL" ]] || die "MULTICAST: No serial passed to multicast script."
jos_load_fog_config

FOG_BASE="$(jos_fog_base_url)"

log "MULTICAST: FOG≈${FOG_VERSION_RAW:-?} mc_sess=${JOS_FOG_MC_SESSION_PATHS}"

log "MULTICAST: Preparing multicast queue for serial: $SERIAL"

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

HOST_ID="$(jos_fog_resolve_host_id "$SERIAL")"

if [[ -z "$HOST_ID" ]]; then
  log "MULTICAST: Could not resolve host id for ${SERIAL}; skipping multicast queue."
  exit 0
fi

log "MULTICAST: Resolved host id: ${HOST_ID}"

TASK_PAYLOAD="$(cat <<EOF
{"taskTypeID": ${JOS_TASK_TYPE_ID}, "shutdown": true}
EOF
)"

jos_curl_json POST "${FOG_BASE}/host/${HOST_ID}/task" "${TASK_PAYLOAD}" >/dev/null 2>&1 || \
  log "MULTICAST: task API returned non-zero (task may still be queued); continuing"

HOST_AFTER="$(jos_curl_json GET "${FOG_BASE}/host/${HOST_ID}" 2>/dev/null || true)"
TASK_ID="$(jos_fog_extract_task_id_from_host_json "$HOST_AFTER")"
if [[ -n "$TASK_ID" ]]; then
  log "MULTICAST: Host task id (from host record): ${TASK_ID}"
else
  log "MULTICAST: Could not read task id from host JSON (FOG may omit body on POST); continuing."
fi

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

MC_JSON="$(jos_fog_api_post_first_id "$FOG_BASE" "$JOS_FOG_MC_SESSION_PATHS" "${MC_PAYLOAD}" 2>/dev/null || true)"
MC_ID="$(jos_fog_extract_json_id "$MC_JSON")"
if [[ -z "$MC_ID" ]]; then
  log "MULTICAST: Could not create multicast session; response: ${MC_JSON}"
  exit 0
fi

log "MULTICAST: Created multicast session id: ${MC_ID}"

if [[ -n "$TASK_ID" ]]; then
  ASSOC_PAYLOAD="$(cat <<EOF
{"msID": ${MC_ID}, "taskID": ${TASK_ID}}
EOF
)"
  ASSOC_JSON="$(jos_fog_api_post_first_id "$FOG_BASE" "$JOS_FOG_MC_ASSOC_PATHS" "${ASSOC_PAYLOAD}" 2>/dev/null || true)"
  if jos_fog_json_has_entity_id "$ASSOC_JSON"; then
    log "MULTICAST: Associated host task to multicast session."
  else
    log "MULTICAST: Could not associate task to multicast session; response: ${ASSOC_JSON}"
  fi
else
  log "MULTICAST: No task id from host record — skipping session association (check deploy task / FOG logs)."
fi

ACTIVE_IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"
[[ -n "$ACTIVE_IFACE" ]] || ACTIVE_IFACE="eth0"

RDV_ADDR="${JOS_MC_RDV_ADDR:-$FOG_SERVER}"

: "${JOS_UDP_RECEIVER_EXTRA_ARGS:=}"

log "MULTICAST: Starting udp-receiver (iface=${ACTIVE_IFACE} rdv=${RDV_ADDR} portbase=${JOS_MC_PORT})"

exec /scripts/jos-udpcast-receiver.sh \
  --interface "${ACTIVE_IFACE}" \
  --portbase "${JOS_MC_PORT}" \
  --mcast-rdv-address "${RDV_ADDR}" \
  --nokbd \
  --nopointopoint \
  ${JOS_UDP_RECEIVER_EXTRA_ARGS}
