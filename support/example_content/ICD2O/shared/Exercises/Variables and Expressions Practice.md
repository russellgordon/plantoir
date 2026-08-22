---
title: Variables and Expressions Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Data in Programs]] — the tracing habit comes
from [[Predict the Output]]. Trace on paper first; the computer checks.

## Questions

1. After these lines run, what is stored in `score`? Explain why `=`
   here cannot mean what it means in maths class.
   ```python
   score = 10
   score = score + 5
   ```
2. **Predict the output**, character by character — spaces count.
   ```python
   first = "Rob"
   last = "Ott"
   print(first + last)
   ```
3. **Predict the output.** Does changing `a` afterwards change `b`?
   ```python
   a = 3
   b = a
   a = 7
   print(b)
   ```
4. **Find the bug.** `prize = "100"` then `total = prize + 50` — and
   line 2 crashes. Name the problem, then fix it two different ways.
5. Write a three-line snippet: your name in one variable, your
   favourite number in another, then print a sentence using both.
6. **Challenge.** Variables `red` and `blue` hold values. Swap them —
   afterwards, each must hold the other's old value.
7. **Data types.** State the data type (`int`, `float`, `str`, or `bool`)
   of each: (a) `42`, (b) `3.14`, (c) `"True"`, (d) `True`, (e) `"0"`.
   Explain why `type("True")` is different from `type(True)` and how each
   is used in a program.
8. **Order of operations.** Determine the exact value of each expression,
   showing the evaluation order: (a) `10 + 4 * 2 ** 3`,
   (b) `(10 + 4) * 2 ** 3`, (c) `20 - 6 // 2 + 5 % 2`. Explain why
   parentheses are required when calculating an average `(a + b) / 2`.

## Answers

> [!success]- Answer 1
> `score` is `15`. In Python, `=` is an instruction — work out the
> right side, store it on the left — so line 2 adds 5 to what is there.

> [!success]- Answer 2
> `RobOtt` — no space, because `+` glues strings together exactly as
> they are. Want `Rob Ott`? Add it yourself: `first + " " + last`.

> [!success]- Answer 3
> It prints `3`. Line 2 copies the *value* 3 into `b` — it does not
> tie `b` to `a` forever. Reassigning `a` later changes nothing.

> [!success]- Answer 4
> `prize` holds the *text* `"100"`, and adding text to a number is a
> `TypeError`. Fix 1: `prize = 100`. Fix 2: `total = int(prize) + 50`.

> [!success]- Answer 5
> One version — yours will differ: `name = "Priya"`, `number = 17`,
> then `print(name + " picks " + str(number) + " every time.")`.

> [!success]- Answer 6
> A third variable holds one value while the other moves:
> `spare = red`, `red = blue`, `blue = spare`. Try it *without* the
> spare and watch a value get overwritten — that is why it exists.

> [!success]- Answer 7
> (a) `int` (integer), (b) `float` (decimal floating-point number),
> (c) `str` (text string), (d) `bool` (Boolean truth value),
> (e) `str` (text string, because quotes surround it). `"True"` is text
> for printing or matching words; `True` is a boolean truth value used
> directly in conditionals (`if True:`) to decide execution flow.

> [!success]- Answer 8
> (a) `42` — exponent first ($2^3 = 8$), then multiply ($4 \times 8 = 32$),
> then add ($10 + 32 = 42$). (b) `112` — brackets first ($10 + 4 = 14$),
> exponent ($2^3 = 8$), then multiply ($14 \times 8 = 112$). (c) `18` —
> division ($6 // 2 = 3$) and modulo ($5 \% 2 = 1$), then left-to-right
> ($20 - 3 + 1 = 18$). Without brackets in `a + b / 2`, division outranks
> addition, dividing only `b` by 2 rather than the sum.

%%curriculum-start%%
## Curriculum connection

![[C1.3]]

![[C1.4]]

![[C2.1]]
%%curriculum-end%%
