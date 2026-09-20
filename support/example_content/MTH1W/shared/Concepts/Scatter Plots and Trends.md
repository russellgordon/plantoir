---
title: Scatter Plots and Trends
publish: true
created: __CREATED__
tags:
  - concepts
---
One variable tells you what happened; two variables let you ask
*whether one thing travels with another*. A scatter plot puts one
variable on each axis and drops a dot for every observation — your
[[Bungee Drop]] data made one, storeys across and stretch up. The
picture answers three questions at a glance: is there a relationship,
which direction does it lean, and how tightly do the points hug it?

## Correlation, and what it does not say

When the dots drift upward together, the correlation is **positive**;
downward, **negative**; a formless cloud means little correlation at
all. Technology will happily fit different regression models to the
same cloud and report how well each fits — your job is to look at the
*shape* first, as in [[Linear Relations]], and judge whether a line is
even the right kind of model before trusting any number about it.

> [!warning] Correlation is not causation
> Ice cream sales and drowning incidents rise together every summer.
> Ice cream does not cause drowning — hot weather drives both. A
> scatter plot can show that two variables move together; it cannot
> tell you *why*. Deciding why takes knowledge from outside the graph,
> and claims that skip that step are exactly what
> [[Who Does Data Serve]] teaches you to interrogate.

## Prediction, and its limits

A line of best fit turns a cloud into a machine for predictions: pick
an $x$, read off a $y$. Predictions *between* your data points stand
on solid ground. Predictions *beyond* the data are on a ledge — your
bungee line says nothing trustworthy about storey fifty, because no
cord was ever tested there. Every prediction should come with its
pedigree: interpolated or extrapolated, tight fit or loose one. Saying
so plainly is part of [[Showing Your Thinking]].

## What a model is for

Fitting a line is not the goal. A **model** is a deliberate
simplification of something real, built so that a decision can be made
before the real thing has finished happening — and that is the only
reason anybody puts up with the simplification. Your bungee line lets
somebody choose a cord length for a drop nobody has tested. That is the
trade the whole exercise is: accept that the line is not the truth, in
exchange for an answer you can act on now.

Decisions get made this way constantly, and usually invisibly. A city
sizes a water main from a model of how a neighbourhood grows. A hospital
staffs a Monday from a model of how many people arrive. A phone
estimates your arrival time from a model of traffic. None of those
models is right. Each is *useful*, and the people who rely on them are
supposed to know the difference — which is what makes the reporting step
below the part that matters, rather than the paperwork at the end.

## Reporting a model honestly

When you hand a model to somebody, four things have to travel with it,
and a model reported without them is worse than no model, because it
will be believed further than it deserves.

| What to report | The bungee example | Why a reader needs it |
| --- | --- | --- |
| What question it answers | how far the cord stretches from a given storey | a model answers one question, not every question |
| How well it fits | points hug the line closely, no fanning out | a loose fit and a tight fit support very different claims |
| Where it stops being trustworthy | tested from storeys 1 to 6 only | outside that range you are extrapolating, and you must say so |
| What it predicts, with its pedigree | "about 280 cm at storey 7, interpolated between tested drops" | the number and its warrant belong in the same sentence |

**Limitations are not an apology.** "This assumes the cord is the same
cord and the mass is the same mass" is not weakness — it is the
condition under which the number is any good, and stating it is what
separates a model from a guess with a graph attached. A group that
reports a fit of "quite good" and a prediction for storey fifty has told
a reader nothing they can check, which means they have told them nothing
at all.

The same four rows are what [[A Data Story]] asks you to write, and what
[[Judging Your Own Work]] asks you to judge yourself against before you
hand it in.

[[Scatter Plot Practice]] builds the mechanics with real datasets,
[[Using Desmos]] fits and compares models in seconds, and
[[A Data Story]] asks you to build an honest claim from a plot of
your own.

%%curriculum-start%%
## Curriculum connection

![[D1.3]]

![[D2.1]]

![[D2.5]]
%%curriculum-end%%
