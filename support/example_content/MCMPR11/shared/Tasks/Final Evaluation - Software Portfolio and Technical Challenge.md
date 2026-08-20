---
title: "Final Evaluation - Software Portfolio and Technical Challenge"
publish: true
created: __CREATED__
tags:
  - tasks
  - summative
  - final-evaluation
enableToc: true
---
> [!abstract] At a glance
> Solo · 3.0-hour final evaluation · Part A: Code Review & Defect Analysis (45 min) · Part B: Emergency Relief Logistics Challenge (75 min) · Part C: Software Ethics, Public Safety & Developer Liability Essay (60 min) · cumulative demonstration of Computer Programming 11 standards.

## Overview of the Final Evaluation

The Computer Programming 11 Final Evaluation assesses your ability to read, debug, engineer, and ethically critique software systems under realistic technical constraints.

---

## Part A: Code Review & Defect Analysis (45 Minutes)

You are handed a legacy Python script written for a BC municipal water reservoir monitoring station in the Okanagan Valley. The script is supposed to monitor reservoir depth, calculate discharge rates through spillway gates, and flag flood stage alerts. However, the municipal engineers report that during heavy spring snowmelt (freshet), the script produced erratic warnings and crashed.

### The Broken Legacy Code

```python
# BC Municipal Water District - Reservoir Telemetry Monitor
def check_reservoir(station_name, readings, threshold):
    print("Processing station: " + station_name)
    total = 0
    max_depth = 0
    anomalies = []
    
    # Process readings list
    for i in range(len(readings)):
        val = readings[i]
        total = total + val
        if val > max_depth:
            max_depth = val
        if val >= threshold:
            anomalies.append(i)
            
    avg_depth = total / len(readings)
    
    # Calculate spillway discharge status
    if avg_depth > 18.0:
        status = "CRITICAL: Open Emergency Spillway"
    elif avg_depth > 14.0:
        status = "ELEVATED: Standard Discharge Active"
    else:
        status = "NORMAL: Gates Closed"
        
    return {
        "station": station_name,
        "average": avg_depth,
        "peak": max_depth,
        "flood_hours": len(anomalies),
        "status": status
    }
```

### Your Tasks for Part A:
1. **Identify 3 latent software bugs or vulnerabilities** in this script:
   - What happens if `readings` is an empty list (e.g. sensor telemetry blackout)?
   - What happens if `readings` contains negative numbers due to a frozen pressure transducer?
   - How does string concatenation in the print statement fail if `station_name` is passed as a numerical ID?
2. **Refactor the function** to be robust, defensive, and PEP 8 compliant, including docstrings, type hinting, and custom exception handling.

---

## Part B: Live Technical Challenge — Emergency Flood Logistics Dispatcher (75 Minutes)

### Scenario
During an atmospheric river event in Southwestern British Columbia, emergency sandbag pallets and water extraction pumps must be dispatched from three regional supply hubs (Surrey, Abbotsford, Hope) to flooded communities across the Fraser Valley.

### Specifications
Write a modular Python program `flood_dispatch.py` that:
1. Maintains supply inventory for each hub (Sandbags, Industrial Pumps, Emergency Generators) using a dictionary.
2. Ingests community requisition requests (Community Name, Urgency Tier 1–3, Requisition Quantities).
3. Allocates supplies prioritizing Tier 1 (Critical Infrastructure at immediate breach risk) over Tier 2 and 3.
4. Decrements hub inventories and flags unfulfilled requests with detailed shortfalls.
5. Employs modular design with pure helper functions and includes at least 3 automated `assert` tests verifying edge-case allocations.

---

## Part C: Technical Essay — Software Ethics, Public Safety & Developer Liability (60 Minutes)

Choose **two** of the following real-world software engineering ethical crises and write a structured, 500-word comparative essay:

1. **The Volkswagen Diesel "Defeat Device" (2015):** Software deliberately programmed to circumvent regulatory environmental standards.
2. **The Boeing 737 MAX MCAS Flight Control Failures (2018–2019):** Single angle-of-attack sensor dependency, lack of sensor disagreement warnings, and failure to document automated override behaviors in pilot manuals.
3. **The UK Post Office Horizon Scandal (Fujitsu, 2000–2024):** Flawed financial accounting software that produced phantom shortfalls, resulting in false criminal convictions due to blind institutional trust in computer output.
4. **The CrowdStrike Global IT Outage (July 2024):** Unvalidated kernel-level configuration update deployment causing worldwide airport, hospital, and emergency dispatch crashes.

### Essay Prompts to Address:
- What technical shortcuts, institutional pressures, or design flaws caused the crisis?
- What was the ethical responsibility of the individual software developers who authored, tested, and reviewed the code?
- How should modern software development organizations implement peer review, independent auditing, and whistleblower protections to prevent similar catastrophes?

---

## Assessment Matrix

| Section | Weight | Focus Standards |
| --- | --- | --- |
| **Part A: Code Review & Refactoring** | 25% | [[K1.15\|test cases]] and defensive rewriting, [[D2.3\|constraints]] on valid input |
| **Part B: Logistics Dispatch Challenge** | 45% | [[K1.8\|control structures and loops]], [[K1.11\|translating a spec into source code]] |
| **Part C: Software Ethics Essay** | 30% | [[T1.2\|unintended negative consequences]], [[T1.3\|technology and societal change]], [[T1.4\|cultural and ethical positions]] |

%%curriculum-start%%
## Curriculum connection

![[D2.3]]

![[D3.3]]

![[D5.2]]

![[K1.8]]

![[K1.11]]

![[K1.15]]

![[T1.2]]

![[T1.3]]

![[T1.4]]
%%curriculum-end%%
