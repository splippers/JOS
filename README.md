# JOS — Jonathan’s Operating System
A Secure-Boot-Compatible Imaging Runtime for FOG

Type: Infrastructure  
Intent: Pillar (credibility / real-world systems)  
Audience: Sysadmins / IT Operations

--------------------------------------------------

OVERVIEW

JOS is a modern, Ubuntu-based replacement for FOG’s legacy FOS imaging environment, designed specifically for contemporary UEFI and Secure Boot deployments.

It provides a zero-touch, API-driven imaging runtime that integrates cleanly with existing FOG infrastructure while addressing long-standing pain points in PXE booting, automation, and operational safety.

--------------------------------------------------

WHY JOS EXISTS

FOG’s FOS environment remains functional, but struggles with:

- Secure Boot requirements
- Modern UEFI hardware
- Version-fragile scripts
- Accidental destructive operations by technicians

JOS exists to solve these problems without replacing FOG itself.

--------------------------------------------------

CORE PRINCIPLES

- FOG-native: uses the FOG REST API rather than brittle screen-scraping
- Zero-touch: no technician interaction required after PXE selection
- Safe by default: destructive disk writes must be explicitly enabled
- Modern boot chain: Ubuntu-based userspace compatible with Secure Boot
- Operationally boring: predictable, auditable, repeatable behaviour

--------------------------------------------------

KEY CAPABILITIES

SECURE BOOT COMPATIBLE RUNTIME
- Ubuntu-based initrd and userspace
- Designed for modern UEFI systems
- Coexists with existing PXE and iPXE flows

DHCP NEXT-SERVER AUTO-DISCOVERY
- Automatically discovers the FOG server via DHCP siaddr
- Removes manual server selection
- Reduces technician error and deployment friction

REST-DRIVEN TASK EXECUTION
- Registers and inventories hosts via the FOG API
- Polls and executes deploy or capture tasks
- Adapts automatically to FOG API version differences

EXPLICIT DESTRUCTIVE-ACTION GATING
- Disk writes are disabled by default
- Imaging requires an explicit allow flag
- Prevents accidental wipes and unsafe execution

--------------------------------------------------

IMAGING MODES

UNICAST IMAGING
- FOS-style deployment workflow
- Uses partclone and sfdisk
- Explicitly gated destructive actions

MULTICAST IMAGING
- Automatic task creation and session joining
- Built-in watchdog for stalled transfers
- Safe reboot on repeated low-throughput detection

--------------------------------------------------

TECHNICIAN WORKFLOW

1. Power on target system
2. Press F12
3. Select Boot from IPv4
4. Walk away

JOS will:
- Acquire DHCP configuration
- Discover the FOG server automatically
- Register or update the host
- Upload inventory
- Wait for a queued task
- Execute imaging without further interaction

--------------------------------------------------

REPOSITORY STRUCTURE

build/     - build scripts for initrd and runtime tooling  
initrd/    - runtime filesystem and boot logic  
config/    - reference PXE and iPXE configuration fragments  
docs/      - architecture, boot flow, and operational notes  

Generated binaries are produced during build and are not committed.

--------------------------------------------------

STATUS

Active development.

This project is functional, evolving, and intended for real-world deployment in controlled environments. Contributions, issues, and discussion are welcome.

==================================================

PROJECT TAGGING SYSTEM (APPLY TO ALL REPOSITORIES)

Each repository should declare three tags near the top of its README.

TAG AXIS 1: TYPE  
What kind of thing the project fundamentally is.

Allowed values:
- Simulation
- Infrastructure
- Game
- Tool
- Meta-System
- Learning
- Satire
- Experiment
- Archive

TAG AXIS 2: INTENT  
Why this project exists from the creator’s perspective.

Allowed values:
- Engine (funds or enables other projects)
- Pillar (credibility, seriousness, trust)
- Playground (experimentation and fun)
- Teaching Tool
- Portfolio Signal
- Legacy Idea

TAG AXIS 3: AUDIENCE  
Who the project is primarily for.

Allowed values:
- Self
- Developers
- Sysadmins
- Learners
- Founders
- Households
- Institutions
- General Public

--------------------------------------------------

EXAMPLE FAMILY GROUPINGS

Infrastructure / Ops Family
- JOS
  Type: Infrastructure | Intent: Pillar | Audience: Sysadmins
- PypeLyne
  Type: Infrastructure | Intent: Support | Audience: Developers

Simulation / Learning Family
- VNA
  Type: Simulation | Intent: Engine | Audience: Learners
- CEO-Simulator
  Type: Simulation | Intent: Legacy Idea | Audience: Founders

Domestic Gamification Family
- BoreDOOM
  Type: Game | Intent: Engine | Audience: Households
- ChoreWars
  Type: Meta-System | Intent: Engine | Audience: General Public
