#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log

# udp-receiver wrapper with mandatory suicide clause:
# every 10s inspect throughput; if parsed avg < 30MB/s for 3 consecutive checks → kill + reboot.
# Unknown/zero parsed speed before the stream starts does not count as a strike.

. /scripts/jos-common.sh

UDP_RECEIVER="${UDP_RECEIVER:-/tools/udp-receiver}"
LOG_FILE="${JOS_UDPCAST_LOG:-/tmp/udp-receiver.log}"

if [[ ! -x "$UDP_RECEIVER" ]]; then
  UDP_RECEIVER="udp-receiver"
fi

require_cmd "$UDP_RECEIVER"
require_cmd reboot

touch "$LOG_FILE"

log "UDPCast: starting receiver (logging to $LOG_FILE)"
"$UDP_RECEIVER" "$@" 2>&1 | tee -a "$LOG_FILE" &
UDP_PID=$!

weak=0
# Ignore suicide strikes for the first N intervals (startup / parse settling). Default ~60s at 10s/step.
GRACE_LEFT="${JOS_UDPCAST_GRACE_CHECKS:-6}"

extract_speed_mb_s() {
  local s
  s="$(tail -n 50 "$LOG_FILE" | \
      sed -n -E 's/.*([Aa]verage[^0-9]*|avg[^0-9]*)([0-9]+(\.[0-9]+)?) *([Mm][Bb]\/s).*/\2/p' | \
      tail -n1)"
  if [[ -z "$s" ]]; then
    s="$(tail -n 50 "$LOG_FILE" | sed -n -E 's/.*[^0-9]([0-9]+(\.[0-9]+)?) *[Mm][Bb]\/s.*/\1/p' | tail -n1)"
  fi
  echo "${s:-}"
}

sleep 1
if ! kill -0 "$UDP_PID" 2>/dev/null; then
  err "UDPCast: udp-receiver exited immediately; last output:"
  tail -n 50 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi

while kill -0 "$UDP_PID" 2>/dev/null; do
  sleep 10

  speed="$(extract_speed_mb_s)"
  speed_int="${speed%%.*}"
  speed_int="$(printf '%s' "$speed_int" | tr -cd '0-9')"
  [ -n "$speed_int" ] || speed_int=0

  if [[ -z "$speed" ]]; then
    log "UDPCast: no throughput parse yet (waiting)"
    weak=0
    continue
  fi

  if [[ "$GRACE_LEFT" -gt 0 ]]; then
    GRACE_LEFT=$((GRACE_LEFT - 1))
    log "UDPCast: grace (${GRACE_LEFT} checks left after this) observed ~${speed}MB/s — not enforcing suicide clause yet"
    continue
  fi

  if [[ "$speed_int" -lt 30 ]]; then
    weak=$((weak + 1))
    err "UDPCast: weak link detected (avg ${speed}MB/s) strike ${weak}/3"
  else
    weak=0
    log "UDPCast: healthy (avg ${speed}MB/s)"
  fi

  if [[ "$weak" -ge 3 ]]; then
    err "UDPCast: suicide clause triggered; killing udp-receiver and rebooting"
    kill "$UDP_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$UDP_PID" 2>/dev/null || true
    reboot -f || reboot || true
    exit 1
  fi
done

wait "$UDP_PID" || true
log "UDPCast: receiver exited"
