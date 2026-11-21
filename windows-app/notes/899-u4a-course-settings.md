# #899 U4a: Course Settings, Add folder and Set School Year (notes for Windows)

## For PROGRESS

- Mac U4a: Course Settings' Save, Add folder and Set School Year are each one step through the door (`saveCourseSettings`, `addFolder`, `setSchoolYear`). Windows owes the same in W8.
- `undo-action-steps.json` has 25 steps; the three new ones carry `members` (editJSON) and `trees` (createTree). `undo-traces.json` has 150 action traces (the first 132 unchanged).
- New contract text: `shared-rules.json` → `undo.wording` (8 sentences), `undo.rule.shadow` reworded, `activityTrail.mustRecord` "undo could not record a step" `carries` reworded, one new stack row, one stack row renamed; `class-planning.json` → `todaysClassOnTheFrontPage.wording.keptGone`.

## For documentation 12

### What W8 copies from U4a

- **Save of Course Settings is ONE step**: one `editJSON` per top-level member whose VALUE the Save changes (keys sorted), each `before` the value in the file read when the step is planned, absent (no `before`) when the member was absent. Each member's bytes move by the member rule (`editJSONCases`); a file that is missing, not one JSON object, or that the member rule cannot move is one `writeFile` of today's whole bytes. A step refused because one of its own members changed between plan and make is planned again from the file, up to three times. A Save that changes no value writes nothing and makes no step. Revert writes nothing.
- **Add folder**: one `createTree` per folder made (the folder and the two scaffold pages), the highest missing folder of its path the tree's root; all or none; the list's own change is Save's step.
- **Set School Year**: one step, one `editJSON` on `reference_school_year`.
- **Undo takes back only its members**: another window's Save of another member, or a build adding a folder, is left; a member of the step changed again refuses the Undo, names `course_config.json`, clears the list.
- **Bytes**: a changed member is spelled compactly (`"hidden" : ["Media"]`); every value is the same as before.

### The lows fixed with U4a that W4c and W7 copy

1. **The `undo could not record a step` line (U3 sweep, finding 2).** Written only once the shadow write has answered, worded by what happened: went ahead ("The change went ahead (the list is not in use yet)."), nothing was changed ("Nothing was changed."), stopped part way ("The change stopped part way; what a file held before is kept beside it."), made with its closing line not yet written ("The change was made; its record is finished at the next chance."). Mac: `UndoUnrecordedChange`, `UndoTrailHook.couldNotRecord(action:course:section:why:after:)` around `writePlainly` and `makeWithoutARecord`, and the shadow swap in `JournaledWrite.perform`. Before, the line said "went ahead" before a write that could still refuse (always for a page that is a link).
2. **Switch-off refusals (finding 3).** `undo.rule.shadow` now says: with the switch off, a daily action whose file is a link, a folder or unreadable is refused before anything changes, as is one whose file changed between plan and make; a refusal part way keeps what a file held beside it. Before U3 those wrote (a link was replaced by a regular file). Windows' door must refuse the same.
3. **Duplicate Class (finding 4).** When the copy is refused and the room alone then cannot be made, the reply is "Nothing was changed: …", never "a blank class page is waiting".
4. **An Undo or Redo never deletes an only copy (U3c review 3, LOW 3).** Under the lock, before the swap: each page's outgoing bytes that the step's other direction needs (a writeFile op's after for an Undo, its before for a Redo) go into the list when it lacks them; when the list will not take them they are kept beside the page and the other direction is made from that kept file.
5. **One kept copy per content (LOW 1).** After a move that kept outgoing bytes beside a page, the step's kept copies beside that page are thinned to one per distinct SHA-256 (the newest move's kept for its content).
6. **Show in File Explorer for a kept file that is gone (LOW 2)**: say `keptGone` in an alert with OK and show nothing.

### Not readable on Windows yet (no ledger row added)

- `actionTraces` for `saveCourseSettings`, `addFolder`, `setSchoolYear` (W7's reader).
- `undo-action-steps.json` `members` and `trees` (W7).
- `undo.wording` (no Windows reader; W4c and W7 say these sentences).

### Ledger rows changed

- `Reason899W4cWithW7`: one stack row renamed (the rollover of only its records, a leftover and the year), one added ("a later rollover's Undo that leaves its record apart keeps an earlier page's kept original beside it, untouched").
- `Reason899W4cKeptAlert`: `keptGone` added to the held `TodaysClassWording` keys.
