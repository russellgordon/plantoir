---
title: Unicode and Accented Text
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - unicode
  - strings
---

Here is a snippet that looks like it should obviously print `True`. Read it carefully — does it?

```python
word_one = "café"
word_two = "café"

print(word_one)
print(word_two)
print(word_one == word_two)
```

Both `print(word_one)` and `print(word_two)` display `café` on your screen. Predict what the final `print` statement outputs.

> [!success]- Answer 1
> `False`
>
> They look identical, but they are stored differently in memory. `word_one` uses a single **composed** character, `é` (one Unicode code point, U+00E9), for the accented letter. `word_two` spells the same visible letter as **two** code points: a plain `e` followed by `́`, a "combining acute accent" that Unicode renders stacked on top of whatever comes before it.
>
> Python compares strings code point by code point, not by how they look on screen — so two strings that render identically can still be unequal.

This is a real, common bug: text typed on different keyboards, pasted from different apps, or saved by different operating systems can end up in either form, and a program that just uses `==` to compare user input will quietly fail for some users and not others.

The fix is to **normalize** both strings into the same form before comparing them, using Python's built-in `unicodedata` library:

```python
import unicodedata

word_one = "café"
word_two = "café"

normalized_one = unicodedata.normalize("NFC", word_one)
normalized_two = unicodedata.normalize("NFC", word_two)

print(normalized_one == normalized_two)
```

> [!success]- Answer 2
> `True`
>
> `"NFC"` stands for one of the standard normalization forms — it rewrites a string so that accented letters are always stored in the single, composed form wherever possible. Once both strings go through `unicodedata.normalize("NFC", ...)`, they end up as the exact same sequence of code points, and `==` correctly reports them as equal.

You will not need `unicodedata` every day, but it is worth knowing it exists, and worth knowing where to find its documentation — this is exactly the kind of pre-built library Python ships with so that you never have to write your own Unicode-handling code from scratch.

%%curriculum-start%%
## Curriculum connection

![[K1.13]]
%%curriculum-end%%
