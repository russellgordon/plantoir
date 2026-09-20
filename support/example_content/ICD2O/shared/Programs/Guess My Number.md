---
title: Guess My Number
publish: true
created: __CREATED__
tags:
  - programs
---
The computer picks a secret number from 1 to 100, and you hunt it down
armed with nothing but "Higher!" and "Lower!". One
[[Loops|while loop]], one [[Conditionals|conditional chain]], and the
`random` module doing the picking.

## The program

```python
import random

secret = random.randint(1, 100)
guesses = 0
guess = 0

print("I am thinking of a number from 1 to 100.")

while guess != secret:
    guess = int(input("Your guess: "))
    guesses = guesses + 1
    if guess < secret:
        print("Higher!")
    elif guess > secret:
        print("Lower!")
    else:
        print("Got it in", guesses, "guesses!")
```

## Read it before you run it

Predict in writing first — then run the program and grade yourself.

- `guess` starts at `0`. Why is that *guaranteed* to be wrong, and
  what does the while loop's condition do with that fact?
- Which branch runs on the winning guess — and why does the loop stop
  immediately afterwards?
- You guess `50` and see `Higher!`. Exactly which numbers are still
  possible? A strategy is hiding in that answer — the same one that
  wins [[Twenty Questions]].

## Make it yours

1. **One line.** Make the secret range 1 to 1000 — then keep the
   welcome message honest.
2. **A few lines.** Add `Way higher!` and `Way lower!` responses when
   a guess misses by more than 25.
3. **A real change.** Allow only seven guesses, and announce a win or
   a loss when the game ends. Seven is enough for 1 to 100 — your
   answer to the third prediction above explains why.

%%curriculum-start%%
## Curriculum connection

![[C1.4]]

![[C2.4]]

![[C3.1]]

![[C3.4]]
%%curriculum-end%%
