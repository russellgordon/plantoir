---
title: Binary and Number Systems
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
You met this at the bench before it had a name — the day
[[Binary Bites]] had you counting on one hand to 31 and
[[Digital Logic Gates|a circuit]] insisted the only answers were on and
off. Everything a computer stores, moves, or shows is, underneath,
numbers written with exactly two digits.

## Counting in twos

Decimal gives each place a power of ten; binary gives each place a
power of two. The number $11110111_2$ is

$$
128 + 64 + 32 + 16 + 0 + 4 + 2 + 1 = 247_{10}
$$

— eight bits, one byte, and the reason "255" haunts computing: it is
the biggest number one byte can hold.

| Place | 128 | 64 | 32 | 16 | 8 | 4 | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Bit | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 1 |

Converting back is a greedy game: take the biggest power that fits,
subtract, repeat. Try 200 in your head before the folded check below.

> [!success]- Self-check: 200 in binary (click to expand)
> $200 - 128 = 72$, $72 - 64 = 8$, $8 - 8 = 0$ — so bits for 128, 64,
> and 8: $11001000_2$. Verify forward: $128 + 64 + 8 = 200$. ✓

## Why two?

Not preference — physics. A wire at 5 volts or 0 volts, a switch open
or closed, a magnetic spot flipped one way or the other: two states
are cheap, fast, and hard to misread. Ten states per wire would save
digits and cost reliability; [[Electronics Fundamentals]] shows the
voltages doing the work.

## Hexadecimal, binary's shorthand

Writing bytes in binary is exhausting, so technicians group bits in
fours and write each group as one of sixteen digits (0–9, A–F):
$11110111_2$ becomes $\mathrm{F7}_{16}$. You have seen hex all along —
in colour codes, in the
[[How Data Travels|hardware addresses]] on every network card.
[[Number Systems Practice]] builds the fluency, and
[[The Gadget]] is where reading a value in three bases stops being a
party trick and starts being Tuesday.

## Representing characters, images, and audio

Computers represent all forms of information using binary encoding
schemes:

- **Text:** Characters map to numeric values. In the ASCII standard,
  the capital letter `A` is $65_{10} = 01000001_2$, `B` is
  $66_{10} = 01000010_2$, and a space is $32_{10} = 00100000_2$.
- **Colours and images:** A pixel is commonly stored as three bytes
  for Red, Green, and Blue (RGB). Pure red is $(255, 0, 0)$ or
  $\mathrm{\#FF0000}_{16}$; white is $(255, 255, 255)$ or
  $\mathrm{\#FFFFFF}_{16}$.
- **Audio:** Analogue sound waves are measured thousands of times per
  second (sampled) and converted into binary integers by an
  analogue-to-digital converter.

The computer does not "know" whether a byte represents a character, a
colour, an audio sample, or a CPU instruction. Only the software reading
it decides the meaning.

%%curriculum-start%%
## Curriculum connection

![[A3.1]]

![[A3.2]]
%%curriculum-end%%
