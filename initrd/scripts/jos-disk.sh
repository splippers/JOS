#!/bin/bash
# shellcheck shell=bash
# Disk inventory helpers — rules: lsblk -J + largest non-removable fixed disk.
# Sourced by jos-inventory.sh (functions only; no top-level side effects).

# Emit lsblk JSON when util-linux lsblk supports -J (BusyBox lsblk often does not).
jos_lsblk_json_full() {
  if ! command -v lsblk >/dev/null 2>&1; then
    echo "{}"
    return 0
  fi
  if lsblk --help 2>&1 | grep -q '[[:space:]]-J'; then
    lsblk -J -b 2>/dev/null || echo "{}"
  else
    echo "{}"
  fi
}

# Largest fixed (non-removable) disk by sysfs sizes; handles VMD/NVMe/USB layout.
jos_largest_fixed_disk_sysfs() {
  local best_name="" best_bytes=0 devpath blk sz rm sector_bytes

  sector_bytes=512

  for devpath in /sys/block/*; do
    [[ -d "$devpath" ]] || continue
    blk="${devpath#/sys/block/}"

    case "$blk" in
      loop*|ram*|dm-*|fd*|sr*|zram*) continue ;;
    esac

    rm="$(cat "${devpath}/removable" 2>/dev/null || echo 1)"
    [[ "$rm" == "0" ]] || continue

    # Partition devices expose a `partition` file; whole-disk devices typically do not.
    if [[ -f "${devpath}/partition" ]]; then
      continue
    fi

    sz="$(cat "${devpath}/size" 2>/dev/null || echo 0)"
    case "$sz" in *[!0-9]*|"") continue ;; esac
    sz=$((sz * sector_bytes))

    if [[ "$sz" -gt "$best_bytes" ]]; then
      best_bytes="$sz"
      best_name="$blk"
    fi
  done

  printf '%s:%s' "$best_name" "$best_bytes"
}
