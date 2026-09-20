---
title: Data Transformation and Filtering
publish: true
created: __CREATED__
enableToc: true
tags:
  - exploration
  - python
  - data
  - lists
---

Real-world data is almost never clean. Before we can analyze data or use it in an application, we often have to transform it, clean it up, and filter out bad entries.

In this exploration, you will process a raw dataset of temperature readings from a BC weather station. The data was scraped from a faulty sensor, so some values are missing or obviously incorrect.

### The Raw Data

Here is the raw data provided as a list of strings. It includes a header row, and the temperatures are in Celsius.

```python
raw_data = [
    "Date,Time,Temperature",
    "2023-11-01,08:00,12.5",
    "2023-11-01,12:00,15.2",
    "2023-11-01,16:00,ERROR",
    "2023-11-02,08:00,9.8",
    "2023-11-02,12:00,999.9", # Impossible temp for BC!
    "2023-11-02,16:00,11.1"
]
```

### Step-by-Step Challenge

Write a script that processes `raw_data` to achieve the following:

1. **Remove the header**: You don't want `"Date,Time,Temperature"` mixed in with your calculations.
2. **Extract the temperatures**: Iterate over the remaining lines. Split each line by the comma `","` and isolate the temperature part.
3. **Filter invalid strings**: Skip any rows where the temperature is `"ERROR"`.
4. **Convert types**: Convert the valid temperature strings into `float` values.
5. **Filter outliers**: The sensor sometimes glitches and records `999.9`. Filter out any temperatures above 50.0 °C.
6. **Calculate statistics**: Compute and print the average of the valid, cleaned temperatures.

### Tips for Success

- Use an accumulator list (like `clean_temps = []`) to store the good values.
- Remember that `string.split(",")` returns a list of pieces. Which index holds the temperature?
- Use a `try/except` block if you want to be extra safe when converting to floats, or just check the strings directly.

> [!success]- Worked Solution
> ```python
> raw_data = [
>     "Date,Time,Temperature",
>     "2023-11-01,08:00,12.5",
>     "2023-11-01,12:00,15.2",
>     "2023-11-01,16:00,ERROR",
>     "2023-11-02,08:00,9.8",
>     "2023-11-02,12:00,999.9",
>     "2023-11-02,16:00,11.1"
> ]
> 
> clean_temps = []
> 
> # Skip the first row using slicing [1:]
> for row in raw_data[1:]:
>     # Split the CSV row
>     parts = row.split(",")
>     temp_str = parts[2]
>     
>     # Filter out errors
>     if temp_str == "ERROR":
>         continue
>         
>     # Convert to float
>     temp_val = float(temp_str)
>     
>     # Filter outliers
>     if temp_val <= 50.0:
>         clean_temps.append(temp_val)
> 
> # Calculate average
> if len(clean_temps) > 0:
>     average = sum(clean_temps) / len(clean_temps)
>     print(f"Clean readings: {clean_temps}")
>     print(f"Average Temperature: {average:.2f}°C")
> else:
>     print("No valid data found.")
> ```

### Extension

How would you change your code to also find the highest (maximum) and lowest (minimum) valid temperature in the dataset?

%%curriculum-start%%
## Curriculum connection

![[K1.5]]

![[K1.8]]
%%curriculum-end%%
