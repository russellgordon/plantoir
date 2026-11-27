# #899 W8c-2a: Get Ready stopped part way is its own outcome (Windows #949)

Branch `issue/899-w8c-2a-get-ready-stop-is-its-own-outcome`, based on `origin/day27b/integration-5` (28707360c), which holds `origin/dev` (99499d6b7). Tests commit dcef14d64; product commit a0a2273ab.

## For PROGRESS

- `AssistWorkspace.PrepareForStartOfYear` tells a part-way stop from a stop that changed nothing by the door's exception alone (`UndoStepLeftPartWayException`), never by a sentence. A part-way stop is its own outcome: `StartOfYearOutcome.StoppedPartWay` (`StartOfYearStoppedPartWay`: section, course code, the backup Go made as a `BackupItem`, the number of files kept). Every other write error stays `writeFailed` with "Nothing was changed: …", as before.
- When no `BackupItem` can be made of Go's backup (`BackupItem.From` null), no offer: the message is the sheet's `wording.writeFailed` with the backup's name, which is true (the mac's review 1, LOW 1).
- `Message` for a part-way stop is unchanged (`RefusalForAStepThatStopped`), so the outside assistant's and the built-in assistant's replies say what they said; the mac's reply piece is unmerged (order file, director 3).
- Trail: the false "the pages could not all be written (writeFailed)" line is gone. A part-way stop writes `ActivityTrail.StartOfYearStoppedPartWayLine` (the mac's `startOfYearStoppedPartWayLine` word for word) on `StartOfYearNotDone`: no count, "1 file kept beside its page", or "N files kept beside their pages"; no page names.
- `StartOfYearWording` carries `stoppedPartWay`, `restoreOffer`, `leaveAsItIsButton`, `restoreCourseButton`, pinned key by key by `EverySentenceIsTheContracts` and `TheRestoreOfferWordsAreTheContracts`.
- Ledger: the four `StartOfYearSheetWording` rows and `Reason899GetReadyRestoreOffer` are gone; the area constant stays (`EverySentenceIsTheContracts` still calls `GapsIn` on it). No other reason named these keys.

## For documentation 12

- Get Ready for the Start of the Year, failure paths: part way is `StoppedPartWay`; the dialog's offer is W8c-2b.

## Tests (in `StartOfYearTests`, file `StartOfYearTests.StoppedPartWay.cs`; the class made `partial`)

- `StoppedPartWayCasesAsTheContractSays`: the three `startOfYear.stoppedPartWayCases` from the JSON, laid out on `cases[0]` (the plain year), the door made to fail by a real holder at `fileInUseAtSwap` and `PutBackFailsAt`. Checks the outcome, pages in draft, the backup item (the zip Go made), the kept count, the trail line. Every key of a case and of its `door` must be known. The answer half of "then leaveAsItIs" and "then restoreCourse" is a named `TODO(W8c-2b)` in the test, not a skip.
- `TheStoppedPartWayLineCountsWhatWasKept`: the line's three count forms.
- `NoOfferWhenNoBackupItemCanBeMade`: a test `BackupMaker` whose name `BackupItem.From` cannot read.
- `TheRestoreOfferWordsAreTheContracts`.

## Must-fail lines

`vm-tools/guest/899-w8c-2a-mustfail.json`: 4 of 4 RED in PC run `w8c-2a-b` (see "Runs").

## Runs

- PC `C:\vm-setup\w8c-2a-a` (`899-w8c-2a-launch-a.ps1`): tests commit dcef14d64 RED (does not compile: `StartOfYearStoppedPartWay`, `StartOfYearOutcome.StoppedPartWay` and `ActivityTrail.StartOfYearStoppedPartWayLine` do not exist, `StartOfYearTests.StoppedPartWay.cs` lines 138, 146, 157, 175). On a0a2273ab both builds exit 0; 259 of 260: `StoppedPartWayCasesAsTheContractSays` asserted two visible planned pages where the plain year lays out three (my number, not the contract's), fixed in 98bab3297. Lock taken and released by the run.
- PC `C:\vm-setup\w8c-2a-b` (`899-w8c-2a-launch-b.ps1`) on 98bab3297: both builds exit 0; `StartOfYearTests`, `StartOfYearSheetTests`, `UndoStartOfYearStepTests`, `ActivityTrailWiringTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`: 260 of 260 passed. Must-fail 4 of 4 RED: (1) `StoppedPartWayCasesAsTheContractSays` "Assert.Null() Failure" (the nothing-written case got an offer); (2) the same and `NoOfferWhenNoBackupItemCanBeMade`, the part-way line not found; (3) `TheStoppedPartWayLineCountsWhatWasKept`, strings differ; (4) `TheRestoreOfferWordsAreTheContracts` and `EverySentenceIsTheContracts`, "startOfYear.wording.leaveAsItIsButton differs". Restored 260 of 260; HEAD unchanged, tree clean; lock released by the run.

## Left for the next piece

- W8c-2b: the dialog's offer, its two buttons, Restore Course, Leave As It Is, and the answer half of the two "then" cases (the `TODO(W8c-2b)` in `StoppedPartWayCasesAsTheContractSays`).

## For the director

- The contract's `activityTrail.mustRecord` → `start of the year not done` line still reads only "did not get ready … — nothing was changed ({reason})"; the part-way line is on the same event on both platforms (the mac's piece did the same). Not changed here (no `contracts/` change allowed).

## Self-check

- Tests red first (compile), then green; must-fail 4 of 4 RED, restored byte for byte by `git checkout`.
- One place decides part way: `error is not UndoStepLeftPartWayException`; no sentence compared.
- Ledger: four rows and the constant gone; no other reason named the keys; the area constant stays.
- No key added to a replay's `KeysChecked`; the new replay has its own known-key sets.
- No run going, no lock held; the only lock touched was this run's own.
- `origin/dev` (99499d6b7) is in the base; no merge needed.
