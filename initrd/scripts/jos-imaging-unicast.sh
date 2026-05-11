#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log
# Unicast deploy/capture (FOG task types 1/2 and debug variants). SMB-safe: disk writes are gated.

ACTION="${1:-}"
SERIAL="${2:-}"
HOST_ID="${3:-}"
TASK_ID="${4:-}"
IMAGE_ID="${5:-}"

. /scripts/jos-common.sh
# shellcheck disable=SC1091
. /scripts/jos-disk.sh
# shellcheck disable=SC1091
. /scripts/jos-nfs.sh

[[ -n "$ACTION" ]] || die "IMAGING: action required (deploy|capture)"
[[ -n "$SERIAL" ]] || die "IMAGING: serial required"
[[ -n "$HOST_ID" ]] || die "IMAGING: host id required"
[[ -n "$IMAGE_ID" ]] || die "IMAGING: image id required"

jos_load_fog_config

jos_part_path_for_index() {
  local base="$1" idx="$2"
  case "$base" in
    nvme*|mmcblk*|loop*) printf '/dev/%sp%s' "$base" "$idx" ;;
    *) printf '/dev/%s%s' "$base" "$idx" ;;
  esac
}

jos_pick_partclone_bin_for_fstype() {
  local fs
  fs="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$fs" in
    *ntfs*) echo "/tools/partclone.ntfs" ;;
    *ext*) echo "/tools/partclone.extfs" ;;
    *fat*|*vfat*) echo "/tools/partclone.fat" ;;
    *)
      echo ""
      ;;
  esac
}

jos_fstype_for_part_from_file() {
  local fstypes="$1" partnum="$2"
  [[ -f "$fstypes" ]] || { echo ""; return 0; }
  grep -m1 -E "p${partnum}([^0-9]|$)|[^a-zA-Z0-9]${partnum}([^0-9]|$)" "$fstypes" 2>/dev/null | awk '{print $2}' || true
}

deploy_from_nfs() {
  : "${JOS_IMAGING_ALLOW_DISK_WRITE:?IMAGING: refusing destructive deploy — export JOS_IMAGING_ALLOW_DISK_WRITE=1}"

  [[ -x /tools/jq ]] || die "IMAGING: /tools/jq missing (rebuild initrd)"

  local img_json core path_rel imgdir pair disk disk_dev mnt
  img_json="$(jos_fog_get_image_json "$IMAGE_ID")"
  core="$(jos_fog_json_core "$img_json")"
  path_rel="$(jos_fog_jq "$core" '.path // empty')"
  [[ -n "$path_rel" ]] || die "IMAGING: image ${IMAGE_ID} has empty path in FOG"

  mnt="/mnt/fog-images"
  jos_mount_fog_image_store "${FOG_SERVER}" "$mnt"

  imgdir="${mnt}/${path_rel}"
  [[ -d "$imgdir" ]] || die "IMAGING: image directory missing: ${imgdir}"

  pair="$(jos_largest_fixed_disk_sysfs)"
  disk="${pair%%:*}"
  [[ -n "$disk" ]] || die "IMAGING: could not select destination disk"
  disk_dev="/dev/${disk}"

  log "IMAGING: deploy image path=${path_rel} disk=${disk_dev} task=${TASK_ID:-?}"

  if [[ -f "${imgdir}/d1.partitions" ]]; then
    local sf="/usr/bin/sfdisk"
    [[ -x "$sf" ]] || sf="sfdisk"
    command -v "$sf" >/dev/null 2>&1 || die "IMAGING: sfdisk missing (rebuild initrd with fetch-sfdisk.sh)"
    log "IMAGING: applying partition layout from d1.partitions"
    "$sf" --force "$disk_dev" <"${imgdir}/d1.partitions"
    sleep 2
  elif [[ -f "${imgdir}/d1.mbr" ]]; then
    case "${JOS_IMAGING_WRITE_MBR:-0}" in
      1|true|yes|on)
        log "IMAGING: writing MBR bootsector (446 bytes) from d1.mbr"
        dd if="${imgdir}/d1.mbr" of="$disk_dev" bs=446 count=1 conv=fsync
        sleep 1
        ;;
      *)
        log "IMAGING: d1.mbr present but JOS_IMAGING_WRITE_MBR not enabled — skipping MBR write"
        ;;
    esac
  else
    log "IMAGING: no d1.partitions or d1.mbr — assuming partitions already exist"
  fi

  local f num fs pctool found=0
  for f in "${imgdir}"/d1p*.img; do
    [ -e "$f" ] || continue
    found=1
    num="$(basename "$f")"
    num="${num#d1p}"
    num="${num%.img}"
    case "$num" in *[!0-9]*|"") die "IMAGING: bad partition image name: $f" ;; esac

    fs="$(jos_fstype_for_part_from_file "${imgdir}/d1.original.fstypes" "$num")"
    pctool="$(jos_pick_partclone_bin_for_fstype "$fs")"
    if [[ -z "$pctool" || ! -x "$pctool" ]]; then
      [[ -x /tools/partclone.extfs ]] && pctool="/tools/partclone.extfs"
    fi
    [[ -x "$pctool" ]] || die "IMAGING: no suitable partclone helper for partition ${num} (fs='${fs:-unknown}')"

    local dest
    dest="$(jos_part_path_for_index "$disk" "$num")"
    [[ -b "$dest" ]] || die "IMAGING: destination block device missing: ${dest}"

    log "IMAGING: restoring ${f} → ${dest} using ${pctool}"
    "$pctool" -r -s "$f" -o "$dest"
  done
  [ "$found" -eq 1 ] || die "IMAGING: no d1p*.img files under ${imgdir}"

  log "IMAGING: deploy finished."
  jos_fog_task_done "${TASK_ID:-}"
  case "${JOS_IMAGING_REBOOT_AFTER_DEPLOY:-1}" in 1|true|yes|on)
    sync
    reboot -f || reboot || true
  esac
}

capture_to_nfs() {
  : "${JOS_IMAGING_ALLOW_DISK_WRITE:?IMAGING: refusing capture — export JOS_IMAGING_ALLOW_DISK_WRITE=1}"
  [[ -x /tools/jq ]] || die "IMAGING: /tools/jq missing (rebuild initrd)"

  local pair disk disk_dev mnt imgdir path_rel
  pair="$(jos_largest_fixed_disk_sysfs)"
  disk="${pair%%:*}"
  [[ -n "$disk" ]] || die "IMAGING: could not select source disk for capture"
  disk_dev="/dev/${disk}"

  local img_json core
  img_json="$(jos_fog_get_image_json "$IMAGE_ID")"
  core="$(jos_fog_json_core "$img_json")"
  path_rel="$(jos_fog_jq "$core" '.path // empty')"
  [[ -n "$path_rel" ]] || die "IMAGING: image ${IMAGE_ID} has empty path in FOG"

  mnt="/mnt/fog-images"
  jos_mount_fog_image_store "${FOG_SERVER}" "$mnt"

  imgdir="${mnt}/${path_rel}"
  mkdir -p "$imgdir"

  log "IMAGING: capture disk=${disk_dev} → ${imgdir} task=${TASK_ID:-?}"

  # Save partition table.
  sfdisk -d "$disk_dev" > "${imgdir}/d1.partitions" 2>/dev/null || \
    dd if="$disk_dev" bs=512 count=1 2>/dev/null | dd bs=446 count=1 > "${imgdir}/d1.mbr" 2>/dev/null || true

  # Capture each partition.
  local partdev partnum fs pctool imgfile
  for partdev in /dev/${disk}[0-9]* /dev/${disk}p[0-9]*; do
    [ -b "$partdev" ] || continue
    partnum="${partdev##*[!0-9]}"
    [ -n "$partnum" ] || continue

    fs="$(blkid -s TYPE -o value "$partdev" 2>/dev/null || true)"
    pctool="$(jos_pick_partclone_bin_for_fstype "$fs")"
    if [[ -z "$pctool" || ! -x "$pctool" ]]; then
      [[ -x /tools/partclone.extfs ]] && pctool="/tools/partclone.extfs"
    fi
    [[ -x "$pctool" ]] || { log "IMAGING: skipping ${partdev} (no partclone for fs='${fs:-unknown}')"; continue; }

    imgfile="${imgdir}/d1p${partnum}.img"
    log "IMAGING: capturing ${partdev} → ${imgfile} using ${pctool}"
    "$pctool" -c -s "$partdev" -o "$imgfile"

    echo "$partnum $fs" >> "${imgdir}/d1.original.fstypes"
  done

  log "IMAGING: capture finished."
  jos_fog_task_done "${TASK_ID:-}"
  sync
  reboot -f || reboot || true
}

case "$ACTION" in
  deploy) deploy_from_nfs ;;
  capture) capture_to_nfs ;;
  *) die "IMAGING: unknown action: $ACTION" ;;
esac

exit 0
