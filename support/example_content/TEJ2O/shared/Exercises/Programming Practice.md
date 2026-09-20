---
title: Programming Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[First Programs]] and [[Decisions and Loops]]
— the same Python that will soon be blinking LEDs in
[[Control Something with Code]]. Predict on paper; run only to check.

## Questions

1. **Predict the output** of `print("Hello,", name)` when
   `name = "Avery"`.
2. **Predict the output.**
   ```python
   age = 15
   if age >= 16:
       print("Can drive")
   else:
       print("Not yet")
   ```
3. **Predict the output** of `for count in range(3):` with
   `print("Blink")` beneath it — how many lines, saying what?
4. **Fix the bug.** This line refuses to run at all:
   `print("Hello, world)`
5. **Fix the bug.** Python complains about the second line.
   ```python
   age = 16
   if age = 16:
       print("Sweet sixteen")
   ```
6. **Challenge.** Ask the user for a number, then print `Too high`,
   `Too low`, or `Got it!` compared with a secret value of 7.
7. **Write an input/output script.** Write a three-line Python program
   that prompts a technician for their first name, prompts for their bench
   number, and prints a formatted login message: `Technician <Name> active at Bench <Number>.`
8. **Calculate with user inputs.** Write a program that asks the user
   for a circuit's voltage (in volts) and resistance (in ohms), converts
   them to floats, computes current using Ohm's law ($I = V/R$), and
   prints the result with unit `A`. If current exceeds $0.02\ \text{A}$
   ($20\ \text{mA}$), print a warning: `Current exceeds safe LED limit!`

## Answers

> [!success]- Answer 1
> One line: `Hello, Avery`. The variable's *value* prints, not its
> name — and `print` supplies the space between its two items.

> [!success]- Answer 2
> `Not yet`. The test `15 >= 16` is false, so the `else` branch
> runs — exactly one of the two branches, never both.

> [!success]- Answer 3
> Three lines, each reading `Blink`. `range(3)` supplies 0, 1, 2 —
> three trips through the loop, none of them numbered 3.

> [!success]- Answer 4
> The closing quotation mark is missing: `print("Hello, world")`.
> Python read to the line's end still waiting for the string to end.

> [!success]- Answer 5
> The test needs `==`, not `=`: `if age == 16:`. A single `=`
> *assigns*; `==` *compares* — ask the question, don't restate it.

> [!success]- Answer 6
> Read, convert, compare: `guess = int(input("Your guess? "))`, then
> `if guess > 7:` print `Too high`, `elif guess < 7:` print
> `Too low`, `else:` print `Got it!`. The `int(...)` matters —
> `input` hands back text, and text compares with nothing.

> [!success]- Answer 7
> ```python
> name = input("Enter technician name: ")
> bench = input("Enter bench number: ")
> print("Technician", name, "active at Bench", bench + ".")
> ```

> [!success]- Answer 8
> ```python
> volts = float(input("Supply voltage (V): "))
> ohms = float(input("Resistance (ohms): "))
> current = volts / ohms
> print("Calculated current:", current, "A")
> if current > 0.02:
>     print("Current exceeds safe LED limit!")
> ```

%%curriculum-start%%
## Curriculum connection

![[B5.1]]

![[B5.2]]

![[B5.3]]
%%curriculum-end%%
