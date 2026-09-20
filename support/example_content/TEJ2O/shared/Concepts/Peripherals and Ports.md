---
title: Peripherals and Ports
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
The back panel you cabled in [[Build a Workstation]] is a row of
promises. Each port's shape declares what will happen if you plug
something in — what signal, how much power, how fast. This page is
the row of promises, stated plainly.

## A connector is a promise

USB-A is the flat rectangle that carries data and modest power to
almost anything. USB-C is its smaller, reversible successor, able to
carry far more of both. HDMI and DisplayPort carry video and sound
out. The RJ45 jack — the one you crimped in [[Crimp and Test a Cable]]
— carries the network. The 3.5 mm round jack carries analogue audio
and nothing else. The rule from the bench holds everywhere: if it
needs force, it is the wrong port. Shapes differ precisely so that
wrong connections are hard to make.

## Matching device to port

A peripheral is any device that lives outside the case — keyboard,
mouse, monitor, printer, headset — and matching one to a port is
reading both sides of the promise. [[Name That Part]] keeps the names
fresh; try the match below before unfolding.

> [!success]- Self-check: which port? (click to expand)
> Monitor → HDMI or DisplayPort. Wired network → RJ45. Keyboard →
> USB-A or USB-C. Headset → 3.5 mm jack, or USB if it carries its own
> sound hardware. If you also said "monitor → USB-C", you are reading
> newer spec sheets correctly — USB-C can carry DisplayPort video.

## Adapters and their limits

Adapters convert shape, not capability. A USB-C to HDMI adapter works
because the video signal was already there, waiting for a different
plug. An adapter cannot add what neither end speaks: no adapter makes
a 3.5 mm jack carry video, and a hub splitting one USB port four ways
shares that one port's bandwidth — it multiplies sockets, not speed.
When an adapter chain fails at the bench, test the promise at each
link, the habit [[Cable Habits]] drills.

## Peripheral functions and system communication

Peripherals classify into three functional categories based on how they
interact with the mainboard:

- **Input peripherals:** Translate user actions or physical phenomena
  into digital signals. Keyboards and mice capture mechanical switch
  events; flatbed and document scanners convert reflected optical
  patterns into bitmap images; microphones digitize pressure waves.
- **Output peripherals:** Convert digital system data into human-usable
  or physical form. Monitors render frame buffers into light; sound
  cards decode PCM audio streams for speakers; printers deposit ink or
  toner onto paper.
- **Bi-directional and expansion devices:** Network interface cards,
  external storage drives, and multi-function touchscreens send and
  receive data simultaneously.

High-speed system buses on the mainboard coordinate these peripherals
without stalling the processor.

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A1.3]]

![[A1.4]]

![[B1.1]]
%%curriculum-end%%
