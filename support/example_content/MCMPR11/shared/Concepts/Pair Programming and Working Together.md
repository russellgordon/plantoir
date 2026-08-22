---
title: Pair Programming and Working Together
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
Mei and Jordan sit down at one laptop to build a program that checks
whether today's UV index means their outdoor class needs sunscreen. Mei
starts typing. Jordan watches the screen, not the keyboard, and after
about thirty seconds says, "Wait — that condition only catches `uv_index
> 8`. What happens at exactly `8`?" Mei hadn't thought about it. They fix
it together in ten seconds, long before it would have become a bug report.

Neither of them wrote that program alone. This way of working — two
people, one keyboard, sharing a single task — is called **pair
programming**, and it's a real, professional practice, not a
consolation prize for not having your own computer.

## Two roles, one task

Pair programming splits into two roles that trade places often:

- The **driver** has the keyboard. They type the code, and only the
  code that's being discussed right now — not the next three ideas
  they're excited about.
- The **navigator** does not touch the keyboard. They read what's
  appearing on screen, watch for bugs and typos, think one step ahead
  ("we're going to need a variable for that next"), and ask questions.

The pair sets a timer — five to fifteen minutes is typical in class — and
when it goes off, they **switch roles**. The person who was navigating
now drives, and vice versa. Switching often keeps both people actively
thinking about the whole problem, instead of one person "driving" the
entire period while the other's attention drifts.

## Why a navigator catches more than a driver

Typing code takes a surprising amount of attention: getting the syntax
right, remembering variable names, watching for the colon at the end of
an `if` line. That attention is exactly what makes it easy to miss a
boundary condition, a typo in a variable name, or a comparison that
should have been `>=` instead of `>`. The navigator isn't doing any of
that typing, so they have spare attention for the bigger picture — which
is precisely why Jordan caught the boundary bug that Mei, mid-keystroke,
did not.

This is not about one person being smarter. It's about splitting a task
so that someone is always positioned to notice the class of mistake the
other person is currently blind to.

## Doing it well

> [!tip] Habits of a strong pair, read before you start
> - The navigator asks questions rather than reaching for the keyboard —
>   "What happens if the list is empty?" does more good than grabbing the
>   mouse and fixing it yourself.
> - Say disagreements out loud, right away, rather than staying quiet and
>   hoping it works out — "I'd have called that variable something else,
>   why `data`?" is a normal thing to say mid-session.
> - Switch roles on the timer even if the driver is "in the middle of
>   something." A short handoff mid-thought is a skill worth building.
> - Build on your partner's idea before replacing it. "Yes, and we could
>   also check..." keeps momentum; a flat "no, do it this way instead"
>   usually doesn't.
> - Narrate what you're typing if you're driving, and narrate what you're
>   thinking if you're navigating. Silence from either seat means the
>   pair has quietly become solo work.

## Coordinating a longer task

For anything bigger than a five-minute exercise, agree on a plan before
either of you opens the editor: what are the two or three pieces the
program needs, roughly how long will each take, and who drives first.
That short planning conversation is what turns pair programming from "two
people improvising together" into two people **coordinating production**
of one piece of work — deciding, out loud, what needs to happen and in
what order, before diving in.

When you finish a pair session, take thirty seconds before packing up to
talk honestly about how the pairing itself went, separate from whether
the code worked: Did you switch often enough? Did the navigator stay
engaged, or drift off? Did one person end up doing almost all the typing?
Naming that out loud is how a pair gets better at pairing, not just at
the program in front of them.

%%curriculum-start%%
## Curriculum connection

![[K1.7]]

![[D3.2]]

![[D6.2]]

![[D7.5]]
%%curriculum-end%%
