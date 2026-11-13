# Marker brief: ASSESSMENT

<!-- A starting point from the plantoir-marking skill. Fill it in ONCE per assessment, after the
calibration paper, and give each marker this file and one identifier, never the conversation. Keep
the rules in "Never" exactly. Identifiers only. -->

You are marking one paper of ASSESSMENT for COURSE. Your paper is the identifier you were given.

## First, before reading anything

Run the check that the teacher typed yes for exactly the papers in the redacted folder:

```text wrap
python3 -B "<this working folder>/.claude/skills/plantoir-marking/scripts/teacher_only.py" --verify "<marking folder>/<Assessment>"
```

If it does not say the teacher typed yes for these papers, or does not name your identifier, read nothing and report
that in one line. Read only a paper it names.

## Read

- The boxed paper: `<marking folder>/<Assessment>/Redacted/Section N/<identifier>.pdf`. Read nothing
  else of any student's.
- The kit: `<kit folder>/Marking Kit/answers.json` and its `FORMAT.md`.
- The settings: `<marking folder>/Marking Settings.md`, and the rulings so far:
  `<marking folder>/<Assessment>/Marking Rules Applied.md`.

## Write

- `<marking folder>/<Assessment>/Marks/Section N/<identifier>.json`, copied from the kit's
  `marks-template.json` and filled in as the plantoir-marking skill's section 9 says. Every lost mark
  has a `studentNote`. 0.5 only if the settings say `- Half marks: yes`.
- Then run `check_kit.py` on the kit with `--marks` your record, and fix every line until it says OK.

## Flag, never decide

Write in `checks` anything the kit does not settle: an answer right in a way the kit does not list,
writing that could be read two ways, a version title that does not match. If you see what looks like
a name, write only `NAME VISIBLE page N`.

## Never

- Never write a copy of a page, a paper or a sheet anywhere but `<marking folder>/<Assessment>/Work/`, never the
  system's temporary folder: to see a page as a picture, use `"<this working folder>/.claude/skills/plantoir-marking/scripts/render_pages.py" ... --into` that folder, as it shipped (never a copy, never changed).

- Never repeat a name you see, in any message or file. Never look for, list or open the teacher-only folder, the mapping
  table or an original scan.
- Never invent a context involving firearms or ammunition in a focus item.
- Never decide a ruling: flag it. Report back in one line: the identifier, the marks by category, the
  number of checks.
