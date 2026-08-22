---
title: Lists, Tuples, and Collection Slicing
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
When a weather station in the Fraser Valley records the temperature every hour, you do not want to create 24 separate variables named `temp1`, `temp2`, up to `temp24`. Instead, you use a collection. In Python, the most common collections are lists and tuples.

## Lists: Ordered and Mutable

A list is an ordered sequence of items. You can add to it, remove from it, and change the items inside it — this ability to be changed is called being **mutable**.

```python
# A list of hourly temperatures (10 AM to 2 PM)
fraser_valley_temps = [14.5, 15.2, 16.8, 18.1, 19.0]
```

### Zero-Based Indexing

To get an item out of a list, you use its index in square brackets. In computer science, we almost always start counting at zero.

```python
print(fraser_valley_temps[0])  # Prints 14.5 (the first item)
print(fraser_valley_temps[2])  # Prints 16.8 (the third item)
```

> [!warning] IndexError
> If you ask for an index that doesn't exist, Python will crash with an `IndexError: list index out of range`. Because counting starts at 0, the last item in a list of 5 elements is at index 4. `fraser_valley_temps[5]` will cause an error!

## Tuples: Ordered and Immutable

A tuple looks like a list, but it uses parentheses instead of square brackets. The critical difference is that tuples are **immutable** — once created, they cannot be changed. 

```python
# A geographic coordinate for Vancouver
vancouver_coords = (49.2827, -123.1207)

# This would cause a TypeError!
# vancouver_coords[0] = 50.0 
```

Use tuples for data that logically belongs together and should never change during the program's execution, like coordinates or fixed settings.

## Slicing: Getting a Sub-section

Sometimes you want more than one item. Python's slicing syntax lets you extract a new list from an existing one using `start:stop:step`.

```python
months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# start is inclusive, stop is exclusive
spring = months[2:5]      # ['Mar', 'Apr', 'May']

# omitting start means "from the beginning"
first_half = months[:6]   # ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun']

# step skips items
every_other = months[0:12:2] # ['Jan', 'Mar', 'May', 'Jul', 'Sep', 'Nov']

# negative step goes backwards
reverse = months[::-1]
```

## The Aliasing Trap

One of the trickiest bugs for new programmers involves how lists exist in memory. 

```python
list_a = [1, 2, 3]
list_b = list_a
list_b[0] = 99

print(list_a) # Prints [99, 2, 3]!
```

When you say `list_b = list_a`, you are not making a copy of the list. You are attaching a second name (an alias) to the **exact same list in memory**. 

| Variable Name | Memory Reference | Actual Data |
| ------------- | :--------------: | ----------- |
| `list_a`      | `0x1A2B`         | `[99, 2, 3]` |
| `list_b`      | `0x1A2B`         | `[99, 2, 3]` |

If you need a true independent copy so you can modify it safely, use slicing: `list_c = list_a[:]` or the `.copy()` method.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
