---
title: Component Identification Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[What a Computer Is]] and the teardown you
did in [[Take It Apart]] — sharpened by the naming drills of
[[Name That Part]]. Name each described part and say what it does.

## Questions

1. A small cylinder with coloured stripes, soldered flat to a
   circuit board. What is it, and what job does it do?
2. A little can-shaped component that stores electric charge and
   releases it when needed. Name and function?
3. One component allows current through in only one direction; a
   popular version of it glows while doing so. Name both.
4. The chip hiding under the largest heatsink and fan in the case.
   What is it, and what does it do all day?
5. Long, thin sticks clipped into slots near that big heatsink.
   Their contents vanish when the power goes off. Name and function?
6. A drive label reads "1 TB, SATA, 5400 RPM". Using precise
   terminology, say what the device is and what each term tells you.
7. **Find the error.** A classmate points at the whole tower case
   and calls it "the CPU". Untangle the mix-up.
8. **Explain your reasoning.** A client says their computer is slow
   — which component would you check first, and why?
9. **Peripheral and bus identification.** Name two standard input
   devices and two standard output devices of a computer system. Where
   does a sound card or dedicated graphics card seat to communicate
   with the CPU at high bandwidth?
10. **Advances in computer hardware.** Name two significant advances in
    electronic semiconductor technology over recent decades, and explain
    why manufacturers transition from older PCI/SATA buses to modern
    PCIe bus architectures.

## Answers

> [!success]- Answer 1
> A resistor. It limits current — the stripes are a colour code for
> how many ohms of limiting it does.

> [!success]- Answer 2
> A capacitor. It stores charge and smooths out bumps in a power
> supply — a tiny reservoir, filled and drained fast.

> [!success]- Answer 3
> A diode restricts current to one direction; an LED is a diode
> that emits light while current flows — a one-way valve that
> reports in.

> [!success]- Answer 4
> The CPU — the processor. It fetches and executes instructions,
> millions per blink. The heatsink is there because thinking is hot.

> [!success]- Answer 5
> RAM — the computer's working memory. Fast, and *volatile*: power
> off means contents gone, which is why storage drives also exist.

> [!success]- Answer 6
> A hard disk drive. 1 TB is its capacity, SATA is the interface to
> the mainboard, and 5400 RPM is how fast its platters spin — a
> hint that it is a spinning drive, and not a quick one.

> [!success]- Answer 7
> The CPU is one chip *inside* the case; the case is just the box
> holding mainboard, power supply, drives, and the CPU itself. A
> client hears "replace the CPU" very differently from "replace the
> case fan" — precise names matter.

> [!success]- Answer 8
> Ask and observe before touching — *slow doing what?* Then check
> RAM first: too little memory forces constant use of the far
> slower drive, and it is the commonest, cheapest fix. Suspect an
> old spinning drive next.

> [!success]- Answer 9
> Input devices: keyboard, optical mouse, flatbed scanner, or
> microphone. Output devices: monitor display, printer, or audio
> speakers. Dedicated expansion cards seat into high-speed **PCIe
> (PCI Express)** slots directly wired to the CPU and mainboard
> chipset.

> [!success]- Answer 10
> 1. Semiconductor fabrication miniaturisation (shrinking transistor
>    gate lengths to nanometre scales), allowing billions of transistors
>    with lower power draw and higher switching frequencies.
> 2. High-speed serial point-to-point PCIe bus architecture replaces
>    shared parallel buses (older PCI), multiplying data bandwidth
>    and eliminating clock skew across long copper traces.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[A1.3]]

![[A1.4]]

![[B2.1]]
%%curriculum-end%%
