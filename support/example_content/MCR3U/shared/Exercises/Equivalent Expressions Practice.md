---
title: Equivalent Expressions Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
Simplifying is only half of each question. The other half is stating
what the variable cannot be — and those restrictions come from the
expression you were **given**, not the one you end up with. Work each on
paper before opening an answer.

## 1. Expand and simplify

$$(2x - 3)(x + 5) - (x - 4)^2$$

> [!success]- Answer 1
> $$(2x^2 + 7x - 15) - (x^2 - 8x + 16) = x^2 + 15x - 31$$
> The bracket around the second expansion matters: every term of
> $x^2 - 8x + 16$ changes sign. Dropping that bracket is the most
> common error in this question and it is invisible afterwards.

## 2. Simplify, and state the restrictions

$$\frac{x^2 - 9}{x^2 + 7x + 12}$$

> [!success]- Answer 2
> Factor both: $\dfrac{(x-3)(x+3)}{(x+3)(x+4)} = \dfrac{x-3}{x+4}$
>
> Restrictions: $x \neq -3$ and $x \neq -4$.
>
> The $-3$ is the one people lose. It came from the original
> denominator, and cancelling it does not make it legal — the original
> expression is undefined there, so the simplified one must carry the
> same hole.

## 3. Add these

$$\frac{3}{x - 2} + \frac{5}{x + 1}$$

> [!success]- Answer 3
> Common denominator $(x-2)(x+1)$:
> $$\frac{3(x+1) + 5(x-2)}{(x-2)(x+1)} = \frac{8x - 7}{(x-2)(x+1)}$$
> Restrictions: $x \neq 2$, $x \neq -1$. Leave the denominator
> factored — it is more useful factored, and it shows the restrictions
> at a glance.

## 4. Multiply and simplify

$$\frac{x^2 - 4}{x^2 - x - 6} \times \frac{x + 3}{x + 2}$$

> [!success]- Answer 4
> $$\frac{(x-2)(x+2)}{(x-3)(x+2)} \times \frac{x+3}{x+2} = \frac{(x-2)(x+3)}{(x-3)(x+2)}$$
> Restrictions: $x \neq 3$, $x \neq -2$. Factor everything before
> cancelling anything — cancelling across an unfactored sum is the
> error this question exists to catch.

## 5. Divide

$$\frac{2x^2 + 6x}{x^2 - 1} \div \frac{4x}{x - 1}$$

> [!success]- Answer 5
> Multiply by the reciprocal:
> $$\frac{2x(x+3)}{(x-1)(x+1)} \times \frac{x-1}{4x} = \frac{x+3}{2(x+1)}$$
> Restrictions: $x \neq 1$, $x \neq -1$, and $x \neq 0$ — that last one
> because $4x$ was a divisor. A restriction from the expression you
> divided BY is the one students forget every time.

## 6. Prove they are equivalent, or show they are not

$$\frac{x^2 - 1}{x - 1} \qquad\text{and}\qquad x + 1$$

> [!success]- Answer 6
> The first simplifies to $x+1$, so they agree for every value except
> $x = 1$, where the first is undefined and the second equals 2. They
> are **not** the same function: their graphs differ by one point, and
> the first has a hole at $(1, 2)$.
>
> This is exactly why restrictions are marked. "Equivalent" means the
> same value everywhere, and a single missing point breaks it.

## 7. Simplify

$$\frac{\dfrac{1}{x} + \dfrac{1}{y}}{\dfrac{1}{xy}}$$

> [!success]- Answer 7
> Multiply the top and bottom by $xy$:
> $$\frac{y + x}{1} = x + y$$
> Restrictions: $x \neq 0$, $y \neq 0$. Multiplying through by the
> common denominator turns a complex fraction into an ordinary one in a
> single step, which beats simplifying top and bottom separately.

%%curriculum-start%%
## Curriculum connection

![[A3.2]]

![[A3.3]]

![[A3.1]]

![[A3.4]]
%%curriculum-end%%
