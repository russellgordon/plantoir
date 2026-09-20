---
title: Testing Without a Debugger
publish: true
created: __CREATED__
tags:
  - code
enableToc: true
---
There is no step button on a microcontroller. You cannot pause the world,
hover over a variable, and watch the motor politely wait for you — the
motor is a physical object with momentum, and the interrupt that fires
every millisecond does not care that you are thinking. Everything you
know about debugging on a laptop has to be rebuilt out of different
instruments, and the ones you have are better than they look.

## The instruments you actually have

| Instrument | What it answers | What it costs |
| --- | --- | --- |
| `print` with a timestamp | What did the program believe, and when? | Time; enough of it to change the timing you are measuring |
| A spare output pin, toggled | Exactly when did this line run, to the microsecond? | One pin, and a scope or logic analyzer |
| An LED or two | Which state am I in, right now, from across the room? | Almost nothing |
| A logic analyzer on the bus | Did the peripheral really answer? | Setup time — see [[Using a Logic Analyzer]] |
| A meter and a scope | Is the electrical side even doing what the code asked? | The habits in [[Using an Oscilloscope Properly]] |
| A log file on the board | What happened while nobody was watching? | Flash wear and write time |

The second row is the one students discover late and then use forever.
Toggle a pin high at the top of a function and low at the bottom, and the
scope shows you exactly how long that function takes and how often it
runs — timing information that `print` is too slow and too intrusive to
give you.

```python
probe = Pin(16, Pin.OUT)      # a spare pin, wired to the scope


def run_one_pass():
    probe.value(1)
    ...                       # the work being measured
    probe.value(0)
```

## Make the program say what it is doing

Prints are only useful if they are readable at speed, so give them a
timestamp, a source, and a level you can turn down.

```python
import time

TRACE = True                 # one switch, flipped for a demonstration


def trace(where, message):
    if TRACE:
        print(time.ticks_ms(), where, message)


trace("control", "state -> running, error 2.4 C, duty 68 percent")
```

Print the *decision*, not the raw data. "raw 28150" tells you almost
nothing at three lines a second; "error 2.4 C, duty 68 percent, state
running" tells you whether the controller is behaving. And keep the
switch, because a device that prints continuously is a device whose
timing you have changed — the classic case of the measurement altering
the thing measured, and the reason a bug can vanish when you add a
`print`.

When the device runs unattended, write the same lines to a file instead:

```python
def log_line(text):
    with open("log.txt", "a") as log_file:
        log_file.write("%d,%s\n" % (time.ticks_ms(), text))
```

Comma-separated, one event per line, so it opens in a spreadsheet and
becomes a graph. Do not log inside the fast path — the write takes real
time and will show up in the worst-case pass measurement from
[[Timing, Interrupts, and Real Time]].

## Test the logic where there is no hardware

The reason [[Structuring a Larger Program]] insisted on modules is that
pure logic can then be tested without a board at all. Replace the
hardware modules with fakes and run the control logic on a laptop, where
you *do* have a debugger.

```python
# fake_sensor.py — stands in for the real thing during logic tests.
readings = [22.0, 24.5, 26.0, 28.5, 29.0, 999.0, 27.0]
_index = 0


def read_celsius():
    global _index
    value = readings[_index % len(readings)]
    _index = _index + 1
    return value
```

Feed it the awkward cases on purpose: the value just below a threshold,
the value just above, the implausible one, the same value repeated
forever. Then assert what should happen rather than reading output and
nodding.

```python
def check(description, actual, expected):
    if actual == expected:
        print("PASS", description)
    else:
        print("FAIL", description, "got", actual, "expected", expected)


check("clamps above full scale", set_percent_clamped(120), 100)
check("clamps below zero", set_percent_clamped(-5), 0)
check("passes a legal value", set_percent_clamped(60), 60)
check("rejects an implausible reading", validate(999.0, 1000), None)
```

Four lines, run in a second, and they will catch the regression you would
otherwise find at the demonstration. Keep them in the repository with the
code — [[Version Control for Firmware]] — and run them before every
commit that changes behaviour.

## A power-on self-test costs ten lines

```python
def self_test():
    """Check what can be checked before the device starts controlling."""
    problems = []

    if len(i2c.scan()) == 0:
        problems.append("no I2C devices found")

    celsius = sensor.read_celsius()
    if not sensor.is_plausible(celsius):
        problems.append("sensor reading implausible: %s" % celsius)

    fan.set_percent(0)
    return problems
```

Run it at boot, print the list, and light the fault LED if it is not
empty. A device that announces "no I2C devices found" saves the next
person — quite possibly you — twenty minutes of reading code that was
never the problem.

## Halve the problem, and write down what you halved

When something is wrong and you have no idea where, stop reading code and
start bisecting. Every test should split the remaining possibilities
roughly in half.

1. **Is it electrical or is it software?** Meter the pin. If the pin is
   doing what the code asked and the load is not moving, the code is
   innocent.
2. **Does the input arrive?** Trace the raw value before any processing.
3. **Does the decision follow from the input?** Trace the error and the
   output the controller computed, and check the arithmetic by hand.
4. **Does the output reach the hardware?** Scope the PWM pin, then the
   gate, then the load.
5. **Change one thing at a time**, and put it back if it did not help. Two
   simultaneous changes that cancel each other out will cost you the
   afternoon.

Then record it, because an undocumented fix is a fix you get to discover
again later in the course. In your [[Tech Journal]] : the symptom, exactly;
what you expected; what you measured; what you changed; what happened next.
That record is also the log the curriculum asks you to keep of work done on
a system, and it is the raw material for the failure analysis in
[[The Engineering Design Project]] and the defence in
[[The Engineering Review]]. "It works now" is not an entry. "The I²C
reads failed above 100 kHz with 30 cm leads; shortened to 10 cm and added
2.2 kΩ pull-ups; 400 kHz now reads reliably over a thousand samples" is.

%%curriculum-start%%
## Curriculum connection

![[B2.2]]

![[B2.3]]

![[B3.4]]
%%curriculum-end%%
