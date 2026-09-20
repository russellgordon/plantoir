---
title: What Happens When You Leave
publish: true
created: __CREATED__
tags:
  - discussions
---
Everyone on your team leaves. Not eventually — at the end of the course. The
community partner you are building for will still have the program, still
need it to work, and will not have any of you. That fact is not the sad part
at the end of the project. It is a design constraint from the first week,
and it is the one most student projects ignore until the last day, when it
is far too late to fix.

Teams use a blunt phrase for this: the **bus factor**. How many
people would have to disappear before the project became
unmaintainable? A bus factor of one means exactly one person
understands something, and it is the most common shape in student
work, because splitting a project by "you do the database, I'll do
the interface" produces four people who each understand a quarter.

## What actually gets handed over

Not the code. The code is the easy part — it is right there. What has
to be transferred is everything that was only ever in somebody's
head:

- **Why it is built this way.** Not what the class does; why it is a
  class. The alternatives you rejected and the reason are worth more
  to your successor than the version you kept.
- **How to run it from nothing.** On a machine that is not yours,
  with no setup, by somebody who has never seen it. Written down and
  then *tested* by someone who did not write it.
- **What it will not do.** The limits, stated in advance. A limit you
  disclose is something people can plan around; a limit discovered in
  use is a broken promise.
- **What is likely to break first.** You know. Say it. The
  half-finished part, the thing hard-coded because there was no time,
  the assumption about the data that held for one term.
- **Who to ask, and until when.** An honest answer, including "nobody,
  after this course", is worth more than a vague offer nobody will take up.

> [!important] A handover is a promise, not a formality
> Somebody agreed to let a group of students build something they
> depend on. Leaving them a program only its authors can operate is
> not a neutral outcome; it is worse than having built nothing,
> because now they have a thing that will break and no way to fix it.
> Software nobody can maintain has not really helped anyone.

Questions worth arguing about:

1. What is your team's bus factor today? Name the specific piece of
   the project only one person understands, and say what it would
   take to change that this week.
2. Documentation costs time you would otherwise spend on features. Be
   honest: when is it genuinely not worth writing? Does your answer
   survive the case where the reader is a volunteer at your
   partner organisation?
3. Is a well-commented program with no written handover better or
   worse than a plain program with excellent instructions? Which
   would you rather inherit — and which would your partner rather
   have?
4. Suppose you knew nobody would ever read your documentation. Would
   you still write it? What does your honest answer say about who you
   have been writing it for?
5. You inherited code in [[The Maintenance Sprint]] and had opinions
   about its author. Write the sentence you wish they had left you.
   Now go and leave that sentence for the next person.
6. Is there ever a responsible way to walk away from a project that
   people depend on? What would you have to do first?

This is the argument that [[The Handover]] turns into an assessed
piece of work, and it is why the finale is a handover rather than a
demonstration. The practical craft sits in
[[Writing Code Others Can Read]] and [[Software Project Management]];
the record of what you decided and why — the thing nobody else can
reconstruct — is your [[Code Journal]]. The related question, about
who carries the cost after you go, is [[Who Maintains This]].

%%curriculum-start%%
## Curriculum connection

![[A2.3]]

![[B1.5]]

![[B1.6]]

![[D4.3]]
%%curriculum-end%%
