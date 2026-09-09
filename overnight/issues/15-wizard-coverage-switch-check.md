# A from-scratch course may write the curriculum-coverage flag from the raw switch

Rank: 15 of 18. A check that may turn out to be nothing.
Kind: verify, then implement only if a real defect is found
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", inside the
exclusions/protection entry — listed there as "a check", not a known defect.

## What to check
Windows' `CourseConfiguration.CurriculumCoverageEnabled` only ENABLES curriculum
coverage while pre-populate AND curriculum pages are both on, and only for a
code whose example content includes curriculum. The concern is that the mac
wizard may write `include_curriculum_coverage` straight from the RAW switch, so
a from-scratch course can end up with coverage enabled and no curriculum folder
to build it from — after which the build reports that it found nothing.

Windows chose that failure deliberately; read their reasoning in the handoff
before deciding the mac should differ.

## What to do
1. Read the mac wizard's path from the switch to the written config.
2. Read `scripts/build_site.py` for what happens when coverage is on and no
   curriculum folder exists.
3. Decide whether the mac's behaviour is a defect, a deliberate difference, or
   identical to Windows already.

**"Checked, no defect, here is the trace" is a complete and valuable outcome.**
Report `BATCH-RESULT: NO-CHANGE-NEEDED` and record the trace in the handoff so
nobody checks it a third time.

## If it IS a defect
Fix it here. Russell confirmed on 2026-09-06 that a defect found by this check
is to be FIXED in the same session, not merely reported — only the finding
needed him, and it does not.

Fix it, test it, and note that the wizard will let a curriculum folder go after
a confirmation — so the state is reachable by a second route as well as by the
switch, and both need to behave.
