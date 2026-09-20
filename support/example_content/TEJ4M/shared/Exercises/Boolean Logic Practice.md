---
title: Boolean Logic Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These follow [[Design and Build a Logic Block]] and come back to it from
the other end. On the bench you went specification → truth table →
simplification → circuit, once, carefully. Here the same route is walked
several times on paper, on problems small enough that you can check
yourself and awkward enough that a guess will not survive.

Two habits are worth naming before you start. **Simplify before you
build, not after** — every gate you remove on paper is a chip you do not
buy, a delay you do not pay for, and a connection that cannot come
loose. And **name the law you used at each step**: an answer that gets
there without saying how is indistinguishable from one that got lucky,
and by Grade 12 the working is most of the mark.

## Reading and simplifying

1. Simplify $A \cdot B + A \cdot \overline{B}$ and name the two laws you
   used. Say how many gates each version needs.
2. Simplify $A + A \cdot B$. This one catches almost everybody the first
   time — write out the four-row truth table for both expressions before
   you decide you have made a mistake.
3. Apply De Morgan's laws to $\overline{A \cdot B}$ and to
   $\overline{A + B}$, and say in one sentence what each result means in
   plain words about the circuit.
4. A bench builds $\overline{A} \cdot \overline{B} \cdot \overline{C}$
   with three inverters and a three-input AND gate — four chips'
   worth of function. Find the single gate that does the same job, and
   name the law that proves it.
5. **Find the error.** A group writes: "$A \cdot (B + C) = A \cdot B + C$,
   because you multiply the $A$ through." Build the eight-row truth table
   for both sides, find the rows where they disagree, and write the
   correct distribution.

## Designing from words

6. A bench drill may run only when the guard is closed AND the start
   button is pressed AND the emergency stop is *not* pressed. Write the
   Boolean expression for the motor output, draw the gate circuit, and
   say which input you would wire so that a broken wire stops the drill
   rather than starting it.
7. A car starts only when the key is turned, the transmission is in park
   **or** the clutch is down, and the driver's seatbelt is fastened.
   Write the expression, tabulate it, and simplify anything the table
   shows is redundant.
8. A tank has a low float switch and a high float switch. Design a
   two-output block: a `fill` output and an `alarm` output, where the
   alarm fires on any combination the plumbing cannot physically
   produce. Give the truth table for both outputs and the expression for
   each.
9. Design a 2-to-4 decoder: two inputs, four outputs, exactly one output
   high for each input combination. Give the truth table, the four
   expressions, and the gate count.
10. Design a half adder — two inputs, a sum output and a carry output —
    from its truth table. Then say what it cannot do, and what a full
    adder adds.

## Karnaugh maps, when the table gets big

11. A conveyor's reject arm fires on this four-input truth table.
    Fill a Karnaugh map from it, ring the largest groups you can, and
    write the simplified expression.

    | $A$ | $B$ | $C$ | $D$ | Reject |
    | --- | --- | --- | --- | --- |
    | 0 | 0 | 0 | 0 | 0 |
    | 0 | 0 | 0 | 1 | 0 |
    | 0 | 0 | 1 | 0 | 1 |
    | 0 | 0 | 1 | 1 | 1 |
    | 0 | 1 | 0 | 0 | 0 |
    | 0 | 1 | 0 | 1 | 0 |
    | 0 | 1 | 1 | 0 | 1 |
    | 0 | 1 | 1 | 1 | 1 |
    | 1 | 0 | 0 | 0 | 0 |
    | 1 | 0 | 0 | 1 | 0 |
    | 1 | 0 | 1 | 0 | 1 |
    | 1 | 0 | 1 | 1 | 1 |
    | 1 | 1 | 0 | 0 | 1 |
    | 1 | 1 | 0 | 1 | 1 |
    | 1 | 1 | 1 | 0 | 1 |
    | 1 | 1 | 1 | 1 | 1 |

12. Three of the sixteen combinations in question 11 can never occur,
    because $B$ and $D$ are opposite ends of one switch. Mark those
    cells as *don't care*, re-ring the map, and say how many gates you
    saved by admitting what cannot happen.
13. Take your two-output tank block from question 8, map each output
    separately, and identify one gate whose output both expressions
    could share. Say what sharing costs you if the specification later
    changes.

## Answers

> [!success]- Answer 1
> $A \cdot B + A \cdot \overline{B} = A \cdot (B + \overline{B})$ by the **distributive law**, and $B + \overline{B} = 1$ by **complementation**, so the whole expression is $A \cdot 1 = A$.
>
> **Gate count:** the original needs an inverter, two AND gates and an OR gate — four. The simplification needs none: run $A$ straight through. Whatever $B$ is doing in that circuit, the output has never depended on it.

> [!success]- Answer 2
> $A + A \cdot B = A$, by the **absorption law**.
>
> | $A$ | $B$ | $A \cdot B$ | $A + A \cdot B$ | $A$ |
> | --- | --- | --- | --- | --- |
> | 0 | 0 | 0 | 0 | 0 |
> | 0 | 1 | 0 | 0 | 0 |
> | 1 | 0 | 0 | 1 | 1 |
> | 1 | 1 | 1 | 1 | 1 |
>
> The last two columns agree on every row. The reason it looks wrong is that ordinary arithmetic has no absorption: $a + ab$ does not reduce to $a$ for numbers. Boolean algebra is a different algebra that happens to borrow the symbols, and this is the question where that stops being a slogan.

> [!success]- Answer 3
> $\overline{A \cdot B} = \overline{A} + \overline{B}$ — "not both" is the same as "either one is missing".
>
> $\overline{A + B} = \overline{A} \cdot \overline{B}$ — "neither" is the same as "not this and not that".
>
> In circuit terms: a NAND behaves like an OR fed with inverted inputs, and a NOR behaves like an AND fed with inverted inputs. That is why a bag of NAND gates can build anything, and why the inverter you were about to add can often be absorbed into the gate ahead of it instead.

> [!success]- Answer 4
> $\overline{A} \cdot \overline{B} \cdot \overline{C} = \overline{A + B + C}$ by **De Morgan's law** — a single three-input NOR gate.
>
> Four packages become one. This is the most common simplification on a real board and the easiest to miss, because the original expression reads perfectly naturally: "none of them is true".

> [!success]- Answer 5
> The claim is false. Correct distribution gives $A \cdot (B + C) = A \cdot B + A \cdot C$ — the $A$ goes onto **both** terms.
>
> | $A$ | $B$ | $C$ | $A \cdot (B+C)$ | $A \cdot B + C$ |
> | --- | --- | --- | --- | --- |
> | 0 | 0 | 0 | 0 | 0 |
> | 0 | 0 | 1 | 0 | **1** |
> | 0 | 1 | 0 | 0 | 0 |
> | 0 | 1 | 1 | 0 | **1** |
> | 1 | 0 | 0 | 0 | 0 |
> | 1 | 0 | 1 | 1 | 1 |
> | 1 | 1 | 0 | 1 | 1 |
> | 1 | 1 | 1 | 1 | 1 |
>
> They disagree on two rows, both with $A = 0$ and $C = 1$. In a real circuit that is an output going active while its enable is off — the kind of fault that passes a casual bench test, because nobody thinks to test the disabled case.

> [!success]- Answer 6
> $\text{Motor} = \text{Guard} \cdot \text{Start} \cdot \overline{\text{EStop}}$
>
> A three-input AND gate with the emergency stop signal inverted on its way in — or, using answer 3, feed the guard and start into an AND and combine with the stop line arranged so that its inactive state is high.
>
> **The wiring question is the real one.** Wire the emergency stop as **normally closed**, so that a healthy circuit holds the line at one level and *any* break — pressed button, cut wire, failed connector, pulled plug — releases it. Then $\overline{\text{EStop}}$ becomes true on a fault and the drill stops. Wired the other way round, a broken wire is indistinguishable from "nobody pressed the stop", and the machine keeps running because a wire fell off. Fail-safe is a wiring decision before it is a logic decision.

> [!success]- Answer 7
> $\text{Start} = \text{Key} \cdot (\text{Park} + \text{Clutch}) \cdot \text{Belt}$
>
> Tabulate all sixteen combinations of the four inputs. The output is 1 on exactly three rows: key, belt, and at least one of park or clutch.
>
> **What the table shows is redundant:** the row where park and clutch are *both* true is already covered by the OR — a car in park with the clutch down starts, and no extra term is needed for it. Anybody who writes the expression as a sum of the individual satisfying rows ends up with $\text{Key}\cdot\text{Park}\cdot\text{Belt} + \text{Key}\cdot\text{Clutch}\cdot\text{Belt} + \text{Key}\cdot\text{Park}\cdot\text{Clutch}\cdot\text{Belt}$, and the third term is absorbed by the first two. Three AND gates and an OR collapse to one OR, one AND, and nothing else.

> [!success]- Answer 8
> With `Low` = 1 meaning the liquid has reached the low float and `High` = 1 meaning it has reached the high float:
>
> | Low | High | Fill | Alarm | What it means |
> | --- | --- | --- | --- | --- |
> | 0 | 0 | 1 | 0 | Empty — fill it |
> | 0 | 1 | 0 | **1** | Impossible: high wet, low dry |
> | 1 | 0 | 1 | 0 | Part full — keep filling |
> | 1 | 1 | 0 | 0 | Full — stop |
>
> $\text{Fill} = \overline{\text{High}}$ and $\text{Alarm} = \overline{\text{Low}} \cdot \text{High}$.
>
> The second row is the whole point of the question. Liquid cannot reach the high float without covering the low one, so that combination means a stuck float, a broken wire or a wiring swap — a *sensor* fault rather than a *tank* state. A block that quietly treats it as "not full, keep filling" floods the room. Designing the impossible combinations an output of their own is the cheap version of the fault state you built in [[State Machines]].

> [!success]- Answer 9
> With inputs $A$ (high bit) and $B$:
>
> | $A$ | $B$ | $Y_0$ | $Y_1$ | $Y_2$ | $Y_3$ |
> | --- | --- | --- | --- | --- | --- |
> | 0 | 0 | 1 | 0 | 0 | 0 |
> | 0 | 1 | 0 | 1 | 0 | 0 |
> | 1 | 0 | 0 | 0 | 1 | 0 |
> | 1 | 1 | 0 | 0 | 0 | 1 |
>
> $Y_0 = \overline{A} \cdot \overline{B}$, $Y_1 = \overline{A} \cdot B$, $Y_2 = A \cdot \overline{B}$, $Y_3 = A \cdot B$.
>
> **Gate count:** two inverters and four two-input AND gates — six gates, and each inverter's output is used twice, which is the sharing question 13 asks about. Note there is nothing to simplify here: every output depends on both inputs, and that is what "decoder" means.

> [!success]- Answer 10
> | $A$ | $B$ | Sum | Carry |
> | --- | --- | --- | --- |
> | 0 | 0 | 0 | 0 |
> | 0 | 1 | 1 | 0 |
> | 1 | 0 | 1 | 0 |
> | 1 | 1 | 0 | 1 |
>
> $\text{Sum} = A \oplus B$ (exclusive-OR) and $\text{Carry} = A \cdot B$. Two gates.
>
> **What it cannot do:** accept a carry *in*. So half adders cannot be chained, which makes them useless for anything wider than one bit. A **full adder** takes a third input, $C_{\text{in}}$, giving $\text{Sum} = A \oplus B \oplus C_{\text{in}}$ and $\text{Carry} = A \cdot B + C_{\text{in}} \cdot (A \oplus B)$ — and *those* chain, one per bit, which is how the arithmetic in [[Bus and Protocol Practice]]'s two's complement questions actually happens in silicon.

> [!success]- Answer 11
> The output is 1 wherever $C = 1$, and also wherever $A = 1$ and $B = 1$.
>
> Ringing the map: the eight cells with $C = 1$ form one group, giving the term $C$. The four cells with $A \cdot B$ form another, giving $A \cdot B$ — and it overlaps the first group in two cells, which is allowed and is exactly what makes both groups as large as they can be.
>
> $\text{Reject} = C + A \cdot B$
>
> Two gates, and $D$ appears nowhere: sixteen rows of table reduce to an OR and an AND, and one of the four sensors turns out never to have mattered. Finding that before you buy the sensor is the argument for doing this on paper.

> [!success]- Answer 12
> If $B$ and $D$ are opposite ends of one switch, then $B = \overline{D}$ always, so every row where $B = D$ is impossible. Marking those cells as *don't care* lets you ring them as 1s wherever that grows a group and ignore them where it does not.
>
> Here it changes little, because the expression $C + A \cdot B$ is already minimal — which is itself the lesson. **Don't-care cells are an opportunity, not a guarantee.** Sometimes they collapse a four-gate expression to one; sometimes they save nothing. What they always do is force you to write down which combinations your design assumes cannot happen, and that list belongs in the specification, because the next person to touch the wiring will not know it.
>
> One warning: a *don't care* is only free if the impossible combination really is impossible. If the switch can break in a way that produces $B = D$, then you have designed a circuit whose behaviour in a fault condition is whatever the simplification happened to give you — which is exactly the trap question 8's alarm output was built to avoid.

> [!success]- Answer 13
> Mapping separately: $\text{Fill} = \overline{\text{High}}$ needs one inverter; $\text{Alarm} = \overline{\text{Low}} \cdot \text{High}$ needs one inverter and one AND. The inverter on `High` is *not* shared — Fill needs $\overline{\text{High}}$ and Alarm needs `High` itself — but if you build Fill from $\overline{\text{High}}$ and then need `High` again, one inverter's output can feed both places rather than fitting a second.
>
> **What sharing costs.** Every shared node couples two outputs that the specification treated as independent. Change the alarm condition later and you are editing a gate the fill logic also depends on, so a one-line change to one requirement silently alters the other. You also load one gate output with two inputs, which is fine at this scale and is a fan-out calculation at any real one.
>
> The honest rule: share aggressively inside one function, cautiously between two functions that could be specified separately — and write down every shared node, because the person modifying it in a year will not be able to see the decision, only the wiring.

Bring questions 6, 8 and 11 to the bench. The drill and the tank are
worth building on the breadboard even though you have already solved
them: a circuit whose truth table you already know is the only kind
where a wrong reading tells you something about your *wiring* rather
than about your reasoning. Log the discrepancy and its cause in your
[[Tech Journal]] — that is the same discipline as
[[Testing Without a Debugger]], one layer down.

%%curriculum-start%%
## Curriculum connection

![[A5.2]]

![[A5.3]]
%%curriculum-end%%
