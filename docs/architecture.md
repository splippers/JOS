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