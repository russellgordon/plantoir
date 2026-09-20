---
title: Inside a Microcontroller
publish: true
created: __CREATED__
tags:
  - concepts
---
The board you were handed in [[Blink, Read, React]] has no screen, no
keyboard, no hard drive, and no operating system in any sense you would
recognise. Plug it in and it starts running your program, immediately,
and it will keep running it until the power goes. It is a whole computer
whose only way of experiencing the world is a row of metal pins.

## A computer that fits in a fingernail

A desktop machine is a processor surrounded by separate chips and cards.
A microcontroller puts the whole set on one piece of silicon:

- **A processor core** that executes instructions, usually far slower
  than a laptop's and entirely adequate for the job.
- **Flash memory** holding your program. It survives power loss, which is
  why the board runs your code the moment it wakes.
- **RAM** — often a startlingly small amount — for variables while the
  program runs. It is gone at power-off.
- **GPIO pins**, the general-purpose input/output lines that are the
  chip's hands and eyes. Each one can be configured as an input to read a
  voltage or an output to drive one.
- **Peripherals** built into the same chip: timers that count clock
  ticks, an analog-to-digital converter that turns a voltage into a
  number, PWM generators, and serial interfaces for talking to other
  chips.

There is no boot sequence to speak of and no BIOS handing off to an
operating system. On reset, the core starts fetching instructions from a
fixed place in flash. On this board that is the MicroPython runtime,
which then runs your program — which is why your code behaves like a
script and the hardware behaves like a machine that never stops.

The one rule that follows from all this: **your program is the only thing
running**. Nothing else will schedule around you, nothing will preempt a
long delay, and nothing will clean up after a loop that never exits. That
is a burden and a gift. It is also why a microcontroller can promise
timing a general-purpose computer cannot.

## Choosing what to interface with

Not every control job wants a microcontroller. The curriculum asks you to
be able to compare the three honest options, and the comparison is a real
one you will make on a job.

| | Desktop computer | Microcontroller | Programmable logic controller |
| --- | --- | --- | --- |
| Cost | Highest | Lowest | High |
| Timing you can trust | Poor — the OS decides | Excellent | Excellent |
| Processing power | Very high | Modest | Modest |
| Ruggedness | Office conditions | Depends on the board | Built for a factory floor |
| Electrical interfacing | Needs added hardware | Pins are the interface | Industrial voltages, isolated inputs |
| Who programs it | Software developer | Technician or engineer | Controls technician, often in ladder logic |
| Best at | Heavy computation, storage, user interface | Small dedicated devices, sensing and control | Machinery in industry, safety-rated control |

Read across the "timing" row carefully, because it is the least obvious
and the most important. A desktop running a general-purpose operating
system cannot guarantee that your code runs in the next millisecond — the
scheduler may have other ideas. For logging temperatures once a minute,
who cares. For a stepper motor's pulse train, it is fatal. That is the
distinction between a computer that is *fast* and one that is
*predictable*, and control work needs the second.

> [!question] Why is a PLC more expensive than the microcontroller inside it?
> Because you are not buying computation, you are buying the rest: inputs
> that tolerate industrial voltages and survive being wired wrong,
> optical isolation between the control side and the machine side,
> certification against safety standards, an enclosure rated for a dirty
> environment, and a decade of guaranteed spare parts. When
> [[When Good Enough Is Not Safe]] asks what failure costs, that price
> difference is the answer written as a number.

## Why it is possible at all

Everything on this page is downstream of one long trend. Switching that
needed a vacuum tube and watts of heater power became a transistor, then
millions of transistors on a chip, then an entire computer with its
memory and peripherals on one die at a price that lets you put a
processor inside a light switch. Each step made the switch smaller,
cheaper, and cooler, and the last property is what set the pace — see
[[Power and Heat]] for why heat, not cleverness, is the limit.

The practical consequence for you is that computation has become the
cheap part of a design. The expensive parts are now the things this
course spends its time on: the sensor at the front, the driver at the
back, and the person who can reason about both.

Get hands on it in [[Your First Embedded Program]], learn what the pins
can and cannot do in [[Digital and Analog Signals]], and check your
understanding against [[Microcontroller Code Practice]].

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A3.4]]

![[A3.5]]
%%curriculum-end%%
