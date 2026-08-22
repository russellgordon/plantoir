---
title: Dictionaries Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Dictionaries]] and
[[Choosing a Data Structure]]. A dictionary is organised by key, which
is how people ask questions — by name, not by position. Most of the
work below is one of two patterns: tally, or look up safely.

## Reading

1. **Predict all four printed lines.**
   ```python
   stock = {"pasta": 4, "soup": 6}
   stock["rice"] = 2
   stock["soup"] = stock["soup"] + 3
   print(len(stock))
   print("Soup" in stock)
   print(stock.get("beans", 0))
   print(stock)
   ```
2. **Find the fault.** This is supposed to answer "should we ask for
   more of this?" for any item, including ones nobody has donated.
   ```python
   def restock_needed(stock, item):
       return stock[item] < 3
   ```
3. **Read somebody else's code.** Say in one sentence what this
   returns, then predict it for
   `[("Nadia", 2), ("Rowan", 1.5), ("Nadia", 2.5)]`.
   ```python
   def mystery(pairs):
       result = {}
       for name, hours in pairs:
           if name not in result:
               result[name] = []
           result[name].append(hours)
       return result
   ```

## Writing

4. Write `tally(items)`, which returns a dictionary counting how often
   each item appears. Test it on
   `["Nadia", "Rowan", "Nadia", "Bea", "Nadia", "Rowan"]`.
5. Write `most_frequent(counts)`, which returns the key with the
   highest value, and returns `None` for an empty dictionary. Say why
   the dictionary cannot answer this quickly.
6. Write `invert(lookup)`, which turns
   `{"Nadia": 12, "Rowan": 11, "Ali": 12, "Bea": 10}` into a
   dictionary from grade to a list of names. Explain why the values
   have to be lists.
7. Write `combine(first, second)`, which returns a **new** dictionary
   holding the totals of two weekly tallies without changing either
   input. Show that `first` is unchanged afterwards.
8. Using this nested structure, print the total gym attendance across
   both days, then a per-day total for every activity:
   ```python
   attendance = {
       "Monday": {"homework club": 12, "gym": 20},
       "Tuesday": {"homework club": 9},
   }
   attendance["Tuesday"]["gym"] = 15
   ```
9. **Judgement.** The community centre has 400 members. It needs: the
   sign-in order for today, instant lookup of a member by card number,
   and a count of visits per member this month. Say what container
   each one needs, and why one of the three might sensibly be two
   containers.

## Answers

> [!success]- Answer 1
> ```text
> 3
> False
> 0
> {'pasta': 4, 'soup': 9, 'rice': 2}
> ```
> `len` counts entries, not values. `"Soup" in stock` is `False`
> because keys are compared exactly and `"Soup"` is not `"soup"` — a
> real bug source when names arrive from a form. `.get("beans", 0)`
> supplies the default instead of raising. The final dictionary keeps
> its keys in the order they were first inserted, and `soup` is still
> in second place even though its value changed.

> [!success]- Answer 2
> It crashes for any item the food bank has never received:
> ```text
> KeyError: 'flour'
> ```
> — which is exactly the case the question is about. Ask safely:
> ```python
> def restock_needed(stock, item):
>     """True when fewer than three of this item are on hand."""
>     return stock.get(item, 0) < 3
> ```
> Now an item with no entry is treated as zero on hand, which is both
> true and useful. Use `stock[item]` only where a missing key means
> your program's assumptions are already broken.

> [!success]- Answer 3
> It groups the pairs by name, returning a dictionary from each name
> to the list of every value recorded for it.
> ```text
> {'Nadia': [2, 2.5], 'Rowan': [1.5]}
> ```
> The tell is `result[name] = []` followed by `.append` — the tally
> pattern with a list instead of a counter. Reading for the *pattern*
> rather than line by line is the habit in
> [[Reading Somebody Else's Code]].

> [!success]- Answer 4
> ```python
> def tally(items):
>     """Return a dictionary of item -> how many times it appears."""
>     counts = {}
>     for item in items:
>         if item in counts:
>             counts[item] = counts[item] + 1
>         else:
>             counts[item] = 1
>     return counts
>
>
> sign_ins = ["Nadia", "Rowan", "Nadia", "Bea", "Nadia", "Rowan"]
> print(tally(sign_ins))
> ```
> ```text
> {'Nadia': 3, 'Rowan': 2, 'Bea': 1}
> ```

> [!success]- Answer 5
> ```python
> def most_frequent(counts):
>     """Return the key with the highest value, or None if empty."""
>     best_key = None
>     best_count = 0
>     for key in counts:
>         if counts[key] > best_count:
>             best_key = key
>             best_count = counts[key]
>     return best_key
>
>
> print(most_frequent(tally(sign_ins)))
> print(most_frequent({}))
> ```
> ```text
> Nadia
> None
> ```
> A dictionary is indexed by key, not by value, so "which value is
> biggest?" needs a full pass — $O(n)$, not $O(1)$. That is not a flaw;
> it is the trade you accepted when you chose lookup by name. If your
> program asks this constantly, keep a running maximum as you tally.

> [!success]- Answer 6
> ```python
> def invert(lookup):
>     """Return a dictionary of value -> list of keys that had it."""
>     flipped = {}
>     for key in lookup:
>         value = lookup[key]
>         if value in flipped:
>             flipped[value].append(key)
>         else:
>             flipped[value] = [key]
>     return flipped
>
>
> print(invert({"Nadia": 12, "Rowan": 11, "Ali": 12, "Bea": 10}))
> ```
> ```text
> {12: ['Nadia', 'Ali'], 11: ['Rowan'], 10: ['Bea']}
> ```
> The values must be lists because keys are unique and values are not:
> two people are in grade 12. Assigning `flipped[12] = "Ali"` would
> silently overwrite Nadia — no error, no warning, one person gone.

> [!success]- Answer 7
> ```python
> def combine(first, second):
>     """Return a new dictionary with the totals of both tallies."""
>     combined = {}
>     for item in first:
>         combined[item] = first[item]
>     for item in second:
>         if item in combined:
>             combined[item] = combined[item] + second[item]
>         else:
>             combined[item] = second[item]
>     return combined
>
>
> week1 = {"pasta": 4, "soup": 6}
> week2 = {"soup": 3, "rice": 2}
> print(combine(week1, week2))
> print(week1)
> ```
> ```text
> {'pasta': 4, 'soup': 9, 'rice': 2}
> {'pasta': 4, 'soup': 6}
> ```
> Copying into a fresh dictionary first is what keeps `week1`
> untouched. A function that quietly modifies its arguments is the
> hardest kind of bug to find in somebody else's program, because the
> damage appears somewhere the function is not mentioned.

> [!success]- Answer 8
> ```python
> print(attendance["Monday"]["gym"] + attendance["Tuesday"]["gym"])
>
> for day in sorted(attendance):
>     total = 0
>     for activity in attendance[day]:
>         total = total + attendance[day][activity]
>     print(f"{day}: {total}")
> ```
> ```text
> 35
> Monday: 32
> Tuesday: 24
> ```
> `attendance["Tuesday"]` is itself a dictionary, so the second
> subscript indexes into it. Two levels of key mean two nested loops —
> and note that `sorted` on the outer keys gives alphabetical order,
> which happens to put Monday before Tuesday here but would not for
> Wednesday and Friday. Ordering days properly needs data you have not
> stored.

> [!success]- Answer 9
> Sign-in order is a **list** — order is the whole point, and it only
> ever grows at the end. Lookup by card number is a **dictionary**
> from card number to the member object, giving average $O(1)$
> instead of scanning 400 records. Visits per member this month is a
> second **dictionary**, from member to a count — the tally pattern.
>
> The one that is sensibly two containers is the membership itself:
> a list of `Member` objects for anything that needs order or a full
> report, plus a dictionary from card number to those same objects for
> instant lookup. Both refer to the same objects, so nothing is
> duplicated — but exactly one method should be allowed to add or
> remove a member, or the two will drift apart. That trade is set out
> in [[Choosing a Data Structure]].

%%curriculum-start%%
## Curriculum connection

![[A1.2]]

![[A1.3]]

![[A1.5]]

![[A3.1]]

![[C1.1]]

![[C2.1]]
%%curriculum-end%%

