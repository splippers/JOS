#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# Deprecated entrypoint — imaging is driven by `jos-fog-task-runner.sh` → `jos-imaging-unicast.sh`.

SERIAL="$1"

. /scripts/jos-common.sh

log "IMAGING: serial=${SERIAL:-unknown} (jos-imaging.sh is deprecated — use jos-fog-task-runner.sh)"

exit 0
