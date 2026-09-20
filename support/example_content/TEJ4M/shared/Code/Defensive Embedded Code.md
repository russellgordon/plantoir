---
title: Defensive Embedded Code
publish: true
created: __CREATED__
tags:
  - code
enableToc: true
---
A program on a laptop that hits an exception prints a traceback and
stops, and somebody reads it. A program on your board that hits an
exception stops too — with the heater still on, because nothing told the
heater otherwise. Defensive code is the difference between a device that
fails and a device that fails *safely*, and by Grade 12 that difference
is a design requirement rather than a nicety.

## Assume every input is wrong until it has been checked

A sensor can be unplugged, shorted, saturated, or simply lying. Your code
sees a number either way, so check it against physics before you act on
it.

```python
PLAUSIBLE_C = (-10.0, 120.0)      # this device lives indoors
MAX_CHANGE_C_PER_SECOND = 5.0     # a plate cannot heat faster than this

last_good_c = None
last_good_ms = None


def validate(celsius, now_ms):
    """Return a trusted reading, or None if it fails a check."""
    global last_good_c, last_good_ms

    if celsius is None:
        return None                             # the device did not answer

    low, high = PLAUSIBLE_C
    if celsius < low or celsius > high:
        return None                             # outside physical range

    if last_good_c is not None:
        seconds = time.ticks_diff(now_ms, last_good_ms) / 1000.0
        if seconds > 0:
            change = abs(celsius - last_good_c) / seconds
            if change > MAX_CHANGE_C_PER_SECOND:
                return None                     # impossible rate of change

    last_good_c = celsius
    last_good_ms = now_ms
    return celsius
```

Two checks, both cheap, and between them they catch most real sensor
faults. A disconnected analog input reads a value pinned at one end of
the range; a failing digital sensor often returns zero or all-ones; a
loose wire produces jumps no physical process could make. Each of those
becomes `None`, and `None` is a condition your state machine already
knows what to do with — the `FAULT` state in
[[State Machines in Code]] exists for exactly this.

Do not silently substitute a default. Returning 20 °C when the sensor is
broken is how a heater runs all night; returning `None` forces the caller
to have a policy.

## Clamp every output, at the point it leaves your code

```python
def set_percent(percent):
    """Drive the fan at 0–100 percent. Anything else is a caller's bug,
    and this function's job is to make it harmless."""
    if percent < 0:
        percent = 0
    if percent > 100:
        percent = 100
    _pwm.duty_u16(int(percent * 65535 / 100))
```

The controller in [[Feedback and Control Systems]] will ask for 120% the
first time the error is large — a gain of 20% per degree meeting a 6
degree error — because arithmetic does not know about limits. Clamp
in the driver, not in the caller, so that every path through the program
is covered by one piece of code you can point at.

The same argument applies to anything with a physical limit: a servo
angle, a step count, a setpoint a user can type. Validate at the
boundary, once.

## Fail into a safe state, deliberately

Every device has a safe state, and you must be able to say what yours is
in one sentence: heater off, motor stopped, valve closed, brake applied.
Then make every exit from the program pass through it.

```python
def main():
    fan.off()                     # known state before anything else runs
    ...


try:
    main()
except Exception as error:
    fan.off()
    sys.print_exception(error)    # keep the evidence
    log_fault(error)
finally:
    fan.off()                     # belt and braces; runs on any exit
```

`finally` runs whether the program ended normally, raised, or was
interrupted at the REPL. Catching `Exception` here is one of the few
places a broad catch is right — the alternative is an unhandled exception
that leaves the hardware energised — but notice that it still *records*
what happened. A bare `except: pass` anywhere in your program is a place
where information goes to die, and it will cost you an evening.

Hardware carries half of this responsibility and cannot be replaced by
software. A pull-down resistor on a MOSFET gate holds the load off while
the microcontroller is resetting and its pins are floating inputs; a
flyback diode protects the driver regardless of what the firmware
believes. [[Transistors as Switches]] is the other half of this page.

## The watchdog, used honestly

A watchdog timer resets the board if your program stops feeding it. It is
the last line of defence against a lock-up you did not predict.

```python
from machine import WDT

wdt = WDT(timeout=5000)           # port-dependent; some cannot be stopped

while True:
    run_one_pass()
    wdt.feed()                    # only here, and only after real work
```

Three rules keep it useful rather than decorative. **Feed it in exactly
one place**, at the bottom of the main loop, after the work — a watchdog
fed from an interrupt or from three places is a watchdog that will
happily keep a hung program alive. **Set the timeout from your measured
worst-case pass time**, with margin, not from a round number you liked.
And **be honest about what it does**: it reboots the device. If a reboot
puts your machine in a dangerous state, or if the fault will simply
recur in ten seconds, the watchdog has bought you a loop of reboots
instead of a fix.

Record why the board started, so a reboot is evidence rather than a
mystery:

```python
import machine

cause = machine.reset_cause()
print("reset cause:", cause)      # compare against your port's constants
```

## The checks that belong in your report

- [ ] Every sensor reading passes a range check and a rate check.
- [ ] Every actuator command is clamped where it leaves the code.
- [ ] The device's safe state is written in one sentence, and reached on
      every exit path.
- [ ] Power-up leaves outputs off before anything else happens.
- [ ] Bus reads have timeouts or are wrapped so a silent device cannot
      hang the loop.
- [ ] Faults are logged with a timestamp, not merely displayed.
- [ ] The failure behaviour has been *tested by causing it* — unplug the
      sensor while it runs, and watch.

That last one is the one that separates a claim from evidence. Pull the
sensor lead out in front of your teacher, and if the fan goes to a safe
state and the fault is logged, the design review is largely over. The
troubleshooting mindset behind all of it is the same logical isolation
you use on the bench in [[Testing Without a Debugger]], and the failure
cases you name here are the ones [[The Engineering Design Project]] asks
you to demonstrate rather than describe.

%%curriculum-start%%
## Curriculum connection

![[B2.3]]

![[B3.4]]

![[B5.2]]

![[B5.4]]
%%curriculum-end%%
