# Adversarial review brief — Growing Success payload revisions

You are an ADVERSARIAL reviewer for ONE payload, named in your task prompt.
Find what is WRONG. Assume every factual claim is misremembered until you have
checked it against a primary source, and every new rule conflicts with an
existing one until you have read the surrounding file. **Do NOT edit any
files.** Do not pad — one line per category where you find nothing.

Repo: /Users/russellgordon/containerized-quartz-for-teachers, branch
bc-curriculum. The changes are UNCOMMITTED:

    git diff -- support/example_content/<CODE>

Specification: `.claude/skills/example-content/SKILL.md` — the Phase 2 section
beginning "Every Ontario course must show all three kinds of assessment", and
the Phase 5 section "Every task page ends with a hidden triangulation prompt".
Work order: `gs-conformance-brief.md` beside this file. Finished reference:
`support/example_content/ICS3U/`.

## Attack these, in priority order

1. **DO THE TRIANGULATION BLOCKS TELL THE TRUTH ABOUT THIS COURSE?** Highest
   value — this is where the first pass has failed every previous time, in
   every payload checked so far. For EVERY block: does the named unit/day
   exist; does that task actually run on that day; is the period described
   ("the counting period", "the conference already on that agenda") really
   what that day's agenda says; is the "product evidence is X on Day N" claim
   correct? Check each against `per_section/All Classes/`. Quote the day's
   real agenda line for every mismatch.

2. **ARE THE CURRICULUM CODES HONEST?** For each code a block names: is it
   listed in that task's own `Curriculum connection`, and does the
   expectation's verbatim text in `shared/Curriculum/` actually describe the
   evidence that question would produce? Two traps seen before: a code about
   *terminology* used to cover reasoning, and a code whose text says
   *"in writing"* used to justify conversation evidence.

3. **DOES `How Marks Work` CONTRADICT ANYTHING?** Its arithmetic (any pie must
   total 100 and match the 70/30 story), and every other page in the payload
   that describes marks — `grep -ril "mark\|assessed\|weight"`. A page still
   describing the old scheme is a defect. If a pie was kept, check the skill's
   pie rules: two slices for the 70/30 split, nothing under 3%, short title.

4. **GROWING SUCCESS FIDELITY.** (a) A feedback checkpoint followed by a
   period to ACT on it, in EVERY unit — verify each pair, do not accept the
   author's list. (b) Are the diagnostics genuinely diagnostic, or relabelled?
   (c) Is the MODELLED first use of the self-assessment page actually
   scheduled on a class page, or only claimed on the page itself? (d) Any peer
   or self judgement still feeding a mark; any common group mark; any
   evaluated work still assigned only as homework.

5. **DID THE EDITS BREAK THE COURSE?** Read every edited class page IN FULL.
   Agendas numbered 1..N with no gaps. Time budget plausible for one period —
   an agenda that gained an item may now be impossible. "Things to do before
   our next class" still matching what the agenda actually did. Anything
   downstream that depended on an activity that was removed or moved.

6. **STYLE AND MECHANICS.** ~80-column wrap, Canadian spelling, no H1. And
   critically: **no `[[wikilinks]]` or `![[transclusions]]` inside any `%%`
   block** — write a script and check, do not eyeball. Blocks placed AFTER
   `%%curriculum-end%%`, never inside. Run
   `python3 .claude/skills/example-content/lint_payload.py <CODE>` and report
   its final line — but clean proves almost nothing here, so do not stop there.

7. **BOILERPLATE.** Compare the blocks against each other AND against
   ICS3U's. Two blocks from different units must share no sentence. Report any
   sentence reused across blocks or lifted from ICS3U — at this volume,
   convergence to a template is the likeliest silent failure.

8. **WHAT WAS MISSED, and give credit accurately.** Which requirements are
   genuinely met by this diff, which are asserted but absent, and which were
   already true before it. Do not credit the diff for what the course already
   did.

## Deliverable

Prioritised concrete defects. For each: file:line, what is claimed, what is
actually true WITH the evidence (the agenda line, the expectation text), and
the smallest correct fix. Separate CONFIRMED from SUSPECTED. End with your
single most important finding.
