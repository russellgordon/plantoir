# #899 W7b2-6: Show on Front Page is ONE step (Windows #949)

**This branch never merges without W7b2-9** (the one alert that names the kept file). Merged alone, a part-way front page would say nothing at all: the view maps `ShownWithWhatItHeldKept` exactly as `Written` for now.

Branch `issue/899-w7b2-6-todays-class`, from `origin/night25/integration-1` 53bb1959f (= `dev` a03fecefd + W7b2-5 + W7b2-11, the director's base). `origin/dev` (a03fecefd) is already contained in the base, so both "merge `origin/dev`" steps were no-ops ("Already up to date"; no merge commit). No `contracts/` change, no `mac-app/` change.

## For PROGRESS

- W7b2-6 (#899): Show on Front Page (`TodaysClassOnTheFrontPage.ShowOnTheFrontPage`, reached by `AssistWorkspace.ShowTodaysClass`, key `showTodaysClassOnTheFrontPage`, made by `sheet`) writes the front page through ONE `UndoActionStep`, the page as the step's content (`writeFile`), never a `recompute`: the teacher's own choice of class, as the mac's `TodaysClassOnTheFrontPage.show(_:in:)`. The step is asked for (`newStep`) only once the page is to be written, so `AlreadyShows` and `NoLongerOffered` make no step. The fixture row is converted (driven on the mac's `morning()` for 2026-09-30, its offer, Unit 2, Day 5 in place of Unit 2, Day 4; out of the ledger; it was never in `HeldButRunnable`), and its traces run the real Windows action.
- `TodaysClassOnTheFrontPage.Outcome` is now a closed record family (`Written`, `ShownWithWhatItHeldKept(KeptOriginals)`, `AlreadyShows`, `NoLongerOffered`, `CouldNotSave`) so the part-way case carries each kept file (full paths; `KeptNames` gives the names), as the mac's `shownKeepingWhatItHeld(from:to:keptOriginals:folder:)`.
- Riding lows: W7b2-5 review 1 L1 (notes), L2 (`PlaceInTheFolder` removed, the step sorts by `Relative`), L3 (`APlanThatChangesNothingMakesNoStep` checks the declined sentence); W7b2-11 review 2 L1 (#1043 named in its notes) and L2 (the held-timetable sentence now has a curly apostrophe: "Nothing was changed: another program, such as a syncing service, is using this section’s class dates. Try again in a moment."; its test changed to match). PROGRESS's own copy of that sentence, if folded in with a straight apostrophe, wants the same curly one.

## For documentation 12

- Show on Front Page's outcomes: a refusal before anything changed is `CouldNotSave` (its sentence, "The front page could not be saved, so it still shows {shown}.", is true: all or none). A step the door left PART WAY (the page holds the new class, its earlier content kept beside it as `.index.md.plantoir-undo-*-orig`) is `ShownWithWhatItHeldKept`, never `CouldNotSave`. Its trail line is the mac's: `put today's class on the front page — {to} in place of {from}. What “index.md” held just before is kept beside it as the hidden file “{kept}”` (event `PutTodaysClassOnTheFrontPage`). Every other trail line is unchanged.
- Today's in-memory undo (`UndoHistory`, Undo Last Change) was never told of this write and still is not: the step is made directly (`step.Make()`), not through `MakeTheUndoStep`, so Undo Last Change behaves as before.
- Windows still does not read the page back after the write (the mac's `show` re-reads it and answers `couldNotSave` when the line does not name the class). Unchanged here: the brief keeps every outcome as it was.

## Must-fail lines

`vm-tools/guest/899-w7b2-6-mustfail.json`, run by `899-w7b2-6-go.ps1` (calling `899-w7b2-6-pc-run.ps1`, a copy of `899-w7b-pc-run.ps1`). Each row is reverted alone, its test run, then restored with `git checkout`.

RUNS_PLACEHOLDER

## Left for the next piece

- Not Today's record (`RecordNotToday`, W7b2-7): the writer-scan entry for `TodaysClassOnTheFrontPage.cs` is now 2 (its `Directory.CreateDirectory` and `File.WriteAllText`) and says so.
- The alert (W7b2-9), see below.

## For the director

- **For W7b2-9.** `AssistWorkspace.ShowTodaysClass` returns `TodaysClassOnTheFrontPage.Outcome.ShownWithWhatItHeldKept` with `KeptOriginals` (each kept file's FULL path, the one to select in File Explorer) and `KeptNames` (file names, for `kept`). The only caller is `SectionDetailView.OfferTodaysClass` (about line 1303): the switch has an arm `Outcome.ShownWithWhatItHeldKept => null` with a comment naming W7b2-9, and the method returns true for it as for `Written` (the page does show the class). That arm is where the alert goes (`keptTitle`, `kept`, `showKept`, `keptGone`; the ledger's `Reason899W4cKeptAlert` and its `TodaysClassWording` row at `NamedGapLedger.cs` about 645, left for piece 9). Piece 9 should also rewrite `Reason899W4cKeptAlert`'s last sentence ("until it lands Windows has no part-way front page to report"), which W7b2-6 made untrue; I left it, as the brief said. The part-way test to copy is `UndoTodaysClassStepTests.APartWayStopIsShownWithWhatItHeldKeptNeverCouldNotSave` (the seams that produce a kept file).
- `ShowOnTheFrontPage` is `internal` now (it takes an `UndoActionStep` maker, an internal type); its only callers were the workspace and the tests through it.
- W7b2-11's could-not-be-read sentences ("this section's class dates could not be read.") keep their straight apostrophe: the director's instruction named only the held-timetable sentence. If the house typography should hold there too, it is two constants in `TimetableMemory.cs` (about 331) and one test string (`TimetableTests.cs` about 788).
- **For the mac (W7b2-5 review 1 L1):** written under "For the director" in `windows-app/notes/899-w7b2-5-start-of-year.md` (the mac's part-way start of the year names no kept file).

## Self-check

SELFCHECK_PLACEHOLDER
