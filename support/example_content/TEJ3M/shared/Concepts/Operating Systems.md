---
title: Operating Systems
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
Underneath every program you have ever run is one piece of software
whose whole job is to stop the programs fighting: over the processor,
over memory, over the one printer. That is the operating system, and
its features matter far less than its functions.

## The five functions

| Function | What it means | What it looks like when it fails |
| --- | --- | --- |
| **Process management** | Deciding which program runs on which core, and for how long | One program freezes the machine instead of just itself |
| **Memory management** | Giving each process its own space and keeping it there | A fault in one program corrupts another |
| **File system management** | Turning blocks on a drive into named files with permissions | Files that vanish, or that anyone can read |
| **Device management** | Talking to hardware through drivers so applications do not have to | A new printer that no program can find |
| **User and security management** | Accounts, permissions, and who may do what | One user's mistake takes down everybody's data |

Everything else — the window manager, the app store, the settings
panel — is a feature. Useful, replaceable, and not what makes it an
operating system.

## The families you will meet on a bench

- **Windows**, because most business desktops run it and most driver
  support targets it first.
- **Linux**, in dozens of distributions, because servers, network
  equipment, and every embedded board in this room run it or something
  like it.
- **macOS**, Unix underneath, with tight hardware integration.
- **Real-time and embedded systems**, where the requirement is not
  speed but *predictability* — a response guaranteed within a stated
  time, which is why they run engines, pacemakers, and industrial
  controllers rather than a general-purpose OS.

## Server, desktop, and why the same kernel does both

A server edition typically ships with no desktop, fewer services
listening, longer support, and features desktops do not need — roles
like file, print, directory, and virtualisation. Same core, different
defaults, because the machine's job is different. A technician who
installs a desktop edition on a server has not made a small mistake;
they have made a support commitment somebody else will inherit.

## Running multiple operating systems: dual boot and virtualisation

When a single physical computer must support workloads requiring different
operating systems, two main architectures exist:

- **Dual-boot configuration:** The storage drive is partitioned with
  distinct file systems, and a bootloader (such as GRUB or Windows Boot
  Manager) presents a menu at startup. Each operating system runs with
  native, bare-metal hardware access and full processor/GPU performance, but
  switching requires a complete reboot and only one system operates at a time.
- **Virtual machines (VMs):** A hypervisor runs on top of the host operating
  system (Type 2 hosted) or directly on bare hardware (Type 1 bare-metal).
  Guest operating systems run concurrently inside isolated virtual hardware
  containers. Virtual disks and snapshots make backups and rollbacks trivial,
  though the guest systems share the host's physical RAM and CPU cores.

## How the OS interacts with firmware and hardware

The handoff between firmware and the operating system is a clean boundary:

1. **Boot handoff:** The BIOS/UEFI discovers and initialises essential
   motherboard hardware, verifies the boot drive, loads the bootloader, and
   passes hardware tables (memory maps, ACPI device descriptions) to the OS
   kernel.
2. **Driver abstraction:** Once running, the operating system kernel does not
   call BIOS routines; instead, it uses dedicated **device drivers** to
   communicate directly with hardware registers, handle interrupts, and manage
   direct memory access (DMA).
3. **Firmware coordination:** The operating system continues to query firmware
   for system-level power management (sleep states, thermal throttling), clock
   synchronisation, and hardware error logging.

## Where this touches your work

The choice is not "which is best" but "which fits the requirement".
That is the reasoning [[The Client Build]] asks you to write down, and
it is the reason two machines on the same bench in
[[Two Operating Systems, One Machine]] can run different systems and
both be right.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A2.1]]

![[A2.4]]

![[B2.3]]
%%curriculum-end%%
