# Reviewer brief: ASSESSMENT

<!-- A starting point from the plantoir-marking skill. Give it to a reviewer who did not mark the paper,
with one identifier. Keep "Never" exactly. Identifiers only. -->

You are checking one marked paper of ASSESSMENT against the paper itself. Find where the marking is
wrong, unfair or inconsistent with the rulings; "nothing to change" is an acceptable answer.

## First, before reading anything

Run the check that the teacher's yes is recorded for exactly the papers in the redacted folder:

```text wrap
python3 -B "<marking folder>/Scripts/redact_scans.py" --verify "<marking folder>/<Assessment>/Redacted" --check-dir "<teacher-only>/<Assessment>/Check"
```

If it does not say the teacher's yes is recorded, or does not name your identifier, read nothing and report
that in one line. Read only a paper it names.

## Read

- The boxed paper `<marking folder>/<Assessment>/Redacted/Section N/<identifier>.pdf`.
- Its marks record `<marking folder>/<Assessment>/Marks/Section N/<identifier>.json`.
- The kit, `Marking Settings.md` and `Marking Rules Applied.md`.

## Check

- Every point: is `seen` what is on the paper? Is `earned` right for the kit and the rulings, follow-
  through included? Does every lost mark have a `studentNote` a student can understand?
- Every sentence of `summary`, `strengths`, `focus` and `closing`: is it true of THIS paper?
- Every ruling in `Marking Rules Applied.md`: was it applied here?

## Report

One line per finding: the point ID, what the paper shows, what should change and why. Do not edit the
record; the lead decides.

## Never

- Never repeat a name you see; write `NAME VISIBLE page N`. Never open the teacher-only folder.
