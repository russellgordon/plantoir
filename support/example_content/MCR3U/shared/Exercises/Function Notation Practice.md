---
title: Function Notation Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[What Is a Function]] and
[[Function Notation]] — first the judgement call, then the language.
Exact answers throughout; no calculator needed.

## Function or not

1. Decide whether each relation is a function, and say how you know:
   (a) $\{(1, 3), (2, 5), (3, 7)\}$;
   (b) $\{(4, 2), (4, -2), (9, 3)\}$.
2. Is $x = y^2$ a function? Support your answer with actual numbers,
   not just a rule quoted from memory.

> [!success]- Answer 1
> (a) A function — every input appears once, so no input has two
> outputs. (b) Not a function — the input 4 appears with outputs 2
> and $-2$. One splitting input is all it takes; the well-behaved
> $(9, 3)$ cannot rescue it.

> [!success]- Answer 2
> Not a function. Feed in $x = 4$: both $y = 2$ and $y = -2$ satisfy
> $4 = y^2$, so one input produces two outputs. Graphically, the
> sideways parabola fails the vertical-line test at every positive
> $x$.

## Evaluate

3. For $g(x) = 3x - 5$, find $g(4)$, $g(0)$, and
   $g\!\left(\frac{2}{3}\right)$.
4. For $f(x) = 2x^2 + 3x - 1$, find $f\!\left(\frac{1}{2}\right)$.
5. Same $f$: find $f(-2)$, then explain why getting the same value as
   question 4 breaks no rules.

> [!success]- Answer 3
> $g(4) = 12 - 5 = 7$; $g(0) = -5$;
> $g\!\left(\frac{2}{3}\right) = 2 - 5 = -3$. Each input goes into
> the rule wrapped in brackets, and everything else follows.

> [!success]- Answer 4
> $f\!\left(\frac{1}{2}\right) =
> 2\left(\frac{1}{4}\right) + \frac{3}{2} - 1 =
> \frac{1}{2} + \frac{3}{2} - 1 = 1$. The most common slip is
> squaring $\frac{1}{2}$ to $\frac{1}{2}$ — brackets first, then
> arithmetic.

> [!success]- Answer 5
> $f(-2) = 2(4) - 6 - 1 = 1$. Two inputs sharing an output is
> many-to-one, which functions allow; only one input with two
> *outputs* is forbidden. (Both points, $\left(\frac{1}{2}, 1\right)$
> and $(-2, 1)$, sit at the same height on the parabola — one on each
> side of the vertex.)

## Interpret and work backwards

6. The height of a ball is modelled by $h(t) = -5t^2 + 20t + 1$, with
   $h$ in metres and $t$ in seconds. Compute $h(2)$, then write what
   the statement $h(2) = \underline{\ \ }$ means as a plain sentence.
7. For $g(x) = 3x - 5$, solve $g(x) = 16$.
8. For $f(x) = x^2 - 4$, find *all* inputs with $f(x) = 21$.

> [!success]- Answer 6
> $h(2) = -20 + 40 + 1 = 21$. Sentence: two seconds after the throw,
> the ball is 21 metres above the ground. The notation packs the
> input, the output, and their meanings into one statement.

> [!success]- Answer 7
> $3x - 5 = 16$ gives $3x = 21$, so $x = 7$. Note the reversal:
> question 3 turned inputs into outputs; this one starts from the
> output — an equation to solve, not a substitution to perform.

> [!success]- Answer 8
> $x^2 - 4 = 21$ gives $x^2 = 25$, so $x = 5$ or $x = -5$. The
> question said *all* inputs for a reason — a quadratic can reach
> the same output from two sides, and reporting only one is the
> most common miss here.

%%curriculum-start%%
## Curriculum connection

![[A1.1]]

![[A1.2]]
%%curriculum-end%%
