---
title: Simulating with Python
publish: true
created: __CREATED__
tags:
  - tutorials
enableToc: true
---
There is a second way to answer a probability question, and it needs
no formula at all: **do the thing many times and count**. That is a
simulation, and it is not a lesser method — it is how professionals
answer questions whose exact mathematics is intractable, and how they
check the exact mathematics when it is not. You do not need to know
Python to use this page. You need about six lines of it, and they are
all below.

## Three tools do almost everything

Python's `random` module is the whole toolkit. Three functions cover
nearly every situation this course can pose:

| Call | What it gives you | Use it for |
| --- | --- | --- |
| `random.random()` | A decimal from 0 up to 1 | Anything with probability $p$: the event happens when the number lands below $p$ |
| `random.randint(1, 6)` | A whole number from 1 to 6 | Dice, birthdays, drawing a numbered ticket |
| `random.shuffle(items)` | Rearranges a list in place | Dealing cards, assigning coats, randomizing an order |

Around them you need one loop that repeats a trial many times and one
counter that tallies the trials where the thing happened. That is the
entire pattern:

```python
number_of_trials = 100000
successes = 0
for trial in range(number_of_trials):
    if something_happened():
        successes = successes + 1

print(successes / number_of_trials)
```

## Start with a question you can already answer

Never trust a simulation you have not calibrated. Before asking a
program something you do not know, ask it something you do — and
check that it agrees.

```python
import random

def roll_two_dice():
    return random.randint(1, 6) + random.randint(1, 6)

number_of_trials = 100000
sevens = 0
for trial in range(number_of_trials):
    if roll_two_dice() == 7:
        sevens = sevens + 1

print(sevens / number_of_trials)
```

This prints something close to `0.167`, and the exact answer is
$\frac{6}{36} = 0.1\overline{6}$. Now you know two things: the
program models two dice correctly, and this pattern of code produces
answers you can believe. That calibration step is not optional. A
simulation of the wrong situation will report a confident, precise,
wrong number and never once look uncertain.

## Now ask something you cannot compute yet

Twenty people check their coats at a party, and a careless attendant
hands them back completely at random. What is the chance that *at
least one* person gets their own coat back?

Everyone guesses low — "one in twenty, surely" — and the counting
method needed to do this exactly is beyond the unit. The simulation
is not.

```python
import random

def someone_gets_their_own_coat(number_of_guests):
    coats = list(range(number_of_guests))
    random.shuffle(coats)
    for guest in range(number_of_guests):
        if coats[guest] == guest:
            return True
    return False

number_of_trials = 100000
matches = 0
for trial in range(number_of_trials):
    if someone_gets_their_own_coat(20):
        matches = matches + 1

print(matches / number_of_trials)
```

It prints about `0.632`. Not one in twenty — closer to two chances in
three. Then run it again with 5 guests instead of 20, and again with
100. The answer barely moves: about 0.633, then 0.632, then 0.632.
A quantity that refuses to depend on the size of the party is a
quantity demanding an explanation, and the explanation turns out to
involve $e$ — the answer approaches $1 - \frac{1}{e}$, which is
$0.6321\ldots$ Nobody expected the coat check to summon a constant
from the exponential functions course. That is the sort of thing
simulation finds for you.

> [!question]- Try it yourself: the birthday problem, by brute force
> Simulating [[The Birthday Problem]] takes the same shape: build a
> list of `number_of_people` random integers from 1 to 365, then
> check every pair to see whether any two match. Run 20,000 trials
> with 23 people and you will get roughly `0.507`, which is the
> exact answer to three decimal places. Then hunt: what is the
> smallest group size where your simulation reliably clears 0.5?

## How many trials is enough?

Run the dice program with `number_of_trials = 100` five times and you
might get 0.13, 0.15, 0.16, 0.12, 0.20. Run it with 100,000 five
times and you get 0.168, 0.167, 0.168, 0.167, 0.168. The estimate is
not becoming *more correct*; it is becoming *less wobbly* — and the
wobble shrinks roughly like $\frac{1}{\sqrt{n}}$, so buying one more
decimal place of stability costs a hundred times the trials.

If that sounds familiar, it should. It is the same $\sqrt{n}$ that
governs the margin of error on a poll, and it is why a national
survey asks about a thousand people rather than a hundred thousand.
A simulation *is* a sample — you are polling an imaginary population
of trials — so everything [[Sampling Techniques]] says about sample
size applies to your program too.

> [!warning] A simulation never proves anything
> It estimates. Report a simulated probability the way you would
> report any statistic: with the number of trials beside it, so a
> reader can judge the wobble — "about 0.63, from 100,000 trials",
> never a bare "0.63207". Extra decimal places you did not earn are
> a claim you cannot defend, which is exactly the standard
> [[Writing About Data]] holds you to. And when an exact method
> exists, the honest workflow is to do both and make them agree,
> the way [[Checking Your Own Work]] insists.

%%curriculum-start%%
## Curriculum connection

![[A1.4]]

![[B1.1]]
%%curriculum-end%%
