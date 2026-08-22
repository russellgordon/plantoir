---
title: Who Maintains This
publish: true
created: __CREATED__
tags:
  - discussions
---
A program is finished the way a building is finished. The ribbon gets
cut, everyone goes home, and then somebody has to unblock the drains
every year for forty years. Writing software is the ribbon. The rest
of the cost — reading it, fixing it, explaining it, keeping it
working when everything around it changes — is paid by people who
mostly did not write it, and who are mostly not thanked.

You have felt this already. [[The Inherited Program]] took a whole
period to understand and would have taken its author ten minutes.
That difference is not a measure of you. It is the actual price of
code, showing up on somebody else's bill.

## Three things that outlive the author

- **A rule that changes.** A program that calculates something using
  a rate, a threshold, or a deadline is a program with an expiry
  date. When the rule changes, somebody must find the number in the
  code. If it is written in one place with a name, that takes a
  minute; if it is typed in four places as a bare number, it takes an
  afternoon and one of the four gets missed.
- **A dependency that moves.** Everything your program stands on —
  the language version, the file format, the machine — keeps moving
  whether or not you do. Code that has not been touched in three
  years is not stable. It is untested against three years of change.
- **A person who leaves.** Every team has code that only one person
  understands. That is fine right up to the day it is not, and the
  cost is not the code, it is the knowledge that was never written
  down.

> [!important] "It works" is a statement about today
> A program that runs is not a program that is finished. The
> honest version of "it works" is "it worked on my machine, on the
> data I tried, this afternoon". Everything [[Testing and Regression]]
> asks you to do is an attempt to make that sentence longer.

Questions worth arguing about:

1. Who *should* maintain a piece of software: the person who wrote
   it, the organisation that uses it, or whoever it now affects? What
   happens when the writer was a student who graduated, and the
   organisation has no programmers?
2. Is there such a thing as software that is finished? Name one, and
   defend it against the three pressures above.
3. Your team's project will take a few weeks to build. Estimate,
   honestly, how many hours it would take somebody else to make one
   small change to it in a year's time. What would cut that number in
   half, and why have you not done it yet?
4. Free and volunteer-maintained software runs an enormous share of
   the systems everyone depends on, often maintained by very few
   people in their spare time. Who is responsible when one of those
   projects breaks — the volunteers, or the organisations that built
   on it without contributing anything back?
5. Suppose keeping a program alive costs more than it saves. Is
   switching it off a failure, or good engineering? Who has to be
   told, and how much notice do they get?
6. Is a program nobody can read the same as a program nobody has? Ask
   it about your own code from Grade 11.

For a community partner the stakes are concrete. When
[[The Software Project]] hands over, the partner is not getting a
program; they are getting a maintenance obligation with a program
attached. Whether that is a gift or a burden is decided by choices
you make weeks earlier, in [[Writing Code Others Can Read]] and in
[[Software Project Management]]. The related argument, about the
moment you personally walk away, is [[What Happens When You Leave]].

%%curriculum-start%%
## Curriculum connection

![[B1.6]]

![[D2.2]]

![[D4.3]]
%%curriculum-end%%
