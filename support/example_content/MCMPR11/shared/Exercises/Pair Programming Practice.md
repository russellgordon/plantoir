---
title: Pair Programming Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
Work through these with a partner, not alone. Each problem names where to
switch driver and navigator, and what the navigator should be watching
for while they're not touching the keyboard. If you don't have a partner
handy, do the switch anyway — write half in your normal editor, then
close it and finish the other half from a blank file, forcing yourself to
re-read what's there before continuing.

## Problems

1. **Frost warning.** Write a function `is_frost_warning(temp_celsius:
   float) -> bool` that returns `True` when the temperature is at or
   below zero.
   *Switch after the function signature and docstring are written, before
   the body.* **Navigator, watch for:** whether the comparison should be
   `<` or `<=` at exactly `0`.

2. **Ferry capacity.** Write a function that takes `booked` and
   `total_spaces`, and returns how many vehicle spaces remain. It should
   never return a negative number, even if `booked` is somehow larger
   than `total_spaces`.
   *Switch after the first version runs without crashing, before you
   test the over-booked case.* **Navigator, watch for:** what happens
   when `booked` is bigger than `total_spaces` — does the current code
   actually stop it going negative, or just look like it does?

3. **High UV days.** Given a list of a week's UV index readings, count
   how many days were "very high" (index 8 or above).
   *Switch halfway through writing the loop — driver writes the `for`
   line and the `if`, then hands off before the counter update.*
   **Navigator, watch for:** whether the counter variable is created
   *before* the loop starts, not inside it.

4. **Clean the sign-in sheet.** Camper names arrive messy — extra spaces,
   inconsistent capitalization: `"  sam okafor "`, `"MEI CHEN"`. Write a
   function that returns a tidy version: no leading or trailing spaces,
   and title case (`"Sam Okafor"`).
   *Switch after the cleaning function is written, before you test it on
   all three messy examples.* **Navigator, watch for:** whether the
   fix handles a name that's messy in *both* ways at once, not just one.

5. **Trails over a threshold.** Given a dictionary mapping trail names to
   their distance in kilometres, print the names of every trail longer
   than a given threshold.
   *Switch before writing the final loop that does the printing — one
   person writes the filtering logic, the other writes the output.*
   **Navigator, watch for:** whether the threshold comparison is
   strictly greater than, or greater-than-or-equal, and whether that
   matches what the problem actually asked for.

6. **Challenge: largest wildfire report.** You have a list of
   dictionaries, each with `"location"` and `"size_hectares"` keys.
   Write a function that returns the dictionary for the single largest
   fire. This combines a loop, a dictionary, and a function — talk
   through the plan together before either of you types a line.
   *Switch driver and navigator after every function you write, not
   partway through one.* **Navigator, watch for:** whether the "current
   biggest so far" variable is being compared correctly on every pass
   through the loop, not just set once at the start.

## Answers

> [!success]- Answer 1
> ```python
> def is_frost_warning(temp_celsius: float) -> bool:
>     """Return True when the temperature is at or below zero."""
>     return temp_celsius <= 0
> ```
> `<=` is correct — a reading of exactly `0` is the frost warning, not
> one degree below it.

> [!success]- Answer 2
> ```python
> def remaining_spaces(booked: int, total_spaces: int) -> int:
>     """Return remaining vehicle spaces, never negative."""
>     spaces_left = total_spaces - booked
>     if spaces_left < 0:
>         return 0
>     return spaces_left
> ```
> Without the check, an over-booked ferry (`booked = 210`,
> `total_spaces = 200`) would report `-10` spaces remaining, which no
> passenger-facing screen should ever show.

> [!success]- Answer 3
> ```python
> def count_high_uv_days(readings: list[int]) -> int:
>     """Count how many readings are 8 or above."""
>     high_days = 0
>     for reading in readings:
>         if reading >= 8:
>             high_days += 1
>     return high_days
> ```
> `high_days` is created once, before the loop starts, at `0`. Creating
> it inside the loop would reset the count to zero on every single
> reading.

> [!success]- Answer 4
> ```python
> def clean_name(raw_name: str) -> str:
>     """Strip extra whitespace and apply title case to a camper's name."""
>     return raw_name.strip().title()
> ```
> `.strip()` removes the leading and trailing spaces, and `.title()`
> fixes the capitalization — chained together, one call handles both
> problems in either order they show up.

> [!success]- Answer 5
> ```python
> def trails_over(trail_distances: dict[str, float], threshold_km: float) -> None:
>     """Print every trail longer than the given threshold."""
>     long_trails = []
>     for name, distance in trail_distances.items():
>         if distance > threshold_km:
>             long_trails.append(name)
>
>     for name in long_trails:
>         print(name)
> ```
> `>` (not `>=`) matches "longer than a given threshold" — a trail
> exactly at the threshold is not longer than it.

> [!success]- Answer 6
> ```python
> def find_largest_fire(fire_reports: list[dict]) -> dict:
>     """Return the report dictionary for the largest fire by hectares."""
>     largest_so_far = fire_reports[0]
>     for report in fire_reports:
>         if report["size_hectares"] > largest_so_far["size_hectares"]:
>             largest_so_far = report
>     return largest_so_far
> ```
> `largest_so_far` starts at the *first* report, not at zero — starting
> at zero would silently work for positive sizes but is the wrong idea:
> the comparison should always be against a real report, not an
> assumption about what "smallest possible" looks like.

%%curriculum-start%%
## Curriculum connection

![[K1.7]]
%%curriculum-end%%
