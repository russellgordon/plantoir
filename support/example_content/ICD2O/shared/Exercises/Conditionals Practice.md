---
title: Conditionals Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Conditionals]]. A conditional is a fork in the
road — the whole skill is knowing which branch runs, and why.

## Questions

1. Which of these jobs needs a conditional, and which is just a
   sequence of steps? (a) greet every name on a list, (b) charge less
   if the customer is a student, (c) print today's date.
2. **Predict the output** when `temp` is `-5`, then when it is `30`.
   ```python
   if temp > 25:
       print("Hot")
   elif temp > 0:
       print("Mild")
   else:
       print("Brrr")
   ```
3. **Find the bug.** Python refuses to run `if mark = 50:` at all.
   What did the writer mean, and why does Python object?
4. **Predict the output** when `age` is `16` — then when it is `20`.
   ```python
   if age >= 13:
       if age <= 19:
           print("Teen")
   ```
5. Write a four-line snippet: ask for a password, then print `Welcome`
   if it equals `sesame` and `No entry` otherwise.
6. **Challenge.** Rewrite question 4 as a *single* `if` using `and` —
   then suggest why real checks often keep conditions separate.

## Answers

> [!success]- Answer 1
> Only (b) — the price *depends on* something. (a) is repetition — a
> job for a [[Loops|loop]] — and (c) is plain sequence.

> [!success]- Answer 2
> `-5`: neither test is true — `Brrr`. `30`: `Hot`, and `Mild` never
> gets a look — an `elif` chain stops at the *first* true test.

> [!success]- Answer 3
> They meant `==`, the *question* "are these equal?". A single `=` is
> a command, and a command cannot be a condition — a `SyntaxError`.

> [!success]- Answer 4
> `16`: both tests pass — `Teen`. `20`: the outer test passes, the
> inner one fails, and *nothing at all* prints — there is no `else`.

> [!success]- Answer 5
> `password = input("Password: ")`; `if password == "sesame":` with
> `print("Welcome")` beneath; `else:` with `print("No entry")`.

> [!success]- Answer 6
> `if age >= 13 and age <= 19:` — one line, same behaviour. Separate
> conditions let each failure carry its *own*, more useful message.

%%curriculum-start%%
## Curriculum connection

![[C1.4]]

![[C1.5]]

![[C2.3]]
%%curriculum-end%%
