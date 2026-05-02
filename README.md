# JOS - Jonathan's Operating System - An Ubuntu-Powered Secure Boot Compatible Imaging Solution

## Overview

**JOS** is a secure, Ubuntu-powered alternative to FOS (Free Operating System) designed specifically for FOG (Free and Open-source Ghost) imaging servers. It provides a modern, Secure Boot-compatible approach to system imaging and deployment.

## Purpose

JOS serves as a replacement imaging solution for FOG servers that requires:
- **Ubuntu-based foundation** - Leveraging the stability and package ecosystem of Ubuntu
- **Secure Boot compatibility** - Support for modern UEFI Secure Boot environments
- **FOG server integration** - Seamless compatibility with existing FOG imaging infrastructure

## Features

- Secure Boot compatible boot process
- Ubuntu-powered operating system base
- FOG imaging server integration
- Modern deployment capabilities

## FOS replacement roadmap (FOG parity)

- **Parity checklist**: `docs/fos-fog-parity-checklist.md`
- **Fork/refactor plan**: `docs/fos-fork-refactor-plan.md`
- **Architecture / boot chain**: `docs/architecture.md`

## Getting Started

To get started with JOS:

1. Clone this repository
2. Review the project structure and documentation
3. Follow the setup instructions for your FOG server environment
4. Deploy as an imaging solution

## DHCP "NEXT SERVER" integration (zero-touch targeting)

JOS is designed so technicians do **not** need to type or select a FOG server. Instead, JOS will automatically talk to the **DHCP-provided "NEXT SERVER"** address (BOOTP `siaddr`) that your PXE flow already depends on.

- **Where JOS gets it**: BusyBox `udhcpc` exposes `siaddr` to its script handler. JOS captures it at boot into `/tmp/jos-next-server`.
- **How JOS uses it**: when any script loads `$FOG_CONFIG_FILE`, if `FOG_SERVER` is not explicitly set, JOS will default `FOG_SERVER` to `/tmp/jos-next-server`.

### What the admin must do

- **DHCP scope**: ensure `next-server` (or equivalent) is set to the IP of your **FOG server**.
  - ISC dhcpd example:

```bash
next-server 10.0.0.5;
filename "ipxe.efi";
```

- **Provide API tokens** to JOS via a config file inside the initrd/OS:
  - Default path: `/etc/fog/jos.conf`
  - Or set `FOG_CONFIG_FILE=/path/to/jos.conf` in your boot environment.

Example `/etc/fog/jos.conf`:

```bash
# FOG_SERVER is optional if DHCP NEXT SERVER is configured (hostname or ip:port).
# FOG_SERVER="10.0.0.5"

FOG_API_KEY="YOUR_GLOBAL_FOG_API_TOKEN"
FOG_USER_TOKEN="YOUR_USER_API_TOKEN"

# HTTPS FOG UI / API (recommended for production): set FOG_USE_SSL=1.
# For lab self-signed certs only: FOG_SSL_INSECURE=1 with curl (/tools/curl).
# Pin a CA bundle inside the initramfs if you terminate TLS locally:
# FOG_CA_BUNDLE="/etc/ssl/certs/fog-ca.crt"

FOG_USE_SSL="0"
# FOG_SSL_INSECURE="0"

# Host registration uses FOG REST routes documented at docs.fogproject.org (GET …/host/search,
# POST …/host/create). Override default enabled client modules if your FOG version requires it:
# JOS_MODULES_JSON='["7","9","13","6","11","2","12"]'

# --- FOG version-aware API paths (automatic) ---
# On boot, JOS probes $(FOG_SERVER)/fog/management/index.php for a semver, caches /tmp/jos-fog-profile.env,
# then picks POST path order (/host/create vs /host root, etc.). Override if needed:
# FOG_VERSION_OVERRIDE="1.5.10.41"
# JOS_FOG_SKIP_VERSION_PROBE="1"
# JOS_FOG_FORCE_PROBE="1"
# JOS_FOG_API_STYLE="modern"    # force path order: modern | legacy | auto (default)

# Optional: enable auto multicast queueing
JOS_IMAGE_ID="3"
JOS_MC_SESSCLIENTS="20"
JOS_MC_IFACE="eth0"
JOS_MC_PORT="57364"
JOS_TASK_TYPE_ID="1"

# Optional: override multicast rendezvous (defaults to DHCP NEXT SERVER / FOG_SERVER)
# JOS_MC_RDV_ADDR="10.0.0.5"

# Optional: extra udp-receiver args (advanced)
# JOS_UDP_RECEIVER_EXTRA_ARGS="--ttl 32"
```

## Multicast receiver binary (udpcast)

JOS uses `udp-receiver` for multicast imaging. The initrd build pulls `udp-receiver` + `udp-sender` from the official udpcast Debian package and places them in `initrd/tools/` so they are available at runtime as:

- `/tools/udp-receiver`
- `/tools/udp-sender`

## Multicast receive behavior (what happens after PXE)

If `JOS_IMAGE_ID` is set, `jos-multicast.sh` will:

- resolve the numeric host id (`GET …/host/search/<name>`)
- queue a deploy task (`POST …/host/<id>/task` with `taskTypeID` per FOG Route::task)
- create a multicast session (`POST …/multicastsession/create`)
- associate task and session when a task id is visible on the host record (`POST …/multicastsessionassociation/create`)
- immediately `exec` into `/scripts/jos-udpcast-receiver.sh`, which runs `udp-receiver` **with the required weak-link watchdog**:
  - every 10 seconds it checks udp-receiver output
  - if avg speed < 30MB/s for 3 consecutive checks, it kills udp-receiver and reboots

Server-side requirement (your portable JOG/FOG server):
- start `udp-sender` for the same `portbase` and rendezvous address so clients can join.

## FOG deploy / capture tasks (unicast — FOS-style workflow)

After registration + inventory, **`jos-fog-task-runner.sh`** polls **`GET /fog/host/{id}`** and executes tasks by **`taskTypeID`** (deploy/capture/debug variants per FOG docs).

- **Deploy (`taskTypeID` 1 / 13 / 15)**: mounts **`${FOG_SERVER}:/images`**, resolves the image directory via **`GET /fog/image/{imageID}`**, restores **`d1.partitions`** (needs **`sfdisk`** baked into initrd at build time) then restores **`d1p*.img`** with **`partclone`**.
- **Destructive writes are gated**: export **`JOS_IMAGING_ALLOW_DISK_WRITE=1`** (and usually confirm imaging intent in your process). Without it, deploy refuses to touch disks.
- **NFS client**: the initrd bundles **`mount.nfs`** from the build host (`nfs-common`). You still need **kernel NFS client support** (modules or built-in) for mounts to succeed at runtime.
- **Capture (`taskTypeID` 2 / 14)**: not implemented yet (`jos-imaging-unicast.sh` exits with a clear message).

### What the technician does

- Power on target laptop
- Press **F12**
- Select **Boot from IPv4**
- Walk away (JOS will DHCP, discover NEXT SERVER, register/update the host, upload inventory, wait for a FOG task, then execute imaging when scheduled — **or** queue multicast if `JOS_IMAGE_ID` is set)

## Repository layout

| Path | Purpose |
|------|---------|
| `build/` | Fetch BusyBox/static tools; assemble `initrd.img` |
| `initrd/` | Initramfs root (`init`, `scripts/`, runtime `tools/` populated at build time) |
| `config/` | Reference configs (e.g. iPXE fragments) — **not** signed boot binaries |
| `docs/` | Architecture and operational notes |

Third-party binaries under `initrd/bin`, `initrd/tools`, etc. are **generated by build scripts** and gitignored — do not commit them.

## Repository Structure

- **Main branch** - `main` (default development branch)
- **License** - Check repository for license details
- **Issues & Pull Requests** - Contributions and issue tracking are enabled

## Contributing

This project supports pull requests and issue tracking. Feel free to contribute improvements or report issues.

## Status

🔄 **Active Development** - Repository recently created and actively maintained
