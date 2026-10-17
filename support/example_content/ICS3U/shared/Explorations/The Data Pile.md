---
title: The Data Pile
publish: true
codeRunner: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Forty index cards land on your table, face down. Each one has a date
and a number: the count of items handed in to a school lost-and-found
bin on one school day. Forty school days, forty cards, one shoebox that
somebody has to empty when it overflows.

The caretaker's question is not "what is the average". It is:

> "When should I empty it? I would rather not walk over there for
> three sweaters."

## The task

**Round one, on the desk.** Answer her question using nothing but the
cards, your hands, and the table. Sort them, stack them, line them up,
group them by weekday — whatever gets you to an answer you would be
willing to say to her face. Write the answer in one sentence, and write
down what you did to the cards to get it.

**Round two, on the machine.** Now make the computer do it. You have
variables, input and output, decisions, and loops. Forty numbers. Go.

Round two is where the exploration actually starts.

## Round two, honestly

Most people begin like this, because it is the only tool they have:

```python run
value1 = 12
value2 = 7
value3 = 19
largest = value1
if value2 > largest:
    largest = value2
if value3 > largest:
    largest = value3
print(largest)
```

That works. It prints `19`. Now do the other thirty-seven, and then
answer a *second* question about the same forty numbers.

Before you type another line, answer these:

1. How many names have you invented, and can you keep them straight?
2. Your loop from last week counts perfectly to forty. Can it reach
   `value17`? Try it. What stops you?
3. What would you need — not what is it called, what would you *need* —
   for the counting loop and the forty values to meet?

> [!note]- Facilitation notes
> **Cards, not a spreadsheet.** The physical round matters. Hands
> discover sorting, grouping, and running totals about five minutes
> before anybody can name them, and the group that lays the cards out
> in five columns by weekday has invented a table, which pays off in
> Unit 2's nested loops.
>
> **Making the cards.** Forty values, one per school day, weekday
> labelled. Build a real pattern in: a Friday bump, a dead week over an
> exam period, and two outliers with an obvious human explanation
> (a track meet, a lost-and-found purge). The outliers are the best
> conversation of the day.
>
> **Timing in a 70-minute period.** Fifteen minutes on cards; ten for
> groups to present their method — *method*, not answer; twenty on
> round two, including the deliberate frustration; then the naming of
> [[Lists]] and a first `for` over a list, together.
>
> **Let question 2 sting.** Students will try to build a variable name
> out of a number. The failure is honest and instructive: names are
> written by you, indexes are computed by the program. That distinction
> is the whole idea, and it lands better as a wall than as a warning.
>
> **The question behind the question.** Bring the room back to the
> caretaker. "Friday averages 11" is a fact; "empty it Friday after
> lunch" is an answer. Facts are not answers, which is the thesis of
> [[The Data Digest]] a few classes from now.

## What tends to surface

Two things, usually in this order. First, that forty separate names for
forty related values is not merely tedious, it is *unworkable* — you
cannot write a loop over things whose names you invented one at a time.
Second, that the pile has structure the cards were hiding: order, days
of the week, a shape. Somebody always says "can we not just number
them?" That sentence is an index, and it arrives about ninety seconds
before anybody says the word.

The caretaker's question also refuses to be answered by a single
number. An average tells you nothing about *when*. That gap between a
statistic and a decision is what the next task is built on.

## Where this goes next

The container you needed is named in [[Lists]], read and modified in
[[Working with Lists]], and drilled in [[Lists Practice]]. Two classes
later, a pile of numbers becomes advice somebody can act on, which is
[[The Data Digest]]. And the outlier cards — the ones with a human
explanation — come back in [[When Code Hurts]], because every data
pile leaves somebody out.

> [!note] The answer is not on this page
> No list syntax is printed here, and neither is the caretaker's
> answer. Your forty cards are not the forty cards in the next room.
> The container gets invented at your tables, out of frustration, which
> is exactly how it was invented the first time.

%%curriculum-start%%
## Curriculum connection

![[A1.5]]

![[A2.3]]
%%curriculum-end%%
