---
title: Dictionaries
publish: true
created: __CREATED__
tags:
  - concepts
enableToc: true
---
[[The Wrong Container]] gave every group the same job: given a pile of
volunteer sign-in lines, answer "how many hours has Rowan done?"
Everybody solved it with a list and a loop, and everybody's solution
had the same shape — walk the whole list, compare names, add up. It
worked. Then the file grew, and the question got asked once per
volunteer, and the loop inside the loop started to show.

The problem was not the loop. It was that a list is organised by
*position*, and nobody at the community centre has ever asked "who is
volunteer number 14?" They ask by name. A dictionary is the container
that is organised by name.

## Lookup by key, not by position

```python
hours = {"Nadia": 4.5, "Rowan": 1.5, "Bea": 2.0}

print(hours["Nadia"])
print("Ali" in hours)
print(hours.get("Ali", 0))
```

```text wrap
4.5
False
0
```

Each entry is a **key** and a **value**. The keys here are names; the
values are hours. No loop, no index arithmetic, no searching — and,
importantly, the lookup does not get slower as the dictionary grows.
That claim has conditions, and [[Choosing a Data Structure]] states
them honestly.

| Operation | Written as | Notes |
| --- | --- | --- |
| Look up | `hours["Nadia"]` | Raises `KeyError` if absent |
| Look up safely | `hours.get("Ali", 0)` | Returns the default instead |
| Add or replace | `hours["Ali"] = 6.0` | Same syntax for both |
| Test a key | `"Ali" in hours` | Checks **keys**, never values |
| Remove | `del hours["Bea"]` | `KeyError` if it was not there |
| Count | `len(hours)` | Number of entries |
| Loop | `for name in hours:` | Gives the keys |
| Loop over both | `for name, served in hours.items():` | Key and value |

Keys must be *hashable*, which in practice means strings, numbers, and
tuples — things that do not change underneath the dictionary. A list
cannot be a key, and Python refuses the attempt rather than storing
something it cannot find again. Values can be anything at all,
including lists, objects, and other dictionaries.

## The tally pattern

Half of the dictionaries you write this year will be counters, and
they all look like this:

```python
signatures = ["soup", "pasta", "soup", "rice", "soup"]

counts = {}
for item in signatures:
    if item in counts:
        counts[item] = counts[item] + 1
    else:
        counts[item] = 1

print(counts)
```

```text wrap
{'soup': 3, 'pasta': 1, 'rice': 1}
```

Start empty. If the key is already there, add to it; if not, create it
with the first value. The same four lines, with `+ quantity` instead
of `+ 1`, are the heart of [[Using a Dictionary]]. Write them enough
times and you will recognise the shape in somebody else's program at a
glance — which is most of what reading code well amounts to.

## A missing key is a decision, not an accident

```python
hours = {"Nadia": 4.5, "Rowan": 1.5}
print(hours["Ali"])
```

> [!example]- What Python says when the key is not there
> ```text wrap
> Traceback (most recent call last):
>   File "hours.py", line 2, in <module>
>     print(hours["Ali"])
>           ~~~~~^^^^^^^
> KeyError: 'Ali'
> ```
> The exception names the exact key it could not find, which is
> unusually helpful as errors go. It is telling you that your program
> assumed Ali was in the dictionary. Either the assumption is right
> and the data is wrong — in which case crashing here is the correct
> behaviour, and you should find out why Ali is missing — or the
> assumption is wrong, and the fix is `.get("Ali", 0)`.

Choosing between them is a **precondition** question: does the caller
guarantee the key exists? Write your answer in the docstring, because
whoever calls your function next cannot read your mind, and
[[C2.1|the precondition expectation]] is asking for exactly that
sentence.

## Order, and what a dictionary will not do for you

Since Python 3.7, dictionaries keep their keys in insertion order. So
the tally above comes out in the order the items were first seen —
which is arrival order, and rarely the order a human wants to read.
Sort at the point of output, with `sorted(counts)` for keys in
alphabetical order, and leave the data alone.

What a dictionary will *not* do: keep things in sorted order for you,
allow duplicate keys (assigning to an existing key replaces its
value — silently, which has cost people entire afternoons), or answer
questions about values quickly. "Which volunteer has the most hours?"
still needs a loop over everything, because the dictionary is indexed
by name, not by hours.

Practise in [[Dictionaries Practice]], see it doing real work in
[[Using a Dictionary]], and read [[Choosing a Data Structure]] before
you decide that everything should be a dictionary.

%%curriculum-start%%
## Curriculum connection

![[C1.1]]

![[A1.3]]

![[C2.1]]
%%curriculum-end%%
