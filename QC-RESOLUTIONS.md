# Example-content QC pass — resolutions and progress log

**Date:** 2026-08-21 · **Branch:** `bc-curriculum` · **Scope:** all 38 payloads in `support/example_content/`

---

## Priority 1 — Resolutions

### 1.1 Coverage depth: SBI4U once-only expectations (29 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across SBI4U by ensuring all 69 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (investigations, concept summaries, exercises, discussions, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md`.

#### Baseline Findings (SBI4U)
- Total expectations: 69 specific expectations (`A1.1` to `F3.5`)
- Addressed only once (29 codes): `A1.2, A1.3, A1.4, A1.7, A2.2, B1.1, B1.2, B2.1, B2.2, B3.2, B3.3, B3.4, B3.5, C1.1, C1.2, C3.4, D2.1, D2.3, D2.4, D3.2, D3.3, D3.5, D3.7, E1.2, E2.3, E2.4, F2.3, F3.3, F3.4`
- Unlinked tutorial with transclusion: `shared/Tutorials/Using a Microscope.md` (carried `A1.2`)
- Duplicate transclusion in single file: `shared/Investigations/Sampling a Population.md` (had two `![[F2.3]]`)

#### Actions Completed

1. **Exercises Enhancement (`shared/Exercises/`)**:
   - `Biochemistry Practice.md`: Added questions 6–8 (immobilized lactase, potato tissue osmometry, condensation/hydrolysis) and curriculum block for `B1.1`, `B2.1`, `B2.2`, `B3.2`, `B3.3`, `B3.4`, `B3.5`.
   - `Metabolism Practice.md`: Added questions 6–8 (microbial bioremediation, chloroplast vs mitochondria chemiosmosis energetics, mitochondrial myopathies/MELAS) and curriculum block for `C1.1`, `C1.2`, `C3.1`, `C3.2`, `C3.3`, `C3.4`.
   - `Molecular Genetics Practice.md`: Added questions 6–9 (DNA vs RNA chemical stability, DNA extraction chemical mechanisms, Hershey-Chase bacteriophage experiment, PCR & Bt corn) and curriculum block for `D2.1`, `D2.3`, `D2.4`, `D3.2`, `D3.3`, `D3.4`, `D3.5`, `D3.7`.
   - `Homeostasis Practice.md`: Added questions 6–8 (endocrine disruptors/BPA/synthetic estrogens, isopod kinesis/taxis in choice chambers, ADH osmoregulation loop) and curriculum block for `E1.2`, `E2.1`, `E2.2`, `E2.3`, `E2.4`, `E3.1`, `E3.2`, `E3.3`.
   - `Population Practice.md`: Added questions 6–8 (Lotka-Volterra predator-prey lag, 10% trophic efficiency & human food security, population age-structure momentum) and curriculum block for `F1.1`, `F1.2`, `F2.1`, `F2.2`, `F2.3`, `F3.1`, `F3.2`, `F3.3`, `F3.4`.

2. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `Proteins and Enzymes.md`: Added section on Canadian biochemist Maud Menten (acknowledging curriculum spelling *Maude Menten*) (`A2.2`), industrial/pharmaceutical applications (`B1.1`), and transclusions `A2.2, B1.1, B2.1, B2.3, B2.4, B3.2, B3.3, B3.4, B3.5`.
   - `Carbohydrates and Lipids.md`: Enriched functional groups and reactions (ester/glycosidic linkages, condensation, hydrolysis), transclusions `B3.2, B3.3, B3.5`.
   - `Nucleic Acids.md`: Enriched functional groups, DNA/RNA chemical comparison, phosphodiester linkages, transclusions `B3.2, B3.3, B3.5, D3.2`.
   - `Water and Life.md`: Transclusions `B2.1, B3.1`.
   - `Membranes and Transport.md`: Added liposomes/targeted drug delivery (`B1.2`), plant tissue osmometry (`B2.2`), transport terminology (`B2.1`), transclusions `B1.2, B2.1, B2.2, B2.5, B3.6, C1.2`.
   - `Cellular Respiration.md`: Added exercise physiology/diet/mitochondrial disorders (`C1.2`), microbial metabolism in bioremediation (`C1.1`), transclusions `C1.1, C1.2, C2.2, C3.1, C3.2, C3.4`.
   - `Photosynthesis in Detail.md`: Added ecosystem energy flow and global carbon cycling (`C1.1`), transclusions `C1.1, C2.3, C3.3, C3.4`.
   - `DNA Replication in Detail.md`: Added historical discoveries (Meselson-Stahl $\ce{^{15}N}$, Griffith, Avery-MacLeod-McCarty, Hershey-Chase $\ce{^{32}P}$) (`D3.7`), transclusions `D2.1, D3.1, D3.2, D3.7`.
   - `Transcription and Translation.md`: Added ribosome subunit structure and translation factors (`D2.4`), transclusions `D2.1, D2.2, D2.4, D3.2, D3.3`.
   - `Regulating Gene Expression.md`: Added Jacob & Monod discovery (`D3.7`), prokaryotic operon switch vs eukaryotic chromatin/epigenetic control (`D3.3`), transclusions `D3.3, D3.6, D3.7`.
   - `Mutations.md`: Transclusions `D3.4, D3.5`.
   - `Biotechnology.md`: Transclusions `B1.2, D1.1, D1.2, D3.5`.
   - `The Endocrine System.md`: Added Canadian discovery of insulin (Banting, Best, Collip, Macleod) (`A2.2`), environmental endocrine disruptors (`E1.2`), transclusions `A2.2, E1.2, E2.3, E3.3`.
   - `Kidneys and Water Balance.md`: Transclusions `E2.1, E3.3`.
   - `The Nervous System.md`: Added invertebrate response mechanisms (giant axons, taxis/kinesis) (`E2.4`), transclusions `E2.2, E2.4, E3.2`.
   - `Homeostasis and Feedback.md`: Transclusions `E2.1, E2.3, E3.1`.
   - `Population Growth.md`: Added fecundity and fluctuation mechanisms (`F3.3`), simulation connection (`F2.3`), transclusions `F2.1, F2.3, F3.1, F3.3`.
   - `Interactions Between Species.md`: Transclusions `F3.2, F3.3, F3.5`.
   - `Human Population and Sustainability.md`: Transclusions `F1.1, F1.2, F3.4`.

3. **Investigations & Lab Protocols (`shared/Investigations/`)**:
   - `Extracting DNA.md`: Created new investigation on isolating plant genomic DNA with detergent lysis, protease digestion, and ice-cold ethanol precipitation (`A1.2, A1.4, D2.3`).
   - `Enzyme Activity.md`: Transclusions `A1.4, A1.8, B2.3, B2.4, B3.4`.
   - `Osmosis in Plant Tissue.md`: Transclusions `A1.2, B2.2, B2.5, B3.6`.
   - `Gel Electrophoresis.md`: Transclusions `A1.4, A1.6`.
   - `Modelling Molecular Genetics.md`: Transclusions `A1.2, D2.1, D2.2, D2.4, D3.4`.
   - `Heart Rate and Recovery.md`: Transclusions `A1.2, E2.1, E2.3, E3.1`.
   - `Reaction Time and the Nervous System.md`: Transclusions `A1.2, E2.2, E2.4, E3.2`.
   - `Sampling a Population.md`: Deduplicated `F2.3`, transclusions `A1.5, F2.2, F2.3`.
   - `Modelling Population Growth.md`: Transclusions `F2.1, F2.2, F2.3, F3.1, F3.3`.

4. **Tasks & Summative Evaluations (`shared/Tasks/`)**:
   - `Biotechnology Brief.md`: Transclusions `A1.3, A1.7, A1.9, A2.1, B1.2, D1.1, D1.2, D3.5, D3.6`.
   - `Enzyme Investigation.md`: Transclusions `A1.1, A1.5, A1.8, B1.1, B2.5, B3.4`.
   - `Metabolism Case Study.md`: Transclusions `A1.7, A1.13, C1.1, C1.2, C2.1, C2.2, C3.1`.
   - `Homeostasis Report.md`: Added academic documentation requirement and rubric row for citing clinical literature (`A1.7`), transclusions `A1.7, A1.11, E1.1, E1.2, E2.1, E2.3, E3.1, E3.3`.
   - `Population Study.md`: Transclusions `A1.8, F1.1, F2.2, F3.2, F3.3, F3.4`.
   - `Final Examination.md`: Transclusions `A1.12, B3.1, B3.2, B3.4, B3.5, C3.1, C3.2, C3.4, D2.2, D3.1, E3.1, F3.3, F3.5`.
   - `Investigation Reports.md`: Transclusions `A1.6, A1.8, A1.10, A1.12, A1.13`.

5. **Discussions, Setup & Class Pages**:
   - `Discussions/What Can This Planet Support.md`: Transclusions `F1.1, F1.2, F3.4`.
   - `Discussions/Testing on Animals.md`: Transclusions `E1.1, E1.2`.
   - `Discussions/Who Gets the Cure.md`: Transclusions `A1.3, D1.1, D1.2`.
   - `Setup/Working with Living Things.md`: Transclusion `A1.4`.
   - `per_section/All Classes/Unit 1, Day 1.md`: Linked `[[Using a Microscope]]`.
   - `per_section/All Classes/Unit 3, Day 2.md`: Linked `[[Extracting DNA]]`.

---

#### Adversarial Audit & Quality Control Review

An adversarial subagent was invoked with instructions to refute, audit alignment against primary Ontario curriculum documents, check formatting rules in `SKILL.md`, and verify reachability.

**Defects Found & Resolved:**
1. *Defect:* `Final Examination.md` transcluded `E2.3` ("plan and conduct an investigation of a feedback system"), which is impossible on a 3-hour seated exam.  
   *Resolution:* Removed `E2.3` from `Final Examination.md` (relying on `Homeostasis Report.md` where a physical/computational model is constructed).
2. *Defect:* `Final Examination.md` transcluded `D3.7` ("historical scientific contributions") without any historical questions in the exam outline.  
   *Resolution:* Removed `D3.7` from `Final Examination.md` (relying on `DNA Replication in Detail.md`, `Regulating Gene Expression.md`, and `Molecular Genetics Practice.md`).
3. *Defect:* `Homeostasis Report.md` transcluded `A1.7` (academic documentation) without an explicit research citation requirement in the instructions or rubric.  
   *Resolution:* Added a research evidence requirement and rubric row for primary clinical/physiological literature citations in accepted academic format.
4. *Defect:* `Gel Electrophoresis.md` transcluded `D2.3` (DNA extraction) and `D2.4` (protein synthesis components), which did not match the gel run protocol.  
   *Resolution:* Removed `D2.3` and `D2.4` from `Gel Electrophoresis.md`. Created `Extracting DNA.md` to authentically investigate DNA extraction (`D2.3`). Confirmed `D2.4` is authentically addressed in `Concepts/Transcription and Translation.md`, `Exercises/Molecular Genetics Practice.md`, and `Investigations/Modelling Molecular Genetics.md`.
5. *Observation:* `Proteins and Enzymes.md` mentioned "Maud Menten", whereas the Ministry document spells it "Maude Menten".  
   *Resolution:* Updated to note both historical accuracy and the curriculum spelling.

---

#### Final Verification Metrics (SBI4U)

- **Total Specific Expectations:** 69 (`A1.1` – `F3.5`)
- **Expectations Addressed $\ge 2$ Times:** 69 / 69 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py SBI4U`):** Clean (266 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: SPH3U once-only expectations (28 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across SPH3U (Grade 11 Physics) by ensuring all 100 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (investigations, concept summaries, exercises, discussions, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding physics concepts over time.

#### Baseline Findings (SPH3U)
- Total expectations: 100 specific expectations (`A1.1` to `F3.10`)
- Addressed only once (28 codes): `A2.2, B1.2, B2.9, B3.2, C1.1, C1.2, C2.2, D1.1, D2.1, D2.11, D2.6, D2.8, D2.9, D3.10, D3.11, D3.6, D3.7, D3.9, E1.2, E2.7, E3.3, E3.6, F1.1, F1.2, F2.4, F2.5, F3.1, F3.9`
- Misplaced transclusions identified:
  - `shared/Investigations/Specific Heat of a Metal.md` carried `D2.8` (mass-energy equivalence $E=mc^2$), which had no relevance to calorimetry; replaced with `D2.9` (specific heat capacity inquiry).
  - `shared/Concepts/The Doppler Effect.md` carried `E2.7` (resonance in air columns); replaced with `E2.1` and placed `E2.7` appropriately in resonance-focused pages.

#### Actions Completed

1. **Exercises Enhancement (`shared/Exercises/`)**:
   - `Kinematic Equation Practice.md`: Added questions 5–6 (stopping distance/photo radar/fuel efficiency, scalar vs vector distance/displacement/speed/velocity) and curriculum block for `B1.2`, `B2.3`, `B2.7`, `B3.2`.
   - `Projectile Practice.md`: Added `B2.9` to curriculum block for 2D projectile motion inquiry and component calculations.
   - `Force and Acceleration Practice.md`: Added questions 5–7 (low-friction magnetic bearings vs athletic shoe friction, vehicle crumple zones impact force reduction, elevator apparent weight and FBDs) and curriculum block for `C1.1`, `C1.2`, `C2.2`, `C2.5`, `C2.6`, `C3.3`.
   - `Free-Body Diagram Practice.md`: Added questions 5–6 (sprinter starting blocks action-reaction/static friction, skydiver terminal velocity & parachute drag FBDs and net force) and curriculum block for `C1.1`, `C1.2`, `C2.1`, `C2.2`, `C3.1`, `C3.2`.
   - `Energy Practice.md`: Added questions 6–10 (electric water heater power/efficiency/thermal losses, heating curve segments & KMT plateaus, nuclear fission mass defect and $E=mc^2$ vs fusion, calorimeter mixture specific heat capacity inquiry, radioisotope half-life decay & radiation shielding comparison) and curriculum block for `D1.1`, `D2.1`, `D2.2`, `D2.3`, `D2.4`, `D2.6`, `D2.8`, `D2.9`, `D2.11`, `D3.1`, `D3.3`, `D3.4`, `D3.6`, `D3.7`, `D3.9`, `D3.10`, `D3.11`.
   - `Waves and Sound Practice.md`: Added questions 5–8 (principle of superposition and beat frequency, open/closed air column resonance and structural tuned mass dampers, bat echolocation time-of-flight and ultrasound resolution, decibel sound intensity comparison and noise cancellation/wall baffles) and curriculum block for `E1.2`, `E2.2`, `E2.4`, `E2.6`, `E2.7`, `E3.2`, `E3.3`, `E3.5`, `E3.6`.
   - `Circuit Practice.md`: Added questions 5–8 (solenoid RHR and 3D closed magnetic field loops, high-voltage transformer transmission line $I^2R$ power loss and electrical safety/GFCI/clearance rules, Maglev trains and MRI superconducting electromagnet applications, Ontario electricity generation mix comparative efficiency and lifecycle sustainability) and curriculum block for `F1.1`, `F1.2`, `F2.3`, `F2.4`, `F2.5`, `F3.1`, `F3.4`, `F3.5`, `F3.6`, `F3.9`.

2. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `Describing Motion.md`: Added scalar vs vector classifications and transclusion `B3.2`.
   - `Projectile Motion.md`: Added transclusion `B2.9`.
   - `Newton's Laws.md`: Added technological and societal applications (low-friction bearings, athletic footwear, vehicle crumple zones, biomechanical prosthetics) and transclusions `C1.1, C1.2, C2.2`.
   - `Thermal Energy and Heat.md`: Added heat pumps, refrigeration cycle, thermal power generation, and transclusions `D1.1, D2.1, D3.7`.
   - `Conservation of Energy.md`: Added transclusion `D2.1`.
   - `Nuclear Energy.md`: Added fission vs fusion comparison, mass defect and $E=mc^2$, Canadian scientists Harriet Brooks and Louis Slotin, and transclusions `A2.2, D2.8, D3.6, D3.9, D3.10, D3.11`.
   - `Resonance and Standing Waves.md`: Added transclusions `E2.7, E3.3`.
   - `Interference and Beats.md`: Added transclusions `E1.2, E3.3`.
   - `Sound Waves.md`: Added natural wave phenomena (infrasound in earthquakes/whales, ultrasound in echolocation/sonography) and transclusion `E3.6`.
   - `The Doppler Effect.md`: Replaced misplaced `E2.7` with `E2.1`.
   - `Magnetic Fields.md`: Added transclusions `F1.1, F2.4`.
   - `The Motor Principle.md`: Added transclusion `F3.1`.
   - `Electromagnetic Induction.md`: Added transclusion `F1.2`.
   - `Electric Current and Circuits.md`: Added practical electrical safety (GFCI outlets, fuses/circuit breakers, high-voltage clearances) and transclusion `F3.9`.

3. **Investigations & Lab Protocols (`shared/Investigations/`)**:
   - `Newton's Second Law.md`: Added transclusion `C2.2`.
   - `Specific Heat of a Metal.md`: Replaced misplaced `D2.8` with `D2.9`.
   - `Measuring the Speed of Sound.md`: Added transclusion `E2.7` (Method B air column resonance).
   - `Mapping Magnetic Fields.md`: Added transclusions `F2.5, F3.1`.

4. **Discussions & Tasks (`shared/Discussions/`, `shared/Tasks/`)**:
   - `Discussions/Nuclear Power in Ontario.md`: Added transclusions `D1.1, D2.8, D3.6, D3.9, D3.10, D3.11`.
   - `Discussions/Where Our Electricity Comes From.md`: Added transclusion `F1.2`.
   - `Tasks/Motion Story.md`: Added transclusion `B3.2`.
   - `Tasks/Model Roller Coaster.md`: Added transclusions `C1.1, D2.1`.
   - `Tasks/The Energy Report.md`: Added transclusion `D2.1`.
   - `Tasks/Sound in a Space.md`: Added transclusions `E1.2, E2.7`.
   - `Tasks/Motor and Generator Report.md`: Added transclusions `F1.1, F3.9`.

---

#### Adversarial Audit & Quality Control Review (SPH3U)

An adversarial subagent was invoked to refute claims of resolution, check curriculum fidelity, test KaTeX math syntax, and inspect task rubric alignments.

**Defects Identified & Corrected:**
1. *Defect:* `The Energy Report.md` initially carried transclusions for `A2.2, D2.6, D2.8, D2.11, D3.6, D3.9, D3.10, D3.11` without corresponding evaluation criteria in the task brief/rubric.  
   *Resolution:* Removed those 8 transclusions from `The Energy Report.md`. Confirmed all 8 expectations are fully and authentically addressed $\ge 2$ times across `Nuclear Energy.md`, `Nuclear Power in Ontario.md`, `Energy Practice.md`, `Heating and Cooling Curves.md`, and `Where This Physics Leads.md`.
2. *Defect:* `Motion Story.md` initially transcluded `B1.2` (technology assessment) while the brief only assesses video motion analysis.  
   *Resolution:* Removed `B1.2` from `Motion Story.md`. Confirmed `B1.2` is authentically covered in `Speed Limiters and Highway Safety.md` and `Kinematic Equation Practice.md` (Question 5).
3. *Defect:* `Sound in a Space.md` initially transcluded `E3.6` (natural phenomena: echolocation/infrasound) on an architectural acoustics task.  
   *Resolution:* Removed `E3.6` from `Sound in a Space.md`. Confirmed `E3.6` is authentically covered in `Sound Waves.md`, `The Doppler Effect.md`, and `Waves and Sound Practice.md` (Question 7).

---

#### Final Verification Metrics (SPH3U)

- **Total Specific Expectations:** 100 (`A1.1` – `F3.10`)
- **Expectations Addressed $\ge 2$ Times:** 100 / 100 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py SPH3U`):** Clean (319 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: MDM4U once-only expectations (18 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across MDM4U (Grade 12 Mathematics of Data Management) by ensuring all 56 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (exercises, concept summaries, tutorials, discussions, tasks, and portfolios), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding statistical and probability concepts over time.

#### Baseline Findings (MDM4U)
- Total expectations: 56 specific expectations (`A1.1` to `E2.4`)
- Addressed only once (18 codes): `A1.1, A1.2, A1.4, B1.3, B2.1, B2.3, B2.4, B2.5, B2.7, C1.2, D1.1, D1.3, D2.4, D3.3, E1.5, E2.2, E2.3, E2.4`
- Exercises folder (`shared/Exercises/`): All 8 practice problem sets lacked curriculum connection blocks despite actively exercising curriculum expectations.

#### Actions Completed

1. **Exercises Enhancement & Curriculum Mapping (`shared/Exercises/`)**:
   - `Probability Practice.md`: Added curriculum block for `A1.1, A1.2, A1.3, A1.4, A1.5, A1.6, A2.5` (real-world event likelihood, discrete vs continuous sample spaces, compound events, simulation convergence).
   - `Distributions Practice.md`: Enhanced Question 4 to explicitly construct and analyze discrete probability histograms with base width 1 ($E(X) = 7$, total area $= 1$, and comparison with frequency histograms); added curriculum block for `A1.2, B1.1, B1.2, B1.3, B1.4, B1.5, B1.6, B1.7, B2.1`.
   - `Normal Distribution Practice.md`: Added Question 10 addressing continuous random variable properties ($P(X = x) = 0$, probabilities over continuous intervals $[a, b]$, and density models); added curriculum block for `B2.1, B2.3, B2.5, B2.6, B2.7, B2.8, D1.4`.
   - `One- and Two-Variable Data Practice.md`: Added curriculum block for `B2.4, C1.2, C2.1, C2.2, C2.3, C2.4, D1.1, D1.2, D1.3, D1.5, D2.1, D2.2, D2.5, D3.1` (continuous intervals/histograms, inherent variability, sampling techniques/bias, 1-variable and 2-variable statistics).
   - `Regression and Inference Practice.md`: Added curriculum block for `D2.1, D2.2, D2.3, D2.4, D2.5, D3.1, D3.2, E1.5` (linear regression fitting, residuals and residual plots, extrapolation, media claims, margin of error, evaluating evidence strength).
   - `Counting Practice.md`: Added curriculum block for `A2.1, A2.2, A2.3, A2.4`.
   - `Conditional Probability Practice.md`: Added curriculum block for `A1.5, A1.6, A2.5`.
   - `Permutations and Combinations Practice.md`: Added curriculum block for `A2.1, A2.2, A2.3, A2.4, A2.5`.

2. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `Probability Basics.md`: Added `A1.4` (Law of Large Numbers and simulation convergence).
   - `Continuous Data and Its Intervals.md`: Added `B2.1, B2.5` (continuous random variables, interval ranges, $P(X = x) = 0$).
   - `The Normal Distribution.md`: Added `B2.3, B2.5` (continuous mathematical models for measurement uncertainty, probability over ranges).
   - `The Binomial Distribution.md`: Added `B2.7` (normal approximation to binomial as $n$ increases).
   - `One-Variable Statistics.md`: Added `C1.2` (sources of inherent variability in data, univariate vs bivariate).
   - `What a Statistical Study Is For.md`: Added `C1.2, E1.5` (variability, 1-variable vs 2-variable distinction, drawing conclusions with stated limitations).

3. **Tutorials & Discussions (`shared/Tutorials/`, `shared/Discussions/`)**:
   - `Tutorials/Simulating with Python.md`: Added curriculum block for `A1.4, B1.1` (simulating experimental probabilities approaching theoretical probability via Python random number generation).
   - `Tutorials/Using a Spreadsheet for Statistics.md`: Added curriculum block for `D1.1, D2.1, D2.4` (spreadsheet computation of one-variable summary statistics, correlation coefficient $r$, and linear regression).
   - `Discussions/When Will I Use This.md`: Added dedicated "Pathways and professions" section detailing data management careers (actuaries, biostatisticians, data scientists, epidemiologists, urban planners) and postsecondary programs; added curriculum block for `D3.3`.
   - `Discussions/What Makes a Model Good.md`: Added curriculum block for `B2.3, D2.2, E1.5` (evaluating mathematical models, continuous modeling challenges, evidence limitations).

4. **Tasks & Portfolios (`shared/Tasks/`, `shared/Portfolios/`)**:
   - `Tasks/The Fair Game Audit.md`: Added transclusions for `A1.1, B1.1` (game probabilities and discrete random variable distributions).
   - `Tasks/The Culminating Investigation.md`: Added transclusions for `D1.1, D1.3, D2.4, E2.2, E2.3` (1-variable numerical/graphical summaries, linear regression/residuals, presenting summary, answering questions/defending conclusions).
   - `Tasks/The Statistical Claim Report.md`: Added transclusions for `E1.5, E2.4` (drawing evidence-based conclusions with limitations, constructive critique of published mathematical claims).
   - `Tasks/The Survey Autopsy.md`: Added transclusions for `E1.5, E2.4` (evaluating evidence strength/limitations, constructive peer review).
   - `Portfolios/Judging Your Own Work.md`: Added curriculum block for `E2.4` (constructive feedback in peer/self critique protocol).

---

#### Adversarial Audit & Quality Control Review (MDM4U)

An adversarial subagent was invoked to refute claims of resolution, audit curriculum alignment, test KaTeX math syntax, verify reachability, and check comment block constraints.

**Audit Results:**
- Verified all 56 expectation definitions against primary curriculum files.
- Confirmed zero `[[links]]` or `![[transclusions]]` inside `%%` comment blocks.
- Confirmed all modified pages are reachable within 2 hops of class schedule agendas.
- Confirmed proper formatting (~80-column wrap, spaced em dashes, Canadian spelling, display math formatting).

---

#### Final Verification Metrics (MDM4U)

- **Total Specific Expectations:** 56 (`A1.1` – `E2.4`)
- **Expectations Addressed $\ge 2$ Times:** 56 / 56 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py MDM4U`):** Clean (259 pages checked, 84 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: ENG4U once-only expectations (17 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across ENG4U (Grade 12 University English) by ensuring all 70 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (concepts, exercises, discussions, portfolios, reading guides, style rules, tutorials, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding literature, writing, oral communication, and media studies over time.

#### Baseline Findings (ENG4U)
- Total expectations: 70 specific expectations (`A1.1` to `D4.2`)
- Addressed only once (17 codes): `A1.1, A1.2, A1.3, A1.7, A1.8, A1.9, A3.2, C2.2, C3.1, C3.4, D1.4, D1.5, D1.6, D3.1, D3.2, D3.3, D3.4`
- Unlinked shared file: `shared/Style/Writing About Literature.md` (carried no class schedule link).
- Empty curriculum block: `shared/Portfolios/Judging Your Own Work.md`.

#### Actions Completed

1. **Concepts & Style Alignment (`shared/Concepts/`, `shared/Style/`)**:
   - `Adaptation and Media.md`: Added comprehensive sections on divergent audience reception across eras/demographics (`D1.4`), ideological representation and power structures in casting/framing (`D1.5`), media industry production/financing/distribution economics and content regulations (`D1.6`), and a 4-step media creation guide (`D3.1, D3.2, D3.3, D3.4`). Transclusions: `D1.1, D1.2, D1.4, D1.5, D1.6, D2.1, D2.2, D3.1, D3.2, D3.3, D3.4`.
   - `Writing About Literature.md`: Added rules 8 and 9 on developing an authoritative critical voice (`C2.2`) and maintaining grammatical cohesion/parallelism (`C3.4`). Transclusions: `B1.3, C2.2, C2.3, C3.1, C3.4`. Linked from `per_section/All Classes/Unit 1, Day 13.md` during essay drafting.
   - `Research Writing.md`: Added academic voice, spelling of critical terms and secondary sources, and complex sentence grammar. Transclusions: `C1.3, C1.5, C2.2, C3.1, C3.2, C3.4, C3.6, C3.7`.
   - `The Extended Essay.md`: Added voice, spelling verification, and grammatical cohesion for long-form essays. Transclusions: `C1.1, C1.4, C2.1, C2.2, C2.7, C3.1, C3.4, C3.5, C3.6`.
   - `Comparative Argument.md`: Added grammatical balance, parallelism, and transitions in comparative claims. Transclusions: `B1.6, C1.2, C1.4, C2.4, C3.4`.
   - `Thesis and Argument.md`: Added syntactic precision in non-run-on analytical thesis statements. Transclusions: `C1.2, C1.4, C3.4`.

2. **Exercises Enhancement (`shared/Exercises/`)**:
   - `Evidence and Analysis Practice.md`: Corrected character attribution (Lady Macbeth); added Questions 6–8 explicitly drilling assertive critical voice revision (`C2.2`), diagnosis and correction of literary homonyms/spelling patterns (*canon* vs *cannon*, *illusory*, *soliloquy*, *elicit* vs *illicit*) (`C3.1`), and parallelism in comparative analysis (`C3.4`). Transclusions: `C2.2, C2.4, C3.1, C3.4, C3.5`.
   - `Paraphrase Practice.md`: Added `C3.1` for using reference resources to verify spelling and archaic vocabulary.

3. **Tutorials, Discussions & Portfolios (`shared/Tutorials/`, `shared/Discussions/`, `shared/Portfolios/`)**:
   - `Seminar Skills.md`: Added explicit guidelines for setting listening purposes/goals (`A1.1`), active listening moves (probing questions, steelmanning, acknowledging dissent) (`A1.2`), and presentation delivery evaluation (vocal pacing, tone, non-verbal cues) (`A1.9`). Transclusions: `A1.1, A1.2, A1.3, A1.5, A1.6, A1.7, A1.8, A1.9, A2.2, A2.3, A2.5, A2.6, A2.7, A3.1`.
   - `Research and Sources.md`: Added `D1.6` for commercial advertising, sponsored media, and corporate ownership factors. Transclusions: `B1.6, C1.3, D1.4, D1.5, D1.6`.
   - `Discussions/Who Is the Canon For.md`: Added listening goals, active listening to opposing viewpoints, listening comprehension, and ideological power analysis. Transclusions: `A1.1, A1.2, A1.3, A1.6, A1.8, A1.9, B1.6`.
   - `Discussions/Does the Lens Make the Reading.md`: Added active listening and perspective evaluation. Transclusions: `A1.2, A1.5, A1.8, B1.6, B1.7`.
   - `Discussions/Is Delay a Character Trait.md`: Added active listening and oral argument analysis. Transclusions: `A1.2, A1.5, A1.7, B1.6, B2.1`.
   - `Discussions/What Does a Warning Owe Us.md`: Added active listening, oral ideological analysis, and dystopian media perspectives. Transclusions: `A1.2, A1.5, A1.8, B1.6, B1.8, D1.5`.
   - `Portfolios/Judging Your Own Work.md`: Created curriculum block connecting self-assessment to oral reflection and reading/writing/media growth. Transclusions: `A3.2, B4.1, C4.1, D4.1`.
   - `Portfolios/What a Strong Entry Looks Like.md`: Added transclusions `A3.2, B4.2, C4.2`.
   - `Portfolios/Portfolio Checklist.md`: Added transclusions `A3.2, C3.1`.

4. **Reading Guides (`shared/Reading/`)**:
   - `Reading/Adaptations and Media Texts.md`: Added sections on audience reception, ideological framing, and mentor models for media text creation. Transclusions: `D1.3, D1.4, D1.5, D1.6, D2.1, D2.2, D3.1, D3.2, D3.3, D3.4`.
   - `Reading/Hamlet.md`: Added listening comprehension and oral soliloquy performance analysis. Transclusions: `A1.3, A1.4, A1.7, B1.1, B2.1, B2.3`.
   - `Reading/Poetry Unit.md`: Added spoken poetry and oral verse delivery analysis. Transclusions: `A1.4, A1.7, B1.5, B2.3`.

5. **Tasks & Summative Evaluations (`shared/Tasks/`)**:
   - `The Hamlet Seminar.md`: Added transclusions `A1.1, A1.2, A1.3, A1.7, A1.8, A1.9, A3.2` reflecting listening purpose, active listening, presentation analysis, and post-seminar oral reflection.
   - `The Adaptation Study.md`: Added transclusions `D1.4, D1.5, D1.6` reflecting audience reception, ideological perspective, and industry constraints.
   - `The Lens Essay.md`: Added transclusions `C2.2, C3.4`.
   - `The Critical Essay.md`: Added transclusions `C2.2, C3.1, C3.4`.
   - `The Comparative Essay.md`: Added transclusions `C2.2, C3.4`.
   - `The Independent Study.md`: Added transclusions `C2.2, C3.1, C3.4`.

---

#### Adversarial Audit & Quality Control Review (ENG4U)

An adversarial subagent was invoked to refute claims of resolution, verify curriculum fidelity against primary source definitions in `shared/Curriculum/`, inspect pedagogical scaffolding, and check structural constraints in `SKILL.md`.

**Audit Verdict:** PASS (0 defects found).
- Confirmed all 70 expectations are authentic, robustly grounded, and covered $\ge 2$ times.
- Confirmed all 13 overall expectations (A1–D4) are evaluated in `shared/Tasks/`.
- Confirmed zero transclusions inside comments, zero curriculum blocks on class pages, and 100% two-hop graph reachability.
- Confirmed Canadian spelling and stylistic conventions maintained throughout.

---

#### Final Verification Metrics (ENG4U)

- **Total Specific Expectations:** 70 (`A1.1` – `D4.2`)
- **Expectations Addressed $\ge 2$ Times:** 70 / 70 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py ENG4U`):** Clean (255 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: CHV2O once-only expectations (13 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across CHV2O (Grade 10 Civics and Citizenship, 2022 Ontario Curriculum) by ensuring all 36 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (concepts, investigations, sources, discussions, tutorials, portfolios, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding civic inquiry, democratic values, governance structures, Charter rights, and youth action over time.

#### Baseline Findings (CHV2O)
- Total expectations: 36 specific expectations (`A1.1` to `C2.2`)
- Addressed only once (13 codes): `A2.3, A2.4, B1.3, B2.4, B2.5, B2.6, B2.7, B2.8, B3.5, B3.6, C1.4, C1.5, C1.6`

#### Actions Completed

1. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `How Canada Is Governed.md`: Added sections on the three branches of government in Canada (`B2.4` — executive, legislative, judicial) and how the separation of powers promotes stability, plus the detailed multi-stage process for passing and amending statutes (`B2.6`). Updated frontmatter with `enableToc: true` and curriculum block with `B2.8, B2.1, B2.4, B2.6`.
   - `What Democracy Asks of You.md`: Added sections on Canada's first-past-the-post electoral system and majority vs minority government formation (`B2.8`), and on national symbols, commemorations (Remembrance Day, National Day for Truth and Reconciliation), and constructive patriotism (`C1.4`). Updated frontmatter with `enableToc: true` and curriculum block with `B1.1, B1.4, B2.8, C1.4`.
   - `Who Decides What, and Where.md`: Added comprehensive section on revenue raising mechanisms across federal, provincial, municipal, and Indigenous orders and budget design balancing short-term operational costs with long-term capital investments (`B2.5`). Updated curriculum block with `B2.2, B2.4, B2.5`.
   - `Rights, and What Limits Them.md`: Added section on rights in a global context (UDHR, ICCPR, UNCRC, UNDRIP) (`B3.5`), and evaluating international responses to human rights violations (targeted Magnitsky sanctions, ICC prosecutions, diplomatic censure, refugee protection) (`B3.6`). Updated frontmatter with `enableToc: true` and curriculum block with `B3.1, B3.4, B3.5, B3.6`.
   - `How Change Actually Happens.md`: Added sections on how domestic advocacy groups (unions, business associations, environmental and Indigenous groups) and international bodies influence public policy and everyday economic life (`B2.7`), and how digital literacy, social media campaigns, and open data portals empower online and offline advocacy (`C1.5`). Updated frontmatter with `enableToc: true` and curriculum block with `B3.3, C2.2, B2.7, C1.5`.
   - `Service and Contribution.md`: Added section detailing professional pathways and careers where civics education is central (public administration, law/justice, non-profit leadership, journalism, labour relations) (`A2.4`). Updated frontmatter with `enableToc: true` and curriculum block with `C1.1, C1.2, C1.6, A2.4`.

2. **Sources & Investigations Enhancements (`shared/Sources/`, `shared/Investigations/`)**:
   - `Sources/Judging Civic Information.md`: Added sections on foreign actor interference, bot networks, election disinformation, and democratic defence mechanisms (`B1.3`), and applying the four concepts of political thinking to current events analysis (`A2.3`). Updated frontmatter with `enableToc: true` and curriculum block with `A1.3, C1.5, B1.3, A2.3`.
   - `Investigations/Who Decided This.md`: Added explicit investigation steps on budget and funding mechanisms (`B2.5`), statutory and bylaw amendment instruments (`B2.6`), and political thinking evaluation (`A2.3`). Updated curriculum block with `A1.1, B2.2, B2.7, B2.5, B2.6, A2.3`.
   - `Investigations/Whose Rights Win.md`: Added analysis connecting Canadian Charter rights conflicts with international human rights conventions (`B3.5`), global violations and international responses (`B3.6`), and political thinking concepts (`A2.3`). Updated curriculum block with `B3.1, B3.4, B3.5, B3.6, A2.3`.

3. **Tutorials, Setup & Portfolios (`shared/Tutorials/`, `shared/Setup/`, `shared/Portfolios/`)**:
   - `Tutorials/Writing to Someone in Power.md`: Added section on digital channels, online consultation portals, social media advocacy, and formal deputations (`C1.5`). Updated frontmatter with `enableToc: true` and curriculum block with `A1.5, B3.3, C1.5`.
   - `Setup/How This Course Works.md`: Added section connecting course inquiry directly to youth service, leadership, and Ontario's 40-hour graduation requirement (`C1.6`). Added curriculum block with `C1.6`.
   - `Portfolios/Where You Stand Now.md`: Expanded Part 3 to connect skills to both professional careers (`A2.4`) and ongoing youth leadership and community service (`C1.6`). Updated curriculum block with `A2.1, A2.2, A2.4, B1.5, C1.6`.

4. **Tasks & Summative Evaluations (`shared/Tasks/`)**:
   - `The Issue Brief.md`: Added `B2.7` (influence of groups and economic/individual impacts of policy) and `A2.3` (applying political thinking concepts to analyze a live current issue) to curriculum block (`A1.1, A1.2, B1.1, B1.2, B2.7, A2.3`).
   - `How Government Works.md`: Added `B2.4` (three branches and stability) and `B2.8` (Canada's form of government, elections, and government formation) to curriculum block (`B2.1, B2.2, B2.3, B2.4, B2.8`).
   - `The Issue Examination.md`: Added `A2.3` (political thinking concepts in analyzing unseen issues and sources), `A2.4` (transferable skills and career reflection in Part 3), and `B1.3` (assessing foreign interference and disinformation in media/social media sources) to curriculum block (`A1.3, A1.4, A1.5, A2.1, A2.3, A2.4, B1.3`).

---

#### Adversarial Audit & Quality Control Review (CHV2O)

An adversarial subagent was invoked to refute claims of resolution, audit curriculum alignment against primary Ministry documents, check KaTeX/Mermaid syntax, verify reachability, and inspect assessment constraints.

**Audit Results:**
- **Verdict:** **CERTIFIED CLEAN** (0 blocking defects found).
- Confirmed all 36 specific expectations (`A1.1` to `C2.2`) are authentically taught and evaluated $\ge 2$ times.
- Confirmed all 7 overall expectations (`A1, A2, B1, B2, B3, C1, C2`) are evaluated across `shared/Tasks/`.
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and 100% two-hop graph reachability.
- Confirmed Canadian spelling and stylistic conventions maintained throughout.

---

#### Final Verification Metrics (CHV2O)

- **Total Specific Expectations:** 36 (`A1.1` – `C2.2`)
- **Expectations Addressed $\ge 2$ Times:** 36 / 36 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py CHV2O`):** Clean (149 pages checked, 42 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: SPH4U once-only expectations (12 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across SPH4U (Grade 12 University Physics) by ensuring all 71 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (exercises, concept summaries, investigations, discussions, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding two-dimensional dynamics, momentum/energy conservation, fields, wave optics, and modern physics over time.

#### Baseline Findings (SPH4U)
- Total expectations: 71 specific expectations (`A1.1` to `F3.4`)
- Addressed only once (12 codes): `A1.4, A2.1, B1.2, B2.1, B2.4, B2.5, C1.1, C3.5, E2.1, E3.3, E3.4, F2.4`
- Unlinked class schedule tutorial: `shared/Tutorials/Analysing Video of Motion.md` (carried no direct class schedule link; linked on Day 10 air table video tracking).

#### Actions Completed

1. **Exercises Enhancement (`shared/Exercises/`)**:
   - `Vectors and Projectiles Practice.md`: Added Question 5 (modified Atwood inclined-plane pulley system / "dumb waiter" calculating system acceleration and string tension with FBDs and algebraic systems) and Question 6 (crate on accelerating flatbed truck calculating maximum static friction acceleration, threshold slipping, and accelerations in ground inertial vs truck non-inertial frames). Added curriculum block for `B2.1, B2.2, B2.3, B2.4, B2.5, B3.2`.
   - `Circular Motion Practice.md`: Added Question 5 (clinical centrifuge blood separation calculating $a_c$ in $g$'s and evaluating diagnostic healthcare vs industrial wastewater sludge treatment impacts) and Question 6 (high-rise traction elevator apparent weight FBD calculations across acceleration, constant velocity, and deceleration, assessing high-density urban land conservation vs suburban sprawl). Added curriculum block for `B1.2, B2.1, B2.5, B2.6, B2.7, B3.3`.
   - `Momentum and Collisions Practice.md`: Added Question 5 (forensic crash reconstruction calculating pre-impact speeds from post-collision skid marks and 2D momentum conservation, proposing crush-box and highway barrier attenuator improvements), Question 6 (Tsiolkovsky rocket equation variable mass propulsion and multistage/aerospike nozzle improvements), and Question 7 (Pauli's neutrino prediction from continuous beta decay energy spectra and non-collinear recoil momentum conservation). Added curriculum block for `C1.1, C2.1, C2.5, C2.6, C2.7, C3.3, C3.4, C3.5`.
   - `Wave Optics Practice.md`: Added Question 5 (defining wave optics terminology: polarization, dispersion, diffraction, and nodal lines $\Delta\phi = \pi$ proving transverse wave nature), Question 6 (soap bubble thin-film constructive interference phase shifts $2t = (m + 1/2)\lambda/n$ and minimum non-zero thickness $t = 100\ \text{nm}$ for green light), and Question 7 (qualitative mechanism of oscillating electric dipoles generating self-propagating EM radiation across radio, microwaves, bremsstrahlung X-rays, and atomic electron orbital transitions). Added curriculum block for `E2.1, E2.2, E2.3, E2.4, E3.1, E3.2, E3.3, E3.4`.
   - `Relativity and Quanta Practice.md`: Added Question 5 (photoelectric effect inquiry data analysis plotting $eV_{\text{stop}} = hf - W$, calculating experimental Planck's constant $h = 6.62 \times 10^{-34}\ \text{J}\cdot\text{s}$, work function $W = 2.26\ \text{eV}$, and threshold frequency $f_0$) and Question 6 (relativistic proton momentum at TRIUMF cyclotron $p = \gamma mv$ vs classical $p = mv$ and magnetic deflection curvature confirming relativistic dynamics). Added curriculum block for `F2.2, F2.3, F2.4, F3.1, F3.2, F3.3`.

2. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `Uniform Circular Motion.md`: Added dynamics terminology covering period $T$, frequency $f = 1/T$, centripetal acceleration, and inertial vs non-inertial frame distinctions. Added transclusions `B2.1, B2.6, B3.3`.
   - `Forces in Two Dimensions.md`: Added static vs kinetic friction models, coordinate resolution, and multi-body system dynamics with FBDs. Added transclusions `B2.1, B2.3, B2.5, B3.2`.
   - `Elastic and Inelastic Collisions.md`: Added dedicated engineering applications section (automotive crumple zones, multi-density EPS helmets, highway water/sand crash attenuators, and controlled structural demolition). Added transclusions `C1.1, C2.6, C3.3`.
   - `Polarization.md`: Added photoelastic stress analysis and birefringence in transparent polymers between crossed polarizing filters producing colour bands. Added transclusions `E1.2, E2.1, E3.2, E3.3`.
   - `The Wave Model of Light.md`: Added oscillating electric dipole EM wave generation mechanism and speed of light in vacuum. Added transclusions `E2.1, E3.2, E3.4`.
   - `The Photoelectric Effect.md`: Added photocell stopping potential $V_{\text{stop}}$ vs frequency inquiry analysis to extract Planck's constant. Added transclusions `F2.2, F2.4, F3.1`.

3. **Investigations & Lab Protocols (`shared/Investigations/`)**:
   - `Double Slit with a Laser.md`: Added `A1.4` to curriculum block matching explicit laser safety protocols.
   - `Emission Spectra.md`: Added `A1.4` to curriculum block matching high-voltage power supply and thermal tube handling safety rules.
   - `Deflecting a Charged Particle.md`: Added `A1.4` to curriculum block matching high-voltage demonstration tube safety rules.

4. **Tasks, Summative Evaluations & Class Schedule (`shared/Tasks/`, `per_section/`)**:
   - `Modern Physics Seminar.md`: Added Pauli's neutrino prediction to seminar topics, added career pathway and training requirements (e.g. photonics researcher, radiation physicist, quantum engineer) to brief and rubric. Added transclusions `A1.11, A2.1, A2.2, C3.5, F1.1, F1.2, F2.1, F2.4, F3.1, F3.3`.
   - `Fields Technology Report.md`: Added career pathway requirement and rubric row for professional/technical careers (e.g. medical physicist, RF systems engineer, accelerator operator). Added transclusions `A1.3, A1.7, A1.9, A2.1, D1.1, D1.2, D2.1, D2.2`.
   - `Final Examination.md`: Updated curriculum block to comprehensively reflect all five examined course units (`A1.12, A1.13, B2.1, B2.3, B2.5, B2.6, B3.3, C1.1, C2.1, C2.5, C2.7, C3.3, C3.5, D2.1, D2.2, D2.3, D3.1, E2.1, E2.3, E3.2, E3.3, E3.4, F2.1, F2.3, F2.4, F3.1, F3.3`).
   - `per_section/All Classes/Unit 2, Day 10.md`: Linked `[[Analysing Video of Motion]]` directly on air table collision tracking day.

---

#### Adversarial Audit & Quality Control Review (SPH4U)

An adversarial subagent was invoked to refute claims of resolution, audit curriculum alignment against primary Ministry documents in `shared/Curriculum/`, test KaTeX syntax, verify two-hop reachability, and check comment block constraints.

**Audit Results:**
- **Verdict:** **CERTIFIED CLEAN** (0 blocking defects, 0 minor observations).
- Confirmed all 71 specific expectations (`A1.1` to `F3.4`) are authentically taught, exercised, or evaluated $\ge 2$ times.
- Confirmed all 12 target expectations are thoroughly represented across multiple authentic destination files (ranging from 2 to 6 files each).
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and 100% two-hop graph reachability.
- Confirmed Canadian spelling and stylistic conventions maintained throughout.

---

#### Final Verification Metrics (SPH4U)

- **Total Specific Expectations:** 71 (`A1.1` – `F3.4`)
- **Expectations Addressed $\ge 2$ Times:** 71 / 71 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py SPH4U`):** Clean (284 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: MPM2D once-only expectations (11 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across MPM2D (Grade 10 Principles of Mathematics) by ensuring all 41 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (concepts, exercises, explorations, discussions, number talks, tutorials, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding quadratic relations, analytic geometry, and trigonometry over time.

#### Baseline Findings (MPM2D)
- Total expectations: 41 specific expectations (`A1.1` to `C3.4`)
- Addressed only once (11 codes): `A1.1, A1.4, A3.3, A3.5, A3.7, B1.4, B1.5, B3.1, C1.1, C2.1, C3.2`
- Landing page teacher comment drift: `per_section/index.md` mentioned Unit 4, Day 5/6 instead of Unit 4, Day 20/21.

#### Actions Completed

1. **Exercises Enhancement (`shared/Exercises/`)**:
   - `Quadratic Graphing Practice.md`: Added Question 7 (collecting and graphing experimental data for an inclined ramp roll and fitting a quadratic curve of best fit $d = 50t^2$), Question 8 (comparing $y = x^2$ with $y = 2^x$, zero and negative exponents $2^0 = 1, 2^{-1} = 1/2, 2^{-2} = 1/4$, and contrasting graph features), and Question 9 (completing the square without fractions for $y = x^2 - 10x + 21$ and $y = 3x^2 + 12x + 5$ into vertex form using algebra and area models). Transclusions: `A1.1, A1.4, A2.3, A2.4, A3.3, A3.5`.
   - `Expanding and Factoring Practice.md`: Added Question 9 (factoring quadratic relation $y = x^2 - 2x - 8$ into factored form $y = (x - 4)(x + 2)$ to identify zeros/intercepts, axis of symmetry, and vertex). Transclusions: `A3.1, A3.2, A3.3`.
   - `Quadratic Formula Practice.md`: Added Question 7 (exploring the algebraic development of the quadratic formula by completing the square on general parameters $ax^2 + bx + c = 0$ mapped side-by-side with numerical equation $2x^2 + 8x - 10 = 0$). Transclusions: `A3.4, A3.7, A3.8`.
   - `Linear Systems Practice.md`: Added Question 8 (developing and applying slope formula $m = \frac{y_2 - y_1}{x_2 - x_1}$ from coordinates and writing linear equations) and Question 9 (translating between standard form $Ax + By + C = 0$ and slope-intercept form $y = mx + b$). Transclusions: `B1.1, B1.2, B1.4, B1.5`.
   - `Midpoint and Length Practice.md`: Added Question 8 (finding slopes and equations of triangle medians and perpendicular bisectors in standard form). Transclusions: `B1.4, B1.5, B2.1, B2.2, B2.5, B3.1, B3.2`.
   - `Similar Triangles Practice.md`: Added Question 7 (verifying similarity between right triangles with a $30°$ angle and computing constant opposite-to-hypotenuse side ratios defining $\sin 30° = 0.5$). Transclusions: `C1.1, C1.2, C1.3, C2.1`.
   - `Trig Ratios and Laws Practice.md`: Added Question 7 (exploring the development of the cosine law by dropping an altitude in acute $\triangle ABC$, splitting the base, and applying the Pythagorean theorem to arrive at $a^2 = b^2 + c^2 - 2bc\cos A$). Transclusions: `C2.1, C2.2, C3.1, C3.2, C3.3, C3.4`.

2. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `The Vertex Form.md`: Enhanced completing the square section with explicit Case 1 ($a = 1$) and Case 2 ($a \neq 1$) without fractions, using area diagrams/algebra tiles. Transclusions: `A2.3, A2.4, A3.5`.
   - `Quadratic Relations.md`: Added dedicated section comparing quadratic growth ($y = x^2$) with exponential growth ($y = 2^x$), exploring patterns for zero and negative exponents ($2^0 = 1, 2^{-1} = 1/2, 2^{-2} = 1/4$), and contrasting parabolic symmetry with exponential asymptotes. Transclusions: `A1.2, A1.3, A1.4`.
   - `Parallel, Perpendicular, and the Bisector.md`: Added slope formula derivation from coordinates and translated right bisector equations between point-slope, slope-intercept, and standard forms ($3x + 2y - 20 = 0$). Transclusions: `B1.3, B1.4, B1.5, B2.5`.
   - `Midpoint and Length.md`: Added slope formula $m = \frac{y_2 - y_1}{x_2 - x_1}$ as the rise-over-run companion coordinate tool derived from the right triangle. Transclusions: `B1.4, B2.1, B2.2`.

3. **Explorations, Discussions & Number Talks (`shared/Explorations/`, `shared/Discussions/`, `shared/Number Talks/`)**:
   - `Explorations/Maximum Enclosure.md`: Transclusions `A1.1, A1.3, A3.5, A4.1`.
   - `Explorations/The Handshake Problem.md`: Transclusions `A1.1, A1.2, Mathematical Process Expectations`.
   - `Explorations/Crossing Paths.md`: Transclusions `B1.1, B1.2, B1.4`.
   - `Explorations/How Tall Is the Flagpole.md`: Transclusions `C1.1, C1.3, C2.1, C2.3`.
   - `Discussions/What Makes a Proof Convincing.md`: Transclusions `B3.1, B3.2, B3.3`.
   - `Number Talks/Always, Sometimes, Never.md`: Transclusions `B3.1, B3.3, C1.1, C1.2, C2.1`.
   - `Tutorials/Checking Your Own Work.md`: Transclusions `A3.5, A3.8, B1.1`.

4. **Tasks, Summative Evaluations & Landing Page (`shared/Tasks/`, `per_section/`)**:
   - `The Perfect Arc.md`: Transclusions `A1.1, A1.3, A2.4, A3.3, A4.2`.
   - `The Quadrilateral Case File.md`: Transclusions `B1.4, B2.1, B2.2, B3.1, B3.2, B3.3`.
   - `Break-Even.md`: Transclusions `B1.1, B1.2, B1.4, B1.5`.
   - `Inaccessible Heights.md`: Transclusions `C1.1, C1.3, C2.1, C2.3, C3.2, C3.4`.
   - `The Math Symposium.md`: Transclusions `Mathematical Process Expectations, A3.7, A3.8`; updated TALK triangulation block to explicitly name `A3.8`.
   - `Final Examination.md`: Transclusions `A3.5, A3.6, A4.1, B1.3, B1.4, B1.5, B2.5, C3.1, C3.2`.
   - `per_section/index.md`: Corrected comment referencing Unit 4, Day 20 as newest published page and Day 21 as held-back example.

---

#### Adversarial Audit & Quality Control Review (MPM2D)

An adversarial subagent was invoked to refute claims of resolution, audit curriculum alignment against primary Ministry documents in `shared/Curriculum/`, test KaTeX syntax, verify two-hop reachability, inspect folder indexes, and check Canadian spelling.

**Round 1 Defects Verified Fixed:**
1. *Defect 1 (Unescaped currency dollar signs):* Verified all currency figures in `Crossing Paths.md`, `Would You Rather.md`, `Writing About Math.md`, and `Linear Systems Practice.md` use properly escaped `\$` syntax.
2. *Defect 2 (Missing concept pages in index):* Verified `shared/Concepts/index.md` contains 100% of concept pages, including `Factors and Intercepts` and `Parallel, Perpendicular, and the Bisector`.
3. *Defect 3 (Missing exploration in index):* Verified `shared/Explorations/index.md` contains 100% of exploration pages, including `Squares Against Doubling`.
4. *Defect 4 (Missing tutorial in index):* Verified `shared/Tutorials/index.md` contains 100% of tutorial pages, including `Scavenger Hunt`.
5. *Defect 5 (`enableToc` rule compliance):* Verified `enableToc: true` is only present on pages with $\ge 4$ H2 headings (`The Vertex Form.md` defaults to false, `Curriculum/index.md` has exactly 4 H2 headings).

**Round 2 Audit Actions & Corrected Defects:**
1. *Spelling Standardization:* Corrected instances of US spelling "skeptic" to Canadian spelling "sceptic" in `shared/Explorations/Maximum Enclosure.md` (line 18) and `per_section/All Classes/Unit 2, Day 10.md` (line 16), ensuring 100% adherence to Canadian English.
2. *KaTeX Multiline In-Callout Formatting:* Corrected inline math formatting in `shared/Exercises/Midpoint and Length Practice.md` (lines 38–39) and `shared/Style/What This Site Can Do.md` (lines 144–145) to prevent potential KaTeX inline span breaks across markdown blockquote lines.

**Audit Results:**
- **Verdict:** **CERTIFIED CLEAN** (0 blocking defects, 0 minor observations).
- Confirmed all 41 specific expectations (`A1.1` to `C3.4`) are authentically taught, exercised, or evaluated $\ge 2$ times.
- Confirmed all 11 target expectations are thoroughly represented across multiple authentic destination files (ranging from 3 to 8 files each).
- Confirmed all folder `index.md` files contain 100% of non-template markdown files.
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and 100% two-hop graph reachability.
- Confirmed Canadian spelling and stylistic conventions maintained throughout.

---

#### Final Verification Metrics (MPM2D)

- **Total Specific Expectations:** 41 (`A1.1` – `C3.4`)
- **Expectations Addressed $\ge 2$ Times:** 41 / 41 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py MPM2D`):** Clean (232 pages checked, 84 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: CHA3U once-only expectations (13 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across CHA3U (Grade 11 American History, University Preparation) by ensuring all 67 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (concepts, investigations, sources, writing guides, tutorials, discussions, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding historical thinking, primary source analysis, and historical inquiry over time.

#### Baseline Findings (CHA3U)
- Total expectations: 67 specific expectations (`A1.1` to `E3.5`)
- Addressed only once (13 codes): `A1.9, B2.4, C2.4, C3.5, D1.3, D2.3, D3.1, D3.2, D3.3, D3.5, E1.2, E1.3, E3.5`
- Unlinked shared files in class schedule:
  - `shared/Style/What This Site Can Do.md`
  - `shared/Tutorials/Scavenger Hunt.md`
- Missing from folder index: `shared/Tutorials/Scavenger Hunt.md` was omitted from `shared/Tutorials/index.md`.

#### Actions Completed

1. **Writing Guides & Inquiry Method (`shared/Writing/`)**:
   - `Building an Argument.md`: Added curriculum transclusion `A1.9` for communicating inquiry findings using appropriate historical terminology and criteria.
   - `Using Evidence.md`: Added curriculum transclusion `A1.9` for interpreting and analyzing evidence with precise historical vocabulary (provenance, standpoint, corroboration).

2. **Concept Pages Alignment & Deepening (`shared/Concepts/`)**:
   - `Before 1492.md`: Added curriculum transclusion `B2.4` for indigenous environmental adaptations, regional geography, and natural resources across North American ecosystems.
   - `Colonies and the People In Them.md`: Added curriculum transclusion `B2.4` for regional environmental and economic differences (New England, Middle Colonies, Chesapeake/Southern plantations).
   - `Politics of a Growing Republic.md`: Added new section "Foreign relations, territory, and domestic power" discussing the War of 1812, Treaty of Ghent, Monroe Doctrine, Texas annexation, Mexican-American War, and Civil War diplomacy; updated frontmatter with `enableToc: true`; added curriculum transclusion `C2.4`.
   - `Reform Movements.md`: Added curriculum transclusion `C3.5` for assessing the individual contributions of Elizabeth Cady Stanton, Sojourner Truth, Frederick Douglass, Dorothea Dix, and William Lloyd Garrison.
   - `Removal and Resistance.md`: Added curriculum transclusion `C3.5` for assessing the individual contributions and leadership of Tecumseh, John Ross, Major Ridge, Andrew Jackson, Chief Joseph, and Lakota leaders.
   - `Jim Crow and Resistance.md`: Added curriculum transclusions `D1.3, D2.3, D3.5` for statutory disenfranchisement, Progressive and civil rights reform organizing (Ida B. Wells, W.E.B. Du Bois, NAACP), and cultural contributions (Harlem Renaissance, blues, jazz, Negro Leagues baseball).
   - `Industry, Labour, and the Cities.md`: Added curriculum transclusions `D1.3, D2.3, D3.2, D3.3` for domestic labour legislation, AFL/IWW reform movements, metropolises (New York, Chicago, Detroit), and industrial technology/assembly lines.
   - `Migration and a Changing Population.md`: Added curriculum transclusion `D3.1` for 19th/20th-century immigration trends, ethnic enclaves, nativism, and immigration restrictions.
   - `Arts, Culture, and Consumer Society.md`: Added curriculum transclusions `D3.2, D3.3, E1.3` for regional culture/heritage, science and technology (broadcasting, motion pictures, recordings, appliances), and postwar consumer economy/globalization.
   - `The Postwar United States.md`: Added curriculum transclusions `E1.2, E3.5` for postwar science and technology (television, digital technologies, medical breakthroughs, space exploration) and arts/popular culture.
   - `Movements and Backlash.md`: Added curriculum transclusions `E1.2, E1.3` for television and environmental science (*Silent Spring*) and economic trends (Rust Belt transition, UFW farmworker boycotts).

3. **Discussions & Seminars (`shared/Discussions/`)**:
   - `Is the United States an Empire.md`: Added curriculum transclusions `C2.4, E1.2, E1.3, E3.5` connecting continental and overseas foreign relations, Cold War defense technologies, transnational economic power, and global cultural soft power.
   - `Who Counts as American.md`: Added curriculum transclusions `D3.1, E3.5` for historical immigration quota acts, national origins exclusions, and cultural assertions of citizenship in literature and popular arts.

4. **Sources & Research Guides (`shared/Sources/`)**:
   - `Newspapers and Print Culture.md`: Added curriculum transclusion `D3.5` for mass-circulation journalism, Pulitzer, Hearst, magazines, muckraking, and comic strips.
   - `Photographs.md`: Added curriculum transclusion `D3.5` for documentary photography, Jacob Riis, Lewis Hine, FSA photography, and popular visual culture.

5. **Investigations & Inquiry Case Studies (`shared/Investigations/`)**:
   - `Whose Story Gets Taught.md`: Added curriculum transclusions `D3.2, D3.5, E3.5` for regional historical narratives, artistic representations in popular film and media, and public monuments/memorials (Maya Lin).

6. **Tasks & Summative Evaluations (`shared/Tasks/`)**:
   - `The Source Study.md`: Added curriculum transclusion `A1.9` for assessing student communication of historical inquiry vocabulary.
   - `The Colonies Compared.md`: Added curriculum transclusion `B2.4` for evaluating environmental, geographic, and natural resource factors in colonial settlement and labour structures.
   - `Slavery and the Nation.md`: Added curriculum transclusion `C3.5` for evaluating individual contributions to anti-slavery organizing, testimony, and resistance.
   - `The Union Divided.md`: Added curriculum transclusion `C2.4` for analyzing how territorial conquest (Mexican-American War) and foreign diplomacy affected domestic sectional crisis.
   - `The Industrial Republic.md`: Added curriculum transclusions `D2.3, D3.1, D3.2, D3.3` for evaluating plant technology/assembly lines (`D3.3`), immigrant workforce and exclusion (`D3.1`), worker organizing and unions (`D2.3`), and regional/metropolitan impact (`D3.2`).
   - `Rights and Movements.md`: Added curriculum transclusions `D1.3, D2.3` for tracing domestic civil rights policy, voting statutes, and reform movements before and after 1945.
   - `The Long Argument.md`: Added curriculum transclusion `E1.3` for synthesizing economic trends, federal power, corporate regulation, and inequality across modern American history.
   - `The Document Examination.md`: Added curriculum transclusion `A1.9` for assessing historical thinking terminology and source criticism on the final evaluation.

7. **Class Schedule & Tutorials Index Alignment**:
   - `per_section/All Classes/Unit 1, Day 1.md`: Linked `[[What This Site Can Do]]` in agenda item 4 and `[[Scavenger Hunt]]` in the homework checklist.
   - `shared/Tutorials/index.md`: Added `[[Scavenger Hunt]]` under Unit 1.

---

#### Adversarial Audit & Quality Control Review (CHA3U)

An adversarial subagent was invoked to refute claims of resolution, audit curriculum alignment against primary Ministry documents, check KaTeX syntax, verify reachability, and check comment block constraints.

**Audit Results:**
- **Verdict:** **CERTIFIED CLEAN** (0 blocking defects found).
- Confirmed all 67 specific expectations (`A1.1` to `E3.5`) are authentically taught, exercised, or evaluated $\ge 2$ times.
- Confirmed all 14 overall expectations (`A1` to `E3`) are evaluated across `shared/Tasks/`.
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and 100% two-hop graph reachability.
- Confirmed Canadian spelling and stylistic conventions maintained throughout.

---

#### Final Verification Metrics (CHA3U)

- **Total Specific Expectations:** 67 (`A1.1` – `E3.5`)
- **Expectations Addressed $\ge 2$ Times:** 67 / 67 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py CHA3U`):** Clean (255 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: CIA4U once-only expectations (2 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across CIA4U (Grade 12 Analysing Current Economic Issues, University Preparation) by ensuring all 64 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (concepts, cases, discussions, models, data, tutorials, portfolios, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding economic inquiry, microeconomic decision-making, macroeconomic indicators and policy, and international trade and global disparity over time.

#### Baseline Findings (CIA4U)
- Total expectations: 64 specific expectations (`A1.1` to `E3.3`)
- Addressed only once (2 codes): `E1.4, E2.4`
- Unlinked tutorial in class schedule: `shared/Tutorials/Scavenger Hunt.md`
- Missing from folder index: `shared/Tutorials/Scavenger Hunt.md` omitted from `shared/Tutorials/index.md`

#### Actions Completed

1. **Models & Conceptual Grounding (`shared/Models/`, `shared/Concepts/`)**:
   - `Models/Comparative Advantage.md`: Added dedicated section on **Trade agreements and international governance** covering regional pacts (CUSMA/NAFTA, CETA, CPTPP), multilateral rules (WTO dispute settlement), and macroeconomic forums (G20), explaining objectives, non-tariff barriers, and domestic sovereignty trade-offs (`E1.4`), plus Ricardo and Smith foundations (`B4.1`). Transclusions: `B4.1, E1.1, E1.2, E1.3, E1.4`.
   - `Concepts/Sustainability and the Economy.md`: Added dedicated section on **Global externalities and citizen action** covering international environmental degradation, cross-border resource extraction, and consumer/worker activism (ethical boycotts/buycotts, fair-trade certification, supply chain due diligence) (`E2.4`). Transclusions: `B3.1, B3.3, E2.4`.
   - `Concepts/Inequality.md`: Transclusions `C2.3, C3.2, D1.3, D1.5, E3.1`.
   - `Concepts/Why Governments Intervene.md`: Transclusions `B4.2, C1.4, C1.5, C1.6, C3.1, C3.3`.
   - `Concepts/Schools of Economic Thought.md`: Transclusions `B4.1, B4.2`.

2. **Cases, Discussions & Data (`shared/Cases/`, `shared/Discussions/`, `shared/Data/`)**:
   - `Cases/The Tariff Year.md`: Enhanced "The reasoning to do" with trade theories (`E1.1`), exchange rate transmission dynamics (`E1.2`), and concepts of economic thinking (`A2.3`). Transclusions: `A2.3, D2.3, E1.1, E1.2, E1.4, E2.2, E2.3`.
   - `Cases/The Cost of a Place to Live.md`: Transclusions `A1.5, B4.3, C2.1, C2.3, C2.4, D2.1, D2.4`.
   - `Discussions/What Do We Owe Other Countries.md`: Expanded institutional analysis with multilateral trade bodies (`E1.4`), trade theories (`E1.1`), and structural causes of global economic marginalization (`E3.1`). Transclusions: `E1.1, E1.3, E1.4, E2.3, E2.4, E3.1, E3.2, E3.3`.
   - `Data/Judging an Economic Claim.md`: Transclusions `A1.1, A1.2, A1.3, A1.4, A1.6, A1.9`.

3. **Tasks & Summative Evaluations (`shared/Tasks/`)**:
   - `The Trade Question.md`: Added subsection on treaty frameworks, dispute mechanisms, and rules of origin (`E1.4`), economic vs ethical criteria (`E1.3`), international events (`E2.2`), and Canadian government responses (`E2.3`). Transclusions: `E1.1, E1.2, E1.3, E1.4, E2.1, E2.2, E2.3`.
   - `The Data Examination.md`: Enhanced Part 3 to explicitly require evaluating individual, NGO, and group actions addressing international economic harms (child labour, sweatshops, environmental degradation, working conditions) (`E2.4`) alongside social movements (`E3.3`). Transclusions: `A1.3, A1.4, A1.5, B4.1, E2.4, E3.3`.
   - `The Economic Issue Report.md`: Enhanced Part 8 ("The international response") and marking criteria to evaluate both intergovernmental bodies (`E3.2`) and grassroots social movements / civil society coalitions (`E2.4`, `E3.3`), using the concepts of economic thinking (`A1.5, A2.3`). Transclusions: `A1.5, A1.6, A1.7, A2.3, E2.2, E2.4, E3.1, E3.2, E3.3`.
   - `The Policy Brief.md`: Transclusions `D1.2, D2.1, D2.2, D2.3, D2.4, D3.1, D3.2, E2.3`.
   - `The Intervention Argument.md`: Transclusions `B3.4, C1.4, C2.1, C2.4, C3.1, C3.2`.

4. **Portfolios, Tutorials, Schedule & Style Standardization**:
   - `Portfolios/Judging Your Own Work.md`: Added curriculum connection block for transferable self-regulation and monitoring habits (`A2.1, A2.2`).
   - `Portfolios/Where Economics Leads.md`: Corrected US spelling `skeptical` to Canadian spelling `sceptical` (line 31).
   - `Curriculum/index.md`: Promoted Strands A through E headings to `##` (H2), providing 5 H2 headings to strictly satisfy the `enableToc: true` 4+ H2 requirement.
   - `Tutorials/index.md`: Added `[[Scavenger Hunt]]` under Unit 1.
   - `per_section/All Classes/Unit 1, Day 1.md`: Linked `[[Scavenger Hunt]]` in the homework checklist.

---

#### Adversarial Audit & Quality Control Review (CIA4U)

Two rounds of adversarial subagent audits were conducted to challenge all claims of resolution, test curriculum fidelity against primary source definitions, check structural/style invariants, and verify reachability.

**Round 1 Defects Identified & Resolved:**
1. *Defect 1 (Canadian Spelling):* Corrected `skeptical` to `sceptical` in `Where Economics Leads.md:31`.
2. *Defect 2 (TOC H2 Rule):* Promoted 5 strand headings in `Curriculum/index.md` to `##` (H2) to satisfy `enableToc: true` rule.
3. *Defect 3 (Superficial Transclusions):* Removed unearned transclusions `C1.6, C1.5, D3.3` from `The Cost of a Place to Live.md`, `D2.2` from `Why Governments Intervene.md`, `E3.3` from `Inequality.md`, `C2.3, D1.5` from `Sustainability and the Economy.md`, and `B1.1, D1.5` from `Schools of Economic Thought.md`.

**Round 2 Audit Results:**
- **Verdict:** **CERTIFIED 100% CLEAN** (0 defects, 0 observations).
- Confirmed all 64 specific expectations (`A1.1` to `E3.3`) are authentically taught, exercised, or evaluated $\ge 2$ times across the course.
- Confirmed all 15 overall expectations (A1, A2, B1, B2, B3, B4, C1, C2, C3, D1, D2, D3, E1, E2, E3) are evaluated in `shared/Tasks/`.
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and 100% two-hop graph reachability.
- Confirmed Canadian spelling and stylistic conventions maintained throughout.

---

#### Final Verification Metrics (CIA4U)

- **Total Specific Expectations:** 64 (`A1.1` – `E3.3`)
- **Expectations Addressed $\ge 2$ Times:** 64 / 64 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py CIA4U`):** Clean (256 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: ICS4U once-only expectations (11 codes)

**Status:** Completed & Adversarially Audited  
**Objective:** Eliminate thin coverage across ICS4U (Grade 12 Computer Science, University Preparation) by ensuring all 47 curriculum expectations are genuinely addressed $\ge 2$ times across authentic destination pages (concepts, exercises, discussions, tutorials, warm-ups, portfolios, and tasks), adhering strictly to `.claude/skills/example-content/SKILL.md` and properly scaffolding object-oriented programming, data structures, algorithm efficiency, theoretical computer science, and collaborative software project engineering over time.

#### Baseline Findings (ICS4U)
- Total expectations: 47 specific expectations (`A1.1` to `D4.4`)
- Addressed only once (11 codes): `A4.4, B1.2, B1.3, B1.4, B1.5, B2.2, B2.3, D3.2, D4.1, D4.2, D4.3`
- Missing from folder indexes:
  - `shared/Tutorials/Scavenger Hunt.md` omitted from `shared/Tutorials/index.md` and unlinked from class pages.
  - `shared/Concepts/How Numbers Actually Fit.md`, `Two-Dimensional Data.md`, and `Computing's Footprint.md` omitted from `shared/Concepts/index.md`.
- Stale teacher comment on landing page: `per_section/index.md` mentioned "Unit 4, Day 6 / Day 7" instead of "Unit 4, Day 24 / Day 25".
- Zero exercise sets in `shared/Exercises/` and zero discussions in `shared/Discussions/` had curriculum transclusion blocks.

#### Actions Completed

1. **Theoretical Foundations, Interdisciplinary Research & Concept Depth (`shared/Concepts/`)**:
   - `Concepts/Ethics, Security, and the Profession.md`: Added dedicated section on **Interdisciplinary computing and research frontiers** documenting collaborative computer science research published in ACM/IEEE literature (`D4.1`) across bioinformatics/genomics (sequence alignment, AlphaFold protein folding), climatology numerical modelling, health informatics (clinical telemetry, federated medical imaging), computational linguistics (transformer architectures, semantic translation), and algorithmic economics. Expanded evaluation of emerging technology research reports (`D3.2`). Transclusions: `D2.1, D2.2, D2.3, D3.2, D4.1, D4.3`.
   - `Concepts/Efficiency and Big-O.md`: Added dedicated section on **Theoretical limits and complexity classes** (`D4.2`) covering the binary decision tree model of comparison sorts, proving the information-theoretic $\Omega(n \log n)$ worst-case lower bound via Stirling's approximation ($\log_2(n!) = \Omega(n \log n)$), complexity classes ($P$ vs $NP$), and Turing computability / undecidability (Halting Problem). Transclusions: `C2.2, C2.3, C2.4, D4.2`.
   - `Concepts/Software Project Management.md`: Enriched sections on project execution, quality standards, budget/time constraints, milestone tracking (`B1.2`), time management across team dependencies (`B2.2`), producing software to specifications with automated tests and user documentation (`B1.3`), external user documentation/manuals (`A4.4`), and project closure criteria (`B1.5`). Transclusions: `B1.1, B1.2, B1.3, B1.4, B1.5, B1.6, B2.2, A4.4`.
   - `Concepts/index.md`: Added missing concept links `[[How Numbers Actually Fit]]` (Unit 1), `[[Two-Dimensional Data]]` (Unit 2), and `[[Computing's Footprint]]` (Unit 4).

2. **Exercises Enhancement (`shared/Exercises/`)**:
   - `Exercises/Efficiency Practice.md`: Added Question 10 and Answer 10 requiring students to model comparison sorting using a binary decision tree and prove the $\Omega(n \log n)$ lower bound (`D4.2`). Transclusions: `C2.1, C2.2, C2.3, C2.4, D4.2`.
   - `Exercises/Recursion Practice.md`: Added Question 10 and Answer 10 requiring students to derive recurrence relations $T(n)$ for linear and branching recursion, formulate an inductive termination proof, and analyze call stack memory bounds (`D4.2`). Transclusions: `A3.6, C1.3, C2.4, D4.2`.
   - `Exercises/Classes and Objects Practice.md`: Added curriculum block with `A1.5, A2.2, A4.3, C1.1, C1.4`.
   - `Exercises/Methods and Encapsulation Practice.md`: Added curriculum block with `A2.2, A4.3, C1.2, C1.4`.
   - `Exercises/Dictionaries Practice.md`: Added curriculum block with `A1.2, A1.3, A1.5, A3.1, C1.1, C2.1`.
   - `Exercises/Stacks and Queues Practice.md`: Added curriculum block with `A1.5, A3.3, C1.1, C1.2, C2.1`.
   - `Exercises/Searching Practice.md`: Added curriculum block with `A1.1, A3.2, C2.1, C2.2`.
   - `Exercises/Sorting Practice.md`: Added curriculum block with `A1.3, A3.4, C2.1, C2.3`.

3. **Discussions, Warm-Ups & Tutorials (`shared/Discussions/`, `shared/Warm-Ups/`, `shared/Tutorials/`)**:
   - `Discussions/Should It Exist.md`: Transclusions `D2.1, D3.1, D3.2, D4.2`.
   - `Discussions/What Happens When You Leave.md`: Transclusions `A2.3, B1.5, B1.6, D4.3`.
   - `Discussions/When Code Hurts.md`: Transclusions `D2.1, D2.2, D4.1`.
   - `Discussions/Who Maintains This.md`: Transclusions `B1.6, D2.2, D4.3`.
   - `Discussions/Whose Code Is It.md`: Transclusions `D2.1, D2.2, D2.3`.
   - `Warm-Ups/Tech Headlines.md`: Transclusions `D3.1, D3.2, D4.1`.
   - `Warm-Ups/Spot the Bug.md`: Transclusions `A2.3, A4.1`.
   - `Warm-Ups/Name That Error.md`: Transclusions `A4.1`.
   - `Warm-Ups/Predict the Output.md`: Transclusions `A1.1, A1.2, A1.3`.
   - `Warm-Ups/Read the Diff.md`: Transclusions `A2.3, B1.7`.
   - `Warm-Ups/Trace It.md`: Transclusions `A1.5, A3.5, C2.1`.
   - `Warm-Ups/Which One Doesn't Belong.md`: Transclusions `C1.1, C1.4`.
   - `Tutorials/Working in a Team.md`: Transclusions `B1.2, B1.4, B1.7, B2.1, B2.2, B2.3`.
   - `Tutorials/Writing Code Others Can Read.md`: Transclusions `A2.2, A4.3, A4.4`.
   - `Tutorials/Writing Tests.md`: Transclusions `A2.3, A4.2, C2.1`.
   - `Tutorials/Using Version Control.md`: Transclusions `A2.3, B1.7, B2.1`.
   - `Tutorials/Profiling and Timing Code.md`: Transclusions `C2.2, C2.3`.
   - `Tutorials/Reading a Traceback in Someone Else's Code.md`: Transclusions `A2.3, A4.1`.
   - `Tutorials/Getting Unstuck.md`: Transclusions `A4.1`.
   - `Tutorials/index.md`: Added `[[Scavenger Hunt]]` to the tutorials table.

4. **Portfolios & Tasks Alignment (`shared/Portfolios/`, `shared/Tasks/`)**:
   - `Portfolios/Final Reflection.md`: Enriched Section 4 to explicitly prompt students to research postsecondary CS/software engineering pathways and career goals (`D4.3`), and review team and individual project performance (`B2.3`). Transclusions: `B2.3, D4.3, D4.4`.
   - `Portfolios/Judging Your Own Work.md`: Transclusions `B2.2, B2.3, D4.4`.
   - `Portfolios/Showing Growth.md`: Transclusions `A2.3, B2.3, D4.3, D4.4`.
   - `Portfolios/Code Journal.md`: Transclusions `A4.1, B2.2, D4.4`.
   - `Tasks/The Software Project.md`: Transclusions `B1.1, B1.2, B1.3, B1.4, B1.5, B1.7, B2.1, B2.2, B2.3, A4.4, D2.1, D2.2, D2.3`.
   - `Tasks/The Handover.md`: Transclusions `B1.3, B1.5, B1.6, B2.2, B2.3, A4.4, D4.4`.
   - `Tasks/The Maintenance Sprint.md`: Transclusions `A2.3, A4.1, A4.2, B1.2, B1.3, B2.2`.

5. **Structural Integrity & Setup Pages**:
   - `Setup/How This Class Works.md`: Transclusions `D4.4`.
   - `Setup/Our Classroom Norms.md`: Transclusions `D2.2, D2.3`.
   - `Style/Writing About Code.md`: Transclusions `A4.3, A4.4`.
   - `Curriculum/index.md`: Promoted Strands A through D headings to `##` (H2) to strictly satisfy the `enableToc: true` 4+ H2 rule.
   - Removed `enableToc: true` from 7 concept pages that had fewer than 4 H2 headings (`Objects Working Together`, `Stacks and Queues`, `Encapsulation`, `Two-Dimensional Data`, `Attributes and Methods`, `Objects and Classes`, `Computing's Footprint`).
   - `per_section/All Classes/Unit 1, Day 1.md`: Linked `[[What This Site Can Do]]` in agenda and `[[Scavenger Hunt]]` in the checklist.
   - `per_section/All Classes/Unit 1, Day 2.md`: Linked `[[Writing About Code]]` in the agenda.
   - `per_section/index.md`: Corrected teacher comment to refer to Unit 4, Day 24 and Day 25.

---

#### Adversarial Audit & Quality Control Review (ICS4U)

An adversarial subagent was invoked to conduct an exhaustive, independent audit against the Ontario curriculum document, `.claude/skills/example-content/SKILL.md` rules, structural invariants, and test suites.

**Audit Findings:**
- **Verdict:** **CERTIFIED 100% CLEAN** (`AUDIT RESULT: CLEAN`).
- Confirmed all 47 specific expectations (`A1.1` to `D4.4`) are authentically addressed $\ge 2$ times across the course payload.
- Confirmed all 12 overall expectations (`A1` to `D4`) are evaluated in `shared/Tasks/`.
- Confirmed 100% two-hop graph reachability from class pages.
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and balanced curriculum markers.
- Confirmed Plantoir test suite (`764 passed, 0 failed`), `verify.sh`, and `setup_course.py` pass without errors.
- Confirmed Canadian spelling and code style maintained throughout.

---

#### Final Verification Metrics (ICS4U)

- **Total Specific Expectations:** 47 (`A1.1` – `D4.4`)
- **Expectations Addressed $\ge 2$ Times:** 47 / 47 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Linter Results (`lint_payload.py ICS4U`):** Clean (256 pages checked, 86 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.

---

### 1.1 Coverage depth: ICD2O once-only expectations (10 codes)

**Course:** ICD2O (Digital Technologies and Innovations in the Changing World, Grade 10, Open)  
**Status:** **RESOLVED**  
**Resolution Date:** 2026-08-22  

#### Context & Baseline Deficiencies
In `QC-FINDINGS.md` (§1.1), `ICD2O` had **10 once-only specific expectations** (25.6% of the 39 specific expectations):
- `A1.3`: develop computational artifacts for a variety of contexts and purposes that support the needs of diverse users and audiences (only on `Tasks/Launch Day.md`)
- `A3.1`: investigate how digital technology and programming skills can be used within a variety of disciplines in real-world applications (only on `Concepts/Technology in Every Field.md`)
- `A3.3`: investigate various career options related to digital technology and programming, and ways to continue their learning in these areas (only on `Portfolios/Final Reflection.md`)
- `B2.1`: use file management techniques, including those related to local and cloud storage, to organize, edit, and share files (only on `Concepts/Files and the Cloud.md`)
- `B2.2`: identify and use effective research practices and supports when learning to use new hardware or software (only on `Tutorials/Finding Answers Online.md`)
- `B2.3`: assess the hardware and software requirements for various users, contexts, and purposes in order to make recommendations for devices and programs (only on `Tasks/The Device Recommendation.md`)
- `B4.3`: investigate emerging innovations related to hardware and software and their possible benefits and limitations with reference to everyday life in the future (only on `Tasks/The Innovation Brief.md`)
- `C1.3`: identify various types of data and explain how they are used within programs (only on `Concepts/Data in Programs.md`)
- `C1.4`: determine the appropriate expressions and instructions to use in a programming statement, taking into account the order of operations (only on `Exercises/Operators Practice.md`)
- `C3.4`: write programs that make use of external or add-on modules or libraries (only on `Concepts/Subprograms and Modules.md`)

---

#### Actions Completed

1. **Concepts Substantive Expansion (`shared/Concepts/`)**:
   - `Concepts/Technology in Every Field.md`: Added 4th H2 section `## Career pathways and continuous learning` exploring tech careers (cybersecurity, UX/accessibility, skilled trades/automation, interdisciplinary dev) and continuous learning routes. Transclusions: `A3.1, A3.2, A3.3`.
   - `Concepts/Computational Thinking.md`: Added 5th H2 section `## Designing for diverse users and contexts` detailing input flexibility, audience contexts, and clear error recovery. Transclusions: `A1.1, A1.2, A1.3`.
   - `Concepts/Bias and Accessibility in Technology.md`: Added section `## Building inclusive computational artifacts` addressing high contrast, cognitive load, and input normalization. Transclusions: `A1.3, A2.4, A2.5`.
   - `Concepts/Hardware Inside the Box.md`: Added section `## Matching hardware specifications to user requirements` mapping CPU/RAM/GPU/storage to workloads. Transclusions: `B1.1, B2.3`.
   - `Concepts/Software and Operating Systems.md`: Added `## File systems and storage organisation` and `## Researching software and assessing requirements`, set `enableToc: true` (5 H2s). Transclusions: `B1.3, B2.1, B2.2, B2.3`.
   - `Concepts/Connected Devices.md`: Added `## Assessing requirements for connected devices`, set `enableToc: true` (4 H2s). Transclusions: `B1.2, B2.3, B4.2`.
   - `Concepts/Automation and Artificial Intelligence.md`: Added `## Emerging innovations and future frontiers` exploring NPUs, edge intelligence, robotics, and societal trade-offs, set `enableToc: true` (4 H2s). Transclusions: `B4.1, B4.3`.
   - `Concepts/Data in Programs.md`: Added `## Expressions and order of operations` detailing evaluation precedence and parenthesis rules, set `enableToc: true` (4 H2s). Transclusions: `C1.3, C1.4, C2.2`.

2. **Exercises Substantive Expansion (`shared/Exercises/`)**:
   - `Exercises/Variables and Expressions Practice.md`: Added Question 7 & Answer 7 identifying/converting primitive data types (`C1.3`), and Question 8 & Answer 8 calculating expressions with operator precedence (`C1.4`). Transclusions: `C1.3, C1.4, C2.1`.
   - `Exercises/Input and Output Practice.md`: Transclusions `C1.3, C2.1, C2.2`.
   - `Exercises/Operators Practice.md`: Transclusions `C1.3, C1.4, C2.5`.
   - `Exercises/Conditionals Practice.md`: Transclusions `C1.4, C1.5, C2.3`.
   - `Exercises/Subprograms Practice.md`: Added Question 7 & Answer 7 importing and using `random` (`C3.4`), and Question 8 & Answer 8 using `math.sqrt()` (`C3.4`). Transclusions: `C3.3, C3.4`.

3. **Programs, Warm-Ups, Discussions, Tutorials (`shared/`)**:
   - `Programs/The Dice Roller.md`: Transclusions `C1.4, C2.2, C3.1, C3.4`.
   - `Programs/Guess My Number.md`: Transclusions `C1.4, C2.4, C3.1, C3.4`.
   - `Programs/Mad Libs.md`: Transclusions `C1.3, C2.1, C3.1`.
   - `Programs/The Chatbot.md`: Transclusions `A1.3, C3.1, C3.3`.
   - `Programs/The Text Adventure.md`: Transclusions `C1.4, C3.1, C3.2`.
   - `Tutorials/Setting Up Python.md`: Added section `## Organising your files and workspace` detailing folder hierarchy, `.py` conventions, and cloud backups. Transclusions: `B2.1, C2.1`.
   - `Tutorials/Getting Unstuck.md`: Added step 6 on researching official technical documentation and error references. Transclusions: `B2.2, C2.6`.
   - `Tutorials/index.md`: Added `[[Scavenger Hunt]]` to the tutorials table.
   - `Warm-Ups/Tech Headlines.md`: Transclusions `A2.1, A3.1, B4.3`.
   - `Warm-Ups/Predict the Output.md`: Added collapsible prediction example testing expressions and operator precedence. Transclusions: `C1.3, C1.4, C2.6, C3.1`.
   - `Discussions/Whose Innovations Count.md`: Transclusions `A2.3, A3.1, B4.3`.
   - `Discussions/Will AI Take the Jobs.md`: Transclusions `A3.1, A3.2, A3.3, B4.1, B4.3`.
   - `Explorations/Inside the Box.md`: Added 4th H2 section `## Assessing components for user requirements`. Transclusions: `B1.1, B2.3`.

4. **Tasks & Portfolios Alignment (`shared/Tasks/`, `shared/Portfolios/`)**:
   - `Tasks/The Device Recommendation.md`: Added research verification sources requirement and rubric row. Transclusions: `A2.2, B1.1, B1.2, B1.3, B2.2, B2.3, B3.1`.
   - `Tasks/The Quiz Machine.md`: Added built for diverse players criteria row. Transclusions: `A1.3, C1.5, C2.3, C2.4, C2.5`.
   - `Tasks/The Remix Project.md`: Added modular library extensions and user audience customization requirements and criteria row. Transclusions: `A1.3, B2.1, C2.6, C3.1, C3.2, C3.4`.
   - `Tasks/The Innovation Brief.md`: Transclusions `A2.1, A2.3, A3.1, A3.2, B2.2, B4.1, B4.3`.
   - `Tasks/Launch Day.md`: Enriched program path requirements and criteria table with modular design and external/standard library integration. Transclusions: `A1.1, A1.2, A1.3, B2.1, B3.2, C2.7, C3.4, C3.5`.
   - `Portfolios/Dev Journal.md`: Set `enableToc: false`. Transclusions: `B2.1, C2.6`.
   - `Portfolios/Showing Growth.md`: Transclusions `A1.1, A3.3`.
   - `Portfolios/Your First Entry.md`: Transclusions `A1.1, B2.1`.
   - `Setup/How Tech Class Works.md`: Transclusions `A3.3`.

5. **Structural Integrity & Formatting Invariants**:
   - `per_section/All Classes/Unit 1, Day 1.md`: Linked `[[What This Site Can Do]]` in agenda and `[[Scavenger Hunt]]` in checklist.
   - `per_section/All Classes/Unit 4, Day 13.md`: Linked `[[Launch Day]]` and `[[Showing Growth]]` in agenda.
   - Removed `enableToc: true` from pages with fewer than 4 H2 headings (`Algorithm Hunt.md`, `Build a Network.md`, `Talk to the Machine.md`, `The Phishing Gallery.md`, `The Sandwich Robot.md`, `Dev Journal.md`, `Curriculum/index.md`).
   - Standardized Canadian spelling across payload (`organisation`, `summarise`, `modelling`, `personalised`).

---

#### Adversarial Audit & Quality Control Review (ICD2O)

An adversarial subagent was invoked to conduct an exhaustive, independent audit against the Ontario curriculum document, `.claude/skills/example-content/SKILL.md` rules, structural invariants, and test suites.

**Audit Findings & Iteration:**
- **Initial Audit:** Identified 4 minor defects:
  1. `Launch Day.md`: Needed explicit modular/library integration in text and rubric for `C3.4`.
  2. `Predict the Output.md`: Needed explicit operator precedence example for `C1.4`.
  3. `Curriculum/index.md`: Contained `enableToc: true` with only 1 H2 heading.
  4. American spellings (`organization`, `summarize`, `modeling`, `personalized`) needed Canadianization.
- **Corrections:** All 4 items were updated and verified.
- **Re-Audit Verdict:** **CERTIFIED 100% CLEAN** (`STATUS: CLEAN`).
- Confirmed all 39 specific expectations are authentically addressed $\ge 2$ times across the course payload.
- Confirmed 100% two-hop graph reachability from class pages.
- Confirmed zero transclusions or links inside comments, zero curriculum blocks on class pages, and balanced curriculum markers.
- Confirmed Canadian spelling and code style maintained throughout.

---

#### Final Verification Metrics (ICD2O)

- **Total Specific Expectations:** 39 (`A1.1` – `C3.5`)
- **Expectations Addressed $\ge 2$ Times:** 39 / 39 (100%)
- **Expectations Addressed Exactly Once:** 0 (0%)
- **Coverage Frequencies of the 10 Target Codes:**
  - `A1.3`: 6 times
  - `A3.1`: 5 times
  - `A3.3`: 5 times
  - `B2.1`: 7 times
  - `B2.2`: 5 times
  - `B2.3`: 5 times
  - `B4.3`: 5 times
  - `C1.3`: 6 times
  - `C1.4`: 8 times
  - `C3.4`: 6 times
- **Linter Results (`lint_payload.py ICD2O`):** Clean (235 pages checked, 85 class pages, 0 errors, 0 once-only expectations).
- **All destination pages reachable within 2 hops of a class page.**
- **`QC-FINDINGS.md` untouched.** All tracking maintained exclusively in this file.






