---
title: Ports and Connection Standards
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
A connector is a promise: this shape carries these signals, at this
voltage, at this speed. When two devices agree on the promise they
work together without anyone thinking about it. When they do not, you
get the fault that looks like a broken device and is actually a wrong
cable.

## What a standard actually specifies

Four things, and a device has to match on all four:

1. **The physical connector** — shape, pin count, keying.
2. **The electrical signalling** — voltages, whether the pairs are
   differential, how much current may be drawn.
3. **The protocol** — what the bits mean and in what order they arrive.
4. **The power budget**, if the standard carries power at all.

Two connectors can be the same shape and disagree on the other three.
That is why a cable that fits is not the same as a cable that works.

## The ones on the benches in this room

| Standard | Carries | What to know |
| --- | --- | --- |
| **USB** (A, B, C) | Data and power, one host in charge | Type-C is a connector, not a speed — the same plug covers USB 2.0 through 40 Gb/s and a cable may support any subset |
| **RS-232 serial** | Slow, simple, one byte at a time | Still everywhere in industry: switches, sensors, and instruments have console ports because serial works when nothing else does |
| **IEEE 1394 (FireWire)** | Data, with devices able to talk without a host | Effectively obsolete; you meet it in old video equipment and it is worth knowing why it lost |
| **VGA** | Analogue video, three colour signals plus sync | Degrades with cable length; no audio; a long VGA run is why some projectors look soft |
| **DVI / HDMI / DisplayPort** | Digital video, and audio on the last two | Digital either works or fails visibly — the picture does not quietly get worse |
| **Ethernet (RJ45)** | Networking on twisted pair | Category rating limits speed and distance; see [[Networks and Protocols]] |
| **SATA / NVMe** | Storage | NVMe drives sit on PCI Express lanes, which is why they are so much faster |

## Serial and parallel, and why parallel lost

A parallel port sent eight bits at once down eight wires, which sounds
faster and was, until speeds rose. At high frequencies the wires stop
arriving in step — **skew** — and the crosstalk between them grows.
Modern fast interfaces are serial and differential instead: fewer
wires, higher clock rates, and noise that cancels because it hits both
wires of a pair equally.

> [!tip] The bench consequence
> When a device is intermittent, check what standard the cable actually
> claims before you suspect the device. A charge-only USB cable, a
> Category 5e cable in a gigabit run at 90 m, and a passive adapter
> between two standards that need an active one produce three faults
> that all look like hardware failure and are none of them.

## Hardware development trends: speed, capacity, and resolution

The history of connection standards is a continuous race against physical
bandwidth and physical space:

- **Processors and memory:** Internal bus speeds shifted from wide, slow
  parallel buses to multi-lane serial interconnects (PCI Express scaling from
  $250\ \text{MB/s}$ per lane in Gen 1 to over $4\ \text{GB/s}$ in Gen 5),
  while memory moved from DDR4 ($2400\text{--}3200\ \text{MT/s}$) to DDR5
  exceeding $6400\ \text{MT/s}$.
- **Video resolution:** As display standards leaped from standard definition
  to $1080\text{p}$, $4\text{K}$, and $8\text{K}$, uncompressed video streams
  demanded enormous bandwidth jumps — driving HDMI and DisplayPort interfaces
  from $4.95\ \text{Gbps}$ to over $40\text{--}80\ \text{Gbps}$.
- **Storage media and density:** Optical media (CDs at $700\ \text{MB}$, DVDs
  at $4.7\ \text{GB}$, and Blu-ray disks at $25\text{--}50\ \text{GB}$)
  provided portable mass storage for decades, but gave way to solid-state
  drives (SSDs). Moving from SATA III ($600\ \text{MB/s}$) to PCIe NVMe M.2
  format pushed transfer speeds past $7000\ \text{MB/s}$ in a form factor the
  size of a stick of chewing gum.

## Reading it off a datasheet

Every connector on a board is named in its datasheet with the standard
it implements and the revision. [[Reading a Datasheet]] shows how to
find the line; the revision matters, because "USB 3.2 Gen 2x2" and
"USB 3.2 Gen 1" are the same words and a fourfold difference in speed.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A1.3]]

![[A1.1]]
%%curriculum-end%%
