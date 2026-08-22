---
title: The Control System
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> In pairs · launched in Unit 3, due at the end of it · a closed-loop
> system that holds a setpoint you chose · with logged tuning evidence
> and a safety limit you tested on purpose

## What you are making

A system that holds something steady without you. Temperature, light
level, position, speed, water level — the quantity is yours to choose,
and the requirement is the same in every case: it senses, it decides, it
acts, and it keeps doing so while conditions change underneath it.

The claim you have to defend is a number, stated in advance. Not "it
holds the temperature" but "it holds $40\ ^\circ\text{C} \pm
1\ ^\circ\text{C}$ for ten minutes, recovering from a
$5\ ^\circ\text{C}$ step in under $90\ \text{s}$, with no overshoot
beyond $2\ ^\circ\text{C}$." Then you show the log that proves it.

Two things are not optional. The controller runs as a state machine that
never blocks, because a control loop that is asleep is not controlling
anything. And a safety limit runs *before* the control logic on every
pass, checking for readings that are impossible and outputs that have
been on too long.

## Milestones

- [ ] **Requirement**, in numbers: the setpoint, the tolerance band,
      the disturbance it must reject, and the recovery time.
- [ ] **Open-loop characterisation**: a logged run at full actuator
      power showing how the system responds with no control at all.
      Every tuning decision refers back to this curve.
- [ ] **Safety limit written and tested first**, with the log of the
      test that proves it — sensor disconnected, output shut off.
- [ ] **State diagram** on paper before the code is written, including
      the fault state and how the system leaves it.
- [ ] **Controller implemented** as a non-blocking state machine, built
      the way [[State Machines in Code]] sets out, in version control.
- [ ] **Tuning evidence**: at least three logged runs at different
      settings, each with overshoot, time to setpoint, settling time,
      and steady-state error read off the log.
- [ ] **Disturbance test**: something changes — a door opens, a load is
      added, the setpoint steps — and the log shows the recovery
      against your stated requirement.
- [ ] **Timing evidence**: your loop period and its worst case,
      measured on the scope, not estimated.

## How it is assessed

The criteria table, weighted as [[How Marks Work]] sets out. A system
that holds a modest setpoint well, with logs that prove it, scores far
above an ambitious system that mostly works. Scope is your decision and
it is assessed as a decision.

The tuning history is where growth is visible, so it lives in your
[[Tech Journal]]: what you changed, what you expected it to do, what it
actually did, and what that taught you about the system. Three logged
runs with reasoning between them is the evidence. Three runs with no
reasoning is a folder of files.

Safety is assessed as engineering. Actuators on their own supply, only
grounds tied, current limits set before connection, inductive loads
protected, and nothing energised and left unattended. Deliberately
testing the failure where the sensor falls off is a design decision, and
we assess it as one.

## What is marked as yours

The bench is shared and the system is one system. The evidence is not.
Divide it at launch and write the division at the top of your
documentation: **one of you owns the drive stage and the safety limit**
— the protection, the deliberate fault test, and the log that proves it
— and **the other owns the open-loop characterisation and the timing
evidence**, the full-power run and the measured loop period with its
worst case.

Tuning belongs to both of you separately: each partner runs, logs and
analyses at least two of the tuning runs, reads the four figures off
their own logs, and writes their own paragraph about what the change
did. At the conference on the second day each of you answers for the
whole system, not only for your half. Nobody here is marked for work
their partner did.

## Success criteria

| Quality | What it looks like at your bench |
| --- | --- |
| A claim in numbers | Setpoint, tolerance, and recovery time stated before building |
| Characterised before tuned | The open-loop log exists and the tuning refers to it |
| A safety limit that runs first | Tested by causing the fault, with the log to show it |
| A diagram you can read back | Standard symbols, the fault state and its exit shown, and the code matches it |
| A loop that never blocks | State machine, measured loop period, no waiting in delays |
| Tuning shown as evidence | Three or more runs, with the four figures read off each |
| Disturbance rejected | The log shows the system recovering, within the stated time |
| Honest limits | You can say what it cannot hold, and why |
| Professional safety practice | Supplies separated, limits set, nothing left running alone |
| Your half, under your name | The evidence set you own, plus your own tuning runs read in your own words |

> [!warning]- If your loop oscillates and raising the gain makes it worse
> That is not a bug — it is your system telling you about its delay.
> Every closed loop has a lag between acting and sensing the result,
> and a gain high enough to correct quickly is a gain high enough to
> overcorrect before the sensor has caught up. Before you touch the
> gain again, go back to your open-loop log and measure the delay. Then
> you have two choices, and they are engineering choices rather than
> coding ones: reduce the gain and accept slower correction, or reduce
> the delay itself — better thermal contact, a faster sensor, a
> smaller thermal mass. Write the choice and its reasoning into the
> journal; a defended trade-off is exactly what the design review will
> ask you about.

%%curriculum-start%%
## Curriculum connection

![[A3.2]]

![[A3.4]]

![[B5.2]]

![[B5.3]]

![[D1.1]]

![[D1.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 3, Day 14, while benches test the safety limit by
causing the fault
  Watch what the humans do, not what the code does. When the limit
  fires — or fails to — does the hand go to the supply's output switch,
  or to a wire in a powered circuit? Does anybody stand between the
  actuator and the room? The log records that the limit worked. It
  records nothing at all about how the two people behaved in the second
  it did not, and D1.2 is entirely about that second.
  Going well: power off before hands go in, every time, without a
  discussion about whether it is necessary this once.
  Stuck: a live rewire, or a bench that runs the fault test with the
  motor still coupled to something that can move.
  Record: a letter per bench — P for power-off-first, L for live — on
  the class list. Five seconds, and it is the criteria row you cannot
  mark from anything they hand in.

TALK — Unit 3, Day 13, at the feedback checkpoint already on that agenda
  Ask: "Show me the state diagram. Which transition would you have got
  wrong if you had written the code first, and what tells you that?"
  Then: "Take me out of the fault state. What has to become true, who
  or what makes it true, and what happens if it never does?"
  A strong first answer points at a transition and says what the
  drawing forced them to decide — usually an edge case with no obvious
  home. A strong second answer knows whether recovery is automatic or
  needs a person, and can say why that choice suits this machine. Both
  are A3.4's second verb, interpret, which a handed-in diagram cannot
  evidence: a correct drawing looks identical whether its author can
  read it back or copied its shape.
  Record: one line per pair in your day plan, naming the transition
  each student pointed at.

The product evidence is the tuning logs, the fault test and the ten
measured trials, in at the end of Day 16. Those arrive on their own.
%%
