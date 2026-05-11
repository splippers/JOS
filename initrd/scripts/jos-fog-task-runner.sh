#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log
# Poll FOG for host tasks (FOG REST: GET /host/{id}) and dispatch imaging like classic FOS workflows.

SERIAL="${1:-}"

. /scripts/jos-common.sh

[[ -n "$SERIAL" ]] || die "TASKS: serial required"
[[ -x /tools/jq ]] || die "TASKS: /tools/jq missing — rebuild initrd (build/fetch-jq.sh)"

jos_load_fog_config

FOG_BASE="$(jos_fog_base_url)"
HOST_ID="$(jos_fog_resolve_host_id "$SERIAL")"
[[ -n "$HOST_ID" ]] || die "TASKS: could not resolve host id for serial=${SERIAL}"

POLL="${JOS_TASK_POLL_SEC:-5}"
MAX_WAIT="${JOS_TASK_WAIT_SEC:-7200}"
elapsed=0

log "TASKS: polling FOG for tasks (host id=${HOST_ID}, poll=${POLL}s, max_wait=${MAX_WAIT}s)"

while [[ "$elapsed" -lt "$MAX_WAIT" ]]; do
  HJSON="$(jos_curl_json GET "${FOG_BASE}/host/${HOST_ID}" 2>/dev/null || true)"
  CORE="$(jos_fog_json_core "$HJSON")"

  if [[ "$(jos_fog_jq "$CORE" '.task|type')" == "null" ]]; then
    log "TASKS: no task yet — sleeping ${POLL}s (${elapsed}/${MAX_WAIT}s)"
    sleep "$POLL"
    elapsed=$((elapsed + POLL))
    continue
  fi

  TYPE="$(jos_fog_jq "$CORE" '(.task.typeID // .task.type.id // empty)')"
  TID="$(jos_fog_jq "$CORE" '(.task.id // empty)')"
  IID="$(jos_fog_jq "$CORE" '(.task.imageID // .task.image.id // empty)')"

  TYPE="${TYPE//\"/}"
  TID="${TID//\"/}"
  IID="${IID//\"/}"

  log "TASKS: active task id=${TID:-?} typeID=${TYPE:-?} imageID=${IID:-?}"

  case "$TYPE" in
    1|13|15)
      [[ -n "$IID" ]] || die "TASKS: deploy task missing imageID"
      jos_fog_task_checkin "$TID"
      exec /scripts/jos-imaging-unicast.sh deploy "$SERIAL" "$HOST_ID" "$TID" "$IID"
      ;;
    2|14)
      [[ -n "$IID" ]] || die "TASKS: capture task missing imageID"
      jos_fog_task_checkin "$TID"
      exec /scripts/jos-imaging-unicast.sh capture "$SERIAL" "$HOST_ID" "$TID" "$IID"
      ;;
    8|16)
      log "TASKS: inventory task — inventory already uploaded earlier this boot; exiting runner."
      jos_fog_task_done "$TID"
      exit 0
      ;;
    12)
      [[ -n "$IID" ]] || die "TASKS: multicast task missing imageID"
      jos_fog_task_checkin "$TID"
      export JOS_IMAGE_ID="$IID"
      exec /scripts/jos-multicast.sh "$SERIAL"
      ;;
    *)
      die "TASKS: unsupported task typeID=${TYPE} — extend jos-fog-task-runner.sh (FOG Route::task)"
      ;;
  esac
done

log "TASKS: timed out waiting for a task (${MAX_WAIT}s)."
exit 0
