---
title: Formula Practice
publish: true
codeRunner: true
created: __CREATED__
tags:
  - exercises
---
Each of these gives you a formula and asks for a program. The work is
the translation: naming the symbols, ordering the steps, and deciding
what the user has to type. Answer on paper first — the whole difficulty
is in the plan, not the typing.

## 1. Distance travelled

$$d = v \times t$$

Ask for a speed in kilometres per hour and a time in hours, print the
distance to one decimal place.

> [!success]- Answer 1
> ```python run
> speed = float(input("Speed, in km/h: "))
> time_taken = float(input("Time, in hours: "))
>
> distance = speed * time_taken
>
> print(f"Distance travelled: {distance:.1f} km")
> ```
> The units are in the prompts on purpose. A program that accepts a
> speed in metres per second and calls the answer kilometres is
> arithmetically perfect and completely wrong.

## 2. Area of a circle

$$A = \pi r^2$$

Ask for a radius, print the area to two decimals. Use `math.pi`, not
3.14.

> [!success]- Answer 2
> ```python run
> import math
>
> radius = float(input("Radius, in cm: "))
>
> area = math.pi * radius ** 2
>
> print(f"Area: {area:.2f} square cm")
> ```
> `radius ** 2` is squaring; `radius * 2` is a different program that
> will look fine and be wrong for every input except 2.

## 3. Celsius to Fahrenheit

$$F = \frac{9}{5}C + 32$$

> [!success]- Answer 3
> ```python run
> celsius = float(input("Temperature, in Celsius: "))
>
> fahrenheit = 9 / 5 * celsius + 32
>
> print(f"{celsius}°C is {fahrenheit:.1f}°F")
> ```
> Check it against a pair you know: 100 must give 212. That single
> check catches the version where somebody wrote `9 // 5`, which is
> integer division and quietly gives 1.

## 4. The cost of running something

$$\text{cost} = \frac{\text{watts} \times \text{hours}}{1000} \times \text{rate}$$

Ask for watts, hours per day, and the price per kilowatt-hour. Print
the daily cost and the cost over a 194-day school year.

> [!success]- Answer 4
> ```python run
> watts = float(input("Power, in watts: "))
> hours = float(input("Hours per day: "))
> rate = float(input("Price per kWh, in dollars: "))
>
> kilowatt_hours = watts * hours / 1000
> daily_cost = kilowatt_hours * rate
> yearly_cost = daily_cost * 194
>
> print(f"Per day:  ${daily_cost:.2f}")
> print(f"Per year: ${yearly_cost:.2f}")
> ```
> `kilowatt_hours` earns its name here: when the yearly figure looks
> absurd, that is the line you print to find out whether the error is
> in the conversion or the multiplication.

## 5. Averaging, with a guard

The mean of a list of readings is the total divided by how many there
are. Write a program that reads numbers until the user types `done`,
then prints the mean — and does not crash when the user types `done`
immediately.

> [!success]- Answer 5
> ```python run
> readings = []
>
> while True:
>     entry = input("Reading (or 'done'): ")
>     if entry == "done":
>         break
>     readings.append(float(entry))
>
> if len(readings) == 0:
>     print("No readings were entered.")
> else:
>     total = 0
>     for reading in readings:
>         total = total + reading
>     print(f"Mean of {len(readings)} readings: {total / len(readings):.2f}")
> ```
> The guard is the whole exercise. Dividing by zero is the formula
> being asked a question it has no answer to, and the program has to
> answer for it.

%%curriculum-start%%
## Curriculum connection

![[B3.2]]

![[A1.3]]

![[A2.1]]
%%curriculum-end%%
