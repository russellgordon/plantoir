---
title: "Designing Test Plans and Automated Assertions"
publish: true
created: __CREATED__
tags:
  - concept
  - testing
enableToc: true
---
> [!abstract] At a glance
> Untested code is broken code. Professional programmers do not rely on eyeballing console output; they construct systematic test matrices and author automated test harnesses that prove software correctness under stress.

## The Anatomy of a Systematic Test Plan

A complete test plan exercises code across three distinct categories of input:

1. **Normal (Equivalence Partition) Cases:** Typical, expected values that represent standard user interactions.
2. **Boundary (Edge) Cases:** Values at the exact thresholds where program behavior transitions (e.g. $0$, minimum limits, maximum limits, off-by-one indices).
3. **Error (Chaos/Exception) Cases:** Invalid, out-of-range, or malformed data that must be safely rejected without crashing.

### Example: Testing a Temperature Lapse Rate Function

```python
def summit_temperature(base_temp: float, elevation_m: float) -> float:
    """Calculate summit temperature using standard atmospheric lapse rate (-6.5C / 1000m)."""
    if elevation_m < 0:
        raise ValueError("Elevation cannot be negative.")
    if elevation_m > 8848:
        raise ValueError("Elevation exceeds Mount Everest summit height.")
    return round(base_temp - (6.5 * (elevation_m / 1000.0)), 2)
```

### Test Matrix

| Test ID | Category | Input: Base Temp | Input: Elevation | Expected Output | Rationale |
| --- | --- | --- | --- | --- | --- |
| `TC-01` | Normal | 15.0°C | 1000.0 m | 8.5°C | Standard 1 km climb ($15.0 - 6.5$). |
| `TC-02` | Boundary | 20.0°C | 0.0 m | 20.0°C | Sea-level baseline (zero elevation change). |
| `TC-03` | Boundary | 0.0°C | 2000.0 m | -13.0°C | Freezing base with severe alpine drop. |
| `TC-04` | Error | 10.0°C | -50.0 m | `ValueError` | Sub-sea level elevation rejected. |
| `TC-05` | Error | 10.0°C | 10,000.0 m | `ValueError` | Impossibly high terrestrial elevation rejected. |

---

## Authoring Automated Assertions in Python

Rather than manually inspecting printed results, write automated assertion scripts:

```python
def run_test_suite():
    print("Executing automated test suite...")
    
    # TC-01: Normal case
    assert summit_temperature(15.0, 1000.0) == 8.5, "TC-01 failed: Expected 8.5C"
    
    # TC-02: Boundary at zero elevation
    assert summit_temperature(20.0, 0.0) == 20.0, "TC-02 failed: Expected 20.0C at sea level"
    
    # TC-03: Alpine freeze
    assert summit_temperature(0.0, 2000.0) == -13.0, "TC-03 failed: Expected -13.0C"
    
    # TC-04: Negative elevation exception
    try:
        summit_temperature(10.0, -100.0)
        assert False, "TC-04 failed: Expected ValueError for negative elevation"
    except ValueError:
        pass  # Test passes because exception was correctly raised
        
    print("✅ All 4 test assertions passed successfully.")

if __name__ == "__main__":
    run_test_suite()
```

## Regression Testing: Guarding Against Silent Breakages

A **regression** occurs when a bug fix or new feature quietly breaks an existing, previously working feature. Automated test suites serve as a protective safety net: every time you modify a function, you re-run your test harness in seconds to guarantee zero regressions.

%%curriculum-start%%
## Curriculum connection

![[D5.2]]

![[K1.15]]
%%curriculum-end%%
