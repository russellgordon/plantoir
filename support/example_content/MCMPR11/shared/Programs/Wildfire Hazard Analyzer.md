---
title: Wildfire Hazard Analyzer
publish: true
created: __CREATED__
tags:
  - programs
---
The BC Wildfire Service evaluates risk by combining multiple environmental factors.
This program divides the problem into modules: one function to parse the data safely,
and another to compute the final hazard rating.

## The program

```python
# Wildfire Hazard Analyzer
# Validates input safely and calculates risk levels

def get_valid_number(prompt):
    """Asks the user for a number until they provide a valid one."""
    while True:
        raw_input = input(prompt)
        try:
            value = float(raw_input)
            if value < 0:
                print("Value cannot be negative. Try again.")
                continue
            return value
        except ValueError:
            print("Invalid input. Please enter a number.")

def calculate_danger_rating(temp, wind, days_since_rain):
    """Returns a danger string based on weather factors."""
    score = temp + (wind * 0.5) + (days_since_rain * 2)
    
    if score > 50:
        return "EXTREME"
    elif score > 35:
        return "HIGH"
    elif score > 20:
        return "MODERATE"
    else:
        return "LOW"

# Main program execution
print("--- BC Hazard Assessment Tool ---")
current_temp = get_valid_number("Enter current temperature (°C): ")
current_wind = get_valid_number("Enter wind speed (km/h): ")
dry_days = get_valid_number("Enter days since last rain: ")

rating = calculate_danger_rating(current_temp, current_wind, dry_days)

print("\n--- Assessment Complete ---")
print(f"Calculated Danger Rating: {rating}")
if rating == "EXTREME":
    print("ACTION: Recommend immediate campfire ban.")
```

```
--- BC Hazard Assessment Tool ---
Enter current temperature (°C): 32
Enter wind speed (km/h): gusty
Invalid input. Please enter a number.
Enter wind speed (km/h): 15
Enter days since last rain: 12

--- Assessment Complete ---
Calculated Danger Rating: EXTREME
ACTION: Recommend immediate campfire ban.
```

## How it works

This program delegates work to functions. `get_valid_number()` guarantees that the rest of the program never has to deal with bad data. It traps the user in a `while True` loop, catching `ValueError` exceptions, until it successfully `return`s a float.

`calculate_danger_rating()` takes three parameters and computes a heuristic score. It does not print anything itself; it simply returns the rating. This makes it a pure function that could easily be reused in a web app or dashboard without modification.

## Change it

1. **One line.** Adjust the score multiplier for `wind` from `0.5` to `1.0` to make the model more sensitive to high winds.
2. **A few lines.** In `get_valid_number()`, add a maximum limit. If the user enters a number greater than 150, print `"Value unrealistically high. Try again."` and continue the loop.
3. **A real change.** Add a fourth parameter to `calculate_danger_rating` called `humidity`. Subtract `(humidity * 0.2)` from the final score before checking the thresholds. Update the main program to ask the user for humidity using `get_valid_number()`.

%%curriculum-start%%
## Curriculum connection

![[K1.3]]
%%curriculum-end%%
