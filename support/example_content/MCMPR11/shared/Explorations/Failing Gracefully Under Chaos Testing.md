---
title: "Failing Gracefully Under Chaos Testing"
publish: true
created: __CREATED__
tags:
  - exploration
  - testing
enableToc: true
---
> [!abstract] At a glance
> Laboratory investigation · testing telemetry parsers against intentionally corrupted, delayed, and malformed environmental sensor streams.

## The Chaos Engineering Challenge

In the real world, telemetry sensors deployed on buoys in the Salish Sea or mountaintops in the Coast Range do not transmit pristine data. They suffer battery dropouts, freezing temperatures, radio interference, and corrupted packets.

Your task is to take a basic telemetry parser and subject it to our **Chaos Stream Simulator**.

### The Vulnerable Parser

```python
def parse_telemetry_line(raw_line: str):
    parts = raw_line.strip().split(",")
    station_id = parts[0]
    timestamp = parts[1]
    temperature = float(parts[2])
    salinity = float(parts[3])
    return {
        "station": station_id,
        "time": timestamp,
        "temp": temperature,
        "salinity": salinity
    }
```

### The Chaos Input Stream

```text
# Packet 1: Normal
VENUS-01,2024-09-01T12:00:00Z,10.5,29.4
# Packet 2: Sensor dropout (blank salinity)
VENUS-01,2024-09-01T13:00:00Z,10.8,
# Packet 3: Truncated radio packet
VENUS-01,2024-09-01T14:00:00Z
# Packet 4: Sensor freeze error code
VENUS-01,2024-09-01T15:00:00Z,-999.0,29.8
# Packet 5: Malformed corrupt string
CORRUPT_NULL_BYTE_STREAM_ERR_0x7F
```

### Your Mission:
1. Run the vulnerable parser on the chaos stream and record every traceback.
2. Refactor the parser to quarantine bad packets into an `error_log` list while successfully returning clean records for valid rows.

%%curriculum-start%%
## Curriculum connection

![[D5.4]]

![[K1.15]]
%%curriculum-end%%
