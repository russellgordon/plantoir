---
title: Fractions, Decimals, and Percents
publish: true
created: __CREATED__
tags:
  - concepts
---
You met this in a [[Fraction Talks]] warm-up: the same shaded square was
called $\frac{3}{4}$ by one group, $0.75$ by another, and $75\%$ by a
third — and everyone was right. Fractions, decimals, and percents are
not three topics. They are three costumes for one number, and the skill
worth practising is choosing the costume that makes your current
problem easiest to see.

## Three costumes, one number

| Fraction | Decimal | Percent | Why it is a good anchor |
| --- | --- | --- | --- |
| $\frac{1}{2}$ | $0.5$ | $50\%$ | the halfway benchmark |
| $\frac{1}{4}$ | $0.25$ | $25\%$ | half of a half |
| $\frac{1}{8}$ | $0.125$ | $12.5\%$ | half again — ruler marks |
| $\frac{1}{3}$ | $0.\overline{3}$ | $33.\overline{3}\%$ | thirds never end |
| $\frac{1}{10}$ | $0.1$ | $10\%$ | slides the decimal point |

Know these cold and most conversions become comparisons instead of
computations: $\frac{3}{8}$ has to sit halfway between $25\%$ and
$50\%$, because three eighths is one quarter plus one eighth.

## Converting is re-describing, not calculating

A fraction *is* a division — $\frac{3}{4}$ means $3 \div 4$ — and a
percent *is* a fraction whose denominator happens to be $100$. Nothing
about the amount changes when you convert; you are re-describing it,
the way "half past six" and "6:30" name the same moment. The building
block underneath is the **unit fraction**: $\frac{3}{4}$ is three
copies of $\frac{1}{4}$, which is exactly why a ruler marked in
quarters can measure it directly.

Signs come along for the ride. A temperature change of $-\frac{3}{4}$
of a degree per hour is the same drop whether you write it as $-0.75$
or as "falling $75\%$ of a degree each hour" — the negative sign
describes direction, exactly as it does in
[[Integers and the Number Line]]. Negative fractions do real work in
this course: they show up as slopes in [[Slope and Rate of Change]] and
inside formulas, where tracking the sign *is* tracking the story.

## Which numbers these are, and where they stop

The table above is doing something quietly worth naming. Every entry in
it can be written as one whole number over another — that is what makes
it a **rational** number, and it is the property that lets the three
costumes exist at all. The decimal costume tells you which kind you
have: divide the numerator by the denominator and the division either
stops ($\frac{3}{4} = 0.75$) or falls into a repeating block
($\frac{1}{3} = 0.\overline{3}$). One of those two things always
happens, and it happens because the remainders you can get while
dividing by $4$, or by $3$, are a short list — sooner or later one
repeats, and from there the pattern is locked.

That gives a set of numbers nested inside each other, each one built by
asking for something the one before could not do:

```mermaid
graph LR
    N["Natural<br/>1, 2, 3, …"] --> W["Whole<br/>0, 1, 2, …"]
    W --> I["Integers<br/>…, −2, −1, 0, 1, 2, …"]
    I --> Q["Rational<br/>any a/b"]
    Q --> R["Real<br/>rationals + irrationals"]
```

Read the arrows as "and also": the whole numbers are the naturals **and
also** zero. The integers are the whole numbers **and also** the
negatives, which is what [[Integers and the Number Line]] is about, and
each step exists because somebody needed an answer the previous set
could not give — $5 - 8$ has no answer in the whole numbers, and
$3 \div 4$ has none in the integers.

**The last arrow is different in kind**, and it is the interesting one.
Rationals and irrationals are both real numbers and both sit on the same
number line, but no fraction of whole numbers will ever produce $\pi$
or $\sqrt{2}$: their decimals run forever without ever settling into a
repeating block. So $\sqrt{2}$ has an exact position on the line — it
is the diagonal of a unit square, and you can construct it — and no
exact decimal, ever. Every calculator you own is lying to you slightly
about it.

Two consequences you will meet again. A number can be *irrational* and
still be perfectly ordinary — $\pi$ is the ratio every circle in
[[Geometric Relationships]] is built on. And "the same number in
different costumes" only works inside the rationals: $\sqrt{2}$ has no
fraction costume to change into, which is why an answer is often more
honest left as $\sqrt{2}$ than rounded to $1.41$.

[[Fraction and Percent Practice]] builds the fluency, and
[[Would You Rather]] is where choosing the most useful costume becomes
a debate worth having.

%%curriculum-start%%
## Curriculum connection

![[B1.2]]

![[B3.2]]

![[B3.4]]
%%curriculum-end%%
