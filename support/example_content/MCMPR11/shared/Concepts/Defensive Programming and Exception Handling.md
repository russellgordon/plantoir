---
title: "Defensive Programming and Exception Handling"
publish: true
created: __CREATED__
tags:
  - concept
  - programming
enableToc: true
---
> [!abstract] At a glance
> Murphy's Law in software engineering: anything that can go wrong will go wrong. Defensive programming is the discipline of anticipating unexpected inputs, corrupted sensor data, and missing files, ensuring programs fail gracefully without catastrophic crashes.

## What is Defensive Programming?

Defensive programming assumes that:
1. **User input is unpredictable:** Users will type words when numbers are requested, submit negative quantities, or paste unexpected Unicode emojis.
2. **External resources fail:** Network connections drop, environmental sensors report null bytes during power brownouts, and configuration files get accidentally moved or deleted.
3. **Internal state drifts:** Functions must validate their preconditions before operating on data.

---

## The Two Layers of Defense

### Layer 1: EAFP vs. LBYL in Python

- **LBYL (Look Before You Leap):** Checking conditions explicitly with `if` statements before performing an operation:
  ```python
  if filename in os.listdir() and os.path.getsize(filename) > 0:
      with open(filename) as f:
          data = f.read()
  ```
- **EAFP (Easier to Ask for Forgiveness than Permission):** Python's preferred idiom—attempting the operation inside a structured `try`/`except` block:
  ```python
  try:
      with open(filename, "r", encoding="utf-8") as f:
          data = f.read()
  except FileNotFoundError:
      print(f"[WARN] Weather station telemetry file '{filename}' is missing. Using cached fallback.")
      data = load_fallback_cache()
  except PermissionError:
      print(f"[ERROR] Insufficient permissions to read '{filename}'.")
      raise
  ```

---

## Authoring Custom Exception Hierarchies

In complex systems like the **BC Wildfire Early Warning Dashboard**, generic `Exception` catches obscure bugs. Define domain-specific exceptions:

```python
class TelemetryError(Exception):
    """Base exception for all weather station telemetry errors."""
    pass

class CorruptedPacketError(TelemetryError):
    """Raised when a sensor telemetry packet fails checksum validation."""
    def __init__(self, station_id: str, raw_packet: str):
        super().__init__(f"Station {station_id} emitted corrupt packet: {raw_packet}")
        self.station_id = station_id
        self.raw_packet = raw_packet

class SensorOutOfRangeError(TelemetryError):
    """Raised when physical sensors report impossible meteorological values."""
    pass
```

### Applying Custom Exceptions in Practice

```python
def validate_rh(relative_humidity: float, station_id: str) -> float:
    """Validate relative humidity percentage (0.0% to 100.0%)."""
    if relative_humidity < 0.0 or relative_humidity > 100.0:
        raise SensorOutOfRangeError(
            f"Station {station_id} reported impossible RH: {relative_humidity}% (Valid: 0-100%)"
        )
    return relative_humidity
```

%%curriculum-start%%
## Curriculum connection

![[K1.15]]

![[D5.4]]
%%curriculum-end%%
