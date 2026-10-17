---
title: The Bad Input Hunt
publish: true
codeRunner: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Your program works. You have run it perhaps thirty times, and every one
of those thirty times you typed exactly what it was expecting, because
you wrote it and you know what it wants.

Your client does not know what it wants. Your client will type "seven".

```python run
hours = int(input("How many hours did you work? "))
print(f"You earned ${hours * 17.20:.2f}")
```

```
How many hours did you work? seven
Traceback (most recent call last):
  File "/home/student/pay.py", line 1, in <module>
    hours = int(input("How many hours did you work? "))
ValueError: invalid literal for int() with base 10: 'seven'
```

To you that is a familiar red block with a clear cause. To the person
you built this for, it is a wall of frightening text that appeared
because they answered a question in English. They will not try again.

## The task

Swap machines. Spend the period trying to break each other's programs —
and then, crucially, writing down *how*.

You are hunting for inputs, not for insults. Some places to start:

- Nothing at all. Just press enter.
- Words where numbers go, and numbers where words go.
- Negative numbers. Zero. A number so large it is silly.
- Decimals where whole things live — 2.5 people, 1.5 sandwiches.
- Spaces before and after. Capital letters where lower case was meant.
- The right answer to the wrong question — a date typed as 03/04, when
  nobody said which came first, the day or the month.
- Answering "y" when it asked for "yes".
- Doing the steps in an order the author did not imagine.

For every break, fill out a bug card:

| Field | Example |
| --- | --- |
| What I typed | `seven` |
| What I expected | A polite "please type a number" |
| What happened | Crashed with a `ValueError` |
| How bad | Client would give up and never return |

Hand the cards to the author. Do not fix anything on somebody else's
machine, and do not explain the fix. The cards are the deliverable.

## The kindness rule

Attack the program, never the programmer. "I typed a space and it fell
over" is a gift. "You forgot to check the input, obviously" is not, and
it teaches the author to hide broken things — which is the one habit
that would actually sink their project.

Say what you typed and what happened. Let the author decide what it
means. And when the cards come back to you, remember that every card in
your hand is a crash your client will now never see.

> [!note]- Facilitation notes
> **Rotate twice.** Two rotations of fifteen minutes beat one of
> thirty. Fresh hunters find different breaks, and the second rotation
> shows authors that the first round's fixes created new gaps.
>
> **Timing in a 70-minute period.** Five to set up and read the
> kindness rule; fifteen hunting; five for cards to be handed back and
> read in silence; fifteen hunting on a different machine; ten for the
> triage below; the rest to write the test plan students will run with
> their real client.
>
> **Rank by interest, not volume.** Ask each pair to nominate the most
> *interesting* break in the room — the one nobody would have thought
> of. Celebrating the surprising break rather than the biggest pile
> keeps the hunt generous. A wall of nominated cards is a good artifact
> to leave up for the rest of the unit.
>
> **The distinction to draw at triage.** Sort the wall into three
> piles: crashes, wrong answers delivered confidently, and confusing
> messages. The middle pile is the frightening one — a program that
> crashes tells you it failed, and a program that quietly returns a
> wrong total does not. Grade 11 students find this genuinely sobering.
>
> **Steer the fixes.** Some breaks deserve a check before the value is
> used; some deserve `try` and `except`; some deserve a clearer prompt
> so the bad input never gets typed; and some deserve to be written
> down as a known limit and left alone. Deciding which is which is the
> engineering judgement being taught — do not let the room conclude
> that every input needs a fortress around it.
>
> **Consent note.** Nobody's program should be broken in front of an
> audience without the author's say-so. Cards, quietly, are enough.

## What tends to surface

That your program was never tested — it was *demonstrated*, thirty
times, by the one person on earth who cannot type the wrong thing into
it. That the crash is not the worst outcome: the worst outcome is the
confident wrong answer, and the second worst is a message so cold the
person blames themselves.

The room also discovers that a test is a prediction. "I expected a
polite refusal and I got a traceback" is only a bug because you said
what you expected first. Write the expectation down before you run it,
and you have invented a test plan without being told what one is.

## Where this goes next

The discipline behind today's cards is [[Testing and Debugging]], and
the tool for the bugs you cannot see by reading is
[[Using the Debugger]]. Tomorrow's discussion, [[Mistakes Are Data]],
argues that these cards are the most valuable thing you collected all
week. And the test plan you write at the end of today is the one you
run *with* your client for [[The Community App]] — where the person
typing "seven" is not a classmate being funny, but the person you built
it for, on their own, after you have gone home.

> [!note] The answer is not on this page
> There is no list here of the inputs that will break your program,
> because your program is not anybody else's. And there is no single
> correct response to a bad input: sometimes you check, sometimes you
> catch, sometimes you ask better, and sometimes you write it down and
> live with it. Your class argues that out at triage, card by card.

%%curriculum-start%%
## Curriculum connection

![[A4.5]]

![[B3.3]]

![[B4.4]]
%%curriculum-end%%
