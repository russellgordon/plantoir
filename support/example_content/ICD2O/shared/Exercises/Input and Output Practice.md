---
title: Input and Output Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Data in Programs]]. Every program here talks
to a person — which means a person can always type the unexpected.

## Questions

1. **Predict the output** of each line — they are not the same.
   ```python
   print("Age:", 15)
   print("Age:" + "15")
   ```
2. **Predict the output** when the user types `Sam` at the prompt.
   ```python
   name = input("Who is this? ")
   print("Hi, " + name + "!")
   print("Bye, " + name + ".")
   ```
3. **Find the bug.** Why does this crash, and what one change fixes it?
   ```python
   age = input("How old are you? ")
   print("Next year you will be", age + 1)
   ```
4. In `n = int(input("Number: "))`, describe what happens when the
   user types `7` — and then what happens when they type `seven`.
5. Write a short program: ask for two numbers, print their sum. Test
   it with `3` and `4` — if it prints `34`, you have found question 3.
6. **Challenge.** Ask for a word and a number, then print the word
   that many times on one line. `cat` and `3` should give `catcatcat`.

## Answers

> [!success]- Answer 1
> `Age: 15` then `Age:15`. A comma in `print` inserts a space; `+`
> glues two strings with nothing added. Different tools.

> [!success]- Answer 2
> Two lines: `Hi, Sam!` then `Bye, Sam.` — read once, reused twice.

> [!success]- Answer 3
> `age` is a string — `input()` always returns text — so `age + 1`
> adds text to a number: a `TypeError`. Wrap the input in `int()`.

> [!success]- Answer 4
> `7` becomes the number `7` and all is well. `seven` defeats `int()`
> completely, and the program stops with a `ValueError`.

> [!success]- Answer 5
> ```python
> first = int(input("First number: "))
> second = int(input("Second number: "))
> print("Sum:", first + second)
> ```

> [!success]- Answer 6
> `word = input("Word: ")`, `times = int(input("How many? "))`, then
> `print(word * times)` — multiplying a string repeats it.

%%curriculum-start%%
## Curriculum connection

![[C1.3]]

![[C2.1]]

![[C2.2]]
%%curriculum-end%%
