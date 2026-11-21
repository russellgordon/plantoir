# #899 U3b, the rollover: notes for the director (fix round four, 2026-11-20)

## For PROGRESS

Nothing new for Windows to show yet: the rollover as one step is W7. When W7
lands, its PROGRESS line should say the rollover moves only what must move
(below) and names every kept file through one chooser.

## For documentation 12

Corrections to the W7 row's U3b passage ("From U3b's fix round three: ..."),
made true by fix round four:

- `undo.netlifyRecordCases` is now 20 rows (was 13). New field
  `currentEndsWithAByteThatIsNotUTF8` (the byte FF follows the row's text).
  `site` is the id a deploy GOES ON WITH: `site_marker.get("id")`, null when
  absent or empty, or when the record is not an object.
- The section's website is that site. A Netlify record that names no site
  (`null`, `{}`, `[]`, a string, an empty `id`) is not a website: a rollover
  moves nothing of it and says the section was on no website. A record whose
  bytes cannot be read at all stays "still pinned" (cannot tell now).
- Only what must move, moves. With no site, nothing is brought in or moved.
  With the legacy record's site, it is brought into the current place (a
  current record there that does not parse first moved to
  `section<N>.unreadable.json`, NEVER moved again). With the current record's
  site, a legacy record that parses and differs is brought in as
  `section<N>.from-built-output.json` and set aside by the step (`setAside`);
  one that says the same is removed; one that does not parse stays in the
  built output. Delete from the row: `section<N>.unreadable.json` as a
  `setAside` leftover, and "a section<N>.json that does not parse" set aside.
- Every kept name of a step comes from one chooser (Mac:
  `DeployCommand.KeptNames`): the file's own name with `.previous-<stamp>`
  before `.json`, then `.2`, `.3`… after the stamp, the first neither on disk
  nor already chosen in the step. A record's kept name that is taken no
  longer leaves the record pinned.
- The "starts at the next login" trail line is written only after the whole
  swap has gone in (Mac: `UndoExternalPlaces.noteItStartsAtTheNextLogin`,
  called by the journal after `.swapped`), never inside the write.

No contract row Windows runs today changed (Windows has no walk over
`netlifyRecordCases`; `scripts/test_netlify_record_a_deploy_reads.py` runs
there through `PythonToolchainTests` and passes on the new rows), so nothing
new is held in `NamedGapLedger.cs`.
