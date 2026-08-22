# Example-content QC pass — findings and to-do list

**Date:** 2026-08-21 · **Branch:** `bc-curriculum` · **Scope:** all 38 payloads in
`support/example_content/` (37 Ontario + MCMPR11, British Columbia).

**Method.** Linter on all 38; scripted structural checks over 9,549 markdown files;
five parallel adversarial auditors (mark pages, Key Links + landing pages,
triangulation blocks, agenda linking, MCMPR11 vs the BC skill); then a sixth
adversarial verifier briefed to REFUTE all of the above. Every claim below survived
that verification, and the corrections it forced are recorded inline. Claims the
verifier killed are listed at the end so they are not re-derived.

**Gate status: `lint_payload.py` reports `clean` for all 38.** Everything here is
invisible to it.

---

## Priority 1 — Do these first

### 1.1 Coverage depth: 18 courses have expectations addressed only once

The skill treats "addressed exactly once" as **thin rather than done**
(`SKILL.md:544-546`). The linter prints these on every run.

| Course | Once-only | Course | Once-only | Course | Once-only |
|---|---|---|---|---|---|
| SBI4U | **29** | MTH1W | 13 | ICS4U | 11 |
| SPH3U | **28** | MCMPR11 | 14 | ICD2O | 10 |
| MDM4U | 18 | SPH4U | 12 | TEJ3M | 9 |
| ENG4U | 17 | MPM2D | 11 | TEJ4M | 7 |
| SBI3U | 17 | CHA3U | 13 | TEJ2O | 5 |
| CHV2O | 13 | CIA4U | 2 | TGJ2O | 1 |

**To do:** for each course, spread transclusions across the pages that genuinely
address each expectation. `python3 .claude/skills/example-content/lint_payload.py <CODE>`
lists the exact codes. Start with SBI4U and SPH3U.

> Read the FULL linter output, not the last few lines. An earlier draft of this
> report said "3 courses" because it truncated to `tail -3`.

### 1.2 Class agendas that link to nothing — 300 pages across 32 courses

An agenda item naming an activity and linking to nothing hands a teacher a topic
sentence, not a lesson. Invisible to the linter. Count = class pages whose entire
agenda contains zero wikilinks, excluding `publish: false` and `review`-tagged pages.
Independently re-derived twice; denominator 3,172 class pages.

```
THJ2O 29  AVI1O 29  CHC2D 19  ENG4U 17  SBI3U 14  SNC2D 13  ENG2D 13
ENG3U 12  SBI4U 12  SCH4U 11  SCH3U 10  SPH4U 10  SNC1W 10  BOH4M  9
SPH3U  9  CIA4U  9  CGF3M  8  CHA3U  7  CHV2O  7  CGC1W  6  TGJ2O  6
ENL1W  6  MCV4U  5  MPM2D  5  MDM4U  5  MHF4U  4  ICS4U  4  MCR3U  4
GLC2O  3  ADA1O  2  ICD2O  1  MTH1W  1
zero: ATC1O, ICS3U, MCMPR11, TEJ2O, TEJ3M, TEJ4M
```

**38 of 39 sampled defects are pages that already exist and were simply not linked.**
This is a linking job, not an authoring job. The single exception with no page anywhere:
`SNC2D/per_section/All Classes/Unit 3, Day 11.md:14` (mitigation vs adaptation).

Verified example: `CHC2D/per_section/All Classes/Unit 2, Day 18.md` — 19 lines, zero
`[[` anywhere, line 13 reads `1. Work period: the wartime decision`, and
`CHC2D/shared/Tasks/The Wartime Decision.md` exists.

**Prioritise by the table above, not by a bare-agenda-item rate.** True defect rates
diverge sharply from raw rates — CGC1W is 75% true / 58% raw, SNC2D 15% / 61%,
ATC1O 29% / 61% — because fixed recurring items (ATC1O's `5. Cool-down` on every page)
and long self-contained instructions inflate the raw rate harmlessly.

**Pattern to copy: ICS3U.** `Warm-up: [[X]]` / `Compare and name it: [[Concept]]` /
`Practise: [[Exercises]]` — a link on every item carrying substance, bare only where the
item is genuinely a runnable instruction.

### 1.3 MCMPR11 — Ontario policy in a British Columbia course

Rules: `.claude/skills/bc-example-content/SKILL.md`, which is self-contained and
overrides the Ontario skill for this payload.

| ID | file:line | Defect | Origin |
|---|---|---|---|
| M1 | `shared/Setup/How Marks Work.md:17-18, 21, 29` | Ontario 70/30 split, as a pie and in prose. BC skill:577-579 — "**do not carry Ontario's 70/30 final-evaluation split into a BC course** — that is an Ontario secondary rule with no BC equivalent." | **Introduced by `39f3e2d9`**, which replaced a seven-slice differentiated pie with the 70/30 pair. |
| M2 | `shared/Setup/How Marks Work.md:13-51` | All three things BC skill:580-582 asks for instead are absent: the three kinds of evidence (neither "observation" nor "conversation" appears in the file), the Curricular Competencies in student words, and reflection as reported content. Worse than absent on the third — `:37-39` frames the journal as "evidence of learning — often the strongest evidence you have", i.e. evidence the teacher marks, **inverting** BC skill:573-575. | `39f3e2d9` |
| M4 | `Task 1:100`, `Task 2:83`, `Task 3:90`, `Task 4:93` | Ontario achievement levels in success criteria: `Exemplary (Level 4) \| Developing (Level 2)`. "Developing" is also a real BC proficiency level meaning something else. Violation is by implication from BC skill:499-501 (criteria "in words a student uses"), not by a named prohibition. | **Predates `39f3e2d9`** — verified identical at `39f3e2d9^`. |
| M5 | `shared/Learning Goals.md:13`, `shared/Curriculum/About These Standards.md:38` | Ontario phrasing: "the overall expectations", "Every specific expectation". | **Predates `39f3e2d9`** — `git log -1` on both returns `9f6f2a5a`. |
| M7 | `Task 3 - Indigenous Language Lexicon Engine.md:122` | OBSERVE says "while students are implementing nested dictionary lookups"; `Unit 3, Day 20.md:13` is "Task 3 Handover — Submitting and presenting". The implementation day is Day 19. | `39f3e2d9` |
| M8 | `Task 3:128` | TALK's "inverted index testing" half points at `Unit 3, Day 21`, after hand-in. (The OCAP half of the same prompt *does* land on a real Day 21 agenda item, so only half is unmoored.) | `39f3e2d9` |
| M9 | `Task 3:131` | Cites D4.1 / K1.4 / K1.7 for "analyzing algorithm complexity". Verbatim: D4.1 = "Identify and apply sources of inspiration and information"; K1.7 = "Pair programming"; K1.4 = "Structures within existing code". D4.1 and K1.7 have no defensible reading. | `39f3e2d9` |
| M11 | `Task 1:144-145`, `Task 3:123-124, :126` | OBSERVE describes what is readable off the submitted Python. (Not uniform — `Task 1:143, :146` and `Task 3:125` are genuinely observation-only, so fix the named lines, not the blocks.) | `39f3e2d9` |
| M12 | all 5 blocks | No "what a strong answer sounds like" anywhere. BC skill:561 requires it alongside the questions. | `39f3e2d9` |
| **NEW** | `Task 4:136` | OBSERVE points at Unit 4, Day 8 for "Canadian Forest Fire Weather Index" work; that day is AQHI / particulate / smoke dispersion. | — |
| **NEW** | `Task 4:142` | TALK points at Day 12 for "integration testing"; Day 12 is advisory formatting and typography. | — |
| **NEW** | `Final Evaluation…:141` | TALK asks about the flood dispatch allocation algorithm on Unit 4, Day 18 — but Day 17 is the preview and Day 18 is portfolio assembly. The work does not exist on the day the questions are scheduled. | — |
| **NEW** | arc-wide | BC **Core Competencies** are never named. BC skill:493-517 calls student self-reflection on them "required reporting content rather than an enrichment activity". `Unit 3, Day 21` and `Unit 4, Day 18` are self-assessment episodes that name none. | — |

**Reverting `39f3e2d9` would not fix M4 or M5.** Both predate it.

**Cleared in MCMPR11:** no *Growing Success* citation; no Ontario ministry reference
(the one "Ontario" string is an explicit contrast at `About These Standards.md:27`);
no achievement-chart categories; no "110–120 hours"; `jurisdiction: BC`,
`credit_value: 4.0`, `final_evaluation_hours: 3.0` correct; BC portal URL and OGL line
match BC skill:220-221 and 270-272; zero unlinked class pages.

---

## Priority 2 — Real, contained, cheap

### 2.1 Twenty-three courses tell students the course ends in June

All 38 manifests set `"class_weekday_step": 1`, so every arc runs **Sept 8 → ~Jan 19**.

`ATC1O AVI1O BOH4M CGC1W CHC2D ICD2O ICS3U ICS4U MCR3U MCV4U MDM4U MHF4U MPM2D`
`MTH1W SBI3U SBI4U SNC1W SPH3U SPH4U TEJ2O TEJ3M TGJ2O THJ2O`

Includes five `Learning Goals.md` pages headed literally `## By June you should be able to`
— ATC1O:9, AVI1O:8, BOH4M:9, CHC2D:9, THJ2O:9 — and
`ATC1O/shared/Setup/How Marks Work.md:17` "averaging September against June".
Genuine calendar dates in CGF3M, CIA4U and SNC1W are excluded.

**Decide first:** are these semestered (change to January) or full-year (change the
manifests)? Do not fix piecemeal.

### 2.2 Eleven stale landing-page teacher comments

Every `per_section/index.md` transcludes the **correct** newest published class page
(verified across all 38, zero mismatches). But in 11, the `%%` comment names a different
day as "the newest PUBLISHED page" and calls a **published** day "the held-back example".

| Course | Transcludes | Comment should say | Held-back should say |
|---|---|---|---|
| ADA1O | Unit 4, Day 23 | Day 23 | Day 24 |
| ICS3U | Unit 4, Day 22 | Day 22 | Day 23 |
| ICS4U | Unit 4, Day 24 | Day 24 | Day 25 |
| MCR3U | Unit 4, Day 25 | Day 25 | Day 26 |
| MDM4U | Unit 4, Day 21 | Day 21 | Day 22 |
| MHF4U | Unit 4, Day 23 | Day 23 | Day 24 |
| MPM2D | Unit 4, Day 20 | Day 20 | Day 21 |
| MTH1W | Unit 4, Day 21 | Day 21 | Day 22 |
| SCH3U | Unit 5, Day 17 | Day 17 | Day 18 |
| SCH4U | Unit 5, Day 16 | Day 16 | Day 17 |
| SNC2D | Unit 4, Day 21 | Day 21 | Day 22 |

The other 27 use three different phrasings and are all consistent — checked by hand,
not by regex.

### 2.3 Forbidden chemistry shape — three instances

`SKILL.md:633-635`: "**Do NOT build formulae out of `\text{}` and `\rightarrow`** — the
payloads were converted away from that and it must not come back."

```
SNC2D/shared/Exercises/Reaction Types Practice.md:76
  $$\text{acid} + \text{base} \rightarrow \text{salt} + \text{water}$$    ← literally the forbidden shape
SCH3U/shared/Exercises/Stoichiometry Practice.md:11
  $$\text{mass given} \rightarrow \text{moles} \rightarrow \text{moles} \rightarrow \text{mass wanted}$$
SCH4U/shared/Concepts/Polarity.md:58
  $$\ce{CO2} \text{ (linear, symmetric)} \rightarrow \text{non-polar} \qquad …$$
```

Separately, **28** `\rightarrow` occurrences sit *between* `\ce{}` groups (SCH4U 21,
SCH3U 6, SNC2D 1). Formulae are correctly mhchem; only the arrow is hand-drawn instead
of `->` inside one macro. Renders fine — style deviation, lower priority.

### 2.4 Triangulation-block defects in the Ontario payloads

| ID | file:line | Defect |
|---|---|---|
| T3.3 | `SNC1W/shared/Tasks/Design Challenge.md:160` | Cites **D2.8**, absent from that task's `Curriculum connection` (A1.3, A2.1, D2.3, D1.1, D1.2, D1.3). D2.8's text fits, so the fix is the list. |
| T3.4 | `SNC1W/shared/Tasks/Culminating Reflection.md` | The only non-index task page in all 282 with no curriculum block, while its block cites A1.2. Note the page explains why at `:66-69` and calls it deliberate — decide whether to keep the exemption or add the block. |
| T3.10 | `MHF4U/shared/Tasks/Final Examination.md`, `MPM2D/shared/Tasks/The Math Symposium.md` | Triangulation blocks naming no curriculum code at all. Exactly two, not three. |
| T4.6 | `TEJ3M/shared/Setup/How Marks Work.md:105-115` | Marks reliability / organization / initiative under D3.5 with no product boundary. `TEJ4M:113-117` covers the equivalent expectation (**D3.4**, not D3.5 — the codes differ between the two courses) and *does* draw it: "it marks **what they produced** … **never how hard somebody appeared to be trying**". Copy that sentence. |

### 2.5 Loose wording worth a pass

- `ATC1O/shared/Setup/How Marks Work.md:17-19` — "Unit 4's work is the final evaluation"
  couples the thirty to one unit. `:30-35` shows the thirty is actually a showing plus a
  complete portfolio, so this is loose phrasing, not the fifth-unit-test the rule forbids.
  Only line in 37 doing it.
- `THJ2O/shared/Setup/How Marks Work.md:9-10` — opening sentence "how you conduct
  yourself on a site" reads as marking the worker. The page draws the boundary properly
  later (`:111-113`, `:123-125` "Being organised is not worth marks") and its safety
  expectations are genuinely curricular (`:84-85`), so this is a first-sentence fix only.
- `THJ2O/shared/Setup/How Marks Work.md:36-37` — "the whole year" on a semestered page.
- `SCH4U/shared/Setup/How Marks Work.md:73-76` — the only page publishing per-category
  percentages (25/30/20/25), the "6% against 5%" false-precision shape `SKILL.md:613-618`
  warns about.
- `TEJ2O/shared/Setup/How Marks Work.md:122` — `[[D3.5|D3.5]]` degrades to a bare code,
  defeating the purpose of the pipe (`SKILL.md:495-498`).

---

## Priority 3 — Not yet checked by anybody

These are rules in the skills that **no** pass in this QC has tested. Listed so the gap
is visible, not because a defect is known.

1. **Curriculum verbatim fidelity against the live portals** — every check so far compares
   payloads against *each other*, never against `dcp.edu.gov.on.ca` or
   `curriculum.gov.bc.ca`. Needs network access. **Largest unexamined surface.**
2. **MCMPR11's real-world case facts** — Clearview AI order language, CrowdStrike BC impact,
   Komagata Maru, Landscapes of Injustice, Te Hiku Media. The BC skill (741-745) calls
   independent fact-checking of these "the highest-priority thing an adversarial reviewer
   checks".
3. **A mark page promising a weighting the task arc does not deliver** (`SKILL.md:365-367`)
   — named in the skill as a live failure mode. Candidates: `ADA1O:29-48`, `SCH4U:73-76`.
4. **The culminating task ends the course** (`SKILL.md:154-161`) — arc ordering untested
   in any payload.
5. **Every task day named, with several varied working periods** (`SKILL.md:162-183`).
6. **Ideas return in a different form on a later day** (`SKILL.md:184-193`) — the rule
   §1.1's numbers are a proxy for.
7. **All three kinds of assessment present in the ARC, not just in `Tasks/`**
   (`SKILL.md:196-220`).
8. **"Check the question is not already printed on the task page"** (`SKILL.md:735-739`).
9. **A pie carries the SHAPE of an answer, never an inventory** (`SKILL.md:598`) — only
   slice mechanics were tested.

---

## Priority 4 — Housekeeping

- **`SKILL.md` is stale about its own example.** It states that
  `ADA1O/shared/Tasks/_DUPLICATE ME.md` "nests one today and loses it on every
  curriculum-free install". It does not — markers at 46/50, block at 52-83, outside them.
  Fixed without the skill being updated.
- **Latent trap:** 10 `_DUPLICATE ME.md` files carry the literal `%%curriculum-start%%` /
  `%%curriculum-end%%` strings inside prose (`CGC1W/shared/Tasks/_DUPLICATE ME.md:42`,
  `ICS4U/…:43`, +8). `strip_curriculum_blocks()` at `scripts/setup_course.py:1482-1487`
  matches whole lines only, and both markers currently share one physical line. Reflow
  that sentence and the file stays count-balanced but becomes semantically wrong.
  Not a defect today.
- **`_DUPLICATE ME.md` scaffolds in `AVI1O/shared/Tasks/` and `TEJ4M/shared/Tasks/`**
  carry a `%%` block with no OBSERVE/TALK/`Record:` and prose after it. Probably intended;
  worth a decision.
- **ENG3U / ENG4U Key Links** have no blank line after the frontmatter, unlike the other
  36. Cosmetic.
- **Two 5-space-indented `$$` lines** at `MCMPR11/shared/Tasks/Task 1 - Pacific Trail
  Route Planner.md:62, 64`. They render correctly and satisfy the rule as written, but
  they are the only indented display math in 9,549 files and any naive ≥4-space lint
  flags them.

---

## Verified clean — do not spend effort re-checking

Scope: 10,116 filesystem entries, 9,549 `.md` files read in full, 3,172 class pages,
2,616 `^text` anchors, 12,120 table rows, 282 real task pages, 38/38 Key Links. Every
regex positive-controlled against a planted defect before being trusted.

**Structure (all 38):** illegal filename characters (tested on all entries including
directories and dotfiles, not just `.md`) · unescaped pipes in table wikilinks ·
`title: index` · hand-written `createdSectionN` / `publishForSectionN` keys · unbalanced
curriculum markers · curriculum blocks on class pages · exactly one `publish: false`
class page per payload (distribution is `{1: 38}` — none has zero) ·
`__CREATED_CLASS_K__` on every class page · "click to expand" in Exercises answer
callouts · read-only-checkbox lies · multi-line `$$` inside a callout · content after a
`^text` anchor.

**Key Links and landing pages (all 38):** every `[[…]]` resolved **by stem against the
real file tree**, not by folder prefix — zero land in a content folder, zero
unresolvable. Closing three bullets exact in 38/38, curriculum link inside the markers
and Scavenger Hunt outside in 38/38. Every landing-page transclusion equals the
highest-numbered published class page.

**Triangulation, 282 real task pages:** 0 links inside a block · 0 blocks nested inside
curriculum markers · 0 blocks not last in file · 0 missing OBSERVE / TALK / `Record:` ·
**0 named days that do not exist as a class page**. Max within-course text overlap 0.071
(near-identical templating scores >0.5) — these are genuinely not boilerplate.

**Mark pages, 37 Ontario (file inventory verified: 38 files, 17 distinct "how the class
runs" filenames — a name-based glob would have covered as few as 1 of 38):** zero
participation marks, zero peer/self scores feeding a mark, zero common group marks, zero
graded homework — all apparent hits are explicit *denials*. All 37 name the four
categories in plain language, state E/G/S/N is reported separately, and name all three
evidence sources. 25 of 37 carry a pie; every one is exactly two slices at 70/30, titles
within 26 characters. Twelve pages carry no pie, which is permitted.

**Pies corpus-wide:** 5-slice pies exist in exactly three payloads and no larger pie
exists anywhere — `TEJ4M/shared/Style/What This Site Can Do.md:216`,
`CGC1W/shared/Style/What This Site Can Do.md:56`,
`SNC1W/shared/Concepts/Where Our Electricity Comes From.md:23`. All three are
composition charts, not weightings.

---

## Claims killed by the verifier — do not act on these

Recorded so they are not re-derived by the next pass.

| Killed claim | Why |
|---|---|
| "MCMPR11 fails to name the Provincial Proficiency Scale" | BC skill:479-480 scopes the scale **"for K–9"**. MCMPR11 is Grade 11. The skill never asks a payload to name it. Not a defect. |
| "MCMPR11's `_DUPLICATE ME.md` is missing its triangulation block" | Fact is true (37 of 38 have one), but `lint_payload.py:221` **exempts the template by name**, and the requirement is in the *Ontario* skill (`SKILL.md:756-758`), not the BC one. |
| "MCMPR11 Task 1 and Task 3 blocks are boilerplate" | The shared skeleton is what BC skill:558-566 compliance produces. The details differ genuinely ("summit elevations exceeding 4000 m" vs "mutable lists as dictionary keys"). Line ranges were also wrong (139-156 / 119-136). |
| "MCMPR11 `Task 1:151` miscites D2.3" | The citation is "D2.3 **and K1.8**"; K1.8 = "logic, decision structure" carries the boolean-tracing claim exactly. Loose, not contradicted. |
| "`MCMPR11/Final Evaluation` names no curriculum code" | It names four — K1.8, K1.11, T1.2, T1.4 at `:144-145`. The original scan used an `[A-E]` character class, which also produced six further false positives on F-strand codes. |
| "`CIA4U/The Policy Brief.md:156` miscites D3.1" | Neither D3.1 nor D3.2 says "lags", and the block already spent D3.2 on the preceding question. A preference, not a miscitation. |
| "`GLC2O/The Plan Defence.md` cites A2.2 as heard when its text says 'document'" | The sentence is at `:127` and does not say "heard"; it quotes A2.2's "commenting on the effectiveness of the strategies" clause accurately. |
| "`BOH4M/The People Problem.md:90` contradicts its own day page" | The full sentence says the tick rides "**on the same pass of the room as the notes**" — it already accounts for Day 1 item 4. |
| "`SPH3U/Motion Story.md` collides OBSERVE and TALK" | `:94` reads "at the conference **already on that agenda**", and Unit 1 Day 17 books both a working period and a conference — this satisfies `SKILL.md:743` rather than violating it. (The cited warning is also at `Sound in a Space.md:73`, not :83.) |
| "`ENG3U` OBSERVE prompts name no code" / "`SPH3U` gives one strong answer for two questions" | True as facts; no rule requires either. The skill's own model block does both. |
| "`ADA1O/Tableau Story Sequence.md:113` miscites A1.2" | The block's gloss matches A1.2's verbatim text word for word. Downgraded before the verification pass and confirmed. |
| "`CGC1W`'s Quality of Life page sits unlinked" | It is linked twice — `Concepts/index.md:47` and `Unit 3, Day 3.md:14`. The honest claim is "unlinked *from Unit 4, Day 13*". |
