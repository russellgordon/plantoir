---
title: Formulas as Algorithms
publish: true
codeRunner: true
created: __CREATED__
tags:
  - concepts
---
A formula from mathematics or science arrives as a single line of
notation. A program needs it as a sequence of steps, with every value
either asked for, calculated, or already known. Getting from one to the
other is a skill, and it is mostly about naming.

Take the cost of running an appliance: energy in kilowatt-hours, times
the price per kilowatt-hour.

$$\text{cost} = \frac{\text{watts} \times \text{hours}}{1000} \times \text{rate}$$

The formula says nothing about where the numbers come from, in what
order to do the arithmetic, or what to do when somebody types "eight"
instead of `8`. The algorithm has to.

When it asks, type the watts, the hours and the price — `1500`, `2`
and `0.13`, say.

```python run readonly
watts = float(input("Appliance power, in watts: "))
hours = float(input("Hours used per day: "))
rate = float(input("Price per kilowatt-hour, in dollars: "))

kilowatt_hours = watts * hours / 1000
daily_cost = kilowatt_hours * rate

print(f"That appliance costs ${daily_cost:.2f} per day to run.")
```

Three things happened in the translation, and they happen every time:

1. **Every symbol became a named variable.** `watts`, not `w`. The
   formula's brevity is a cost, not a feature, once it is code.
2. **The middle got a name.** `kilowatt_hours` is not in the formula,
   but naming it makes the line readable and gives you somewhere to
   look when the answer is wrong by a factor of a thousand.
3. **Units were decided.** Watts and hours in, dollars out. A comment
   or a prompt that states the unit prevents the most common wrong
   answer in this kind of program, which is a correct calculation of
   the wrong quantity.

## The method, for any formula

1. Write the formula down as it is given, symbols and all.
2. List every symbol: is it input, is it calculated, or is it a
   constant like the 1000 above?
3. Order the calculations so nothing is used before it exists.
4. Name each intermediate value.
5. Check it by hand with one set of numbers you can verify — and keep
   that pair as your first test case, exactly as
   [[Writing a Test Plan]] describes.

Step 5 is the one students skip and professionals never do. A formula
transcribed with a misplaced bracket produces plausible numbers
forever, and only a hand-worked example catches it. Python follows the
usual order of operations, so `watts * hours / 1000` is fine — but
`watts * (hours / 1000)` would be too, and only one of them is what you
meant.

%%curriculum-start%%
## Curriculum connection

![[B3.2]]

![[A1.3]]
%%curriculum-end%%
