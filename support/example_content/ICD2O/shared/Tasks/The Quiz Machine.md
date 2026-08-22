---
title: The Quiz Machine
publish: true
created: __CREATED__
tags:
  - tasks
enableToc: true
---
> [!abstract] At a glance
> Solo, with a play-tester and one paired workday · six working periods
> mid-course · play-tested in class twice, in threes and then across the
> room · one Python program plus a test log

## What you are making

A quiz program in Python on a topic you genuinely care about — a sport,
a band, a game, a language, your neighbourhood. It asks questions,
reads answers, checks them, keeps score, and gives feedback, and it
must use [[Conditionals]] and at least one [[Loops|loop]].

Checking answers is where the craft lives — exact matching rejects
`"ottawa"` because you typed `"Ottawa"`, so your checker forgives it:

```python
guess = input("What is the capital of Canada? ")
if guess.strip().lower() == "ottawa":
    score = score + 1
```

Then a classmate play-tests it, and every piece of their feedback is
either addressed in the code or logged in an honest known-issues list.

## How to work

1. Choose the topic — the test is that you would happily talk about it
   at lunch. Write your questions and accepted answers on paper first.
2. Build **one** question end to end — ask, read, check, score — and
   get it working before you write ten. [[The Password Checker]] is
   full of checking patterns worth borrowing.
3. Add forgiving matching, so spacing and capitals never cost a point.
   Decide, and comment, what your checker forgives and what it does not.
4. Notice the repetition — question two looks like question one. That
   pattern is your loop. Comment as you go, in the spirit of
   [[Writing Good Comments]]: a stranger should follow your checker.
5. Add the final score and feedback that actually says something —
   "7 out of 10, your goalie knowledge is elite" beats a bare number.
6. Play-test in class: your classmate plays while you stay silent and
   take notes. Address each finding or log it honestly. The building
   happens in the working periods, at a keyboard I can stand beside,
   which is the only way I ever get to watch anybody debug —
   [[How Marks Work]] explains why that counts as evidence.

## Success criteria

| Quality | What it looks like in your program |
| --- | --- |
| A topic that is yours | The questions could only have been written by you |
| Runs end to end | A player gets from first question to final score |
| Forgiving checking | Spacing and capitals never cost a correct player, and the rule that decides it reads in one line — `and`, `or` and `not` where you need them |
| Structures where they are needed | Each conditional is there because something has to be decided, and the loop is there because something would otherwise be typed out again |
| Built for diverse players | Prompts and feedback are clear, forgiving of capitalization and spacing, and tested with diverse classmates |
| Readable throughout | Comments let a stranger follow the checking logic |
| Feedback honoured | Every play-test finding is fixed or honestly logged |

## Reflect

Write a [[Dev Journal]] entry after the play-test: what did your
tester find that you could not have found yourself, and why not? Your
tester did you the favour of not knowing what you know.

> [!success]- If your program only half-works (click to expand)
> Ship the half that works, with a known-issues list naming the half
> that does not. A readable program with honest known bugs outscores a
> flashy one nobody can follow — that is the rule in [[How Marks Work]].

%%curriculum-start%%
## Curriculum connection

![[A1.3]]

![[C1.5]]

![[C2.3]]

![[C2.4]]

![[C2.5]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 13, the working period where everybody breaks
somebody else's quiz on purpose
  Watch for: where a student's eyes go when hostile input crashes
  their program. The file will show you the fix they chose; only this
  period shows how they arrived at it. Both routes produce a working
  quiz, and they are not the same understanding.
  Going well: the comparison line itself gets opened and read — the
  strip, the lower, the double equals — and one thing changes before
  the program is run again.
  Stuck: another conditional is stacked on top of the last one until
  the symptom stops, with the original comparison never reread. Four
  branches deep and still growing is the tell.
  Record: two columns on a sticky note per machine — read it, or
  buried it. Photograph the note at the bell.

TALK — Unit 2, Day 10, at the conference the agenda already schedules
  Ask: "Show me an answer that is right and your checker still marks
  wrong — then tell me what your comparison is actually deciding."
  Then: "Your player gets one wrong. For them to have a second go,
  where would the program have to decide something new, and where would
  something have to repeat?"
The second question is C1.5 — identifying and explaining where a
  conditional or a repeating structure is REQUIRED — which is the one
  code on this page a conversation can reach; the other three all begin
  "write programs", and the file answers those on its own. A strong
  answer puts the decision at the check, the repetition around the
  asking, and says why the score has to survive the repeat instead of
  being made inside it. "Add another if" for both halves is the answer
  to come back to.
  The first question only corroborates C2.5, which the file shows you
  anyway — but it shows it fast, and a student who cannot produce a
  single false rejection has not tested their own rule. Expect a
  trailing full stop, a synonym, or a number typed as a word; all three
  are right answers that `strip().lower() == "ottawa"` throws out.
  Record: a mark against the class list, plus the one name you want to
  come back to on Day 11.

The product evidence is the program and its test log, at the Day 15
play-test.
%%
