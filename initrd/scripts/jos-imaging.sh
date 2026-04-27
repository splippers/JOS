#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log
# FOS parity: NFS + partclone deploy/imaging paths (stub — no fragile half-implementations).
# See docs/architecture.md and .cursor/rules/jos-unified.mdc §10.

SERIAL="$1"

. /scripts/jos-common.sh

log "IMAGING: serial=${SERIAL:-unknown}"

: "${JOS_ENABLE_NFS_IMAGING:=0}"
: "${JOS_ENABLE_PARTCLONE_DEPLOY:=0}"

if [[ "$JOS_ENABLE_NFS_IMAGING" != "1" && "$JOS_ENABLE_PARTCLONE_DEPLOY" != "1" ]]; then
  log "IMAGING: NFS/partclone imaging not enabled (set JOS_ENABLE_*=1 when implemented). OK."
  exit 0
fi

die "IMAGING: experimental flags set but NFS/partclone pipeline is not implemented in this initramfs yet."
