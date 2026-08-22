---
title: Two Operating Systems, One Machine
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
Clients ask for it constantly: the machine has to run one thing that
only exists on Windows and another that only runs properly on Linux.
There are two answers, they fail differently, and today you build both.

> [!danger] Safety notes
> The hazard here is not electrical. **Everything on the target drive
> will be destroyed**, so before anything is installed you confirm the
> drive is a lab drive, you confirm it twice with a partner, and you
> confirm there is nothing on it anybody needs. Partitioning the wrong
> disk is the single most expensive mistake in this course, and it
> cannot be undone with a screwdriver.

## What you need

- [ ] A lab machine whose drive may be erased
- [ ] Installation media for two operating systems
- [ ] Virtualisation support enabled in firmware — check it first
- [ ] A second machine, or a phone, for looking things up when the one
      you are working on is mid-install

## Part A — Dual boot

1. **Back up, or prove there is nothing to back up.** Write which it
   was in your journal.
2. **Plan the partitions on paper** before touching the installer: how
   much for each system, where the shared data will live, which
   filesystem each can read.
3. **Install the first system**, leaving unallocated space.
4. **Install the second** into that space and let the bootloader pick
   up both.
5. **Boot each in turn**, and record the boot menu behaviour.

## Part B — A virtual machine

1. **Create a VM** on your primary system: memory, cores, and virtual
   disk sized deliberately, not by accepting the defaults.
2. **Install the guest system**, then the guest tools or additions.
3. **Configure networking** — bridged versus NAT — and test reachability
   from another machine. Record which mode allowed what.
4. **Take a snapshot**, break something in the guest on purpose, and
   restore it. Time the restore.

## The comparison you are here for

| | Dual boot | Virtual machine |
| --- | --- | --- |
| Performance | Full hardware speed | Shares the host's resources |
| Hardware access | Direct — the right answer for GPUs and unusual devices | Through the hypervisor; some devices simply will not pass through |
| Both at once? | No — reboot to switch | Yes, side by side |
| Recovery from a mistake | Reinstall | Restore a snapshot in seconds |
| Backup | The whole machine | Copy one file |
| Risk to the host | Partitioning errors are permanent | The guest is isolated |

Fill it in with your own measurements and observations rather than
copying the words, and add a final row: **which one you would sell to
the client in the brief you built in
[[Build a Machine to Spec]]**, with a reason.

## Maintenance, while you are in here

Run the utilities from both systems on the same drive: check free
space, run a filesystem check, and run one full and one incremental
backup of a small folder. Restore one file from each and confirm it
opens. Record the times — the difference between a full and an
incremental backup is the whole reason both exist.

%%curriculum-start%%
## Curriculum connection

![[A2.1]]

![[A2.3]]

![[A2.4]]

![[B2.2]]

![[B2.3]]
%%curriculum-end%%
