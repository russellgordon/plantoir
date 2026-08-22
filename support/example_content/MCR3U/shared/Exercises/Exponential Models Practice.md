---
title: Exponential Models Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[The Exponential Function]] — recognising the
family, reading its properties, and putting it to work on growth and
decay. Round final answers sensibly and keep the model exact until
the last step.

## Recognising the family

1. A function's outputs at $x = 0, 1, 2, 3$ are $3, 6, 12, 24$.
   Explain how you know the function is exponential rather than
   linear or quadratic, and write its equation.
2. For $f(x) = 5^x$: state the $y$-intercept, domain, range, equation
   of the asymptote, and whether the function increases or decreases.
3. How is $g(x) = \left(\frac{1}{2}\right)^x$ related to
   $f(x) = 2^x$? Give both an exponent-law answer and a
   transformation answer.

> [!success]- Answer 1
> First differences are $3, 6, 12$ — not constant, so not linear;
> nor do those differences change steadily, so not quadratic. But
> each output is *double* the last: a constant ratio, the exponential
> signature. Equation: $f(x) = 3 \cdot 2^x$ — initial value 3, ratio
> 2.

> [!success]- Answer 2
> $y$-intercept 1 (since $5^0 = 1$); domain all real numbers; range
> $y > 0$; asymptote $y = 0$; increasing everywhere, since the base
> exceeds 1.

> [!success]- Answer 3
> By the laws, $\left(\frac{1}{2}\right)^x = 2^{-x}$. As a
> transformation, that is $f(x) = 2^x$ reflected in the $y$-axis.
> One function, two descriptions — and its graph *decreases*, as any
> base between 0 and 1 must.

## Growth and decay

4. A town's population is modelled by $P(t) = 2000(1.03)^t$, with $t$
   in years. What do the 2000 and the 1.03 each mean, and what is the
   population after 10 years?
5. A patient receives 80 mg of a medication with a half-life of
   6 hours, so $M(t) = 80\left(\frac{1}{2}\right)^{t/6}$. How much
   remains after 15 hours?
6. A cooling drink follows $T(x) = 60\left(\frac{1}{2}\right)^{x/30}
   + 20$, with $T$ in °C and $x$ in minutes. State the initial
   temperature, the meaning of the $+20$, and the temperature after
   one hour.
7. A ball dropped from 2 m rebounds to 60% of its previous height
   each bounce. Find the height of the fourth bounce.

> [!success]- Answer 4
> 2000 is the starting population; 1.03 is the annual multiplier —
> each year keeps 100% and adds 3%. After 10 years:
> $P(10) = 2000(1.03)^{10} \approx 2688$ people.

> [!success]- Answer 5
> Fifteen hours is $\frac{15}{6} = 2.5$ half-lives, so
> $M(15) = 80\left(\frac{1}{2}\right)^{2.5} \approx 14.1$ mg.
> Sanity check: two half-lives leave 20 mg, three leave 10, and 14.1
> sits between them. ✓

> [!success]- Answer 6
> At $x = 0$: $T = 60 + 20 = 80$°C. The $+20$ is the room's
> temperature — the asymptote the drink cools *toward* but never
> quite reaches. After one hour, $x = 60$ is two half-lives of the
> gap: $T(60) = 60\left(\frac{1}{4}\right) + 20 = 35$°C.

> [!success]- Answer 7
> Each bounce multiplies by 0.6:
> $h = 2(0.6)^4 = 2(0.1296) \approx 0.26$ m. The model's domain is
> honest here too — bounce number is a whole number, so this is
> really a geometric sequence wearing a decay costume.

## Build your own

8. An exponential function has $y$-intercept 5 and horizontal
   asymptote $y = 3$. Give one possible equation, and explain why
   more than one function fits.

> [!success]- Answer 8
> The asymptote forces the form $y = a \cdot b^x + 3$; the intercept
> forces $a + 3 = 5$, so $a = 2$. Any allowed base works:
> $y = 2(2)^x + 3$ and $y = 2(5)^x + 3$ both satisfy the clues, and
> $y = 2(2)^{-x} + 3$ sneaks in as a decreasing option. Two
> properties pin down two letters, and the base was never mentioned —
> so it stays free. Compare candidates in [[Using Desmos]].

%%curriculum-start%%
## Curriculum connection

![[B2.1]]

![[B2.2]]

![[B2.3]]

![[B2.5]]

![[B3.1]]

![[B3.2]]

![[B3.3]]
%%curriculum-end%%
