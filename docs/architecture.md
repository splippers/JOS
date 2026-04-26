# JOS Architecture

JOS is a Secure Boot–compatible PXE micro‑OS built on Ubuntu Minimal.

## Boot Flow
shim → grub → kernel → initrd → JOS init

## Core Components
- Networking (udhcpc)
- Serial detection
- Auto-registration
- Inventory capture
- Multicast queue logic

## DHCP NEXT SERVER as "FOG target"

In a PXE environment, DHCP provides a "next-server" field (BOOTP `siaddr`). JOS treats this value as the authoritative address for the imaging server, and uses it as the default `FOG_SERVER` value.

### Data flow

- `udhcpc` runs with `-s /scripts/udhcpc-jos.sh`
- On `bound` / `renew`, the handler writes:
  - `/tmp/jos-active-iface`: interface used for DHCP
  - `/tmp/jos-next-server`: DHCP `siaddr` (NEXT SERVER)
  - `/tmp/jos-boot-file`: DHCP boot file (option 67 / `boot_file`)

### Consumption

- `jos_load_fog_config` loads `$FOG_CONFIG_FILE` (default `/etc/fog/jos.conf`)
- If `FOG_SERVER` is not set in the config, JOS sets `FOG_SERVER="$(cat /tmp/jos-next-server)"`

This preserves a minimal admin experience: the DHCP scope controls which FOG server a technician boots into.