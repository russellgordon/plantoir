# The folders sheet names the raw curriculum key, not the folder the build resolves

Rank: 2 of 18. Affects every real course checked.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Contract cases waiting on the mac" — the two cases
"the curriculum folder is named even when the course never recorded one" and
"a recorded name the course no longer has is not shown", both proposed
2026-09-06 and already present in `contracts/shared-rules.json` →
`specialFoldersHelp` → `cases`, tagged PROPOSED FROM WINDOWS.

## The defect
`mac-app/QuartzTeachers/Views/CourseSettings/SpecialFoldersHelpView.swift`
line ~36 reads the raw key:

    if let curriculum = course.configuration.curriculumFolder, !curriculum.isEmpty {

so a course that never recorded one gets the "Your curriculum folder"
placeholder, and a course whose recorded name went stale is shown a folder it
does not have. Nothing in the mac Swift ever writes `curriculumFolder` — only
`scripts/setup_course.py` does, and only from an example-content or skeleton
manifest — so **the key absent is the normal case, not a corner case.** The
sheet currently tells those teachers to create a folder they already have.

## The fix already exists
`CurriculumFolderRule.resolvedCurriculumFolder(for:)` —
declared in `mac-app/QuartzTeachers/Models/SpecialNames.swift` around line 167,
owned by `enum CurriculumFolderRule`, NOT by `SpecialNames` (grepping the file
name as a type finds nothing). Already used for folder protection in
`CourseSettingsView.swift` around line 578.

## THIS SESSION ALSO OWNS ISSUE 03
Issue 03 — retiring the placeholder's second sentence — is the `else` branch of
the same `if`, four lines below. Do both here; they are one edit and one test.
The sentence to retire is "One page per expectation, in a folder whose name
mentions the curriculum." It publishes the matching rule in plain words, which
is exactly what this sheet's design exists to avoid. The placeholder NAME stays
and still tells the teacher what to make; the explanation beside it does not
change. See `specialFoldersHelp.rows[curriculum].whyPlaceholder` in the
contract, which explains the reasoning at length.

## What done looks like
- The `if` names the resolved folder; the `else` keeps the placeholder name and
  drops the second sentence.
- A NEW test deserialises `specialFoldersHelp` from `contracts/shared-rules.json`
  and runs its cases, rows, listing grammar and banned vocabulary.
  `mac-app/Tests/QuartzTeachersTests/SpecialFoldersHelpTests.swift` exists but
  reads none of the contract, and its fixture defaults to
  `curriculum: String? = "Ontario Curriculum"`, so the placeholder branch has
  never run in a test. The scaffold to copy is in
  `SharedRulesContractTests.swift`.
- **Two pieces of prose go stale the moment this lands and must be fixed in the
  same session**: `specialFoldersHelp.rows[curriculum].whyPlaceholder` (it says
  "The mac has a SECOND sentence here today"), and `contracts/README.md`
  (search for "mac side not yet adopted"). `shared-rules.json` is hand-authored,
  not generated, so nothing regenerates these for you.
- `MAC-HANDOFF.md` waiting lines removed, ledger entries marked done.

## Caution
The banned-vocabulary list now includes "substring", "segment" and
"case-insensitive" alongside "container". The rule is scoped to text the
PRODUCT writes — a teacher's own folder called "Scripts" is their word, not a
wording bug.
