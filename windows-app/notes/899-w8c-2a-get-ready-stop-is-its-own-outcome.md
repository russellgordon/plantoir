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

`vm-tools/guest/899-w8c-2a-mustfail.json`, run in PC run `w8c-2a-a`: see "Runs".

## Runs

- PC `C:\vm-setup\w8c-2a-a` (`899-w8c-2a-launch-a.ps1`): red run of dcef14d64, classes and must-fail on a0a2273ab. Result: see below.

## Left for the next piece

- W8c-2b: the dialog's offer, its two buttons, Restore Course, Leave As It Is, and the answer half of the two "then" cases (the `TODO(W8c-2b)` in `StoppedPartWayCasesAsTheContractSays`).

## For the director

- The contract's `activityTrail.mustRecord` → `start of the year not done` line still reads only "did not get ready … — nothing was changed ({reason})"; the part-way line is on the same event on both platforms (the mac's piece did the same). Not changed here (no `contracts/` change allowed).
