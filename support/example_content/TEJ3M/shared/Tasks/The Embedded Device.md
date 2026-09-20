---
title: The Embedded Device
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Pairs · a design period and four bench periods · a working device, its
> code, its schematic, a fault log, and one measured claim ·
> demonstrated at the end of Unit 3

## What you are making

One sensor in, one actuator out, one job. A greenhouse fan that runs when
the soil sensor reads dry. A doorway counter that logs how many people
passed. A night light that fades up as the room darkens. A reaction-time
game with a scoreboard. A cooling fan that starts at a temperature you
chose and can defend.

What makes this a Grade 11 task is the claim. When you demonstrate, you
will state something specific and testable about your device — "the fan
starts within two seconds of the sensor crossing 700 counts, and it did
so on ten trials out of ten" — and then you will show the data that backs
it. [[Sensors and Actuators]] and [[Digital and Analog Signals]] are the
concepts; [[Blink, Read, React]] and [[Drive a Motor]] are the hands.

## Milestones

- [ ] **One sentence.** What it senses, what it does, and for whom.
- [ ] **Block diagram** — sensor, board, driver, actuator, supplies —
      before any component is chosen.
- [ ] **Schematic with values**, including the driver stage and, if
      anything inductive is in it, the flyback diode.
- [ ] **Current budget.** What every branch draws, checked against the
      pin limits and the supply, per [[Driving Outputs Safely]].
- [ ] **Code that a stranger could follow**, structured as
      [[Structuring Embedded Code]] describes: named constants, small
      functions, pin numbers in one place.
- [ ] **The measured claim**, with at least ten trials of data.
- [ ] **Fault log** — every fault, where you looked first, and what
      finally located it.

## How it is assessed

The criteria below, plus the framework in [[How Marks Work]]. Bench
periods are assessed as they happen. Your [[Tech Journal]] holds the fault
log and the trial data, and both of those are worth more here than a tidy
final photograph.

You work in pairs and you are evaluated one at a time. The device is
shared; what is yours is your own journal — your share of the fault log,
your trial data, the calculation behind the branch you were responsible
for — and the conference, where either partner can be asked to trace the
whole chain from sensor to code to actuator without help from the other.
A pair that split the work so cleanly that neither can do that has a
problem worth finding out about before the demonstration.

Before you demonstrate, you will read your own device against the table
below and fix the weakest row, with a period still left to do it in.
[[Judging Your Own Work]] is the routine; it changes nothing about your
mark and quite a lot about your device.

## Success criteria

| Quality | What it looks like at your bench |
| --- | --- |
| A device that does its job | The one-sentence job happens, on demand, repeatably |
| A claim that survives testing | A specific number, ten trials, and the data to show |
| A safe driver stage | Nothing inductive without a diode, nothing large hung off a pin |
| A budget that was checked | Every branch current calculated before it was connected |
| Code somebody else can read | Named constants, small functions, comments that explain why |
| A traced system | Either partner can narrate sensor to code to actuator |
| Faults chased methodically | The log shows halving and testing, not swapping parts |

## Reflect

In your [[Tech Journal]]: which half of this device fought you harder,
the hardware or the software — and how long did you spend searching the
wrong half? Then the useful part: what measurement, taken early, would
have told you which half to look in?
[[Debugging Hardware and Software Together]] is the technique; your entry
is the evidence you used it.

> [!example]- A claim worth making, and a claim that is not
> **Not a claim:** "The fan turns on when it gets hot." Unfalsifiable —
> at what reading, after how long, how reliably? **A claim:** "The fan
> starts within 2 s of the sensor reading rising above 700 counts —
> about 2.26 V at the input, on this board's ten-bit converter with a
> 3.3 V reference — and it did so on 10 of 10 trials." That version can
> be wrong, which is exactly what makes it worth stating and testing.

%%curriculum-start%%
## Curriculum connection

![[A3.5]]

![[B5.1]]

![[B5.2]]

![[B5.3]]

![[A1.1]]

![[A3.4]]

![[D1.1]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 3, Day 16, the period where the code goes in
  Take this in the body of the period: the last fifteen minutes of Day
  16 belong to the self-check, and nobody is uploading anything then.
  Watch for: how many things change between one upload and the next.
  One edit, upload, look — or three edits, upload, and a shrug when the
  behaviour moves. The finished program is identical either way, and the
  fault log only ever records the faults that were recognised as faults,
  so watching is the one thing that can corroborate it. Day 13 taught
  this rule explicitly, which makes today the fair test of whether being
  told it changed anybody's hands.
  Going well: a pair says what they expect the change to do before they
  upload it, and one of them writes the result down without being asked.
  Stuck: the code is edited faster than it is read; the same upload
  happens three times unchanged; nobody can say what the last edit was.
  Record: two columns on your day plan — one change, or many. Add a dot
  when you hear a prediction before an upload. B5.3 asks them to write,
  test AND debug; that column is the testing half of it, caught in the
  only place it happens.

TALK — Unit 3, Day 14, the conference already on that agenda
  Do NOT ask them to compare a microcontroller with a desktop in
  general. That comparison is printed as a table on the concept page
  Inside a Microcontroller, read on the first day of this unit, and half
  of it was set as a journal prompt the same night. They will recite it.
  Ask instead: "A client says put a laptop in the corner and be done
  with it. For YOUR device, which row of that table would you take them
  to first, and what number would you bring to it?"
  Then: "Which row would you concede? Name the thing the laptop would
  genuinely do better here."
  A strong answer moves the general table onto a specific device and
  gives ground on a real point instead of defending the board because it
  is the one on the bench. That is the second half of A3.5 —
  disadvantages as well as advantages — which the table hands them and
  their own device does not.
  Record: one line per pair, and circle any trade-off named with a
  number attached.

The product evidence is the device, its code, its schematic, its fault
log and its trial data, handed in on Day 18.
%%
