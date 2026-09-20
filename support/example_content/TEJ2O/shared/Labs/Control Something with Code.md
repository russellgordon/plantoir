---
title: Control Something with Code
publish: true
created: __CREATED__
tags:
  - labs
enableToc: true
---
Everything meets here: a small Python program on your workstation
drives a real output — a light, a buzzer, or the on-screen simulator
when hardware is scarce — through an interface board. The loops you
wrote in [[Decisions and Loops]] and the wiring sense you built in
[[Breadboard a Circuit]] become one system, and learning to trace
that system end to end is the skill [[The Gadget]] will demand of you.

> [!danger] Safety notes
> **Nothing connects to a computer port except through the interface
> board** — the board's job is to protect the port, and its rated
> current limit is a wall, not a suggestion. **Wire with everything
> unpowered**, and connect the computer last, after a bench check.
> **Anything warm or smelling hot** — hands off, power off, teacher,
> exactly as [[Safety in the Lab]] says. Simulator crews: your
> hazards today are posture and eye strain — sit well, look away
> often.

## What you need

- [ ] Workstation with Python and the class interface library
- [ ] Interface board and one output — light or buzzer — or the
      on-screen simulator, which answers to the same commands
- [ ] Jumper wires, and your journal for the wiring sketch and plan

## The work

1. **Know your output before writing a line.** Hardware or simulator,
   the interface gives you the same two commands — `turn_on()` and
   `turn_off()` — so the program cannot tell which world it is in.
   That interchangeability is the design idea in
   [[Code Meets Hardware]].
2. **Wire the output through the board, unpowered**, and sketch the
   connections. (Simulator crews: launch it and confirm it responds
   to a single `turn_on()` before anything fancier.)
3. **Predict, in writing, what ten one-second blinks should look or
   sound like.** A prediction is what turns a demo into a test.
4. **Write the program** — everything in it comes from
   [[First Programs]] and [[Decisions and Loops]]:

   ```python
from time import sleep

# turn_on() and turn_off() come from the class
# interface library — or the simulator, same names.
blinks = 10
for count in range(1, blinks + 1):
    turn_on()
    print("Blink", count, "of", blinks)
    sleep(1)
    turn_off()
    sleep(1)
```

5. **Bench check, connect, run.** Count the blinks against your
   prediction — and notice the loop ends with `turn_off()`, because a
   control program's last duty is leaving the hardware in a safe,
   known state.
6. **Break it on purpose, then trace the chain.** Unplug one jumper
   and run again: the program is happy, the output is dark. Walk the
   links — program, interface, wiring, output — testing each until
   the break shows itself. That trace is the lab's real lesson.

## What can go wrong

- **The program runs; nothing happens.** Does `print` still appear?
  Then the code executed and the break is downstream — wiring, the
  wrong output channel, or an unpowered board. Trace, don't guess.
- **`NameError: turn_on is not defined`.** The interface library was
  never imported, or the simulator is not running. Python only knows
  the names it has been handed.
- **The output sticks on after the program ends.** The program
  stopped between `turn_on()` and `turn_off()` — [[Debugging Basics]]
  calls this dying in an unsafe state, and real machinery is why the
  habit in step 5 matters.

## Level up

Ask the user how many blinks with `input()`, or blink a pattern —
three short, three long, three short — and have a neighbour decode it
from across the room. Either one is a first sketch of [[The Gadget]].

%%curriculum-start%%
## Curriculum connection

![[B2.3]]

![[B2.4]]

![[B5.1]]

![[B5.2]]

![[B5.4]]
%%curriculum-end%%
