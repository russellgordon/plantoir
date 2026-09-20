---
title: Dictionary Lookup Speed Round
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - dictionaries
---

A dictionary stores key-value pairs, and looking one up is one of the most common operations you will write in any real program. Here is a small dictionary of BC provincial park entrance fees, in dollars per vehicle per day.

```python
park_fees = {
    "goldstream": 3,
    "manning": 5,
    "wells gray": 0,
    "mount robson": 5
}
```

Without running anything, predict what each of the following five lines prints — or whether it crashes the program instead.

```python
print(park_fees["manning"])
print(park_fees.get("wells gray"))
print(park_fees.get("garibaldi"))
print(park_fees.get("garibaldi", "no fee on record"))
print(park_fees["garibaldi"])
```

Go through all five before checking the answers — one of them is a trap.

> [!success]- Answer 1
> `5`
>
> Square-bracket lookup on a key that exists simply returns its value.

> [!success]- Answer 2
> `0`
>
> This is the trap most people miss: `"wells gray"` **is** a valid key, with a value of `0`. It is easy to assume a missing or empty-looking result means the key isn't there, but `0` is a perfectly real value — it just happens to also look like "nothing."

> [!success]- Answer 3
> `None`
>
> `"garibaldi"` is not a key in the dictionary. `.get()` does not crash on a missing key — it returns `None` by default, which prints as `None`.

> [!success]- Answer 4
> `no fee on record`
>
> `.get()` accepts a second argument: the value to return instead of `None` when the key is missing. Since `"garibaldi"` isn't in the dictionary, this returns the fallback text you supplied.

> [!success]- Answer 5
> `KeyError`
>
> Square-bracket lookup (`park_fees["garibaldi"]`) has no fallback. If the key does not exist, Python raises a `KeyError` and the program crashes right there, unless something else catches it.

The pattern worth taking away: `[]` is fine when you are certain the key exists, but `.get()` — with a sensible default — is almost always the safer choice when a key might be missing, because it lets your program keep running instead of crashing.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
