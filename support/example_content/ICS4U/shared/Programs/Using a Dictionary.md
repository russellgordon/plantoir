---
title: Using a Dictionary
publish: true
created: __CREATED__
tags:
  - programs
---
The food bank the school collects for wants one number per item at the
end of the drive: how much pasta, how much soup, how much rice. The
volunteers do not hand in one number per item. They hand in a sheet
with one line per box, in the order the boxes arrived, with the same
item written down four times.

A list cannot answer "how much soup" without searching for soup every
single time. A dictionary can, because it is built to be asked by
name.

## The program

The volunteers' sheet, saved beside the program as `donations.csv`:

```text
item,quantity
pasta,4
soup,6
rice,2
soup,3
beans,5
pasta,1
soup,2
oats,7
rice,4
```

```python
# Donation tally for the food bank the school collects for. Volunteers
# write one line per box on a shared sheet; this program adds up the
# lines by item and writes the summary the coordinator reads out at the
# end of the drive. Donor names are never collected, so they are not
# in the file and cannot leak from it.

import csv

RESTOCK_BELOW = 6


def tally_donations(filename):
    """Return a dictionary of item name -> total quantity donated."""
    totals = {}
    with open(filename, newline="") as file:
        reader = csv.DictReader(file)
        for row in reader:
            item = row["item"]
            quantity = int(row["quantity"])
            if item in totals:
                totals[item] = totals[item] + quantity
            else:
                totals[item] = quantity
    return totals


def most_donated(totals):
    """Return the name of the item with the highest total."""
    best_item = None
    best_count = 0
    for item in totals:
        if totals[item] > best_count:
            best_item = item
            best_count = totals[item]
    return best_item


def needs_restocking(totals, threshold):
    """Return a list of item names whose total is below the threshold."""
    short = []
    for item in sorted(totals):
        if totals[item] < threshold:
            short.append(item)
    return short


def write_summary(totals, filename):
    """Write one line per item, in alphabetical order, to a text file."""
    with open(filename, "w") as file:
        for item in sorted(totals):
            file.write(f"{item}: {totals[item]}\n")


totals = tally_donations("donations.csv")

print("Donation drive summary")
for item in sorted(totals):
    print(f"  {item:<8} {totals[item]}")

print(f"Different items: {len(totals)}")
print(f"Most donated:    {most_donated(totals)}")
print(f"Soup boxes:      {totals['soup']}")
print(f"Flour boxes:     {totals.get('flour', 0)}")
print(f"Ask for more:    {needs_restocking(totals, RESTOCK_BELOW)}")

write_summary(totals, "summary.txt")

print()
print("summary.txt now contains:")
with open("summary.txt") as file:
    for line in file:
        print(f"  {line.rstrip()}")
```

```text
Donation drive summary
  beans    5
  oats     7
  pasta    5
  rice     6
  soup     11
Different items: 5
Most donated:    soup
Soup boxes:      11
Flour boxes:     0
Ask for more:    ['beans', 'pasta']

summary.txt now contains:
  beans: 5
  oats: 7
  pasta: 5
  rice: 6
  soup: 11
```

## How it works

`totals` starts as `{}` — an empty dictionary — and grows a key the
first time each item is seen. The four lines at the heart of the
program are the tally pattern, and you will write them again all semester:

```python
if item in totals:
    totals[item] = totals[item] + quantity
else:
    totals[item] = quantity
```

`in` on a dictionary asks about **keys**, not values, and it does not
search the whole dictionary to answer. Nine lines here, or nine
thousand, the lookup costs about the same — which is the reason to
reach for this container rather than a list of pairs. The honest
version of that claim, and its conditions, is in
[[Choosing a Data Structure]].

Everything arrives from the file as text. `row["quantity"]` is the
string `"4"`, and `"4" + "6"` would be `"46"`, so `int(...)` converts
it before any arithmetic happens. That conversion is where sloppy data
turns into a crash: a stray `four` in the quantity column produces
`ValueError: invalid literal for int() with base 10: 'four'`, at the
line that tried, not three functions later.

Two ways to ask a dictionary a question, and they behave differently
on purpose:

| Written as | When the key exists | When it does not |
| --- | --- | --- |
| `totals['soup']` | the value | raises `KeyError: 'flour'` |
| `totals.get('flour', 0)` | the value | the default you supplied |

Use the square brackets when a missing key means the program's
assumptions are broken and you want to know immediately. Use `.get`
with a default when a missing key is ordinary — no flour was donated,
and zero is the truthful answer.[^order]

The summary is written with `sorted(totals)`, which sorts the keys
alphabetically. Dictionaries hand back their keys in the order they
were first inserted, which here is arrival order — fine for a
computer, unhelpful for a coordinator reading a list aloud. Sorting at
the point of output leaves the data alone and fixes the report.

[^order]: `.get` is also how you avoid the most common dictionary bug
    of all: testing `if totals["flour"] > 0`, which crashes before the
    comparison ever happens. `totals.get("flour", 0) > 0` asks the
    same question and survives the answer.

## Change it

1. **One line.** Change `RESTOCK_BELOW` to `7`. The shortage list
   becomes `['beans', 'pasta', 'rice']` — rice has six boxes and now
   qualifies. Because the threshold is a named constant at the top,
   the food bank's policy change is a one-line edit, not a search
   through the program.
2. **A few lines.** Add a total across every item. Loop over the keys,
   add up `totals[item]`, and print it: the drive brought in `34`
   boxes. Then print the average per item to one decimal place — `6.8`
   — and notice that the average is far less useful to the food bank
   than the shortage list, which is worth remembering when somebody
   asks you for "some statistics".
3. **A real change.** Add a `week` column to the sheet and tally by
   week *and* item, using a dictionary whose values are themselves
   dictionaries. With weeks 1, 2, and 3 on the sheet above, the result
   prints as:
   ```text
   Week 1: {'pasta': 4, 'soup': 6}
   Week 2: {'rice': 2, 'soup': 3, 'beans': 5}
   Week 3: {'pasta': 1, 'soup': 2, 'oats': 7, 'rice': 4}
   ```
   The tally pattern appears twice, once for each level: create the
   inner dictionary when the week is new, then tally into it. Nesting
   is where dictionaries stop being a convenience and start being a
   data model.

Read [[Dictionaries]] for the idea and
[[Choosing a Data Structure]] for when *not* to use one, then practise
in [[Dictionaries Practice]]. The classroom version of this problem is
[[The Wrong Container]].

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A3.1]]

![[C1.1]]
%%curriculum-end%%
