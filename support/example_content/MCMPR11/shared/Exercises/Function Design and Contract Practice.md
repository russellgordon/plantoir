---
title: Function Design and Contract Practice
publish: true
created: __CREATED__
tags:
  - exercises
---
Functions let you package logic so it can be reused safely. A good function has
a clear contract: what it takes in, and what it guarantees to return.

| Term | Meaning |
| --- | --- |
| **Parameter** | The variable listed in the function definition. |
| **Argument** | The actual value passed when calling the function. |
| **Return** | The value passed back to the caller. |

## Reading

1. What prints when this code runs?
   ```python
   def to_celsius(fahrenheit):
       return (fahrenheit - 32) * 5/9
       
   temp = to_celsius(50)
   print(temp)
   ```
2. Identify the parameter and the argument in the code from question 1.
3. What is wrong with this function?
   ```python
   def calculate_risk(humidity, wind):
       risk_score = (wind * 2) - humidity
       print(risk_score)
   ```
4. **Scope Trace.** What prints at the end?
   ```python
   multiplier = 2
   
   def scale(value):
       multiplier = 5
       return value * multiplier
       
   result = scale(10)
   print(multiplier)
   ```

## Writing

5. Write a function called `is_freezing` that takes a temperature in Celsius and returns `True` if it is 0 or below, and `False` otherwise.
6. Write a function `calculate_hazard` that takes `temperature` and `wind_speed`. It should return `"High"` if temperature > 30 and wind_speed > 20, otherwise `"Low"`.
7. Rewrite the function from question 3 so that it *returns* the value instead of printing it. Then write the code to call it and print the result.
8. **Challenge.** Write a function `find_hottest` that takes a list of temperatures and returns the highest one. Do not use `max()`. What should your function do if the list is empty?

## Answers

> [!success]- Answer 1
> `10.0`. `50 - 32` is `18`. `18 * 5 / 9` is `10.0`.

> [!success]- Answer 2
> The **parameter** is `fahrenheit`. The **argument** is `50`.

> [!success]- Answer 3
> It `print`s the result instead of `return`ing it. A function that calculates a value should hand it back to the caller, so the caller can decide whether to print it, save it, or use it in another calculation.

> [!success]- Answer 4
> `2`. The `multiplier = 5` inside the function creates a new, *local* variable that only exists while the function is running. It does not change the *global* `multiplier` defined at the top.

> [!success]- Answer 5
> ```python
> def is_freezing(temp):
>     if temp <= 0:
>         return True
>     else:
>         return False
>         
> # Or, more simply:
> # def is_freezing(temp):
> #     return temp <= 0
> ```

> [!success]- Answer 6
> ```python
> def calculate_hazard(temperature, wind_speed):
>     if temperature > 30 and wind_speed > 20:
>         return "High"
>     else:
>         return "Low"
> ```

> [!success]- Answer 7
> ```python
> def calculate_risk(humidity, wind):
>     risk_score = (wind * 2) - humidity
>     return risk_score
> 
> final_risk = calculate_risk(40, 30)
> print(final_risk)
> ```

> [!success]- Answer 8
> ```python
> def find_hottest(temps):
>     if len(temps) == 0:
>         return None
>         
>     hottest = temps[0]
>     for t in temps:
>         if t > hottest:
>             hottest = t
>     return hottest
> ```
> Handling the empty list explicitly prevents an `IndexError` when trying to access `temps[0]`.

%%curriculum-start%%
## Curriculum connection

![[K1.3]]
%%curriculum-end%%
