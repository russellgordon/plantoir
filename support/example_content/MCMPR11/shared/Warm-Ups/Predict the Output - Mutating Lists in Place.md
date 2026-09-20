---
title: Predict the Output - Mutating Lists in Place
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - memory
  - lists
---

Lists in Python are mutable, which means they can be changed in place. When multiple variables point to the same list, changing the list through one variable affects the other. This is called aliasing.

Predict the exact output for each of the following snippets.

### Snippet A

```python
stations = ["YVR", "YYJ", "YXX"]
backup_stations = stations
backup_stations.append("YXS")
print(stations)
```

> [!success]- Answer 1
> `['YVR', 'YYJ', 'YXX', 'YXS']`
> 
> `backup_stations` and `stations` refer to the exact same list in memory. Appending to `backup_stations` modifies the original list.

### Snippet B

```python
temps = [12, 14, 15, 18]
new_temps = temps.copy()
new_temps[0] = 99
print(temps[0], new_temps[0])
```

> [!success]- Answer 2
> `12 99`
> 
> Using `.copy()` creates a new list in memory. Modifying `new_temps` does not affect `temps`.

### Snippet C

```python
def clear_readings(data):
    data = []

sensor_data = [4.5, 6.2, 5.1]
clear_readings(sensor_data)
print(sensor_data)
```

> [!success]- Answer 3
> `[4.5, 6.2, 5.1]`
> 
> Inside the function, reassigning `data = []` simply makes the local parameter `data` point to a new empty list. It does not mutate the original list that `sensor_data` points to. To clear the list in place, you would use `data.clear()` or `data[:] = []`.

%%curriculum-start%%
## Curriculum connection

![[K1.6]]
%%curriculum-end%%
