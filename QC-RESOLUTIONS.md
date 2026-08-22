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



