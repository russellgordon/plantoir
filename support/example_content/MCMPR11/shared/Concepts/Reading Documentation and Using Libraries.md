---
title: Reading Documentation and Using Libraries
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
You need the middle value in a list of daily snowpack readings from a
station in the Coast Mountains — not the average, the actual **median**.
You could write it yourself: sort the list, find the middle index, handle
the annoying case where the list has an even length and there are two
middle values to average. Or you could write one line:

```python
import statistics

readings = [142, 138, 155, 149, 161, 147]
print(statistics.median(readings))
```

Someone already solved the even-length case correctly, tested it, and
shipped it as part of Python itself. Using it isn't cutting corners — it's
recognizing that "find the median" is a solved problem, and your time is
better spent on the parts of your program that are actually new.

## Python's standard library

Every install of Python ships with a large collection of ready-made
modules called the **standard library** — no extra install required, just
`import`. A few you'll reach for often:

| Module | What it's for | One thing you'd call |
| --- | --- | --- |
| `statistics` | Summarizing numeric data | `statistics.mean(readings)` |
| `json` | Reading and writing JSON data — the format most web APIs use | `json.loads(raw_text)` |
| `datetime` | Working with dates and times | `datetime.date.today()` |

A quick example with `json`, reading a small weather station record that
arrived as text:

```python
import json

raw_text = '{"station": "Whistler Peak", "temp_c": -8.4, "snowing": true}'
reading = json.loads(raw_text)

print(reading["station"], reading["temp_c"])
```

`json.loads()` turns a JSON string into ordinary Python data — here, a
dictionary — so you can work with it using everything you already know
about dictionaries.

## Reading a real signature

Knowing a module *exists* only helps if you can figure out how to call
its functions, and for that you read the official documentation at
[docs.python.org](https://docs.python.org). Every built-in function's
entry starts with a **signature** — its name and parameters — and reading
one carefully tells you exactly what it expects.

Take `sorted()`. Its documentation gives the signature as:

```
sorted(iterable, *, key=None, reverse=False)
```

Break that apart piece by piece:

- `iterable` has no `=` after it, so it's **required** — you must supply
  something to sort.
- The `*` marks a boundary: everything after it must be passed by name
  (`key=...`), not by position.
- `key=None` and `reverse=False` both have a default value already
  filled in, which means they're **optional** — you only mention them
  when you want something other than the default.

`key` is worth a closer look, because it's easy to skip past. It expects
a *function*, and `sorted()` calls that function on each item to decide
what to sort by, instead of comparing the items directly. Say you have a
list of trail dictionaries and want them ordered by distance:

```python
trails = [
    {"name": "Juan de Fuca Marine Trail", "distance_km": 47},
    {"name": "Stawamus Chief", "distance_km": 11},
    {"name": "Berg Lake Trail", "distance_km": 23},
]

shortest_first = sorted(trails, key=lambda trail: trail["distance_km"])
```

Reading the signature is what told you `key` existed and what shape of
answer it wanted — a small function that, given one item, returns the
value to sort by.

## Before you adopt a library

Not every tool that turns up in a search is worth using. Before pulling
in something beyond the standard library, check: is it actively
maintained, does it have real documentation (not just a bare list of
function names), and does it actually solve the problem you have, rather
than a bigger one you'd have to configure your way around? The standard
library has already passed that bar — that's part of why it's the first
place to look.

%%curriculum-start%%
## Curriculum connection

![[D4.1]]

![[K1.12]]

![[K1.13]]

![[T1.1]]
%%curriculum-end%%
