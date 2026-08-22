---
title: Code Meets Hardware
publish: true
created: __CREATED__
tags:
  - code
---
Somewhere between your program and a real LED sits an *interface*
— the electronics that turn a line of code into an actual current
in an actual wire. You will build one for real in
[[Control Something with Code]]; this page builds the software
half first, with the hardware simulated in text. Simulated is not
cheating — it is how you separate "my logic is wrong" from "my
wiring is wrong" before both can be wrong at once.

## A status light, simulated

```python
def set_light(colour):
    print("[LIGHT is now " + colour.upper() + "]")

set_light("green")
set_light("amber")
set_light("red")
```

`def` creates a small named action of your own; the two indented
lines are what `set_light` does each time it is called. Here it
stands in for the interface: one clear name, with the messy
details of *how* hidden inside. On real hardware only that
function changes — the `print` becomes a signal on a pin — and the
rest of the program never notices. That is the whole idea of an
interface: a boundary that lets each side change without asking
the other's permission.

## Making the light mean something

```python
def set_light(colour):
    print("[LIGHT is now " + colour.upper() + "]")

temperature = int(input("CPU temperature in Celsius? "))

if temperature < 70:
    set_light("green")
elif temperature < 90:
    set_light("amber")
else:
    set_light("red")
    print("Shut it down and check the cooling.")
```

Now the light *reports*: the program reads a value from the world
and drives a signal back out into it. Sense, decide, signal —
every gadget you own is this loop wearing a costume, and
[[The Gadget]] asks you to sew one yourself.

## Make it yours

1. Add a fourth state — flashing red, say — for temperatures over
   100, and decide what text stands in for "flashing".
2. Swap the sensor: make the light report battery percentage, or
   free disk space, or anything numeric worth watching.
3. Write one sentence: on real hardware, which lines of your
   program would survive unchanged, and why is it almost all of
   them?

%%curriculum-start%%
## Curriculum connection

![[B2.3]]

![[B2.4]]

![[B5.1]]

![[B5.2]]

![[B5.4]]
%%curriculum-end%%
