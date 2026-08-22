---
title: Salish Sea Marine Monitor
publish: true
created: __CREATED__
tags:
  - programs
---
Ocean Networks Canada operates a massive array of underwater sensors in the
Salish Sea. This program simulates a monitoring station that processes a sequence
of temperature readings and flags anomalies that could affect local ecosystems.

## The program

```python
# Salish Sea underwater temperature monitor
# Processes sequential sensor readings and detects anomalies

# In a real system, this list would come from an API or file
readings = [9.2, 9.4, 9.5, 11.8, 9.3, 9.1, 8.9, 12.1, 9.0]
baseline = 9.5

anomalies = 0
highest_temp = readings[0]

print("--- Sensor Array Data Log ---")

for temp in readings:
    if temp > highest_temp:
        highest_temp = temp
        
    if temp > baseline + 2.0:
        print(f"ALERT: Severe temperature spike detected: {temp}°C")
        anomalies = anomalies + 1
    elif temp > baseline + 1.0:
        print(f"Warning: Elevated temperature: {temp}°C")

print("-----------------------------")
print(f"Total readings processed: {len(readings)}")
print(f"Maximum temperature recorded: {highest_temp}°C")
print(f"Severe anomalies found: {anomalies}")
```

```
--- Sensor Array Data Log ---
ALERT: Severe temperature spike detected: 11.8°C
ALERT: Severe temperature spike detected: 12.1°C
-----------------------------
Total readings processed: 9
Maximum temperature recorded: 12.1°C
Severe anomalies found: 2
```

## How it works

The program uses a `for` loop to iterate through the `readings` sequence. It maintains two **accumulators**:
1. `anomalies`: A counter that increments when a reading is significantly above the baseline.
2. `highest_temp`: A "king of the hill" variable that remembers the largest value seen so far.

Notice that `highest_temp` starts at `readings[0]` rather than `0`. If we started at `0` and all our readings were negative (e.g., Arctic monitoring), the program would incorrectly report `0` as the maximum temperature!

## Change it

1. **One line.** Change the loop to also count how many readings were exactly on the baseline.
2. **A few lines.** Add a `lowest_temp` accumulator. Initialize it correctly, update it inside the loop, and print it at the end.
3. **A real change.** Filter the data. Create a new empty list called `valid_readings`. Iterate through the original list, but only `.append()` values to `valid_readings` if they are between 0°C and 20°C (ignoring obvious sensor glitches). Print the new list at the end.

%%curriculum-start%%
## Curriculum connection

![[K1.4]]
%%curriculum-end%%
