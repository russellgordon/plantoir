---
title: Pacific Route Simulator
publish: true
created: __CREATED__
tags:
  - programs
---
BC Ferries coordinates dozens of vessels across complex coastal routes. This
simulator models a simplified routing decision system that determines whether a
vessel can sail based on wind conditions and mechanical status.

## The program

```python
# Route simulator for coastal ferry operations
# Determines sailing status based on wind and maintenance

destination = input("Destination port: ")
wind_speed_input = input("Current wind speed (km/h): ")

try:
    wind_speed = int(wind_speed_input)
except ValueError:
    print(f"Could not read '{wind_speed_input}' as a number. Assuming 0.")
    wind_speed = 0

print()

if wind_speed >= 90:
    print(f"{destination} route: CANCELLED.")
    print("Sustained winds exceed safe operational limits.")
elif wind_speed >= 65:
    print(f"{destination} route: DELAYED.")
    print("Vessel holding in port until gale conditions subside.")
elif wind_speed >= 40:
    print(f"{destination} route: ADVISORY.")
    print("Sailing proceeds with caution. Expect rough waters in the Strait.")
else:
    print(f"{destination} route: ON TIME.")
    print("Conditions are nominal for scheduled crossing.")
```

```
Destination port: Tsawwassen
Current wind speed (km/h): 72

Tsawwassen route: DELAYED.
Vessel holding in port until gale conditions subside.
```

## How it works

The decision logic branches based on the `wind_speed`. Order is critical here.

| `wind_speed` | Branch | Reason |
| --- | --- | --- |
| `90` or more | CANCELLED | `wind_speed >= 90` is checked first |
| `65` to `89` | DELAYED | First condition failed, `wind_speed >= 65` passed |
| `40` to `64` | ADVISORY | First two failed, `wind_speed >= 40` passed |
| `39` or less | ON TIME | None matched, falling through to `else` |

If we checked `>= 40` first, a wind speed of 100 km/h would trigger the ADVISORY branch instead of the CANCELLED branch, which is a serious logic error in a safety system.

The `try/except` block protects the program from crashing if a user types "calm" instead of a number.

## Change it

1. **One line.** The threshold for a delay is lowered to 60 km/h due to vessel constraints. Update the code to reflect this new safety margin.
2. **A few lines.** Ask the user for the `wave_height` in metres. If the wave height is over 3.0 metres, print an additional warning message regardless of the wind speed.
3. **A real change.** Ask the user `Is this a dangerous goods sailing? (yes/no)`. If it is a dangerous goods sailing, the cancellation threshold drops to 70 km/h instead of 90 km/h. You will need to nest an `if` statement or use boolean logic.

%%curriculum-start%%
## Curriculum connection

![[K1.8]]
%%curriculum-end%%
