#!/bin/bash
set -e
exec 2>>/tmp/jos_error.log

# Minimal udhcpc handler for initramfs.
# Key output: DHCP "NEXT SERVER" (siaddr) for auto-targeting FOG.

. /scripts/jos-common.sh

[[ -n "${1:-}" ]] || die "UDHCPC: missing action"
ACTION="$1"

case "$ACTION" in
  deconfig)
    ifconfig "$interface" up || true
    ifconfig "$interface" 0.0.0.0 || true
    ;;

  renew|bound)
    # udhcpc provides: interface, ip, subnet, broadcast, router, dns, siaddr, boot_file, serverid, etc.
    local_bcast=""
    local_mask=""
    [[ -n "${broadcast:-}" ]] && local_bcast="broadcast $broadcast"
    [[ -n "${subnet:-}" ]] && local_mask="netmask $subnet"

    ifconfig "$interface" "$ip" $local_bcast $local_mask

    # Default route
    if [[ -n "${router:-}" ]]; then
      while route del default gw 0.0.0.0 dev "$interface" 2>/dev/null; do :; done
      for r in $router; do
        route add default gw "$r" dev "$interface" || true
      done
    fi

    # Capture the important DHCP values for later scripts.
    echo "${interface}" > /tmp/jos-active-iface
    [[ -n "${siaddr:-}" ]] && echo "${siaddr}" > /tmp/jos-next-server
    [[ -n "${serverid:-}" ]] && echo "${serverid}" > /tmp/jos-dhcp-serverid
    [[ -n "${boot_file:-}" ]] && echo "${boot_file}" > /tmp/jos-boot-file

    # Optional: DNS list
    if [[ -n "${dns:-}" ]]; then
      echo "$dns" > /tmp/jos-dns
    fi

    log "UDHCPC: iface=$interface ip=$ip siaddr=${siaddr:-} boot_file=${boot_file:-}"
    ;;
esac

exit 0

