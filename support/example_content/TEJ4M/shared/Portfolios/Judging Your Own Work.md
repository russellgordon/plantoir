---
title: Judging Your Own Work
publish: true
created: __CREATED__
tags:
  - portfolio
---
Every task in this course publishes a criteria table before you start.
Most people read it once on launch day and never open it again — and
then hand in a build that misses two rows they could have closed in a
period. This page is that period, and it is a bench habit rather than a
writing one: an inspection against a written standard, done by the
person who did the work, before anybody else looks.

That is not a school invention. A technician signs off their own work
against a checklist before the inspector arrives, and the reason is not
the paperwork — it is that at that point there is still time to fix
what the checklist finds.

We run it together the first time, on a specification from an earlier
year, so the move is familiar before it is your own board on the bench.

## The routine

1. Put the task's criteria table beside the actual evidence — the
   captures, the logs, the schematic, the handover page. Not beside
   your memory of them.
2. Take the rows in order. Mark each one **holds**, **partly**, or
   **not yet**, and write the one piece of evidence that decides it:
   the trace, the log line, the page of the handover. A row marked
   "holds" with nothing named beside it is an opinion.
3. Name your weakest row. Not the quickest to close — the weakest. If
   two are level, take the one a client would notice.
4. Write the fix as a job: what changes, at which bench, in which
   period, and how you will know it worked.
5. Do it, in the time this course leaves after the check — sometimes
   the rest of the same period, sometimes the first job of the next
   one. The self-check is never the last thing on an agenda, because an
   inspection you cannot act on is only a worry with a clipboard.

Steps 2 and 3 are the whole exercise. Everything else is bench work you
already know how to do.

> [!example]- One row, inspected honestly
> From [[The Control System]]: *"A safety limit that runs first —
> tested by causing the fault, with the log to show it."*
>
> **Partly.** The limit is written and it runs before the control
> logic on every pass, and I have the code to show that. I tested it
> by unplugging the sensor, which the log has. I never tested the
> output-on-too-long branch, because I did not want to sit there for
> four minutes. Weakest row: it is the branch that protects the
> heater.
> **Fix:** shorten the timeout to twenty seconds for one deliberate
> test, log it, then set it back — next period, first thing, before
> the ten trials.
>
> Six honest words per row beat "looks fine" on all ten, and this one
> took under two minutes to write.

## What it is worth, and what it is not

Your judgement of your own work is not part of your mark, and neither
is a classmate's — [[How Marks Work]] says so plainly and this page
does not quietly contradict it. Nothing you write here can cost you
anything, which is exactly what makes an honest answer cheap.

What it changes is the work. A row you closed on Thursday is a row I
read as closed on Monday, and that is the cheapest improvement
available in this course.

Two habits worth stealing from the trade. Read your judgement out loud
to the bench next to you: you will hear the rows where you were being
generous before they say a word. And keep the sheet — a self-check
that later turned out to be right, or wrong, is a decision with a
measurement attached, which is precisely what your [[Tech Journal]] is
collecting all semester.
