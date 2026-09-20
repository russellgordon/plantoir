# Adversarial review findings, kept on disk

Every independent review in the Growing Success sweep lands here as a file
before any fix is applied.

**This folder exists because the sweep lost a set of findings.** ICD2O, ENG2D
and AVI1O were each reviewed, the findings were delivered into a conversation,
the fix round started, and the conversation was then summarised away. Their
commit messages claim the confirmed findings were applied and there is nothing
left to check that claim against — so the only honest option is to review those
three again from scratch.

A review is worth more than the fix round that follows it: it is the expensive
half, it is the half that cannot be re-derived from the files, and it records
what was DELIBERATELY not fixed, which is invisible in a diff. So it gets
written down before it is acted on.

One file per review, named `<CODE>-<date>.md`. Keep the reviewer's own words —
including the findings that turn out to be wrong, marked as rejected with the
reason. A rejected finding is evidence about the reviewer and about the trap,
and the next reviewer will otherwise walk into it again. This has already
happened twice: one reviewer under-counted a defect class by a third, and
another flagged text that was correct, where the "fix" would have deleted a
true number off the page.
