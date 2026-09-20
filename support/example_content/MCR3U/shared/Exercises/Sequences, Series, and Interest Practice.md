---
title: Sequences, Series, and Interest Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Sequences and Their Rules]], [[Series]], and
[[Money Over Time]] — one road from patterns to dollars. A scientific
calculator earns its keep from question 7 onward; money answers to
the nearest cent.

## Sequences

1. Classify each as arithmetic, geometric, or neither, with the
   evidence: (a) $5, 9, 13, 17, \ldots$ (b) $4, 12, 36, 108, \ldots$
   (c) $1, 4, 9, 16, \ldots$
2. For the arithmetic sequence $7, 10, 13, \ldots$: write the general
   term, then find $t_{20}$.
3. A geometric sequence has $t_1 = 3$ and $r = 2$. Write the general
   term and find $t_{10}$.
4. (a) Write a recursion formula for $2, 6, 18, 54, \ldots$
   (b) Write the first four terms of $t_1 = 5$, $t_n = t_{n-1} - 4$.

> [!success]- Answer 1
> (a) Arithmetic — constant difference $d = 4$. (b) Geometric —
> constant ratio $r = 3$. (c) Neither — the differences
> $3, 5, 7$ grow, and the ratios shrink. (They are the perfect
> squares: a discrete quadratic, not a member of either family.)

> [!success]- Answer 2
> $t_n = 7 + (n - 1)(3) = 3n + 4$. Then
> $t_{20} = 3(20) + 4 = 64$ — the general term teleports; no need to
> climb through nineteen steps.

> [!success]- Answer 3
> $t_n = 3 \cdot 2^{n-1}$. Then $t_{10} = 3 \cdot 2^9 =
> 3(512) = 1536$. Note the exponent is $n - 1$: the first term has
> been multiplied zero times.

> [!success]- Answer 4
> (a) $t_1 = 2$, $t_n = 3t_{n-1}$ — starting value plus growth rule;
> a recursion without its first term is a rule with nowhere to
> stand. (b) $5, 1, -3, -7$ — arithmetic, with $d = -4$.

## Series

5. Find the sum of the first 40 terms of $3 + 7 + 11 + \cdots$
6. Find the sum of the first 10 terms of $2 + 6 + 18 + \cdots$

> [!success]- Answer 5
> Arithmetic, $a = 3$, $d = 4$:
> $S_{40} = \frac{40}{2}\left[2(3) + 39(4)\right] = 20(162) = 3240$.
> Gauss's pairing in formula form — forty additions traded for one
> multiplication.

> [!success]- Answer 6
> Geometric, $a = 2$, $r = 3$:
> $S_{10} = \frac{2\left(3^{10} - 1\right)}{3 - 1} = 3^{10} - 1 =
> 59{,}048$. Notice the last *term* is only
> $2 \cdot 3^9 = 39{,}366$ — in geometric series, the final term
> carries most of the total.

## Money

7. \$1000 is invested for 10 years at 6% per year. Find the amount
   if interest compounds (a) annually and (b) monthly, and state how
   much the extra compounding earned.
8. An investment earns 8% per year, compounded annually. Use
   systematic guess-and-check to find how many years it takes to
   double.
9. You deposit \$100 at the end of every month for 5 years into an
   account earning 6% per year, compounded monthly. Find the future
   value, and how much of it is interest.
10. A \$2000 credit-card balance sits unpaid for two years at 20%
    per year, compounded monthly. What is the debt then, and what
    did the waiting cost?

> [!success]- Answer 7
> (a) $A = 1000(1.06)^{10} \approx \textdollar 1790.85$.
> (b) $i = 0.005$, $n = 120$:
> $A = 1000(1.005)^{120} \approx \textdollar 1819.40$. Monthly compounding
> earned an extra \$28.55 — same rate on paper, more meetings with
> the multiplier.

> [!success]- Answer 8
> Solve $(1.08)^n = 2$ by hunting: $(1.08)^5 \approx 1.47$,
> $(1.08)^9 \approx 1.999$, $(1.08)^{10} \approx 2.16$. Doubling
> takes almost exactly 9 years. Every guess was cheap; the *strategy*
> — bracket the target, then close in — is the reusable part.

> [!success]- Answer 9
> An ordinary annuity: $R = 100$, $i = 0.005$, $n = 60$, so
> $FV = \dfrac{100\left[(1.005)^{60} - 1\right]}{0.005} \approx \textdollar 6977.00$.
> You deposited $60 \times \textdollar 100 = \textdollar 6000$; the other
> \$977.00 is interest — the geometric series doing the saving
> alongside you.

> [!success]- Answer 10
> $i = \frac{0.20}{12}$, $n = 24$:
> $A = 2000\left(1 + \frac{0.20}{12}\right)^{24} \approx \textdollar 2973.86$.
> Waiting cost about \$974 — nearly half the original debt again,
> in two years. The same exponential that grew question 9's savings
> works just as tirelessly for the lender.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[C1.2]]

![[C1.3]]

![[C1.4]]

![[C1.5]]

![[C2.1]]

![[C2.2]]

![[C2.3]]

![[C2.4]]

![[C3.1]]

![[C3.2]]

![[C3.3]]

![[C3.4]]

![[C3.5]]

![[C3.6]]
%%curriculum-end%%
