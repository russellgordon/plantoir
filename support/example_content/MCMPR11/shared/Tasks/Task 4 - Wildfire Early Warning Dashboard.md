---
title: "Task 4 - BC Wildfire & Community Air Quality Early Warning Dashboard"
publish: true
created: __CREATED__
tags:
  - tasks
  - summative
  - culminating
enableToc: true
---
> [!abstract] At a glance
> Solo or pairs · launched Unit 4, Day 1 and running across 15 working days through Unit 4, Day 17 · a multi-module emergency management system modeled after the BC Wildfire Service and BC Air Quality Health Index · modular decomposition, defensive programming, automated regression test suites, and critical infrastructure ethics · the culminating project of this course.

## What you are making

A multi-module Python software system that processes weather telemetry, computes the **Canadian Forest Fire Weather Index (FWI) System**, forecasts fire behaviour for BC Fire Centres (Kamloops, Cariboo, Prince George, Southeast, Coastal, Northwest), and models **Air Quality Health Index (AQHI)** smoke dispersion for downstream communities.

In British Columbia, wildfires and seasonal smoke are pressing realities. The **2021 Lytton wildfire**, the **2023 record-breaking fire season** (which burned over 2.84 million hectares in BC), and recurring atmospheric smoke events require emergency coordinators to make rapid, data-informed evacuation decisions.

Your software will read multi-station weather telemetry, compute fuel moisture indices, determine hazard levels, generate community smoke advisories, and output automated emergency dispatch summaries.

```
================================================================================
BC WILDFIRE EARLY WARNING SYSTEM — FIRE CENTRE TELEMETRY DASHBOARD v4.1
Reporting Centre: KAMLOOPS FIRE CENTRE (Okanagan / Thompson Zone)
Date: 2024-08-12 16:00:00 PDT | Status: ACTIVE EMERGENCY LEVEL 3
================================================================================

--- STATION METEOROLOGICAL TELEMETRY & FUEL MOISTURE INDICES ---
Station ID   Location        Temp (°C)  RH (%)  Wind (km/h)  Rain (24h)   FFMC    DMC    DC     ISI    BUI    FWI   Danger Class
-------------------------------------------------------------------------------------------------------------------------
KFC-101      Lytton Valley      38.4      12.0     38.0        0.0 mm     94.2   142.0  780.0   28.4  210.5   54.2  EXTREME (5)
KFC-104      Kamloops Airport   34.1      18.0     22.0        0.0 mm     90.1    88.0  540.0   12.8  132.0   31.6  HIGH (4)
KFC-109      Kelowna East       32.0      22.0     15.0        0.0 mm     87.4    64.0  420.0    7.2   98.0   21.4  HIGH (4)
KFC-115      Merritt Ridge      29.5      26.0     31.0        0.0 mm     89.0    75.0  490.0   14.1  114.0   33.2  EXTREME (5)

--- COMMUNITY AIR QUALITY HEALTH INDEX (AQHI) & SMOKE ADVISORY ---
Community        PM2.5 (µg/m³)   AQHI Rating   Health Risk Level    Recommended Public Action
-------------------------------------------------------------------------------------------------
Kamloops City        184.2          10+          VERY HIGH RISK      Cancel outdoor activities; run HEPA air filtration.
Vernon Central       112.0           9           HIGH RISK           At-risk individuals (asthma, seniors) remain indoors.
Kelowna North         78.5           7           HIGH RISK           Reduce strenuous outdoor exertion.
Penticton             34.0           4           MODERATE RISK       No immediate action for general population.

================================================================================
CRITICAL EVACUATION ALERT TRIGGERED:
[ALERT-01] Station KFC-101 (Lytton Valley): FWI = 54.2 with Wind Gusts > 35 km/h.
           Rate of Spread forecast exceeds direct attack capabilities.
           Triggering automated dispatch notification to Thompson-Nicola Regional District.
================================================================================
```

## System Architecture & Module Contracts

Your codebase must be split into distinct, decoupled Python modules:

1. `telemetry_parser.py`: Ingests raw weather station CSV/JSON streams. Validates data bounds and handles corrupted packets.
2. `fwi_engine.py`: Implements the mathematical formulas of the Canadian Forest Fire Weather Index:
   - **FFMC (Fine Fuel Moisture Code):** Moisture of surface litter fuels.
   - **DMC (Duff Moisture Code):** Moisture of loosely compacted organic layers.
   - **DC (Drought Code):** Deep organic layers and seasonal drought indicator.
   - **ISI (Initial Spread Index):** Combines wind speed and FFMC to model rate of fire spread.
   - **BUI (Buildup Index):** Combines DMC and DC to model fuel available for combustion.
   - **FWI (Fire Weather Index):** Overall numerical rating of fire intensity.
3. `air_quality.py`: Evaluates particulate matter ($PM_{2.5}$) and calculates official BC AQHI scales (1 to 10+).
4. `advisory_generator.py`: Formats executive summaries, generates plain-language alerts, and writes export files.
5. `test_suite.py`: An automated test harness containing unit tests and assertions verifying every calculation against official Canadian Forestry Service benchmark tables.

## Critical Infrastructure Failures: Software Reliability Case Studies

In mission-critical software, a defect is not an inconvenience; it can paralyze public safety infrastructure. Two recent events highlight the absolute necessity of rigorous automated testing:

### 1. The CrowdStrike Global Outage (July 2024)
A faulty sensor configuration update (`Channel File 291`) pushed by cybersecurity company CrowdStrike bypassed automated validation checks and crashed 8.5 million Windows computers worldwide. In British Columbia, the outage grounded flights at Vancouver International Airport (YVR) and disrupted computer systems at Vancouver Coastal Health and Fraser Health (preventing access to patient charts) — BC's own 911 emergency calling system stayed operational throughout, unlike systems in some other jurisdictions (Edmonton's 911 call-handling was disrupted the same day), which is itself worth noticing: identical software, different outcomes, depending on what each system depended on.
- **Root Cause:** A mismatch between the number of parameters expected by an engine parser and the parameters supplied in the update file, causing a null pointer memory access violation in kernel space.
- **Lesson for Developers:** Automated validation logic must execute in testing sandboxes *before* configuration files reach production systems.

### 2. The UK Post Office Horizon Scandal (Fujitsu)
Accounting software (Horizon) contained silent bugs that recorded phantom financial shortfalls in subpostmasters' branch accounts. Post Office executives trusted the software over human operators, resulting in over 900 wrongful criminal convictions of innocent people.
- **Lesson for Developers:** Software is never infallible. Transparent audit trails, reproducible logs, and the ability to challenge automated outputs are foundational human rights in digital systems.

## Milestones Across Unit 4 (15 Working Days)

- **Day 1–2 (System Architecture):** Define file structures, module interfaces, and data schemas.
- **Day 3–5 (FWI Engine & Unit Tests):** Implement mathematical index formulas and write automated `assert` tests.
- **Day 6–8 (Air Quality & Weather Parsing):** Build telemetry ingestion and AQHI classification algorithms.
- **Day 9–11 (Integration & Error Recovery):** Connect modules together and implement chaos testing (corrupted data files, missing fields).
- **Day 12–14 (Advisory Output & Code Review):** Polish console formatting, export JSON/CSV advisories, and conduct peer code audit.
- **Day 15 (Handover & Submission):** Deliver final codebase, test report, and software engineering reflection.

## Success Criteria

| Quality | Exemplary (Level 4) | Developing (Level 2) |
| --- | --- | --- |
| **Modular Decomposition** | Codebase cleanly separated into single-responsibility modules with clear contracts and no circular imports. | Monolithic single-file script; tightly coupled logic with global variable leakage. |
| **FWI Calculation Accuracy** | All 6 FWI components (FFMC, DMC, DC, ISI, BUI, FWI) match benchmark reference values to within 0.1% tolerance. | Mathematical formulas contain order-of-operation errors or unit mismatches. |
| **Automated Test Coverage** | Dedicated `test_suite.py` containing $>15$ assertions testing normal, boundary, and extreme meteorological conditions. | Minimal testing; relies on eyeballing console output without automated assertions. |
| **Defensive Architecture** | Handles missing data, malformed CSV records, and extreme weather spikes gracefully without unhandled exceptions. | Crashes immediately on unexpected formatting or missing telemetry fields. |
| **Engineering Ethics** | In-depth, analytical reflection connecting the project to real-world software failures (CrowdStrike, Horizon) and public safety. | Superficial reflection lacking connection to professional software engineering standards. |

%%curriculum-start%%
## Curriculum connection

![[D1.1]]

![[D3.3]]

![[D4.2]]

![[D5.2]]

![[D5.3]]

![[D6.1]]

![[D6.2]]

![[D7.4]]

![[K1.4]]

![[K1.11]]

![[K1.15]]

![[S1.2]]

![[T1.1]]

![[T1.2]]
%%curriculum-end%%
