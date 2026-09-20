---
title: Whiteboard Challenge - String Reversal Without Slicing
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - algorithms
  - strings
---

In Python, reversing a string is famously easy. You just use slicing: `reversed_string = my_string[::-1]`.

But what if you were programming in a language without slicing, or you were asked in an interview to demonstrate your understanding of loops?

**The Challenge:** Write a function `reverse_string(text)` that takes a string and returns the reversed version. You may **not** use `[::-1]` or any built-in `.reverse()` methods. You must use a loop.

Grab a whiteboard or a piece of paper, and trace how your loop builds the new string step by step.

> [!success]- Answer 1
> ```python
> def reverse_string(text):
>     result = ""
>     for char in text:
>         # By putting the new char BEFORE the existing result,
>         # we effectively build the string backwards!
>         result = char + result
>     return result
> 
> print(reverse_string("salish")) # Output: hsilas
> ```
> 
> **Trace Table for `"cat"`**:
> | `char` | `result` (before) | `char + result` | `result` (after) |
> |--------|-------------------|-----------------|------------------|
> | `'c'`  | `""`              | `'c' + ""`      | `"c"`            |
> | `'a'`  | `"c"`             | `'a' + "c"`     | `"ac"`           |
> | `'t'`  | `"ac"`            | `'t' + "ac"`    | `"tac"`          |

### Why learn this?
Slicing `[::-1]` is highly optimized in Python (written in C under the hood) and should absolutely be used in production code. However, the manual approach teaches you how an accumulator pattern works, how strings are concatenated, and how iterative algorithms process data — skills that apply universally across all programming languages.

%%curriculum-start%%
## Curriculum connection

![[K1.8]]
%%curriculum-end%%
