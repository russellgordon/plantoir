---
title: Dictionary Frequency and Lookup Drills
publish: true
created: __CREATED__
tags:
  - exercises
---
Dictionaries let you map keys to values. They are essential for lookups,
frequency counting, and structuring real-world data like community resources.

- [ ] Practice retrieving values safely
- [ ] Practice iterating over keys and values
- [ ] Practice the frequency counter pattern

## Reading

1. What prints when this runs?
   ```python
   shelters = {"Downtown": 45, "Eastside": 120, "North": 30}
   print(shelters["Eastside"])
   ```
2. What happens if you run `print(shelters["Westside"])`? How can you prevent that error?
3. Trace this frequency counter. What does `word_counts` look like at the end?
   ```python
   corpus = ["raven", "bear", "raven", "eagle", "bear", "raven"]
   word_counts = {}
   for word in corpus:
       if word in word_counts:
           word_counts[word] = word_counts[word] + 1
       else:
           word_counts[word] = 1
   ```
4. Look at this nested dictionary. How would you print the `capacity` of the `"Main"` shelter?
   ```python
   network = {
       "Main": {"capacity": 50, "open": True},
       "Annex": {"capacity": 20, "open": False}
   }
   ```

## Writing

5. Write code to add `"South": 60` to the `shelters` dictionary.
6. Write a loop that prints every shelter and its capacity from the `shelters` dictionary in the format `Shelter: Downtown, Capacity: 45`.
7. You are analyzing text from a FirstVoices language revitalization project. Write a function that takes a list of words and returns a dictionary of their frequencies.
8. **Challenge.** Given `resources = {"Food Bank": ["Monday", "Wednesday"], "Clinic": ["Tuesday"]}`, write code that searches for "Monday" and prints all resource names that are open on that day.

## Answers

> [!success]- Answer 1
> `120`. Dictionaries look up the value associated with the key provided.

> [!success]- Answer 2
> A `KeyError` crashes the program. You can prevent it by using the `.get()` method: `shelters.get("Westside", 0)`, which returns `0` (or another default) if the key is missing. Or, use `if "Westside" in shelters:`.

> [!success]- Answer 3
> `{"raven": 3, "bear": 2, "eagle": 1}`. The loop checks if each word is already a key. If it is, it increments the count; if not, it adds it with a count of `1`.

> [!success]- Answer 4
> `print(network["Main"]["capacity"])`. The first bracket gets the inner dictionary, and the second bracket gets the value from that inner dictionary.

> [!success]- Answer 5
> ```python
> shelters["South"] = 60
> ```

> [!success]- Answer 6
> ```python
> for location, capacity in shelters.items():
>     print(f"Shelter: {location}, Capacity: {capacity}")
> ```
> `items()` is the cleanest way to loop over both keys and values simultaneously.

> [!success]- Answer 7
> ```python
> def count_words(word_list):
>     counts = {}
>     for word in word_list:
>         if word in counts:
>             counts[word] = counts[word] + 1
>         else:
>             counts[word] = 1
>     return counts
> ```

> [!success]- Answer 8
> ```python
> resources = {"Food Bank": ["Monday", "Wednesday"], "Clinic": ["Tuesday"]}
> target_day = "Monday"
> for name, days in resources.items():
>     if target_day in days:
>         print(name)
> ```
> This prints `Food Bank`. It iterates over the dictionary and checks if the target day is in the list of days for each resource.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
