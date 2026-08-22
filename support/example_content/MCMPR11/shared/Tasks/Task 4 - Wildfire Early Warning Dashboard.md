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
> Solo or pairs · launched Unit 4, Day 3 and running across 14 working days through Unit 4, Day 16 · a multi-module emergency management system modeled after the BC Wildfire Service and BC Air Quality Health Index · modular decomposition, defensive programming, automated regression test suites, and critical infrastructure ethics · the culminating project of this course.

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

## Milestones Across Unit 4 (14 Working Days)

Every day below is a class day in Unit 4, so this list and your class pages
name the same day.

- **Days 3–4 (System Architecture):** Define file structures, module interfaces, and data schemas, and set up the repository.
- **Days 5–7 (FWI Engine & Unit Tests):** Implement the six index formulas, check them against the Canadian Forestry Service reference tables, and write the automated `assert` tests. Milestone 1 check on Day 7.
- **Days 8–9 (Air Quality & Failure Handling):** Build AQHI classification and smoke dispersion, then run chaos testing against dropouts, corrupted rows, and frozen sensors.
- **Days 10–11 (Integration & Regression Safety):** Connect the modules, build the end-to-end regression harness, and remove circular dependencies. Milestone 2 check on Day 11.
- **Days 12–13 (Advisory Output & Code Review):** Polish console formatting, export JSON/CSV advisories, and take a classmate's audit of your codebase.
- **Day 14 (Handover Assembly):** Package the code, the test harness, and user documentation, and test the guide on somebody who has not seen the project.
- **Days 15–16 (Demonstration & Post-Mortem):** Run the pipeline on unannounced meteorological datasets, take peer critique, and write the architecture post-mortem.

**The list above is a plan, and no fourteen-day build has ever survived
one intact.** Something will be harder than it looks: a reference table
that disagrees with your formula, a library that does not do what its
documentation implies, a data schema you chose on Day 3 that fights you
on Day 10. When that happens, changing the plan is the correct move and
abandoning the milestone is not — you are expected to change tools,
change the data structure, or reorder the work, and then to say so.

Each milestone check therefore asks two questions, and the second is the
one worth preparing: *what runs now*, and *what did you change since the
last check, and why*. A schema replaced because the first one made every
lookup a search is a good answer. A schema replaced because the code
"felt messy" is an answer that needs a measurement behind it. Record
each of these in [[Learning Journey Log]] as you go, with the commit
that carried it — reconstructing on Day 14 what you decided on Day 8 is
guesswork, and it shows.

## Success Criteria

| Quality | What strong work looks like | What it looks like when it is not there yet |
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

![[D3.4]]

![[D4.2]]

![[D4.4]]

![[D5.2]]

![[D5.3]]

![[D6.1]]

![[D6.2]]

![[D7.1]]

![[D7.4]]

![[K1.4]]

![[K1.11]]

![[K1.15]]

![[S1.2]]

![[T1.1]]

![[T1.2]]
%%curriculum-end%%

%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 4, Day 7, at the Milestone 1 check, while students write assertions in test_suite.py and verify the Fire Weather Index engine against the reference tables
  Watch for: how a student chooses what to assert — the test that would catch a real mistake, or the test that is certain to pass.
  Going well: opens the Canadian Forestry Service reference table and picks a benchmark row on purpose; runs the suite after each new assertion instead of writing fifteen and hoping.
  Stuck: only asserts values already seen to pass; cannot say which module a failure came from, and starts changing lines at random to see what happens.
  Record: on the milestone board, tick who took a red test to green inside the period — the sequence matters more than the final count.

TALK — Unit 4, Day 11, at the Milestone 2 integration check and instructor review
  Ask: "Walk me through how your test suite proves the Initial Spread Index is right when the wind gusts are extreme."
  A strong answer names the specific case and why that one — the wind speed where the exponential term starts to dominate — and says where the expected number came from, a reference table or a calculation done by hand. A weak one says "it passes".
  Then: "How did the CrowdStrike outage or the Horizon scandal change what your code does when it meets bad data?"
  A strong answer points at their own error handling — a quarantined row logged rather than silently dropped, a fallback state the advisory labels as stale — and ties it to the failure it came from: an unvalidated update that reached production, or an output nobody was allowed to challenge. A weak one retells the case study without touching the program.
  The first assesses D5.2 and K1.15: designing a test that could actually fail, and defending the numbers it checks against.
  The second assesses T1.2 and D7.4: naming the unintended consequences of a design choice and what the student changed in their own process because of it.
  Record: two sentences per team in the culminating evaluation record.

The product evidence is the multi-module Python codebase, automated test suite, sample exported incident advisories, and technical reflection in the Learning Journey Log.
%%
