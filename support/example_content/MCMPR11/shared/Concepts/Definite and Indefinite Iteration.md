---
title: Definite and Indefinite Iteration
publish: true
created: __CREATED__
tags:
  - concept
enableToc: true
---
A computer's greatest strength is doing boring, repetitive tasks perfectly at high speed. In programming, repeating a block of code is called **iteration** or **looping**. We divide loops into two main categories: definite (when you know how many times to repeat) and indefinite (when you don't).

## Definite Iteration: The `for` Loop

Use a `for` loop when you have a specific collection of items to process, or when you know exactly how many times the code should run. 

Ocean Networks Canada operates sensors off the BC coast. If we have a week of daily average temperatures from the Salish Sea, we can iterate over them:

```python
daily_temps = [9.2, 9.4, 9.1, 8.8, 9.0, 9.3, 9.5]

for temp in daily_temps:
    print(f"Recorded temperature: {temp}°C")
```

When you need to count, use Python's `range()` function. 

```python
# Prints 0, 1, 2, 3, 4
for i in range(5):
    print(i)
```

> [!warning] The Off-By-One Error
> `range(5)` starts at 0 and stops *before* 5. It produces exactly 5 numbers, but 5 is not one of them. Forgetting that `range` is exclusive at the upper bound is a classic source of off-by-one bugs.

## Indefinite Iteration: The `while` Loop

Use a `while` loop when the number of repetitions is unknown. The loop will keep running as long as a specific condition remains `True`.

This is perfect for validating user input. You can't know how many times a user will type an invalid menu option before they get it right.

```python
selection = ""

# The loop acts as a sentinel, guarding the rest of the program
while selection != "1" and selection != "2":
    print("BC Ferries Terminal Kiosk")
    print("1. Tsawwassen to Swartz Bay")
    print("2. Horseshoe Bay to Departure Bay")
    selection = input("Select a route (1 or 2): ")

print("Route selected. Proceeding to payment...")
```

> [!danger] The Infinite Loop
> If the condition in a `while` loop never becomes `False`, the loop will run forever. This usually happens because you forgot to update the variable being checked inside the loop. If your terminal is frozen, press `Ctrl` + `C` to forcefully interrupt the program.

## The Accumulator Pattern

Loops become powerful when combined with the **accumulator pattern**. This involves setting up an "empty" variable outside the loop, and updating it on every pass. You can use this to sum values, count occurrences, or find a minimum/maximum.

Let's find the average temperature from our marine sensors:

```python
daily_temps = [9.2, 9.4, 9.1, 8.8, 9.0, 9.3, 9.5]

# 1. Set up the accumulator
total_temp = 0.0
count = 0

# 2. Update it inside the loop
for temp in daily_temps:
    total_temp = total_temp + temp
    count = count + 1

# 3. Use the accumulated result
average = total_temp / count
print(f"Average water temp: {round(average, 2)}°C")
```

This structural pattern appears everywhere in computer science. Master it, and you can reduce any massive dataset down to a single meaningful number.

%%curriculum-start%%
## Curriculum connection

![[K1.8]]
%%curriculum-end%%
