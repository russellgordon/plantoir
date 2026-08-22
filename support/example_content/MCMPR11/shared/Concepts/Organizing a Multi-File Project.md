---
title: Organizing a Multi-File Project
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
A weather dashboard project starts as one file, `dashboard.py`. By week
three it's 400 lines: functions for reading raw sensor readings, functions
for calculating a fire weather index, functions for formatting a report,
a couple of leftover `print()` statements from debugging two weeks ago,
and one very long scroll to find anything. You and your pair-programming
partner keep editing the same file at the same time, which means every
session starts with sorting out whose changes go where. Nothing about the
*code* is wrong — it's just all in one place, and one place has stopped
being enough.

## Splitting a script into modules

Any `.py` file can be treated as a **module**: a chunk of code another
file can borrow from with `import`. Splitting the dashboard by
responsibility might look like this:

```
dashboard/
├── main.py
├── telemetry_reader.py
├── fire_index.py
└── report.py
```

`telemetry_reader.py` holds only the functions that read and clean raw
sensor data. `fire_index.py` holds only the calculations for the fire
weather index. `report.py` holds only the formatting and printing.
`main.py` ties them together:

```python
# main.py
from telemetry_reader import load_readings
from fire_index import calculate_index
from report import print_summary

readings = load_readings("station_42.csv")
index = calculate_index(readings)
print_summary(readings, index)
```

`main.py` is short enough to read in ten seconds, and it reads almost
like an outline of the whole program — load, calculate, report — with the
real work delegated to the module actually responsible for it.

> [!tip] One module, one job
> The test for whether a module is well organized: can you describe what
> it's for in one sentence, without using the word "and"? `fire_index.py`
> is "the calculations for the fire weather index." If you catch yourself
> writing "it calculates the index *and* also formats the report," that's
> the module telling you it's time to split it again.

## Why this helps a pair, specifically

Splitting by responsibility isn't just tidiness — it changes how two
people can work on the project at once. If Mei is improving
`fire_index.py` and Jordan is working on `report.py`, they can genuinely
work in parallel instead of taking turns inside one shared file, because
neither module's internals depend on the other file staying still while
they edit.

## `if __name__ == "__main__":`

Sometimes you want a module to be runnable on its own — useful for
testing `fire_index.py` in isolation — but you don't want that test code
to run automatically every time `main.py` imports it. The guard
`if __name__ == "__main__":` solves exactly that:

```python
# fire_index.py

def calculate_index(readings: list[dict]) -> float:
    """Estimate a fire weather index from a list of station readings."""
    # ... real calculation here ...
    return 0.0

if __name__ == "__main__":
    # This block only runs when fire_index.py is executed directly,
    # e.g. `python fire_index.py` — never when another file imports it.
    test_readings = [{"temp_c": 28, "humidity": 12}]
    print(calculate_index(test_readings))
```

Python sets the built-in variable `__name__` to `"__main__"` only when a
file is run directly. When the same file is imported by `main.py`,
`__name__` is set to the module's own name instead, so the test block is
silently skipped — you get a file that's useful both as a piece of a
larger program and as a standalone script to poke at on its own.

## When to split

There's no fixed line count that forces a split — the honest signal is
when you start scrolling to find things, or when you and a partner keep
editing near each other in the same file. A single-purpose exercise
belongs in one file. A project with distinct phases — read data,
calculate something, report the result — is usually clearer from the
start as separate modules, one per phase.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]

![[D6.1]]
%%curriculum-end%%
