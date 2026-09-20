---
title: Debugging Hardware and Software Together
publish: true
created: __CREATED__
tags:
  - code
enableToc: true
---
"It doesn't work" is not a fault report. On an embedded system it is not
even a category — the sensor could be miswired, the pin could be the
wrong one, the supply could be sagging under load, the logic could be
inverted, or the code could be running perfectly on a board whose ground
is not connected to anything. The skill this page teaches is narrowing
that list quickly, in an order that cannot waste your time.

## Decide which half is lying

Every embedded fault lives in one of two places, and one question splits
them: **can the program prove it is running, and prove what it thinks it
is seeing?**

```python
print("Boot: fan controller revision 3")

while True:
    raw = sensor.read_u16()
    print("raw", raw, "state", state)
    time.sleep_ms(500)
```

Those two prints answer more than they look like they should. If nothing
appears, the problem is before your logic entirely — power, connection,
or the board not running your file. If the boot line appears and the loop
line does not, the program is stuck between them. And if `raw` sits at 0
or at 65535 and will not move while you wave your hand at the sensor,
your code is fine and the fault is in front of the pin.

A **heartbeat** does the same job when no computer is attached:

```python
if time.ticks_diff(now, last_beat) >= 1000:
    last_beat = now
    status_led.value(1 - status_led.value())
```

An LED blinking once a second means the loop is alive. An LED that stops
means the loop stopped, which is a completely different fault from an
output that never turns on — and you can see it from across the room,
with the device in its case.

## Six checks, in this order

Work from the physical outward. Each of these is cheaper than the one
after it, and each rules out a whole class of fault.

1. **Power and ground.** Meter across the board's supply pins. Then check
   that the board and the load share a ground. Missing common ground is
   the single most common fault in this room and it produces symptoms
   that look like anything at all.
2. **Supply under load.** Measure again *while the load is switched on*.
   A supply that reads 5 V idle and 3 V with the motor running is your
   answer, and no amount of reading the code will find it.
3. **The pin, not the plan.** Confirm you are physically on the pin your
   constant names. Boards number pins in more than one way — a silkscreen
   number, a chip port number, a connector position — and the two
   disagreeing is a classic afternoon lost.
4. **The pin's actual voltage.** Meter it while the program drives it
   high and low. If the pin does what you asked and the load does not
   move, the fault is downstream: driver, load, or wiring.
5. **The input's actual voltage.** Same trick backwards. Meter the sensor
   pin while you change the thing being sensed. If the voltage moves and
   your printed number does not, you are reading the wrong pin or the
   wrong way.
6. **Substitute a known-good part.** Swap the LED, the resistor, the
   sensor, the board. Change *one* thing at a time and write down what
   you changed — two simultaneous changes cannot be untangled afterwards.

> [!tip] Halve the problem, do not sweep it
> Testing every possibility in order is slow and gets slower as projects
> grow. Instead, cut the system in half and prove which half contains the
> fault, then halve that. Sensor to code, code to output, output to load
> — three cuts locate a fault in a system with eight parts. It is the
> same discipline as the diagnostic ladder in
> [[Networks and Protocols]], and it is why an experienced technician
> looks slow for two minutes and then finished.

## Faults that look like software and are not

- **A floating input.** Behaviour that changes when you touch the bench
  or move your hand. The pin has no pull-up or pull-down. Nothing in the
  code can fix this.
- **Contact bounce.** One press counted many times, or a sensor that
  triggers in bursts. Debounce it — see [[Input, Output, and Timing]].
- **Brownout.** The board resets whenever the motor starts. Separate
  supplies, common ground, and check the supply while loaded.
- **An analog pin that is not one.** A reading pinned at one extreme and
  refusing to move. Not every pin has a converter behind it.
- **Inverted logic.** An active-low input treated as active-high, so
  everything works backwards and looks almost right. Meter the pin and
  read the actual voltage rather than trusting the variable name.
- **A cold solder joint.** Intermittent, and worse when you press on the
  board. Reflow it — [[Soldering Safely]] shows what a sound joint looks
  like.

Notice how many of those are found with a meter rather than with a print
statement. The instruments matter: a multimeter for steady voltages, a
logic probe for a pin's high-low-floating state, and an oscilloscope for
anything intermittent, fast, or oscillating. A signal that is wrong only
during a transition is invisible to the first two and obvious on the
third — [[Using an Oscilloscope]] earns its setup time exactly here.

## Keep a fault log

Every fault you find goes in your [[Tech Journal]] in four lines:
**symptom, what you suspected, what you tested, what it turned out to
be.** That is not a school exercise; it is what maintenance
documentation is, and being able to produce it on demand is one of the
things that separates a technician from a hobbyist.

Two reasons it pays immediately. Half the faults you meet at the end of the
course will be faults you already solved weeks ago, and your log is the only
place that memory survives. And when you are genuinely stuck, writing the
four lines out forces you to state what you have actually tested — which is
frequently the moment the answer arrives, before anyone else has read a word
of it. [[Getting Unstuck]] takes it from there.

> [!question] The two questions to answer before you ask for help
> What did you expect, and what did you measure? Bring the numbers. A
> question with two numbers in it gets solved at your bench in ninety
> seconds; a question without them turns into somebody else debugging
> your project for you, which helps this build and no future one.

## Make it yours

1. Take a working circuit and break it deliberately in a way a partner
   cannot see — a lifted ground, a swapped pin constant, a resistor
   replaced with a much larger one. Time how long the six checks take to
   find it.
2. Add a heartbeat LED and a boot print to every program you write for
   the rest of the unit, and leave them in for the demonstration.
3. Write up one real fault from your own build in the four-line form, and
   include it in your submission for [[The Embedded Device]]. The fault
   you found and fixed is evidence of skill in a way a working device
   alone is not.

%%curriculum-start%%
## Curriculum connection

![[B1.4]]

![[B3.2]]

![[B5.3]]
%%curriculum-end%%
