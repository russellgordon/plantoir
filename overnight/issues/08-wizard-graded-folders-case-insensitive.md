# The new-course wizard exact-matches graded folders where the Python and Windows do not

Rank: 8 of 18.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", inside the long
exclusions/protection entry from Windows (search for `reconciledGradedFolders`).
It is a finding with no contract case behind it — part of what you owe is
deciding whether it deserves one.

## The defect
`mac-app/QuartzTeachers/Views/NewCourse/NewCourseWizardView.swift` around line
1075, `reconciledGradedFolders`, matches folder names exactly. The Python and
the Windows app both match case-insensitively, so a course whose folder is
`tasks` rather than `Tasks` has its graded folder silently DROPPED by the mac
wizard and kept by everything else.

Verify all three sides before changing anything: read the Python
(`scripts/`), read the C# (`windows-app/Plantoir.Core/Models/`), and read the
Swift. The write-up needs to say what each does today, not what you assume.

## The direction is settled
Align the MAC to the Python and Windows, not the other way round. Two of three
already agree, the Python is what actually builds the site, and a teacher whose
folder is `tasks` is currently having it silently dropped — so the mac is the
one that is wrong. Do not "fix" the Python to match the Swift.

## What done looks like
- The mac matches the same way the other two do.
- If the three disagree in some further way you find while reading, say so
  rather than quietly aligning to one of them.
- A contract case if this is a rule with inputs and expected outputs — which it
  looks like. `file-formats.json` or `shared-rules.json` are the candidates;
  justify the choice.
- A test.

## Caution
Case-insensitive comparison has a locale trap. Prefer an explicitly
case-insensitive comparison over lowercasing with the current locale, and say
which you used and why.
