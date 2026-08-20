---
title: Trace the Loop
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - loops
---

Tracing a loop by hand — writing down what each variable holds after every pass — is one of the most useful debugging skills you can build. Before you run any code below, grab a scrap of paper and trace it yourself.

### Snippet A: A running total

```python
ferry_fares = [9.00, 18.00, 18.00, 9.00, 0]
total = 0

for fare in ferry_fares:
    total = total + fare

print(total)
```

What does this print?

> [!success]- Answer 1
> `54.0`
>
> `total` starts at `0` and picks up each fare in turn: `0 + 9.00 = 9.00`, then `9.00 + 18.00 = 27.00`, then `27.00 + 18.00 = 45.00`, then `45.00 + 9.00 = 54.00`, then `54.00 + 0 = 54.00`.

### Snippet B: A loop counter

```python
count = 0

for number in range(1, 20, 3):
    count += 1

print(count)
```

Trace through `range(1, 20, 3)` by hand first — what values does it actually produce? Then predict what `count` ends up holding.

> [!success]- Answer 2
> `7`
>
> `range(1, 20, 3)` produces `1, 4, 7, 10, 13, 16, 19` — starting at 1, adding 3 each time, and stopping *before* 20 (22 would be the next value, which is past the stop). That is 7 values, so `count` is incremented 7 times.

### Snippet C: A while loop with a tricky stop condition

```python
readings = [4.2, 5.1, 5.9, 6.4, 7.0, 7.8]
index = 0
above_six = 0

while index < len(readings) and readings[index] < 7.0:
    if readings[index] > 6.0:
        above_six += 1
    index += 1

print(index, above_six)
```

This one is easy to get wrong — trace `index` and `above_six` together, pass by pass, and predict both final values.

> [!success]- Answer 3
> `4 1`
>
> The loop keeps running only while `readings[index] < 7.0` — the moment it hits `7.0` at index 4, the condition becomes `False` and the loop stops *without* processing that element. Trace it:
> - `index = 0`: `readings[0] = 4.2 < 7.0`, loop runs. `4.2 > 6.0`? No. `index → 1`.
> - `index = 1`: `5.1 < 7.0`, loop runs. `5.1 > 6.0`? No. `index → 2`.
> - `index = 2`: `5.9 < 7.0`, loop runs. `5.9 > 6.0`? No. `index → 3`.
> - `index = 3`: `6.4 < 7.0`, loop runs. `6.4 > 6.0`? Yes, `above_six → 1`. `index → 4`.
> - `index = 4`: `readings[4] = 7.0 < 7.0` is `False` — the loop stops here. `index` stays at `4`.
>
> The final `readings[4]` (7.0) and everything after it never get checked at all.

Tracing loops by hand — before you ever press run — is a habit that pays off every time you meet a bug you cannot immediately explain: it forces you to slow down and follow the computer's exact steps instead of guessing what the code "probably" does.

%%curriculum-start%%
## Curriculum connection

![[K1.6]]
%%curriculum-end%%
