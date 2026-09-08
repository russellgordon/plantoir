# Repair results are keyed by finding name, so duplicate findings collapse

Rank: 7 of 18. Real, small, and unreachable through today's single caller.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", the same folder-problems
entry from Windows (2026-09-06) that produced issue 06. This is the second of
the two defects that review found in the mac's repair code.

## The defect, confirmed
`mac-app/QuartzTeachers/Models/SiteHealthRepair.swift` around lines 259-266:
`repair(_:in:)` returns a `[String: Result]` keyed by `finding.name`. Two
findings of the same kind — two `sectionIndexMissing`, say — collapse to
whichever was processed last, so one of them is silently reported with the
other's outcome.

## Why it is not urgent, and why it is still worth fixing
The only caller today is `SectionDetailView.swift` (around line 376), going
through `outcome(ofRepairing:)` with the findings from ONE section's runner, so
duplicates cannot arise in practice. That makes this a latent defect rather
than a live one — say so honestly in the write-up rather than dressing it up.
It is worth fixing because the collapse is silent and the next caller will not
know the constraint exists.

## What done looks like
- Results are keyed by something that is actually unique per finding, or the
  return shape changes to one that cannot collapse.
- A test proves two same-kind findings keep separate outcomes.
- The write-up says plainly that this was unreachable through the current
  caller, so nobody later mistakes it for a shipped bug.

## Caution
Issue 06 owns the `index.md` directory defect in this same file and ran before
you. Do not redo it, and do not "tidy" it. If issue 06 failed and left the file
in a broken state, say so and stop rather than untangling both.
