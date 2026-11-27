# W8b-21b1a (#899, Windows #949): where this PC cannot make a link, the page becomes a copy of the lesson and the link is set aside

Brief `vm-tools/briefs/2026-11-27-899-w8b-21b1a-copy-the-lesson-where-a-link-cannot-be-made.md` (Russell's Q2, 2026-11-27: "Copy the lesson instead"; kept small, as he asked). Same branch as 21b1, `issue/899-w8b-21b-relink`, from its pushed head dc0ca0fab. Windows only: the Mac can always make a link. No `contracts/` or `mac-app/` change. Inert: no teacher action calls it until 21b5 wires it into `RelinkLink`.

## For PROGRESS

- `UndoLinks.CanMakeALink(UndoSeams? seams = null)`: answered ONCE per process (a `Lazy`) by `CanMakeALinkIn(UndoJournalLocation.Folder)`, which makes a file's symbolic link under a dot name (`.can-make-a-link-<pid>-<guid>`, to a dot name never made) in the Undo list's own folder and removes it; true only when it was made AND removed. Never the registry's Developer Mode key, never per file. The seam `UndoSeams.CanMakeALinkAnswers` (a `bool?`) answers in its place.
- `UndoActionStep.CopyTheLessonInsteadOfALink(linkFull, newFull)`: reads the bytes of the file the link leads to NOW (`UndoLinks.FileALinkLeadsTo`, then `UndoLinks.ReadAll`, read only, from the disk), then plans (1) `MoveLink(link, SetAsideName(link))`, the link as itself, and (2) `WriteBytes(newFull, lesson)`, a new file. Records the copy in `CopiedInsteadOfLinks` (for 22b's line). Returns false, planning nothing, for a link leading nowhere or to a folder (no lesson: its caller moves it as itself). A place that is not a link refuses `cannotTellNow`, as `MoveLink`.
- `SetAsideName`: `.<name>.link-kept-by-undo`, then `-2`, `-3` and on, the first neither on disk (`UndoLinks.Look` says `Nothing`) nor chosen in the step (`IsChosenInThisStep`: planned as a file, or a planned move starts or ends there, by `UndoOp.PartInside`). Never holds `UndoSwap.StagedMarker`, so `TidyLeftovers` never removes it; a dot file, which Obsidian and the site build pass over. The set-aside link is never thinned or removed (the ruling's "set aside, never deleted").
- Undo, Redo and the unrecorded make need nothing new: the step is a link's move and plain `writeFile` ops, already handed over and ordered by 21a6. Undo removes the copy (judged by its `afterSha`: a copy edited since is changed since) and moves the link back, text and all.
- Review 3 of the 21a line, LOW 1: `UndoCurrent.ReadWithoutFollowingALink` reads `UndoLinks.What.CannotLook` as `CannotReadNow(1920)` (ERROR_CANT_ACCESS_FILE: cannot tell, never a copy or a state), never `Read` through it. A `look` seam (default `UndoLinks.Look`) lets a test meet a tag that cannot be read.
- `UndoWriterScanTests`: `UndoOpKinds.cs` 11 to 14 writing calls (`Directory.CreateDirectory`, `File.CreateSymbolicLink`, `File.Delete` in `CanMakeALinkIn`), reason extended. `UndoJournalLocation`'s summary names `CanMakeALink` as its second reader.

## For documentation 12

Where Windows cannot make a symbolic link (no Developer Mode, no elevation, no policy grant), a relink becomes a copy (Russell, 2026-11-27): `UndoLinks.CanMakeALink()` asks once per process by making and removing one link in the Undo list's folder; where it is false, `UndoActionStep.CopyTheLessonInsteadOfALink` moves the link as itself to `.<name>.link-kept-by-undo` (then `-2`, …) beside it and writes a plain copy of the file it leads to at the link's new name. Every op is a plain move or write, so Undo and Redo need no privilege; Undo removes the copy (refused changed since if edited) and puts the link back byte for byte. The set-aside name never carries the staged marker, so no tidy removes it, and it is never deleted. Rejected: reading the registry's Developer Mode key (elevation and policy grant the privilege too), asking per file (one probe per process is enough and cheaper), and removing the link (Undo could not put it back without the privilege).

## Tests

- `UndoLinkCopyTests` (new; `[SymbolicLinkFact]` but for the one plain `[Fact]`): Insert Class's shape by hand (Day 4 a link holding `Unit 1, Day 3.md`; the copy planned at Day 5; Day 3's page written at Day 4 and removed; a new Day 3): one step, Day 5 a plain file holding the lesson, the link under `.Unit 1, Day 4.md.link-kept-by-undo` holding its text unchanged, no op at the set-aside name but the link's move; Undo gives the course exactly as laid (the link at Day 4 with its text); Redo exact. The set-aside name taken: `-2`, the plain file there untouched. The copy edited since: Undo refused `ChangedSince`, nothing changed. Unrecorded: the same end tree, no begin. A link leading nowhere: false, nothing planned. `CanMakeALinkSaysWhatMakingOneInATemporaryFolderDoes` (plain `[Fact]`): `CanMakeALinkIn` and `CanMakeALink()` equal what `File.CreateSymbolicLink` does in a temporary folder, and the list's folder holds only what it held.
- `UndoKeptPageUnderAVisibleNameTests.APlaceThatCannotBeLookedAtIsCannotReadNowAndNeverReadThrough` (plain `[Fact]`, the riding low).

**For the window E reviewer:** run `UndoLinkCopyTests` once on a Windows VM (Developer Mode off): the laid-link tests skip there, and the one plain `[Fact]` that compares `CanMakeALink()` with what `File.CreateSymbolicLink` does in a temporary folder must pass (false on the VM, true on the PC).

## Must-fail lines (`vm-tools/guest/899-w8b-21b1a-mustfail.json`)

RED 4 of 4 (run w8b-21b1a-a, ref c4574263b):
1. the link removed instead of set aside: RED, 3 of 6 (`TheLinkIsSetAside…`, `ASetAsideNameAlreadyTaken…`, `Unrecorded…`: "Expected: Link").
2. the set-aside name built with `StagedMarker`: RED, 3 of 6 (the same three, the link not at `.…link-kept-by-undo`).
3. the copy read at the link's new name: RED, 4 of 6 (`Assert.True() Failure`: nothing copied).
4. review 3 LOW 1, the `CannotLook` arm removed: RED, `APlaceThatCannotBeLookedAtIsCannotReadNowAndNeverReadThrough` ("Expected: typeof(…CannotReadNow)").

Restored 348 of 348, HEAD-AFTER same, status clean.

## Runs

- w8b-21b1a-a (PC, ref c4574263b, red ref aee39138c; lock taken 08:06 after the director's integration run, released by its own run): **red 7 of 7** at the tests-first commit (every `UndoLinkCopyTests` test, `NotImplementedException` from the inert stubs, and the riding low's test, "Value is not the exact type", `Bytes` for `CannotReadNow`); both builds 0 errors; **348 of 348 passed** (`UndoLinkCopyTests`, `UndoRelinkTests`, `UndoHandedOverPlaceTests`, `UndoActionStepTests`, `UndoActionStepLinkTests`, `UndoKeptPageUnderAVisibleNameTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`); must-fail RED 4 of 4; restored 348 of 348.
- `origin/dev` moved to 454ef4c6f (day27b integration-1) after that run: merged in (60f80972a), and the classes run again as w8b-21b1a-b.
- w8b-21b1a-b (PC, ref b0f863e49, the merged head): both builds 0 errors; **349 of 349 passed** (the same classes; the merge brought one test); lock taken and released by its own run.

## Ledger

No row (inert). `NamedGapLedgerTests` run.

## Self-check

1 to 6 (NIGHT3): own classes only on the PC under the turn lock, no UI class, no whole suite; tests first in their own commit (aee39138c), seen red; must-fail recorded; notes written. 7 to 10: no fixture row (inert), the writer-scan count true (14 in `UndoOpKinds.cs`), the riding low fixed with its test and its must-fail row, no action step. 11 to 14: no held row; no key added; one function per rule (`UndoLinks.CanMakeALink` for whether a link can be made, `UndoLinks.Look` for a link, `UndoLinks.FileALinkLeadsTo` for the lesson, `UndoOp.PartInside` for "chosen in the step"); the director's backslash reading untouched (this piece writes no link text); no run left going, no lock removed that this piece did not take.

## Left for the next piece

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- 21b5: call `CopyTheLessonInsteadOfALink` from `RelinkLink` where `UndoLinks.CanMakeALink()` is false. 22b: the line a teacher reads (from `CopiedInsteadOfLinks`), and dating and titling the copy as a class page.
- The copy is read from the disk at plan time: 21b5 and 22 must plan it before any write of the file the link leads to (documented on the function).

## For the director

Struck by Russell's ruling of 2026-11-27: a class page is never a symbolic link; nothing here is to be built.

- Nothing parked.
