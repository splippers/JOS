#!/bin/bash
# shellcheck shell=bash
# NFS client helpers (kernel modules + mount.nfs from initrd). Sourced by imaging scripts.

jos_try_load_nfs_modules() {
  # Best-effort: requires matching kernel modules in the initramfs (or built-in NFS client in kernel).
  local m
  for m in sunrpc lockd grace nfs nfsv2 nfsv3 nfsv4; do
    modprobe "$m" 2>/dev/null || true
  done
}

# Mount FOG image store (default export /images) from FOG_SERVER.
jos_mount_fog_image_store() {
  local server="$1"
  local mnt="${2:-/mnt/fog-images}"
  local export_path="${JOS_FOG_IMAGES_EXPORT:-/images}"
  local vers="${JOS_FOG_NFS_VERS:-3}"

  jos_try_load_nfs_modules
  mkdir -p "$mnt"

  local mn=""
  for cand in /sbin/mount.nfs /usr/sbin/mount.nfs /tools/mount.nfs; do
    if [[ -x "$cand" ]]; then
      mn="$cand"
      break
    fi
  done
  [[ -n "$mn" ]] || die "NFS: mount.nfs not found (bundle nfs-common mount helper at build time)"

  log "NFS: mounting ${server}:${export_path} → ${mnt} (nfs vers=${vers})"
  # Match typical FOG fstab-style NFS mounts (TCP, moderate r/w sizes).
  "$mn" -o "nolock,rsize=32768,wsize=32768,tcp,vers=${vers}" "${server}:${export_path}" "$mnt"
}
