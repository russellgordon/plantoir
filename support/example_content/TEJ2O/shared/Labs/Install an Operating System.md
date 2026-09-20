---
title: Install an Operating System
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
Your workstation POSTs, but POST is just the hardware calling roll —
without an operating system it is an expensive space heater. Today
you take a machine from boot media to first login, documenting every
choice, because the next technician (possibly future-you) inherits
them all. [[Software and Operating Systems]] explains what you are
installing; this lab is where you install it.

> [!danger] Safety notes
> **The case is closed and fastened before power is applied** — this
> is the first lab where machines run all period, and a running
> machine is never an open machine. **Route power cords off the
> floor** and behind the bench; a tripped cord takes the machine and
> maybe you with it. **Anything smelling hot** — hands off, bench
> master switch, teacher, per [[Safety in the Lab]].

## What you need

- [ ] Your workstation from [[Build a Workstation]], teacher-checked
- [ ] Boot media prepared with the operating system your class uses
- [ ] Your journal, open to a page titled with the machine's name

## The work

1. **Tell the machine where to look.** Enter firmware setup at
   power-on and put your boot media first in the boot order — the
   machine checks a list, and will boot the old drive forever if you
   let it.
2. **Read every installer screen before clicking.** Installers are
   runbooks written by someone who cannot see your machine; your
   judgement fills the gap.
3. **Partition in plain terms.** A drive is a cabinet; partitions
   are its shelves. Let the installer build sensible shelves — but
   write down what it built and how big each one is.
4. **Triple-check the target drive before any erase step** — the one
   step with no undo. Match size and name to the drive you mean;
   "probably that one" has wiped a lot of good data.
5. **Choose the account name and password deliberately**, recorded
   where your class stores them — a machine nobody can log into is a
   machine nobody can use.
6. **First login, then hunt for what the system missed** — no
   network, no sound, odd screen size — and install the drivers that
   hardware needs. [[Finding Answers Online]] is how technicians
   actually do this step.
7. **Run updates, then write the closing journal entry**: every
   choice, in order, so the next technician could repeat your
   install without you in the room.

## What can go wrong

- **The machine ignores your media and boots the old system.** Boot
  order — step 1 did not stick, or the media sits in a port the
  firmware skips. Change one thing and retry.
- **The installer cannot see the drive.** Usually a data or power
  cable that looked seated and is not — power down and reseat, as
  [[Storage and Drives]] warns.
- **No network after first login.** The network card wants a driver
  — awkward, when drivers live online. This is why technicians keep
  drivers on the boot media; note it for next time.

## Level up

Reinstall from your notes alone, no memory allowed — every gap you
hit is a gap in the documentation. Or install a different operating
system on a spare drive and compare the choices its installer made.

%%curriculum-start%%
## Curriculum connection

![[B1.1]]

![[B4.1]]

![[B4.2]]

![[B4.4]]
%%curriculum-end%%
