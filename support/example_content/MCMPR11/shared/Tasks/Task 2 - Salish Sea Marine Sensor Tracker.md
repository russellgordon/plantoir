---
title: "Task 2 - Salish Sea Marine Sensor Stream & Telemetry Analyzer"
publish: true
created: __CREATED__
tags:
  - tasks
  - summative
enableToc: true
---
> [!abstract] At a glance
> Pairs · launched in Unit 2, Day 18 and due Unit 2, Day 22 · telemetry stream analyzer for Ocean Networks Canada and DFO marine observation stations · batch processing, rolling window statistics, anomaly detection, and ethical data handling.

## What you are making

A Python telemetry data analysis engine that ingests, cleans, and analyzes environmental sensor streams from marine observation stations in the **Salish Sea** (including the **Strait of Georgia VENUS observatory**, **Saanich Inlet subsea node**, and **Haro Strait acoustic buoy**).

The Salish Sea is an ecologically vulnerable marine corridor facing urban runoff, ocean acidification, warming events (marine heatwaves), and heavy vessel traffic that impacts the endangered **Southern Resident Killer Whale** population. High-frequency oceanographic sensors record gigabytes of telemetry every week. Scientists need automated software to detect environmental anomalies—such as sudden drops in dissolved oxygen (hypoxia) or dangerous surface temperature spikes.

```
======================================================================
SALISH SEA OCEAN OBSERVATORY — DATA TELEMETRY PIPELINE v2.4
Station: VENUS-SOG-CENTRAL (Depth: 170m) | Timeframe: 2024-09-01 to 2024-09-07
======================================================================
[INFO] Reading sensor stream 'sog_telemetry_2024_09.csv'...
[INFO] Parsed 1,008 hourly telemetry records.
[WARN] 14 corrupt or dropped sensor packets identified and quarantined.

--- ENVIRONMENTAL METRIC SUMMARY ---
Metric                 Minimum     Average     Maximum     Anomaly Count
----------------------------------------------------------------------
Water Temp (°C)           8.42       10.85       15.20      12 (Marine Heatwave)
Salinity (PSU)           26.10       29.40       31.20       4 (Atmospheric River Runoff)
Dissolved O2 (mg/L)       2.10        5.80        8.40      18 (Hypoxic Event Detected)
Acoustic Noise (dB)      82.40      104.30      138.90      31 (Critical Vessel Noise)

--- ANOMALY INCIDENT REPORT ---
Incident 1: 2024-09-03 04:00:00 UTC
  - Trigger: Critical Hypoxia (Dissolved O2: 2.10 mg/L < threshold 3.0 mg/L)
  - Impact:  Benthic marine organisms at risk of asphyxiation in Saanich basin.

Incident 2: 2024-09-05 14:00:00 UTC
  - Trigger: Extreme Underwater Noise (138.90 dB in 100-1000 Hz whale band)
  - Impact:  Vessel speed restriction violation flagged for DFO Orca protection corridor.

PIPELINE OUTPUT GENERATED:
-> Cleaned dataset exported to: 'output/sog_clean_telemetry.csv'
-> Incident log written to:      'output/marine_incident_report.json'
======================================================================
```

## Computational Requirements

Your data pipeline must implement:

1. **Structured Data Ingestion:**
   - Parse CSV/TSV data streams where each record contains: `timestamp`, `station_id`, `temperature_c`, `salinity_psu`, `dissolved_o2`, and `acoustic_noise_db`.
   - Implement graceful recovery for malformed lines, missing fields, or out-of-range sensor noise (e.g. sensor disconnect reporting `-999.0`).
2. **Definite Iteration and Rolling Statistics:**
   - Maintain lists for each measurement dimension.
   - Compute descriptive statistics manually (using explicit loops rather than high-level black-box functions): mean, minimum, maximum, and rolling 24-hour moving averages.
3. **Threshold Anomaly Identification:**
   - **Marine Heatwave Alert:** Surface temperature $> 2.5^\circ\text{C}$ above seasonal baseline for $\ge 48$ consecutive hours.
   - **Hypoxia Event:** Dissolved Oxygen $< 3.0\text{ mg/L}$ (severe hypoxia $< 1.4\text{ mg/L}$).
   - **Freshwater Influx:** Salinity $< 27.0\text{ PSU}$ indicating massive Fraser River freshet or atmospheric river flood runoff.
   - **Acoustic Disturbance:** Ambient vessel noise $> 120.0\text{ dB}$ in Southern Resident Killer Whale feeding zones.
4. **Structured Incident Export:**
   - Output a clean tabular report to the console and export formatted incident records to an output file.

## Case Study in Software Ethics: The Volkswagen Diesel Defeat Device

In 2015, the US Environmental Protection Agency discovered that Volkswagen had installed software in millions of diesel vehicles designed specifically to detect when the car was undergoing laboratory emissions testing (by monitoring steering wheel angle, engine run time, vehicle speed, and barometric pressure). When the software detected test conditions, it dialed up emissions controls to pass the test; during real-world driving, it disabled controls, emitting up to 40 times the legal limit of nitrogen oxides ($NO_x$).

**The Crucial Insight for Computer Programmers:**
The defeat device was not a mechanical breakdown or an accidental bug; it was **deliberate, carefully engineered code authored by software developers**.

Discuss with your partner and answer in your [[Learning Journey Log]]:
1. If a telemetry system detects that an industrial plant or vessel is exceeding environmental limits, who owns the data?
2. What are the ethical implications if a programmer is asked to write "smoothing filters" that conceal sensor spikes during official inspection periods?
3. How do professional codes of ethics (such as the ACM Code of Ethics or Engineers and Geoscientists BC) protect the public interest over employer directives?

## Success Criteria

| Quality | Exemplary (Level 4) | Developing (Level 2) |
| --- | --- | --- |
| **Data Parsing & Cleaning** | Flawlessly parses CSV data; filters out missing values, NaN markers, and sensor disconnect codes (`-999.0`) without crashing. | Crashes when encountering empty lines, corrupted numbers, or missing CSV headers. |
| **Statistical Computations** | Accumulator loops calculate precise minimum, maximum, mean, and moving averages using clean, readable algorithms. | Inaccurate statistical math; incorrect accumulator formulas. |
| **Anomaly Filtering** | Correctly detects sustained multi-hour threshold violations and flags ecological incidents accurately. | Misses anomaly duration logic (triggers on single-point noise instead of sustained thresholds). |
| **Ethical Reflection** | Nuanced analysis of data integrity, sensor tampering, and the developer's responsibility to scientific truth. | Superficial reflection that treats software ethics as purely someone else's responsibility. |

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D2.2]]

![[D3.3]]

![[D4.4]]

![[D5.1]]

![[D6.2]]

![[K1.2]]

![[K1.6]]

![[K1.9]]

![[K1.15]]

![[T1.2]]

![[T1.4]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 2, Day 20, while pairs are implementing list accumulators and rolling window calculations
  Watch for: how partners divide driver and navigator roles when writing the 24-hour moving average algorithm.
  Going well: accumulator variables are cleanly initialized outside loops, and index arithmetic is checked against list boundaries before slicing.
  Stuck: off-by-one errors when computing moving averages, or attempting to modify the data list in-place while iterating over it.
  Record: mark on the seating plan which pairs successfully quarantined corrupted sensor rows without halting the data ingestion pipeline.

TALK — Unit 2, Day 21, during the anomaly detection testing and ethics case study discussion
  Ask: "How does your pipeline distinguish between a single faulty sensor reading and a sustained 48-hour marine heatwave?"
  Then: "If your employer asked you to smooth out dissolved oxygen telemetry to hide a localized industrial fish kill, what code of ethics governs your response?"
  The first assesses D4.4 and K1.6: explaining nested list filtering and statistical threshold algorithms verbally.
  The second assesses T1.2 and T1.4: professional responsibility, developer whistleblowing, and public data integrity.
  Record: note key arguments and student reasoning in the course tracking log.

The product evidence is the Python data pipeline script, exported cleaned CSV and incident JSON files, and reflection in the Learning Journey Log.
%%
