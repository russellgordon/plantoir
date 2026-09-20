---
title: Collection Manipulation Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
These questions follow [[Lists, Tuples, and Collection Slicing]]. Every one of them uses the same starting list
of coastal weather station temperatures, so keep it in a file and edit as you go:

```python
stations = [14.2, 12.8, 15.1, 13.5]
```

> [!info] Data Sources
> Environment Canada updates these arrays continuously. In real applications, this data might come from a buoy in the Strait of Georgia.

## Positions and bounds

1. What does each print? `stations[0]`, `stations[3]`, `stations[-1]`, `len(stations)`.
2. What happens when you run `print(stations[4])`, and why is `4` a reasonable-looking mistake?
3. Starting from the original list each time, give the list after `stations.append(11.0)`, then after `stations.insert(1, 16.0)`, then after `stations.remove(15.1)` — applied one after the other.

## Loops over lists

4. Write the loop that totals the temperatures and prints the average to one decimal place.
5. Write a linear search that reports the position of `"Tsawwassen"` in `terminals = ["Swartz Bay", "Duke Point", "Tsawwassen", "Horseshoe Bay"]`, and prints `-1` when the terminal is not there.
6. Count how many of `departures = [8.5, 10.0, 11.5, 13.0, 14.5]` are before `12.0` (noon).
7. Find the lowest value in `stations` without using `min()`.
8. **Challenge.** Build a *new* list holding only the temperatures above 14.0 from `stations`, then print how many there are and what they are.

## Answers

> [!success]- Answer 1
> `14.2`, `13.5`, `13.5`, `4`. Positions run 0 to 3, so `stations[3]` and `stations[-1]` are the same element reached from opposite ends, and `len` counts elements rather than naming the last position.

> [!success]- Answer 2
> `IndexError: list index out of range`. There are four elements, so `4` looks right if you forget that counting starts at zero. The highest valid index is always `len` minus one.

> [!success]- Answer 3
> `[14.2, 12.8, 15.1, 13.5, 11.0]`, then `[14.2, 16.0, 12.8, 15.1, 13.5, 11.0]`, then `[14.2, 16.0, 12.8, 13.5, 11.0]`. `append` adds to the end, `insert` shifts items to make room, and `remove` deletes the first matching *value*.

> [!success]- Answer 4
> ```python
> total = 0
> for temp in stations:
>     total = total + temp
> print(f"Average: {total / len(stations):.1f}")
> ```
> Dividing by `len(stations)` ensures the code still works if more sensors are added.

> [!success]- Answer 5
> ```python
> terminals = ["Swartz Bay", "Duke Point", "Tsawwassen", "Horseshoe Bay"]
> target = "Tsawwassen"
> position = -1
>
> for index in range(len(terminals)):
>     if terminals[index] == target:
>         position = index
>
> print(position)
> ```
> Looping over `range(len(terminals))` gives you indices. Starting at `-1` handles the "not found" case gracefully.

> [!success]- Answer 6
> ```python
> departures = [8.5, 10.0, 11.5, 13.0, 14.5]
> morning_sailings = 0
> for time in departures:
>     if time < 12.0:
>         morning_sailings = morning_sailings + 1
> print(morning_sailings)
> ```

> [!success]- Answer 7
> ```python
> lowest = stations[0]
> for temp in stations:
>     if temp < lowest:
>         lowest = temp
> print(lowest)
> ```
> `12.8`.

> [!success]- Answer 8
> ```python
> warm = []
> for temp in stations:
>     if temp > 14.0:
>         warm.append(temp)
> print(f"{len(warm)} warm stations: {warm}")
> ```
> Building a second list preserves the original data for other calculations.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
