---
title: The Hundred-Line Problem
publish: true
codeRunner: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
A student council treasurer has a small, real problem. The council
saves a fixed amount each week toward one purchase, and she is asked,
constantly, "how much will we have by week such-and-such?" She would
like a printed schedule she can pin to the wall.

Here is the program she has. It handles two weeks.

```python run
week = 1
balance = 25.00
print(f"Week {week}: ${balance:.2f}")
week = 2
balance = balance + 7.50
print(f"Week {week}: ${balance:.2f}")
```

Run it. It prints exactly what you would expect:

```
Week 1: $25.00
Week 2: $32.50
```

## The task

She needs one hundred weeks.

That is the whole task. You know everything you need — assignment,
addition, `print`, f-strings — and there is nothing clever available to
you yet. Get her the hundred weeks. Copy, paste, edit. Start the clock.

Nobody is being tricked here. You are being *timed*, and the number
that matters is not how fast you finish but where you are at the
fifteen-minute mark.

## The change request

At some point during the work — your teacher chooses the moment, and
it will not be a convenient one — the treasurer sends an update:

> Sorry! The weekly amount changed. It is $9.25 now, not $7.50. And we
> start from $40, not $25.

Do not groan quietly. Groan out loud, and then answer three questions
in writing, because the answers are the lesson:

1. How many lines do you now have to change?
2. How many of them will you miss?
3. If she changes it again next week, what exactly is your plan?

> [!note]- Facilitation notes
> **Do not mention loops.** Not once, not as a hint, not as a wink.
> The word arrives at the end, from the room, as a relief. If a student
> already knows the word, give them the extension below and swear them
> to secrecy — they will enjoy the conspiracy.
>
> **Timing in a 70-minute period.** Five minutes to set the scene and
> run the two-week program; fifteen of grim copy-paste; the change
> request at minute twenty, sprung with theatrical apology; ten minutes
> of repair and the three questions; five for the count below; then
> twenty-five for the consolidation into [[Repetition]] and a first
> loop written together.
>
> **The count.** Before naming anything, poll the room: how many lines
> did you write? How many of you got all hundred correct? How many
> found a mistake only after the change request? The honest numbers on
> the board are more persuasive than any explanation of why loops
> exist.
>
> **What to listen for.** "There has to be a way to just tell it to do
> that a hundred times." That sentence, from a student, is the lesson
> arriving on schedule. Write it on the board with their name beside
> it, and build the first `for` loop from their words.
>
> **Extension for the fast or the forewarned.** Ask for the *last* week
> the balance is under $500, without printing the schedule at all. That
> quietly needs a condition inside the repetition, which sets up the
> accumulator work later in the unit.

## What tends to surface

The pain is not the typing. The pain is the change request, and the
discovery that a hundred copies of an idea means a hundred chances to
be wrong about it. Somebody will notice that only two things differ
between one block and the next — the week number and the balance — and
that everything else is identical. That observation *is* the concept.
The name is the easy part.

You also meet a professional truth early: the requirements changed
halfway through, which is not a cruel trick but a description of the
job. It happens to your community client too, and
[[The Software Development Process]] has a whole vocabulary for it.

## Where this goes next

Everything you did by hand this morning collapses into about three
lines. The name for those three lines is in [[Repetition]], a working
example is in [[Looping Programs]], and the mechanics get drilled in
[[Loops Practice]]. The treasurer, for the record, gets her schedule —
and by the end of Unit 2 she gets something she can act on, which is
what [[The Data Digest]] is about.

> [!note] The answer is not on this page
> The three-line version is not printed here, deliberately. Your class
> writes it together, from the sentence somebody in the room says out
> loud when the copying becomes unbearable. If you skip ahead and paste
> a loop from the internet today, you will have the code and not the
> reason — and the reason is the only part that is hard to get back.

%%curriculum-start%%
## Curriculum connection

![[A2.2]]

![[B1.1]]
%%curriculum-end%%
