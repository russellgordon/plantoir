# Growing Success sweep — outstanding work when the account limits hit

Every payload below is **linter-clean and passes the mechanical checks**, so
none is broken. Each is at a different point in the author → adversarial
review → verified fix cycle, and the differences matter.

## Authored and self-reviewed; NO independent review yet

- **SNC1W** — its own pass plus a sub-agent found 18 defects, all fixed.
  Created `Tasks/Lab Reports.md` for seven investigations whose eleven
  expectations were marked but invisible to the coverage map. Dropped C2.6
  as the one code no investigation asserts.
- **BOH4M** — its own pass found 18. Removed two outright policy breaches: a
  "Team review — each member's account of what the team did well and badly"
  feeding individual marks, and a "Professionalism — on time, prepared,
  discreet" criterion. Found The People Problem was an evaluated task with no
  class working period at all.

## Reviewed; fix round started and did not finish

- **SPH3U** — 12 findings. The important one: the D2.5 leg was written on the
  INPUT side only (V, I, t), with no method, apparatus, criteria row or period
  for the output, and the motor the course builds is unloaded, so there is no
  mechanical work to measure. Also two transformer codes on a task with no
  transformer, and the five write-ups' check-in promised twice and scheduled
  nowhere.
- **TGJ2O** — 10 findings, fix round barely started. The important one: the
  rewritten row "Filed while it is news | The recap reaches readers within two
  days" against an arc that publishes six class days after the event — every
  student fails it for obeying the schedule. Also A3.3 and D2.4 carrying the
  whole learning-skills exception with no section, row or period on either
  task page.
- **CHC2D** — two rounds of review. Round two found 17 more, including the
  notebook handed in three classes before students are told to bring it (and
  into the examination), and a "Conduct" criteria row on the culminating task
  while the mark page says conduct is not marked.
- **CHA3U** — reviewed against a moving target (files changed mid-review; the
  reviewer said so and pinned a timestamp). 14 findings including a Document
  Examination OBSERVE whose window ends where the observed behaviour would
  start, and five of eleven OBSERVE prompts being one probe in five costumes.

## Authoring interrupted mid-pass

- **SPH4U** — was mid-fix on its own self-review findings. Its independent
  review has since reported (its routing failed and it arrived via the main
  session): B3.3 transcluded on a task that never asks for a derivation, and
  it is the only B3 code on any Tasks page, so the B3 overall rests on it; a
  C1.2 leg written around a "measured speed" the course never measures; and
  two legs given a section and a row but no period.

*(MDM4U finished and was committed in `3191fa98`; its independent review has
since reported and its fix round is running.)*

## Not started (16)

ATC1O · AVI1O · CGC1W · CGF3M · CIA4U · ENG2D · ENG4U · ICD2O · MCR3U ·
MHF4U · MTH1W · SBI4U · SCH4U · SNC2D · TEJ2O · TEJ4M

CGC1W was dispatched and its author died before writing anything — the
payload is untouched, not half-edited.

## To resume

The two briefs are `gs-conformance-brief.md` (417 lines, 24 failure modes)
and `gs-review-brief.md`, both beside this file. `verify_gs.py` runs the
mechanical checks, including a simulation of the build's own comment
stripping to catch teacher text that would reach students.


---

# Cross-payload defects found during the sweep, deliberately not fixed

Both are real, both are outside a Growing Success brief, and both need the
live ministry document or a payload-wide sweep. A half-done sweep is worse
than none, so no instance of either was touched.

## Calendar drift in the English payloads

Every English payload runs `class_weekday_step: 1` over 86 classes — September
to mid-January — and every one of them names months outside that window:

| payload | pages naming February–June |
|---|---|
| ENG3U | 26 |
| ENG4U | 24 |
| ENL1W | 20 |
| ENG2D | 15 |

ENG4U's author documented the specifics on its own payload: the independent
study is described as "October to April", its checkpoints are dated
"Mid-February" and "Late March", and `Showing Growth`, `Your First Entry` and
`Portfolios/index` refer to May and June. `How This Class Works` and
`Tasks/index` carry it too.

Not every hit is a defect — a month can appear in a text, a quotation or a
generic reference — so this needs reading per instance rather than a
find-and-replace. The scheduling claims are the ones that mislead.

## Truncated and corrupted curriculum text

The skill's Phase 1 rule is verbatim or not at all. Beyond the nine pages
recorded earlier, ENG4U's pass found two more truncated mid-sentence —
**C1.5** ("determine whether the ideas and information") and **C3.6** ("use a
variety of presentation features, including") — both of which sit on task
pages. **C4.1** also has a stray teacher-prompt fragment spliced on after its
closing parenthesis.

Authors have been told not to cite any truncated code in a triangulation
block, and none has. But a teacher following ENG4U's Critical Essay block
opens a C4.1 page with junk on the end of it.

Fixing these means re-fetching the live Ontario English curriculum. It is a
Phase 1 job, cheap to do on its own, and it should be done before the English
payloads are shown to anyone.
