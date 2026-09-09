# Retire the placeholder's second sentence — expected to be already done by issue 02

Rank: 3 of 18.
Kind: verify (expected no-op)
Gate: unit

## Read this first
This issue is the `else` branch of the same `if` that issue 02 fixes, four
lines apart in the same file. **Issue 02 was briefed to do both.** It ran before
you.

## Your job
Check whether it is done, and act accordingly.

1. Read
   `mac-app/QuartzTeachers/Views/CourseSettings/SpecialFoldersHelpView.swift`,
   the `else` branch of the curriculum row (around line 44).
2. If the sentence "One page per expectation, in a folder whose name mentions
   the curriculum." is GONE and the placeholder name "Your curriculum folder"
   remains, and a test covers the placeholder branch: you are done. Verify the
   contract's `whyPlaceholder` note and `contracts/README.md` were updated too,
   fix them if not, and report
   `BATCH-RESULT: NO-CHANGE-NEEDED` with what you checked.
3. If it is still there — issue 02 failed, was blocked, or did only half —
   finish it here to the same standard: retire the sentence, keep the
   placeholder name, cover the branch with a test that deserialises
   `contracts/shared-rules.json` → `specialFoldersHelp`, and update the stale
   prose.

## Why the sentence must go
It publishes the matching rule in plain words. This sheet's whole design is to
name the folders a course actually has rather than describe how they are found
— saying "any folder whose name mentions the curriculum" invites a teacher to
get creative with it and turns an implementation detail into a promise the
product then has to keep. The mac's own jargon test never caught it because
"mentions" is not a banned word and the fixture course always has a curriculum
folder, so the branch never ran.

Do not invent extra work to justify the session. A clean no-op is the expected
and correct outcome.
