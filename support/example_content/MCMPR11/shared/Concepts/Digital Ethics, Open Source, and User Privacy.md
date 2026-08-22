---
title: "Digital Ethics, Open Source, and User Privacy"
publish: true
created: __CREATED__
tags:
  - concept
  - ethics
enableToc: true
---
> [!abstract] At a glance
> Software is not neutral. Code embodies the values, oversights, and incentives of the humans who author it. We examine the ethical responsibilities of computer programmers, the history of software disasters, open source licensing models, and Indigenous data sovereignty.

## Why Software Ethics Matters

Every line of code you write makes assumptions about who will use the software, what conditions it will operate under, and who might be harmed when it fails. In modern society, software controls medical infusion pumps, railway switches, power grids, financial records, and environmental monitoring networks.

When a bridge collapses, civil engineers face legal and professional liability. In computer programming, software developers have historically operated with less formal regulation—making **personal ethics, professional codes of conduct, and institutional rigor** even more critical.

---

## Landmark Software Disasters & Ethical Lessons

### 1. The Volkswagen Diesel "Defeat Device" (2015)
- **The Context:** German automaker Volkswagen sought to market "clean diesel" vehicles in North America that met strict Environmental Protection Agency (EPA) nitrogen oxide ($NO_x$) limits while maintaining high fuel economy and acceleration.
- **The Software Cheat:** Engineers wrote an engine control algorithm that monitored steering angle, wheel speed, and atmospheric pressure. When the software recognized the specific drive cycle of an EPA emissions laboratory test, it engaged full pollution controls. During ordinary road driving, the software disabled these controls to boost performance, spewing up to 40 times the legal limit of smog-forming toxins into the air.
- **The Ethical Takeaway:** The defeat device was not a glitch—it was engineered intentionally by software developers obeying corporate mandates. Software engineers must adhere to professional codes of ethics (such as the ACM Code of Ethics) which state: *A computing professional should avoid harm and never knowingly create deceptive software.*

### 2. The Boeing 737 MAX MCAS Crashes (2018–2019)
- **The Context:** To compete with Airbus, Boeing installed larger, more fuel-efficient engines on the 737 airframe, changing the aircraft's aerodynamic pitch. To compensate, engineers designed MCAS (Maneuvering Characteristics Augmentation System) software to automatically push the aircraft's nose down.
- **The Software Failure:** MCAS relied on a **single Angle-of-Attack (AoA) sensor**. When that sensor malfunctioned on Lion Air Flight 610 and Ethiopian Airlines Flight 302, the software repeatedly forced the planes into fatal dives, despite pilot efforts to pull up. Furthermore, Boeing did not include descriptions of MCAS in the flight crew operating manuals to avoid costly simulator retraining requirements.
- **The Ethical Takeaway:** Critical safety-critical systems must never have single points of failure, and automated software overrides must always be transparent to human operators.

### 3. The UK Post Office Horizon Scandal (Fujitsu)
- **The Context:** Between 1999 and 2015, the UK Post Office prosecuted over 900 local subpostmasters for theft and false accounting after their computerized accounting system (Horizon) showed unexplained financial shortfalls.
- **The Software Failure:** Horizon contained severe database synchronization bugs and silent transaction errors. Despite internal knowledge of these software defects, Post Office and Fujitsu leadership maintained in court that the computer system was "robust and infallible," ruining innocent lives.
- **The Ethical Takeaway:** Organizations and developers must never treat computer systems as infallible, and automated logs must be accessible and auditable when human liberty and livelihoods are at stake.

### 4. The CrowdStrike Global Outage (July 2024)
- **The Context:** A single flawed configuration update deployed by cybersecurity provider CrowdStrike to its Falcon sensor caused 8.5 million Windows computers to blue-screen, halting air travel, hospital surgeries, and 911 dispatch across the globe.
- **The Ethical Takeaway:** Deployment pipelines must have rigorous sandboxing, gradual rollouts (canary releases), and automated assertion gates.

---

## Indigenous Data Sovereignty: The OCAP® Principles

When working with data from First Nations communities in British Columbia—including oral histories, traditional ecological knowledge, and language recordings—software developers must recognize that data is not merely a free public resource.

The **First Nations Information Governance Centre (FNIGC)** established the **OCAP® principles**:

| Principle | Meaning in Software Engineering |
| --- | --- |
| **Ownership** | The community owns its cultural and linguistic data collectively. Software authors do not acquire copyright over cultural assets. |
| **Control** | First Nations have the right to control how their data is gathered, stored, and utilized. |
| **Access** | The community decides who may access specific information (e.g. sacred stories may be restricted to community members). |
| **Possession** | Physical stewardship. Data must be stored where the community can manage and retrieve it, free from proprietary lock-in. |

---

## Open Source Licensing Models

Choosing a software license determines how others can use, modify, and redistribute your code:

- **Permissive Licenses (MIT, Apache 2.0, BSD):** Grants anyone the right to use, copy, modify, merge, publish, and even sell your code in proprietary applications with minimal restrictions (only requiring copyright attribution).
- **Copyleft Licenses (GNU General Public License / GPL):** Requires that any modified versions or derivative works of your software must also be released under the same open-source license. Prevents commercial companies from taking community code proprietary.
- **Public Domain (CC0 / Unlicense):** Total waiver of copyright.

%%curriculum-start%%
## Curriculum connection

![[D4.3]]

![[T1.2]]

![[T1.4]]

![[K1.17]]
%%curriculum-end%%
