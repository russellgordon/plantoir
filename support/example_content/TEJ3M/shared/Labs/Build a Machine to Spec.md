---
title: Build a Machine to Spec
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
A brief, a box of parts, and a machine that has to do a stated job by
the end of the period. Grade 10 built a computer; this is the same
work with a requirement attached, which is what makes it engineering
rather than assembly.

> [!danger] Safety notes
> **Unplugged, and the power supply switched off, before anything is
> opened** — and give a supply thirty seconds to bleed down before you
> touch inside it. **Anti-static discipline throughout**, per
> [[Anti-Static Habits]]: strap on, board on the mat, components in
> their bags until the moment they go in. **Nothing is powered with the
> case open** except under supervision and with hands out.

## What you need

- [ ] A brief from the pile: gaming, business, media centre, graphic
      design, or a media-capture workstation
- [ ] Parts trolley, anti-static mat and strap, screwdrivers
- [ ] At least one peripheral to add later: printer, camera, or
      external drive
- [ ] Your [[Tech Journal]], open, photographing as you go

## The work

1. **Read the brief and restate it as requirements.** "For gaming" is
   not a requirement; "runs current titles at 1080p and 60 frames per
   second, under $1,200, quiet enough for a bedroom" is three.
2. **Choose parts against the requirements**, checking compatibility
   the way [[Reading a Datasheet]] teaches: socket, chipset, memory
   type and speed, power supply wattage and connectors, physical
   clearance.
3. **Build it.** Standoffs first, board out of the case for the
   processor and memory if that is easier, cables routed as
   [[Documenting Your Build]] expects them to be photographed.
4. **First power-up.** Confirm it posts. If it does not, work the
   sequence on [[BIOS, Firmware, and Boot]] rather than swapping parts:
   did the fans spin, are there beep codes or board LEDs, does it post
   with one stick of memory?
5. **Firmware settings**, recorded as you set them: boot order, virtual
   support if the brief needs it, fan profile, and the storage mode.
6. **Install and configure a peripheral.** Physical connection, driver,
   configuration, and a test that proves it works — a printed page, a
   captured frame, a file written to and read from the external drive.
7. **Benchmark against the brief.** One measurement per requirement.
   A machine that meets the brief on your say-so has not been tested.

## Record in your journal

| Requirement from the brief | Part chosen | Why | Measured result |
| --- | --- | --- | --- |

Plus: firmware version and every setting you changed, the peripheral's
driver version, and a photograph of the finished cable routing.

## Think about it

1. Which single part in your build is the one you would change first if
   the budget rose by 15%? Defend it against the requirements, not
   against preference.
2. Your machine posts but the peripheral is not detected. List the
   checks in the order you would make them, and say what each one rules
   out.
3. The brief's owner asks for "a bit more storage" a year from now.
   What did you choose today that makes that easy or hard?

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A1.3]]

![[A2.2]]

![[A2.3]]

![[A2.4]]

![[B1.1]]

![[B1.3]]

![[B2.1]]
%%curriculum-end%%
