---
title: The Handshake Problem
publish: true
created: __CREATED__
tags:
  - explorations
enableToc: true
---
Five strangers meet at a party, and every person shakes hands with
every other person exactly once. How many handshakes is that? Easy
enough to act out — which is exactly why the real question waits one
sentence longer: what about 10 people? What about $n$?

## The task

Settle the party of 5 beyond argument — act it out if you like. Then
scale: 10 people, then our whole class, then $n$ people, where the
answer must be an expression, not a number. Along the way, keep a
table of people against handshakes and study how the total *grows*
from one party size to the next. Your group's board should end with
two things: a formula you can defend, and a reason it can never
double-count or miss a handshake.

> [!question]- Getting started (click to expand)
> - Add guests one at a time. When the sixth person walks in, how
>   many *new* handshakes happen — and why only that many?
> - Count each person's handshakes and add them all up. What went
>   wrong with that total, and how badly?
> - Difference your table once, then difference it again. Where have
>   you seen that behaviour before?

## What mathematics tends to surface

The totals 1, 3, 6, 10, 15 grow by an ever-larger step — first
differences 2, 3, 4, 5, but *second* differences stuck on 1. A
constant second difference is the fingerprint of a quadratic, the
signature [[Quadratic Relations]] is built around, and the same
one your table left behind in [[Visual Patterns]]. The two counting
arguments — everyone-shakes-$n-1$-hands versus one-at-a-time — give
expressions that look different and agree, and the "divide by 2" that
repairs the double count is a reason, not a rule.

## An extension

How many diagonals does a 20-sided polygon have, and why is that
*almost* the same problem? Then the reverse question, which is where
quadratics start earning money: a season of round-robin games needs
exactly 45 matches — how many teams entered? Write up your argument
for the [[Math Journal]]; the counting-two-ways move is one worth
keeping, and [[Showing Your Thinking]] shows how to lay it out.

> [!note] The answer is not on this page
> No formula is printed here. The party of $n$ belongs to your group
> and the boards.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]

![[Mathematical Process Expectations]]
%%curriculum-end%%
