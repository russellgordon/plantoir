---
title: Writing About Code
publish: true
created: __CREATED__
tags:
  - reference
enableToc: true
---
Half of this course happens at a keyboard. The other half happens
when you put technical thinking into words somebody else can follow.
This year that list got longer: your [[Code Journal]], the comments
in your programs, **commit messages**, **review comments**, and the
handover documents a community partner will read months from now
without any of you standing beside them. One rule does most of the
work:

> [!important] Write for the next person, who might be you
> Every comment, entry, message, and explanation is addressed to
> somebody who cannot see inside your head — including the version of
> you who returns in three weeks remembering nothing, and the
> volunteer who inherits this in a year and has never met you. If it
> only makes sense with you there to narrate it, it is not finished.

## Precision is kindness

The same moments, described vaguely and then usefully:

| Instead of… | Try… |
| --- | --- |
| "It doesn't work" | "It returns -1 for a name that is on the list, but only when the list is unsorted" |
| "I fixed it" | "The upper bound was `len(values)`, one past the last position — the search only crashed on a target above everything in the list" |
| "We used a dictionary" | "Keyed the roster by member ID; rejected a sorted list with binary search because we insert far more often than we search" |
| "It's faster" | "About three thousand times faster on 200 000 names, over 100 runs; the ratio moved between runs so treat it as an order of magnitude" |
| "The AI helped" | "Asked an AI for a `unittest` skeleton, wrote the cases myself, noted it in a comment" |
| "It's done" | "Meets all criteria; known limit: assumes the sign-in sheet is sorted, which the export does not guarantee" |

Every phrase in the right-hand column can be checked by somebody
else. That is the whole standard, and it is the same one
[[Writing Code Others Can Read]] applies inside the program.

## Four genres, four different readers

| What you are writing | Who reads it | What it must do |
| --- | --- | --- |
| Commit message | A teammate, and you in March | Say what changed and why, in one line |
| Review comment | The person who wrote the code | Describe the code, ask before asserting, state a decision |
| Journal entry | Only me | Record what you decided, what you rejected, and what broke |
| Handover notes | Someone who is not a programmer | How to run it, what it will not do, who to ask |

Mixing them up is the common mistake. A commit message is not a
journal entry; nobody wants your feelings in the history. A review
comment is not a private opinion; it is a decision somebody is
waiting on. And handover notes are not documentation for
programmers — they are instructions for a person who has never seen
a terminal, and they are the only one of the four that will be read
by somebody with no obligation to be patient with you.

## Sentence stems that unlock a stuck page

- I expected the program to… but it actually… which tells me…
- I chose… over… and… because… If… ever changes, … becomes better.
- The measurement says… which I would report as… because a single run
  varies by…
- What made you choose… here? I would have reached for… and I might
  be missing something.
- This will not handle… so before relying on it you would need…

That second stem is the one worth memorising. A decision with its
rejected alternatives and its expiry condition is the single most
valuable sentence you can leave behind, and the one nobody can
reconstruct later — see [[What a Strong Entry Looks Like]].

## Writing for the person who will use it

Handover notes are their own genre. Three things belong in them: what
the program does in one sentence, how to run it step by step on a
machine that is not yours, and what it will not handle. That last one
is not an admission of failure — a limit stated in advance is a limit
somebody can plan around, while a limit discovered in use is a broken
promise.

Then test the writing the only way that works: hand it to somebody
who has never run the program and watch, silently, without helping.
Every hesitation is a line you owe them. [[The Handover]] assesses
exactly this, and [[What Happens When You Leave]] is the argument for
why it is the most important writing in the course.

## Claims about technology need evidence too

When you write about efficiency, accessibility, security, or whether
a thing should exist at all, the standard does not soften. Specific
beats sweeping, sources get named, numbers come with the conditions
under which they were measured, and "I read somewhere" is a bug.
Strong writing about technology sounds like a strong bug report: a
claim, the evidence, and an honest note about what you do not yet
know — which is exactly how the arguments in [[Should It Exist]] and
[[When Code Hurts]] are meant to be conducted.

%%curriculum-start%%
## Curriculum connection

![[A4.3]]

![[A4.4]]
%%curriculum-end%%
