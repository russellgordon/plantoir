---
title: Troubleshooting Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Build a Workstation]] and
[[Install an Operating System]], with [[What a Computer Is]] as the
map. For each symptom, name the most likely cause and your *first*
check. The order is always the same: look, smell, listen, read.

## Questions

1. Fans spin, the power light is on, the machine sounds three beeps
   — and the display stays black.
2. Nothing at all: no lights, no fans, no beeps.
3. The machine boots and runs, but everything is slow, and a
   rhythmic clicking comes from inside the case.
4. Moments after power-on, a sharp burning smell from the case.
5. The computer is clearly running, but the monitor announces
   "No signal" and shows nothing else.
6. After a move to a new desk, the keyboard no longer responds.
7. **Explain what is wrong with this approach.** A classmate's first
   move on *any* fault is to reinstall the operating system.
8. **OS versus application fault.** A user reports that when they launch
   a photo-editing application, it immediately crashes with an error,
   but all other applications (browser, text editor) work smoothly. Is
   this an operating system kernel fault, a hardware fault, or an
   application software issue? How would you verify?
9. **Utility software selection.** Which utility software tool from
   [[Maintenance Utilities]] would you use for each scenario:
   (a) an accidental file deletion from a local folder;
   (b) a mechanical drive that takes minutes to open large folders;
   (c) verifying how much free space remains on a USB backup drive?

## Answers

> [!success]- Answer 1
> *Listen* — beeps are the machine talking, and three commonly means
> a memory fault. First check: power off, unplug, anti-static gear
> on, reseat the RAM. Then *read* up this board's beep codes.

> [!success]- Answer 2
> *Look* at power first, wall inward: outlet live, power supply's
> rocker switch on, cable seated at both ends? Most "dead" machines
> are unplugged somewhere. Only then suspect the supply itself.

> [!success]- Answer 3
> *Listen* — rhythmic clicking is the classic sound of a hard drive
> failing. First move is not repair at all: back up the data while
> the drive still answers. Then plan its replacement.

> [!success]- Answer 4
> *Smell* — and act: cut the power immediately, at the switch or the
> wall. Safety comes before diagnosis, every time. Once unplugged,
> look for scorched or bulging parts before any second attempt.

> [!success]- Answer 5
> *Read* the message — "No signal" means the monitor is fine but
> nothing is arriving. Check the cheap things: cable seated at both
> ends, right input selected, right video port on the computer.

> [!success]- Answer 6
> *Look* — what changed? The machine moved, so check connections
> first: the keyboard cable almost certainly worked loose in
> transit. The last thing changed is the first thing checked.

> [!success]- Answer 7
> Reinstalling wipes the evidence and the user's data to fix what
> may be a loose cable — and a failing drive fails just as hard
> with a fresh system on it. Diagnose first; smallest fix first.

> [!success]- Answer 8
> It is an application-level fault. Because the operating system and
> other applications run normally, the OS kernel, memory, and hardware
> are sound. Verify by checking the application's configuration files,
> testing in another user account, checking event logs, or updating and
> reinstalling only that specific application.

> [!success]- Answer 9
> (a) File recovery / undelete utility or restoring from an active backup;
> (b) Disk defragmenter to reorganise non-contiguous file sectors;
> (c) Disk management / storage properties utility to inspect storage
> capacity and volume usage.

%%curriculum-start%%
## Curriculum connection

![[B1.1]]

![[B4.1]]

![[B4.4]]

![[D1.1]]
%%curriculum-end%%
