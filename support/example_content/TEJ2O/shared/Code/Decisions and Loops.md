---
title: Decisions and Loops
publish: true
created: __CREATED__
tags:
  - code
---
When a computer powers on, its firmware runs a POST — a power-on
self-test — checking parts and deciding whether to boot or beep.
You watch a real one scroll past in [[Build a Workstation]]; this
page is the same idea in software: programs that *choose* and
*repeat*. Our toy POST simulates the decisions, not the circuits.

## Choosing with if and else

```python
fan_spinning = input("Is the CPU fan spinning? (yes/no) ")

if fan_spinning == "yes":
    print("POST: fan check passed.")
else:
    print("POST: halt! Never run a CPU without cooling.")
```

The `==` asks a question — is this equal to that? — and exactly
one of the two paths runs. One `=` stores; two `==` compares.
Predict what happens if you answer `YES` in capitals, then run it.

## Repeating with a loop

```python
for attempt in range(1, 4):
    print("Memory test pass", attempt, "of 3...")

print("Memory: all passes complete.")
```

`range(1, 4)` counts 1, 2, 3 — it stops at the second number.
Indented lines run each time around; the unindented line waits.

## Both at once

```python
beeps = 0
for check in ["fan", "memory", "keyboard"]:
    result = input("Did the " + check + " check pass? (yes/no) ")
    if result != "yes":
        beeps = beeps + 1
        print("Beep! Problem found with:", check)
if beeps == 0:
    print("POST complete. Booting.")
else:
    print("POST failed with", beeps, "beep(s). Check the codes.")
```

A loop with a decision inside and a counter keeping score — that
shape, small as it is, is most of the programs you will ever
write. Trace it on paper for a run where only the memory check
fails, and predict every printed line.

## Make it yours

1. Add a fourth check to the list; predict the output first.
2. Real machines beep in patterns — two beeps means one fault,
   three another. Print a different message for each beep count.

%%curriculum-start%%
## Curriculum connection

![[B5.1]]

![[B5.2]]

![[B5.3]]
%%curriculum-end%%
