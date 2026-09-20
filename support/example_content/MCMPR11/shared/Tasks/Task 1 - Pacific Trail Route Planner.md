---
title: "Task 1 - Pacific Trail & Alpine Hazard Simulator"
publish: true
created: __CREATED__
tags:
  - tasks
  - summative
enableToc: true
---
> [!abstract] At a glance
> Solo · launched in Unit 1, Day 14 and due Unit 1, Day 18 · a console-based route and alpine hazard assessment engine for BC backcountry expeditions · arithmetic decomposition, multi-factor risk indexing, and defensive input parsing.

## What you are making

A Python expedition planning engine that models travel times, elevation profiles, and weather hazard thresholds for real British Columbia wilderness routes (such as the **West Coast Trail** on Vancouver Island, the **Howe Sound Crest Trail** in the Coast Mountains, or the **Berg Lake Trail** in Mount Robson Provincial Park).

Backcountry safety in British Columbia depends on rigorous mathematical modeling. Hikers and Search and Rescue (SAR) teams cannot rely on casual estimates when traversing technical alpine terrain where temperatures drop with elevation and daylight diminishes rapidly in autumn.

Your program will accept route parameters (trail distance, total elevation gain, technical terrain rating, starting temperature at sea level, and group pack weight ratio), apply established mountaineering algorithms, and produce a detailed trip advisory report.

```
============================================================
PACIFIC TRAIL ADVISORY ENGINE — BC EXPEDITION PLANNER
============================================================
Selected Route: Howe Sound Crest Trail (Coast Mountains, BC)
Distance: 29.0 km | Elevation Gain: 1830 m | Max Summit: 1654 m

--- TRIP ESTIMATION BREAKDOWN ---
Base Hiking Time:              5.80 hours (at 5.0 km/h baseline)
Elevation Penalty:             3.05 hours (Naismith: 1.0 h / 600m gain)
Terrain & Pack Multiplier:     1.25x (Technical scramble + 18kg pack)
------------------------------------------------------------
Total Estimated Moving Time:   11.06 hours (11h 04m)
Estimated Sunset Buffer:       -1.50 hours [CRITICAL WARNING: FINISHES IN DARK]

--- ALPINE HAZARD & FREEZING LEVEL ASSESSMENT ---
Sea-Level Base Temperature:    14.0°C
Summit Temperature (1654m):     3.2°C (Lapse rate: -6.5°C / 1000m)
Freezing Level Altitude:       2154 m
Precipitation Forecast:        18.0 mm (Heavy Rain)
Hypothermia Risk Index:        HIGH (Cold rain + exposure above 1200m)
Avalanche Danger Tier:         EARLY SEASON CAUTION (Wet loose snow above 1500m)

ADVISORY RECOMMENDATION:
[!] HIGH RISK: Projected travel time exceeds available daylight.
    Mandatory headlamps, emergency bivy, and winter thermal gear required.
    Trip postponement recommended unless experienced in night alpine navigation.
============================================================
```

## Computational Requirements

Your program must implement:

1. **Naismith's Rule with BC Mountain Adjustments:**
   - Base pace: $5.0\text{ km/h}$ over flat trail.
   - Elevation penalty: $+1.0\text{ hour}$ for every $600\text{ m}$ of ascent (or $0.1\text{ h}$ per $60\text{ m}$).
   - Terrain modifier: A multiplicative factor ($1.0\times$ for groomed trail, $1.15\times$ for rocky roots, $1.30\times$ for alpine scree/scramble).
   - Fatigue/pack modifier: If pack weight exceeds $20\%$ of hiker body weight, add $10\%$ to total moving time.
2. **Environmental Lapse Rate Calculation:**
   - Standard atmospheric temperature lapse rate: Temperature drops by $6.5^\circ\text{C}$ per $1000\text{ m}$ of elevation gain:

$$T_{\text{summit}} = T_{\text{base}} - \left(6.5 \times \frac{\text{elevation}}{1000}\right)$$

   - Freezing level calculation: Altitude where temperature reaches $0.0^\circ\text{C}$:

$$\text{Freezing Level (m)} = \text{Elevation}_{\text{base}} + \left(\frac{T_{\text{base}}}{6.5} \times 1000\right)$$
3. **Multi-Tier Risk Assessment Logic:**
   - **Hypothermia Risk:** Evaluated from the combination of summit temperature, wind exposure factor, and precipitation volume.
   - **Daylight Hazard:** Compares total travel time against entered daylight hours. If moving time $\ge$ daylight, trigger critical darkness alert.
4. **Defensive Input Validation:**
   - Reject impossible values (negative distances, elevations greater than Mount Waddington at $4019\text{ m}$, temperatures below $-50^\circ\text{C}$).
   - Use structured `if`/`elif`/`else` control flow to validate all user inputs before executing calculations.

## Ethics and Software Reliability: The Cost of False Confidence

In software design, **a false sense of security is more dangerous than an outright crash**. 

If a navigation app underestimates travel time by 3 hours in the North Shore Mountains, hikers may be trapped in sub-zero alpine conditions without shelter. Consider:
- How does your software communicate uncertainty?
- When sensor telemetry or user inputs are ambiguous, should the system default to optimistic or conservative safety ratings?
- Why do SAR organizations in BC emphasize that software tools must never replace human judgment and physical safety gear?

## Milestones & Schedule

- **Day 14 (Launch):** Decomposition on paper. Flowchart all decision branches and write function signatures.
- **Day 15 (Core Algorithms):** Implement Naismith pace calculation and temperature lapse rate models.
- **Day 16 (Risk Engine):** Implement multi-variable risk conditionals and warning triggers.
- **Day 17 (Testing Matrix):** Run structured test cases (see test table below) and fix boundary anomalies.
- **Day 18 (Handover & Demonstration):** Peer walkthrough and submission with code journal reflection.

## Test Matrix

| Test Case | Distance | Elev Gain | Summit Alt | Base Temp | Precip | Expected Time | Expected Warning |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1. Juan de Fuca (Coastal) | 12.0 km | 240 m | 120 m | 16.0°C | 2.0 mm | 2.80 h | LOW / Normal daylight |
| 2. Black Tusk (Alpine) | 29.0 km | 1740 m | 2319 m | 12.0°C | 15.0 mm | 10.38 h | HIGH / Freeze at summit (-3.1°C) |
| 3. Garibaldi Winter | 18.0 km | 1200 m | 1500 m | 2.0°C | 25.0 mm | 6.44 h | EXTREME / Heavy snow & darkness |
| 4. Zero/Negative Distance | -5.0 km | 100 m | 500 m | 10.0°C | 0.0 mm | ERROR | "Distance must be positive" |

## Success Criteria

| Quality | What strong work looks like | What it looks like when it is not there yet |
| --- | --- | --- |
| **Algorithmic Accuracy** | Mathematical models (Naismith, lapse rate, pack ratios) faithfully implemented with correct units. | Calculations produce incorrect results on non-trivial elevation or pace values. |
| **Conditional Logic** | Nested conditionals cleanly evaluate all compound risk states without dead branches or duplicate checks. | Incomplete conditional checks miss boundary risk conditions (e.g. freezing level at summit). |
| **Defensive Validation** | Rejects invalid numerical bounds with clear, respectful error messages. | Crashes on negative numbers or extreme values. |
| **Code Craftsmanship** | PEP 8 compliant, meaningful identifier names (`elevation_gain_m`, `lapse_rate`), modular functions. | Single monolithic block of code, cryptic variable names (`x`, `t1`, `temp2`). |

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D2.1]]

![[D2.3]]

![[D3.1]]

![[D4.2]]

![[D5.2]]

![[D6.1]]

![[S1.1]]

![[K1.1]]

![[K1.8]]

![[K1.9]]

![[K1.11]]

![[K1.15]]

![[T1.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 1, Day 16, during the work period on freezing-level logic, multi-tier hazard warnings, and defensive input gates
  Watch for: how a student works the branching out before typing it — on paper, at the whiteboard, or straight into the editor and then rearranged three times.
  Going well: tries a value right at a threshold the moment the branch is written rather than saving every check for the Day 17 test matrix, and says out loud which case is being tested.
  Stuck: re-runs the whole program to check one condition instead of tracing it by hand; sits with a blank editor for several minutes without reaching for paper, for the Day 14 flowchart, or for a neighbour.
  Record: three columns on the seating chart — traced it, guessed it, needed a prompt — and a word on who you had to prompt and about what.

TALK — Unit 1, Day 17, during the test matrix and boundary testing period
  Ask: "If a hiker enters a summit temperature of 2°C with 25 mm of precipitation at 1500 m, how does your code decide between a high hypothermia risk and an avalanche warning? Walk me through the branch that fires."
  A strong answer names the actual condition and the order things are evaluated in — "the hypothermia check runs first because it can be true at the same time as the avalanche check, so I let both fire" — and can say what would change the answer. A weak one narrates what the screen prints.
  Then: "Your program has just printed HIGH RISK with a 1.5-hour sunset shortfall. What would have to be wrong in the inputs for that advisory to be dangerously optimistic instead?"
  A strong answer picks a real input and follows it through — an under-reported pack weight, a base temperature taken at the trailhead on a warm afternoon, a distance that ignores the approach road — and says what the hiker would do on the strength of the wrong number. A weak one says the program would just be wrong, without anybody in the answer.
  The first checks D2.3 and K1.8 heard out loud: whether the student can trace compound boolean logic without guessing.
  The second checks T1.2: understanding the real-world safety consequences of algorithmic assumptions.
  Record: two sentences per conversation on the daily tracking sheet.

The product evidence is the Python expedition advisory script, test matrix execution results, and reflection entry in the Learning Journey Log.
%%
