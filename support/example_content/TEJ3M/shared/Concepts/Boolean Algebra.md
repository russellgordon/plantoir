---
title: Boolean Algebra
publish: true
created: __CREATED__
tags:
  - concepts
---
Your first attempt at the puzzle in [[Gates on the Bench]] probably used
five or six gates. Somebody else's used two, and did exactly the same
thing. Neither of you was wrong — but one of those circuits costs less,
draws less current, has fewer joints to fail, and fits on a smaller
board. Boolean algebra is how you get from the first circuit to the
second on paper, before you cut anything.

## The rules, and where they come from

Boolean algebra works on variables that can only be 0 or 1, with three
operations: AND written as multiplication, OR written as addition, and
NOT written as a bar over the top. The borrowed arithmetic symbols are
not a coincidence — AND really does behave like multiplication here —
but the resemblance stops at $1 + 1 = 1$, because nothing in this system
ever exceeds 1.

> [!abstract] The identities worth knowing by heart
> $A \cdot 1 = A$ and $A \cdot 0 = 0$
>
> $A + 0 = A$ and $A + 1 = 1$
>
> $A \cdot A = A$ and $A + A = A$
>
> $A \cdot \overline{A} = 0$ and $A + \overline{A} = 1$
>
> $\overline{\overline{A}} = A$
>
> Distribution: $A(B + C) = AB + AC$
>
> Absorption: $A + AB = A$ and $A(A + B) = A$
>
> De Morgan: $\overline{A \cdot B} = \overline{A} + \overline{B}$ and $\overline{A + B} = \overline{A} \cdot \overline{B}$

Every one of those can be proved by writing out the truth table for both
sides and checking that the columns match. That is not a formality — it
is the *definition* of two expressions being equal here, and it is a
proof method you can always fall back on when an identity looks wrong.

De Morgan's pair is the one that pays rent. In words: breaking a bar over
a group flips the operation underneath it. "Not (A and B)" is the same
claim as "not A, or not B" — the alarm is quiet unless both conditions
hold, which is the same as saying it sounds if either one fails.

## Simplifying, with the proof attached

Here is a four-term expression of the kind a truth table hands you:

$$F = \overline{A}\,\overline{B}C + \overline{A}BC + A\overline{B}C + ABC$$

Group the first two and the last two, then factor:

$$F = \overline{A}C(\overline{B} + B) + AC(\overline{B} + B) = \overline{A}C + AC = C(\overline{A} + A) = C$$

Four AND gates and an OR gate collapse into a piece of wire. That claim
is large enough to deserve checking, so check it:

| A | B | C | $\overline{A}\,\overline{B}C$ | $\overline{A}BC$ | $A\overline{B}C$ | $ABC$ | $F$ | C |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1 | 1 |
| 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 0 | 1 | 0 | 0 | 1 | 1 |
| 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 1 | 0 | 1 | 0 | 0 | 1 | 0 | 1 | 1 |
| 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 1 | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 1 |

The $F$ column and the C column are identical in all eight rows, so the
simplification holds. Make this your habit: **simplify algebraically,
then verify with a truth table.** Algebra is fast and occasionally
careless; the table cannot be argued with.

## From a requirement to a circuit

The real workflow runs in one direction, and every project in Unit 2 uses
it.

1. **Write the requirement in plain language.** "The motor runs when the
   system is enabled and there is no fault — or when it is enabled and
   someone holds the override."
2. **Assign a variable to each condition.** $E$ for enabled, $F$ for
   fault, $V$ for override.
3. **Write the expression the words dictate.**
   $M = E\overline{F} + EV$.
4. **Simplify.** Factor out the common $E$: $M = E(\overline{F} + V)$.
   Three gates become two, and the plain-language reading improves as
   well — the system must be enabled, *and* either be fault-free or
   overridden.
5. **Verify with a truth table**, then draw the schematic and build it.

That fourth step is worth pausing on. A simplified expression is usually
also a clearer *statement of the requirement*, which means the algebra is
not only saving gates — it is telling you what your specification really
said. When the simplified form surprises you, the specification was
ambiguous, and better to discover that on paper than in
[[Build the Logic Machine]].

Simulation software will do the truth table and the gate count for you,
and it is worth using for anything with more than three inputs. Use it to
check your work, not to replace it: the point of the algebra is that you
can look at a circuit somebody else built and say what it does.

Practise the manipulations in [[Boolean Simplification Practice]], and
keep [[Logic Gates]] open beside it for the truth tables.

%%curriculum-start%%
## Curriculum connection

![[A5.3]]

![[B3.3]]

![[B3.4]]
%%curriculum-end%%
