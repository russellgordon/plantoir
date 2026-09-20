---
title: Binary and Hexadecimal
publish: true
created: __CREATED__
tags:
  - concepts
---
[[Binary Bites]] takes four minutes and you have been doing it since
Grade 10. What changes this year is what the bits are *for*: a memory
address, a colour on a screen, a byte on a network, the raw output of an
analog-to-digital converter. The counting is old ground. Reading it as
data is the new part.

## Place value is the whole idea

Decimal gives each column a value ten times the one to its right. Binary
does the same with two, and hexadecimal with sixteen. Nothing else is
going on.

The byte `10110101` unpacks column by column: 128, 64, 32, 16, 8, 4, 2,
1 from left to right, and you add the ones where a 1 sits.

$$128 + 32 + 16 + 4 + 1 = 181$$

Going the other way, subtract the largest power of two that fits and
repeat. For 201: 128 fits, leaving 73; 64 fits, leaving 9; 8 fits,
leaving 1; 1 fits, leaving 0. Bits set at 128, 64, 8, and 1 gives
`11001001`.

Hexadecimal uses sixteen symbols — 0 to 9, then A for 10 through F for
15 — and its one genuinely useful property is that **one hex digit is
exactly four bits**. That means converting between binary and hex needs
no arithmetic at all, just grouping:

$$\underbrace{1011}_{\text{B}}\ \underbrace{0101}_{5} = \text{0xB5} = 181$$

Split a byte into two nibbles of four bits, translate each, done. This is
the only reason hexadecimal exists in this trade: it is a compact,
error-resistant way to write binary that humans can read aloud without
losing their place.

| Decimal | Binary | Hex |
| --- | --- | --- |
| 47 | 0010 1111 | 2F |
| 181 | 1011 0101 | B5 |
| 201 | 1100 1001 | C9 |
| 255 | 1111 1111 | FF |

## Where you actually meet these

**Colour.** A web or display colour like `#1E90FF` is three bytes: red
`1E` = 30, green `90` = 144, blue `FF` = 255. Each channel gets 8 bits,
so 256 levels each, and $256^3$ combinations in total. Written in
decimal that colour would be "30, 144, 255" — which is fine, but the hex
form makes the byte boundaries visible at a glance.

**Addresses.** Memory addresses are printed in hex because the boundaries
that matter to hardware — every 256 bytes, every 4 kB — fall on round hex
numbers and ragged decimal ones. The same argument makes MAC addresses
hexadecimal: 48 bits written as twelve hex digits instead of a
forty-eight-character run of ones and zeros.

**Characters.** Text is numbers too. Capital A is 65, or `0x41`, and the
letters run consecutively from there — which is why comparing letters and
sorting names works at all.

**Ranges.** Bit width sets the range, always. With $n$ bits you get $2^n$
distinct values, so 12 bits gives 4096 of them, numbered 0 to 4095. When
[[Digital and Analog Signals]] tells you a converter is "10-bit", it has
just told you the readings run 0 to 1023 and nothing finer.

## Letting the computer do the tedious part

You should be able to convert a byte by hand — it is faster than reaching
for anything, and you will need it while staring at a logic probe. But
once you are writing code, conversion is a library call:

```python
value = 181

print(bin(value))            # 0b10110101
print(hex(value))            # 0xb5
print(format(value, "08b"))  # 10110101, padded to eight bits

print(int("B5", 16))         # 181
print(int("10110101", 2))    # 181
```

The `format` call is the one worth remembering, because padding matters:
a byte is eight bits whether or not the leading ones are zero, and
dropping them is how off-by-one bugs get into address arithmetic.

> [!tip] Negative numbers, briefly
> Fixed-width hardware represents negatives in **two's complement**:
> write the magnitude, flip every bit, add one. For −37 in eight bits,
> 37 is `00100101`, flipping gives `11011010`, and adding one gives
> `11011011` — which is 219, or `0xDB`. The shortcut is that the
> pattern for $-x$ is just $256 - x$ in an eight-bit field. You will see
> this the first time a sensor reading goes below zero and prints as a
> suspiciously large number instead.

Drill conversions until they are boring in [[Number Systems Practice]],
then use them where they bite: [[Logic Gates]] treats those bits as
decisions, and [[Networks and Protocols]] treats them as addresses.

%%curriculum-start%%
## Curriculum connection

![[A5.1]]

![[A5.2]]
%%curriculum-end%%
