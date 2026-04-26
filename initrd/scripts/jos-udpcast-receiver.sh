#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log

# Wrapper to run udp-receiver with the mandatory "suicide clause" monitor:
# - Check output every 10 seconds
# - If avg speed < 30MB/s for 3 consecutive checks -> kill receiver and reboot

. /scripts/jos-common.sh

UDP_RECEIVER="${UDP_RECEIVER:-/tools/udp-receiver}"
LOG_FILE="${JOS_UDPCAST_LOG:-/tmp/udp-receiver.log}"

if [[ ! -x "$UDP_RECEIVER" ]]; then
  UDP_RECEIVER="udp-receiver"
fi

require_cmd "$UDP_RECEIVER"
require_cmd reboot

touch "$LOG_FILE"

# Start receiver
log "UDPCast: starting receiver (logging to $LOG_FILE)"
"$UDP_RECEIVER" "$@" 2>&1 | tee -a "$LOG_FILE" &
UDP_PID=$!

weak=0

extract_speed_mb_s() {
  # Best-effort parse of udp-receiver output. Different udpcast versions vary.
  # We look for patterns like:
  #   "Average rate: 45.6MB/s"
  #   "avg 28.1 MB/s"
  #   " 31.2MB/s"
  local s
  s="$(tail -n 50 "$LOG_FILE" | \
      sed -n -E 's/.*([Aa]verage[^0-9]*|avg[^0-9]*)([0-9]+(\.[0-9]+)?) *([Mm][Bb]\/s).*/\2/p' | \
      tail -n1)"
  if [[ -z "$s" ]]; then
    s="$(tail -n 50 "$LOG_FILE" | sed -n -E 's/.*[^0-9]([0-9]+(\.[0-9]+)?) *[Mm][Bb]\/s.*/\1/p' | tail -n1)"
  fi
  echo "${s:-0}"
}

# If the receiver exits quickly (arg error, missing perms, etc.), do not hang.
sleep 1
if ! kill -0 "$UDP_PID" 2>/dev/null; then
  err "UDPCast: udp-receiver exited immediately; last output:"
  tail -n 50 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi

while kill -0 "$UDP_PID" 2>/dev/null; do
  sleep 10

  speed="$(extract_speed_mb_s)"
  # integer compare without bc: compare floor value
  speed_int="${speed%.*}"
  [[ -n "$speed_int" ]] || speed_int=0

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

