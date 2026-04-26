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
# FOG_SERVER is optional if DHCP NEXT SERVER is configured.
# FOG_SERVER="10.0.0.5"

FOG_API_KEY="YOUR_GLOBAL_FOG_API_TOKEN"
FOG_USER_TOKEN="YOUR_USER_API_TOKEN"

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

- create a host deploy task in FOG
- create a multicast session
- associate the host task to the multicast session
- immediately `exec` into `/scripts/jos-udpcast-receiver.sh`, which runs `udp-receiver` **with the required weak-link watchdog**:
  - every 10 seconds it checks udp-receiver output
  - if avg speed < 30MB/s for 3 consecutive checks, it kills udp-receiver and reboots

Server-side requirement (your portable JOG/FOG server):
- start `udp-sender` for the same `portbase` and rendezvous address so clients can join.

### What the technician does

- Power on target laptop
- Press **F12**
- Select **Boot from IPv4**
- Walk away (JOS will DHCP, discover NEXT SERVER, register/update the host, upload inventory, and queue multicast if enabled)

## Repository Structure

- **Main branch** - `main` (default development branch)
- **License** - Check repository for license details
- **Issues & Pull Requests** - Contributions and issue tracking are enabled

## Contributing

This project supports pull requests and issue tracking. Feel free to contribute improvements or report issues.

## Status

🔄 **Active Development** - Repository recently created and actively maintained
