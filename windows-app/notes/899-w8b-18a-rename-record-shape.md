# #899 W8b-18a: the rename record is written with moved and mayHaveMoved and read by shape (2026-11-27)

Base: `origin/issue/899-w8b-17-rename-record-owned` 26984c34d. Merges of `origin/dev` (8046ca2e8), before proving and before hand-back: already up to date both times, so no merge commits.

## For PROGRESS

- The rename record (`file-formats.json` → `folderRenameRecord`) is now written in the contract's shape. `RenameRecordClaim.RenameIsStarting(moves, sectionNumbers)` writes `moved` and `mayHaveMoved`, copied from the mac's `renameIsStarting`. `moved` is first the earlier record's `moved`, when that record is of this same rename, and then this run's places. `mayHaveMoved` is `SpecialFolderRenamer.PlacesAnEarlierRunMayHaveMoved`, read before anything moves, less anything in `moved`. Both are JSON arrays of strings, left out when empty, as the mac leaves them out. Because `RenameIsStarting` runs only when folders move, `moved` is never empty.
- Every reader goes through `SpecialFolderRenamer.ReadRenameRecord(byte[]?)`, which returns a typed `RenameRecordNote` (`From`, `To`, `Scope`, `Moved`, `MayHaveMoved`). That covers the claim, `InterruptedRenameTarget` and `LooksLikeAnInterruptedRename`.
  - `from`, `to` and `scope` must be JSON strings, or the file is not a record (night25-4 sweep LOW 3).
  - Every other key is read only as an array of strings, and is otherwise taken as not said, as the mac's `stringsIn` does.
  - Strict UTF-8, one leading BOM skipped, and `DateParseHandling.None`, so a value that looks like a date stays a string.
- New helpers: `PlaceInside` (the mac's `placeInside`, by `UndoOp.PartInside`), `HoldsThePlace` (place equality, by `UndoOp.PartInside` returning ""), `PlacesMoved` (the mac's `placesMoved(byTheRecord:)`), and `WhatIsAt(path, spelledExactly)` (the mac's `presence`, by `UndoLinks.Look`, plus the parent's listing for a capitalisation-only rename).
- Bytes: Newtonsoft indented (CRLF on Windows), then one LF, as before. Key order: `from`, `to`, `scope`, `moved`, `mayHaveMoved`.
- Nothing a teacher reads changes. 18b uses `moved` and `mayHaveMoved` for the part-way sentences.

## For documentation 12

- "What W4c and W8 owe from U4b2-6", the bullets under "The rename record": the first two are built on Windows. The third ("Windows today writes `from`, `to` and `scope` only") is now untrue and should say that Windows writes all five keys (W8b-18a).
- The same section's last bullet but one ("A start run writes `mayHaveMoved` …") is built too.
- `file-formats.json` → `folderRenameRecord`'s note still describes Windows as it was before this piece ("Windows' reader today … takes each with ToString()", and "Windows today writes 'from', 'to' and 'scope' only"). I did not change it, because this brief allows no `contracts/` change. A later contract pass should drop both sentences. The first example ("what Windows writes today") stays true of a released build, which is the only older shape Windows must read.

## Tests that failed first

At c2df8e384 (the tests, with stubs that keep today's behaviour so that they build), run `w8b-18a-a`'s red half. See "Runs" for the lines.

- `RenameRecordShapeTests`: the new class.
  - `EveryContractExampleIsReadAsTheContractSays` reads every `folderRenameRecord` example by name. The contract has an explicit verdict key, `expect.read`, so the verdict is read rather than derived. A key that `expect` leaves out is taken as one the record does not say: `moved` null, `mayHaveMoved` empty, which is the note's rule.
  - `AFromToOrScopeThatIsNotAStringIsNotARecord` and `ANumberInFromIsNotAnInterruptedRenameOfAFolderSoNamed`.
  - `AKeyInAnotherShapeIsNotSaidAndTheRecordIsStillRead`: a guard that passes on today's product, and it is must-fail row 3's test.
  - The writer's tests: `AStartRunWritesMovedAsAnArrayOfThisRunsPlaces`, `ASharedFoldersPlaceIsItsNewName`, `ASameRenameReRunKeepsTheEarlierRunsMovedPlaces`, `APlaceBothRunsNameIsWrittenOnce`, `AnotherRenamesRecordLendsNoPlaces`, `AStartRunWritesTheCannotTellPlacesItReadsBeforeItMovesAnything`, `TheEarlierMayHaveMovedIsCarriedForwardLessWhatIsMoved` and `ACapitalisationOnlyRenameAsksTheListingForEachSpelling`.
- `SpecialFolderRenamerTests.ARenameThatStoppedPartWayKeepsARecordThatSaysWhatItMoves`: the path through the real `Rename`.

## Must-fail lines

`vm-tools/guest/899-w8b-18a-mustfail.json`, run in `w8b-18a-a`: 4 of 4 RED, each built with 0 errors.

1. `moved` written as one string: 9 failed, among them `AnotherRenamesRecordLendsNoPlaces`, `TheEarlierMayHaveMovedIsCarriedForwardLessWhatIsMoved` and `ASharedFoldersPlaceIsItsNewName`. Each failed with "Assert.Equal() Failure: Collections differ".
2. A number in `from` read as a record (each key read by its text): `AFromToOrScopeThatIsNotAStringIsNotARecord` failed with "read as a record: {"from": 3, …}" and four more values. `ANumberInFromIsNotAnInterruptedRenameOfAFolderSoNamed` failed with "Assert.False() Failure".
3. A record with `"written": 3` read as not a record: `EveryContractExampleIsReadAsTheContractSays` failed with "1 of 4 folderRenameRecord examples read wrongly: a key in another shape is not said, and the record is still read: read False, expected True". `AKeyInAnotherShapeIsNotSaidAndTheRecordIsStillRead` failed with "Assert.NotNull() Failure".
4. The earlier same-rename `moved` dropped: `ASameRenameReRunKeepsTheEarlierRunsMovedPlaces` and `TheEarlierMayHaveMovedIsCarriedForwardLessWhatIsMoved` failed with "Collections differ".

## Runs

- `w8b-18a-a` on the PC, using `899-w8b-18a-pc-run.ps1` through `899-w8b-18a-launch-a.ps1`, modes `classes,mustfail`, red ref c2df8e384. It ran from 02:49 to 02:53 EST on 2026-11-27, and took and released its own lock.
- Red half at c2df8e384: the build had 0 errors. 12 of 61 failed: every new test except the guard `AKeyInAnotherShapeIsNotSaidAndTheRecordIsStillRead`, which passes on today's product by design.
- At 02c2ca190: both builds had 0 errors. 332 of 332 tests passed, 0 skipped. The classes were `RenameRecordShapeTests`, `SpecialFolderRenamerTests`, `FolderRenameApplyTests`, `UndoRenameFolderStepTests`, `NamedGapLedgerTests`, `UndoWriterScanTests`, `UndoOpKindsContractTests` and `UndoStackContractTests`.
- After the must-fail rows, the restored run passed 332 of 332. HEAD-AFTER was the same commit, and the status was clean.

## Left for the next piece

- For 18b: read `moved` and `mayHaveMoved` through `ReadRenameRecord(_earlierRecord)`, as `RenameIsStarting` does, and `PlacesMoved` / `PlacesAnEarlierRunMayHaveMoved` with the claim's `_earlierRecord`. `WhatIsAt` is the no-follow check with the capitalisation-only listing. It gives `UndoLinks.What`, so it carries no reason text. The "could not tell whether these are at the new name: <place> (<reason>)" clause needs the system's message, so 18b will need a variant that returns it.

## For the director

- Piece 17's one choice that differs from the mac (any exception from the make that is not an I/O or access error keeps the record) is untouched. Nothing in this piece shows it to be wrong.
- Nothing parked.
