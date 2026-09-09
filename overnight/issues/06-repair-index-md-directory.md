# A directory named `index.md` is reported to the teacher as "already put right"

Rank: 6 of 18.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", the folder-problems entry
from Windows dated 2026-09-06. Windows built the folder-problem front end and
in doing so found two defects in the MAC's own repair code. This is the first;
issue 07 is the second.

## The defect, confirmed
`mac-app/QuartzTeachers/Models/SiteHealthRepair.swift` around line 294:

    if FileManager.default.fileExists(atPath: index.path) { return .alreadyFine }

No `isDirectory:` out-parameter. So a *directory* named `index.md` satisfies the
check and the repair reports `.alreadyFine`. `outcome(ofRepairing:)` (around
line 98) sorts `.alreadyFine` into neither `restored` nor `failed`, so the
teacher is told the problem was already put right when their section still has
no front page and will not publish correctly.

Compare `restoreMedia` in the same file (around line 277), which uses the
`isDirectory:` form and has a comment explaining why — so the correct pattern is
already in the file, four functions away.

## What done looks like
- The check distinguishes a file from a directory.
- **Russell decided the behaviour on 2026-09-06, before the batch ran: refuse
  and explain, touch nothing.** Report it as a problem the teacher must resolve,
  naming the folder, and do not move, rename or delete anything. The rejected
  alternative was to move the directory aside and write a proper index page —
  rejected because that relocates a folder which may hold their pages without
  asking, and neither app can see what is inside it. Record the rejection and
  the reason.
- The refusal is new text a teacher reads, so the sentence belongs in
  `contracts/shared-rules.json` and is named rather than quoted elsewhere.
- A test covers the directory case.
- If the teacher-facing outcome changes, `contracts/shared-rules.json` and the
  activity trail (rule 5) may both need updating — check rather than assume.

## Caution
Do not widen the change into a general audit of `SiteHealthRepair`. Issue 07
owns the other defect in this same file; leave it alone.
