---
title: Sensors and Actuators
publish: true
created: __CREATED__
tags:
  - concepts
---
[[Drive a Motor]] is the class where somebody always asks why we cannot
just wire the motor to a pin. The answer is a number: the motor wants
several hundred milliamps and the pin can supply a few tens. Every idea
on this page comes from taking that mismatch seriously at both ends of
the system — what the world can tell your board, and what your board can
make the world do.

## Sensors: turning something physical into a voltage

A sensor's job is to make a quantity you care about show up as an
electrical quantity you can read. What you need to know about any sensor
is which kind of signal it hands you, because that decides the code.

| Sensor | What changes | How the board reads it |
| --- | --- | --- |
| Push button, limit switch | Contact opens or closes | Digital input with a pull-up or pull-down |
| Potentiometer | Resistance of a divider | Analog input |
| Light-dependent resistor | Resistance falls with light | Divider, then analog input |
| Thermistor | Resistance changes with temperature | Divider, then analog input |
| Optical / infrared detector | Output switches, or varies | Digital or analog, check the part |
| Accelerometer, many modern parts | Digital value on a serial bus | Serial interface, using a library |

Notice how many of those rows say "divider". A resistance is not
something a microcontroller pin can read. Put the sensing resistance in
series with a fixed resistor across the supply, and the point between
them becomes a voltage that moves as the sensor does — the voltage
divider from [[Series and Parallel Circuits]], earning its place.

Two disciplines make sensor readings trustworthy:

- **Every digital input needs a defined idle state.** A button connects a
  pin to ground; a pull-up resistor holds it high the rest of the time.
  Without the resistor the pin floats and reads randomly. Most boards
  have internal pull-ups you can switch on in software, which is what
  `Pin.PULL_UP` is doing in [[Input, Output, and Timing]].
- **Every sensor needs calibrating against reality.** The raw number
  means nothing until you have written down what it reads in two known
  conditions. Do it in your [[Tech Journal]], with the conditions
  recorded, or the numbers are unusable next week.

## Actuators: turning a decision into motion, light, or heat

| Actuator | What it wants | The catch |
| --- | --- | --- |
| LED | 10 – 20 mA, current-limited | Needs a series resistor, always |
| DC motor | Hundreds of mA and up | Far beyond a pin; generates voltage spikes |
| Servo | Its own supply, plus a control pulse | Pulse width sets the angle, not the speed |
| Stepper motor | A driver producing a coil sequence | Holding torque costs current even when still |
| Relay | Coil current, tens of mA and up | Inductive; switches a separate circuit entirely |
| Solenoid, valve | Large current in short bursts | Strongly inductive; gets hot if held on |

A servo is worth a sentence of its own because it behaves unlike anything
else here. It expects a pulse roughly every 20 ms, and the *width* of
that pulse — around 1 ms to 2 ms — commands a position, not a speed. Send
a 1.5 ms pulse and it drives itself to centre and holds there, fighting
you if you push. That internal feedback loop is what you are buying.

> [!danger] Three rules that keep boards alive
> **Never connect a motor, solenoid, or relay coil directly to a
> microcontroller pin.** Use a transistor or a purpose-made driver chip.
> The pin's job is to switch the driver; the driver's job is to carry the
> current.
>
> **Always fit a flyback diode across an inductive load.** A coil resists
> a change in its current, so switching it off produces a reverse voltage
> spike that can far exceed the supply and will punch through a
> transistor. The diode, fitted so it does *not* conduct in normal
> operation, gives that energy a harmless loop to die in.
>
> **Give a motor its own supply, and tie the grounds together.** Motors
> drag the rail down when they start, and a microcontroller that browns
> out mid-instruction does not fail politely. One shared ground, separate
> positive supplies.

## Putting a system together

A control system is always the same three stages: sense, decide, act. The
sensing stage produces a number; your program decides what that number
means; the acting stage has enough current behind it to do something
about it. Most projects that fail do so at one of the two joints, not in
the middle.

When you design one, work backwards from the load:

1. **What does the actuator need?** Voltage, current, and whether it is
   inductive. Get these from the part, not from memory.
2. **What driver carries that?** A transistor rated comfortably above the
   current, with the base or gate resistor worked out, plus a flyback
   diode if the load has a coil in it.
3. **What supply feeds it?** Sized for the actuator's *stall* or inrush
   current, not its running current.
4. **What does the sensor give you?** Digital or analog, and over what
   range in the conditions you will actually meet.
5. **Only then, write the code.** [[Reading Sensors]] and
   [[Driving Outputs Safely]] handle the two ends;
   [[Structuring Embedded Code]] keeps the middle readable.

That order is deliberate. Code written before the electrical design is
settled gets rewritten, and worse, it hides the design decisions inside
itself where nobody can review them. Do the wiring diagram first — see
[[Reading Schematics]] — and bring both to [[The Embedded Device]].
[[Microcontroller Code Practice]] rehearses the numbers that decide
whether a pin can drive a thing at all.

%%curriculum-start%%
## Curriculum connection

![[A3.2]]

![[B3.1]]

![[B5.3]]
%%curriculum-end%%
