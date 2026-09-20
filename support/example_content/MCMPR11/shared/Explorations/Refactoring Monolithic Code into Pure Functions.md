---
title: "Refactoring Monolithic Code into Pure Functions"
publish: true
created: __CREATED__
tags:
  - exploration
  - craftsmanship
enableToc: true
---
> [!abstract] At a glance
> Laboratory investigation · taking a 100-line monolithic script and decomposing it into single-responsibility, unit-tested pure functions.

## The Monolith Problem

A "monolithic script" executes everything from top to bottom in one giant block: reading files, calculating math, asking user questions, and formatting output. Monoliths are impossible to test with automated assertions and extremely difficult for a team to maintain.

### Refactoring Guidelines

1. **Identify the Responsibilities:**
   - Input/Ingestion (reading files, user input).
   - Core Business Logic (mathematical algorithms, data transformations).
   - Presentation (formatting tables, printing summaries).
2. **Extract Pure Functions for Logic:**
   - Pure functions take inputs as arguments and return outputs without touching the screen or hard drive.
3. **Write Unit Tests First:**
   - Before moving code, write an assertion for the mathematical formula to ensure the refactored function preserves identical behavior.

%%curriculum-start%%
## Curriculum connection

![[K1.5]]

![[K1.3]]
%%curriculum-end%%
