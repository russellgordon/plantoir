---
title: Recursion Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Recursion]]. Every answer below is marked on
two things before anything else: is there a base case, and does every
call get closer to it. Write those two lines first, every time.

## Reading

1. **Predict the output**, and say what the function computes.
   ```python
   def mystery(n):
       if n == 0:
           return 0
       return n + mystery(n - 1)

   print(mystery(4))
   ```
2. **Find the fault.** This runs, prints a lot, and then stops badly.
   What is missing, what exactly does Python say, and why is raising
   the recursion limit the wrong fix?
   ```python
   def countdown(n):
       print(n)
       countdown(n - 1)

   countdown(3)
   ```
3. **Find the fault.** This one has a base case and still never
   reaches it. Why?
   ```python
   def count_down_by_two(n):
       if n == 0:
           return "done"
       return count_down_by_two(n - 2)

   print(count_down_by_two(7))
   ```

## Writing

4. Write `sum_to(n)`, returning $1 + 2 + \dots + n$ recursively, with
   `sum_to(0)` as the base case. Check it on 5, 0, and 100.
5. Write `countdown(n)`, printing `n` down to 1 and then `Go`.
6. Write `total_of(items)`, which adds up numbers in a list that may
   contain other lists, to any depth. Test it on `[1, [2, 3, [4]], 5]`
   and on `[]`.
7. Write `backwards(text)` recursively, and say what your base case
   does with the empty string.
8. Write `power(base, exponent)` recursively for exponents of zero or
   more.
9. **Cost.** Rewrite `fib` so that it returns both the answer and the
   number of calls it made, then report the counts for `n` of 5, 10,
   20, and 25. Explain the growth, and write the loop version that
   does not have the problem.
10. **Theoretical foundations.** Write the recurrence relations for
    `sum_to(n)` and for naive `fib(n)`. Explain how mathematical
    induction proves that a recursive function with a correct base
    case terminates for all legal inputs, and how the call stack depth
    governs auxiliary space complexity.

## Answers

> [!success]- Answer 1
> ```text
> 10
> ```
> It adds the whole numbers from `n` down to 1 — here
> `4 + 3 + 2 + 1 + 0`. The base case returns `0` at `n == 0`, and each
> call is one closer to it. Trace it as five calls stacked up, then
> five returns folding back: `4 + (3 + (2 + (1 + 0)))`.

> [!success]- Answer 2
> There is no base case, so nothing ever stops the calls. It counts
> down past zero for ever until the call stack runs out:
> ```text
> RecursionError: maximum recursion depth exceeded
> ```
> Raising the limit with `sys.setrecursionlimit` is the wrong fix
> because the function is not deep, it is **endless** — a bigger limit
> just delays the same crash and risks taking the interpreter down
> with it. The fix is a base case:
> ```python
> def countdown(n):
>     """Print n down to 1, then 'Go'."""
>     if n == 0:
>         print("Go")
>         return
>     print(n)
>     countdown(n - 1)
> ```

> [!success]- Answer 3
> Starting from 7, the values go 7, 5, 3, 1, -1, -3, and so on. They
> never equal zero, so the base case is stepped over. A base case must be
> *reachable from every legal starting value*. Either widen it to
> `if n <= 0:` or make the progress land on it. This is the subtler
> half of infinite recursion, and the reason to state your base case
> as a condition rather than a single value.

> [!success]- Answer 4
> ```python
> def sum_to(n):
>     """Return 1 + 2 + ... + n. Base case: sum_to(0) is 0."""
>     if n == 0:
>         return 0
>     return n + sum_to(n - 1)
>
>
> print(sum_to(5), sum_to(0), sum_to(100))
> ```
> ```text
> 15 0 5050
> ```
> `sum_to(100)` builds a stack a hundred frames deep — fine. Try
> `sum_to(5000)` and you will meet `RecursionError`, which is your
> reminder that recursion costs memory a loop does not.

> [!success]- Answer 5
> ```python
> def countdown(n):
>     """Print n down to 1, then 'Go'."""
>     if n == 0:
>         print("Go")
>         return
>     print(n)
>     countdown(n - 1)
>
>
> countdown(3)
> ```
> ```text
> 3
> 2
> 1
> Go
> ```
> A bare `return` ends the function without a value, which is exactly
> right for a function whose job is to print.

> [!success]- Answer 6
> ```python
> def total_of(items):
>     """Add up numbers in a list that may contain other lists."""
>     total = 0
>     for item in items:
>         if isinstance(item, list):
>             total = total + total_of(item)
>         else:
>             total = total + item
>     return total
>
>
> print(total_of([1, [2, 3, [4]], 5]))
> print(total_of([]))
> ```
> ```text
> 15
> 0
> ```
> The base case is quiet: a list with no lists inside it never
> recurses, and an empty list returns `0` because the loop does not
> run. This is the shape from [[Recursion]] — the function does not
> need to know how deep the nesting goes, which is why a loop cannot
> replace it here.

> [!success]- Answer 7
> ```python
> def backwards(text):
>     """Return text reversed, recursively."""
>     if len(text) <= 1:
>         return text
>     return backwards(text[1:]) + text[0]
>
>
> print(backwards("holds"))
> ```
> ```text
> sdloh
> ```
> `len(text) <= 1` handles both the empty string and a single
> character, each of which is already its own reverse. Writing
> `if len(text) == 0:` would work too; writing `if text == "a":` would
> not, and that is the kind of base case that passes one test and
> fails everything else.

> [!success]- Answer 8
> ```python
> def power(base, exponent):
>     """Return base to the exponent, for exponent >= 0."""
>     if exponent == 0:
>         return 1
>     return base * power(base, exponent - 1)
>
>
> print(power(2, 10), power(5, 0), power(3, 3))
> ```
> ```text
> 1024 1 27
> ```
> Anything to the power of zero is 1, which is the base case doing
> real mathematical work rather than just stopping the recursion.

> [!success]- Answer 9
> ```python
> def fib_with_count(n):
>     """Return the nth Fibonacci number and how many calls it took."""
>     if n <= 1:
>         return n, 1
>     left_value, left_calls = fib_with_count(n - 1)
>     right_value, right_calls = fib_with_count(n - 2)
>     return left_value + right_value, left_calls + right_calls + 1
>
>
> for n in [5, 10, 20, 25]:
>     print(n, fib_with_count(n))
> ```
> ```text
> 5 (5, 15)
> 10 (55, 177)
> 20 (6765, 21891)
> 25 (75025, 242785)
> ```
> Each call makes two more, so the number of calls roughly doubles for
> every step of `n` — from 177 at `n = 10` to nearly 243 000 at
> `n = 25`. The same subproblems are recomputed over and over:
> `fib(23)` alone is calculated twice, `fib(22)` three times, and so
> on. That is exponential growth, and it is the pitfall named in
> [[C2.4|the recursion pitfalls expectation]].
>
> The loop version does the same job in a single pass:
> ```python
> def fib_loop(n):
>     """The same numbers, with a loop."""
>     if n == 0:
>         return 0
>     previous = 0
>     current = 1
>     for step in range(n - 1):
>         previous, current = current, previous + current
>     return current
>
>
> for n in range(10):
>     print(fib_loop(n), end=" ")
> ```
> ```text
> 0 1 1 2 3 5 8 13 21 34
> ```
> Recursion is the right tool when the *data* is nested. Fibonacci is
> a sequence, and sequences are loops.

> [!success]- Answer 10
> The recurrence relations express running time in terms of subproblem
> costs:
>
> - `sum_to(n)`: $T(n) = T(n - 1) + O(1)$ with $T(0) = O(1)$.
>   Unrolling this gives $T(n) = O(n)$ time.
> - Naive `fib(n)`: $T(n) = T(n - 1) + T(n - 2) + O(1)$ with
>   $T(0) = T(1) = O(1)$. The recurrence matches the Fibonacci
>   sequence itself, yielding $T(n) = O(\phi^n) \approx O(1.618^n)$, an
>   exponential complexity class ($O(2^n)$).
>
> **Termination via mathematical induction**:
> 1. *Base case ($n = 0$)*: The base condition is explicitly handled
>    and terminates in $O(1)$ without further recursion.
> 2. *Inductive hypothesis*: Assume the function terminates correctly
>    for all non-negative integers $k < n$.
> 3. *Inductive step*: For input $n$, the recursive call executes with
>    $n - 1$ (which is $< n$). By the hypothesis, the subproblem
>    terminates in finite steps, so the call at $n$ terminates.
>
> **Auxiliary space**: Each recursive call allocates a stack frame
> storing local variables and return addresses. The peak call stack
> depth equals the maximum recursion tree depth, so linear recursion
> requires $O(n)$ auxiliary memory even when the return value is a
> single number.

%%curriculum-start%%
## Curriculum connection

![[A3.6]]

![[C1.3]]

![[C2.4]]

![[D4.2]]
%%curriculum-end%%

