# #899 W8-10: an Undo or Redo whose content is gone from the list keeps an only copy (Windows #949; U4a review 1, LOW 4), 2026-11-26

Branch `issue/899-w8-10-content-gone-calls`, from `origin/issue/899-w8-9-kept-line-by-path` 54362cef8 (piece 9, unmerged, built on `origin/dev` 4f228c923; `dev` had nothing newer at the start or at hand-back, so no merge commit was needed).

## For PROGRESS

- W8-10: the stack replay (`UndoStackContractTests`) knows the call `afterContentGone` (only the newest step's after content of p1 taken out of the list, and the blob's own folder when that leaves it empty, as the mac's replay does) and the key `keptBesideThePage` (how many files are kept beside p1 under a staged name ending `-orig`, any step's, in p1's own folder), as `stackCasesHow` says them.
- U4a's two (a) stack rows pass on Windows' door as it is: the behaviour they pin (the outgoing bytes written into the list under the lock before the swap, or kept beside the page when the list takes no new file, and the other direction made from that) is `UndoRecovery.StoreWhatTheOtherDirectionNeeds`, which W8-9 built. No door change in this piece. They are gone from the ledger, and `Reason899U4aContentGone` with them.
- The (b) row (seven moves, one kept copy per content per page) stays held, under the new `Reason899U4aThinning`: Windows does not thin kept copies. Measured on the PC (run `899-w8-10-a`): 8 files kept beside p1, holding 2 contents. The replay's count of `keptBesideThePage` names that gap ("… the thinning of kept copies to one per content per page is not built on Windows yet") only when the surplus files hold a content another holds; the stack replay accepts that words as a gap (`RunAsTheLedgerSays`), beside "this replay does not know" and "does not check". The piece that builds the thinning takes that branch and that accepted words out.

## For documentation 12

- "The lows fixed with U4a that W4c and W7 copy": item 4 was built on Windows by W8-9 (`UndoRecovery.StoreWhatTheOtherDirectionNeeds`, for a page put back from the list; W4c had built it only for a page put back from a kept original, `StoreWhatKeptOriginalsGive`), and its stack rows are run since W8-10. Item 5 (thinning kept copies to one per content per page, the mac's `UndoRecovery.removeSupersededKeptCopies`) is NOT built on Windows; its row is held under `Reason899U4aThinning`. The section's heading and any sentence saying W4c built items 4 and 5 should be corrected so (a writer does not edit documentation 12).

## Tests that failed first

- The three rows were held, so the first run with the replay taught is the red: run `899-w8-10-a` (5e1570111), `UndoStackContractTests.EveryStackCase` failed for all three. The two (a) rows failed at `NamedGapLedger.cs:866` ("ledgered as not built here yet … it now EXISTS": the gap closing); the (b) row at `NamedGapLedger.cs:868` with "8 files kept beside the page, not 2" (a real failure until the named gap was added). Before the replay was taught, the rows stopped at "a key this replay does not check: keptBesideThePage".

## Must-fail lines

`vm-tools/guest/899-w8-10-mustfail.json`, from a clean committed tree on the PC, each sabotage alone, restored with `git checkout`. The brief's third row (thinning off) is left out: there is no thinning on Windows to turn off (the director's instruction).

Run `899-w8-10-b` at 15c162808: **2 RED of 2**, then 274 of 274 passed restored, `git status` empty, HEAD unchanged.

1. The outgoing bytes not written into the list before the swap (`UndoRecovery.StoreWhatTheOtherDirectionNeeds` always hands the page to the swap to keep instead of storing): RED, 1 failed, "U4a, LOW 4 (a), stored" at an `Assert.Equal` (values differ: a kept file and its trail line where the list should have held the bytes).
2. The kept copy not made when the list takes no new file (the store's failure ignored, the page not handed to the swap): RED, 2 failed, "U4a, LOW 4 (a)" (`Assert.Equal`, values differ: the Redo not made, its only copy tidied away) and the U4b2-4 case (`Assert.Equal`, strings differ: the kept line).

## Runs

- `899-w8-10-a` (PC, 5e1570111, the replay taught, ledger unchanged): both builds 0 errors; 271 of 274, the three U4a rows failing as described under "Tests that failed first". Lock taken and released by this run.
- `899-w8-10-b` (PC, 15c162808, classes and must-fail): both builds 0 errors; **274 of 274 passed** (`UndoStackContractTests`, `UndoDoorTests`, `UndoStoreTests`, `UndoRecoveryTests`, `NamedGapLedgerTests`, and the scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests`); must-fail 2 RED of 2; lock taken and released by this run; nothing left running.

## Riding lows

- The three review files named by the director (`2026-11-26-899-w8-11-13-review-1.md`, `2026-11-26-899-w8-7-8-review-1.md`, `2026-11-26-day26-6-sweep.md`): none of their lows sits in code or documentation this piece touches (`UndoStackContractTests.cs`'s replay and checks, `NamedGapLedger.cs`'s U4a rows, reasons and the U3c comment). W8-7-8 L4 is in `UndoTestSupport.cs`, which this piece does not change; the documentation 12 and PROGRESS lows are in files a writer does not edit. None fixed here. The documentation 12 sentence about W4c building items 4 and 5 is corrected above, under "For documentation 12", for the director to fold in.
- The ledger's U3c comment now records the (a) rows going and `Reason899U4aContentGone` going, and where the (b) row stays.

## Self-check

NIGHT3-COMMON:
1. Broke each fix and watched its test fail: no product change in this piece; the behaviour the rows pin is broken two ways by the must-fail rows (above), each RED.
2. No timed waits: none added.
3. Failure-path sentences: no teacher sentence touched. The only new sentence is the replay's failure text, which is true only when the surplus kept files hold a duplicated content.
4. `dev` merged before proving: `origin/dev` 4f228c923 is in the base (piece 9's); nothing newer on `dev` at the start or at hand-back.
5. No number tuned by trial: the 8 of the (b) row is measured and written in the reason only as a measurement; nothing asserts it.
6. Contract cases run from the JSON; no `contracts/` or `mac-app/` change.

W7b2 COMMON 7 to 10: 7 n/a (no fixture row); 8 n/a (no writer moved); 9 no riding low in this piece's code (above); 10 n/a.

W8 COMMON:
11. The two (a) rows pass and are out of the ledger; `Reason899U4aContentGone` is gone; no other reason sentence named `afterContentGone` or `keptBesideThePage` (grep of `NamedGapLedger.cs`). The (b) row's reason is rewritten to say exactly what fails and where.
12. `keptBesideThePage` is carried by these three stack rows only (none in `recoveryCases` or `checkCases`, read in Python); the one still held, (b), stops at the accepted named gap (run b).
13. One function per rule: no new path comparison; the kept files are found by the staged-name prefix in p1's folder, as the mac's replay does, and their contents compared by `UndoCheck.Sha`.
14. No run left going, no lock left held, no lock removed that this run did not take (the run script removes the lock only when `owner.txt` names this run).

## Left for the next piece

- Thinning kept copies to one per content per page (item 5): see "For the director".

## For the director

- **Thinning, as its own piece.** What it needs on Windows:
  - Copy the mac's `UndoRecovery.removeSupersededKeptCopies(of:root:paths:newestLabel:)` (`mac-app/QuartzTeachers/Models/Undo/UndoRecovery.swift:468`, about 30 lines): for each page in `notTaken.outgoingOf`, read each of the step's kept originals beside it (`KeptOriginalFiles`, already on Windows), hash it, keep the one this move just made (`newestLabel`) for its content or else the first by name, and remove the rest by `UndoSwap`'s staged-file removal; an unreadable copy is never removed.
  - Call it in `UndoDoor.cs` after `Finish(...)` and before `SayWhatItKept`, when `notTaken.OutgoingOf` is not empty (the mac's call is `UndoCheck.swift:2249`). Check whether recovery's own put-back path (`UndoRecovery.cs` about line 1170) needs the same call (the mac's is only in the door).
  - Files: `Plantoir.Core/Undo/UndoRecovery.cs`, `UndoDoor.cs`, `Plantoir.Tests/UndoStackContractTests.cs` (take out `CheckTheFilesKeptBesideThePage`'s named-gap branch and the accepted "is not built on Windows yet"), `NamedGapLedger.cs` (the (b) row and `Reason899U4aThinning` go), and a small door-level test class (the mac has `UndoKeptCopiesTests.swift`).
  - Rows held: one, "U4a, LOW 4 (b): both contents gone and the list taking no new file, seven moves: one kept copy per content per page, two files in all".
  - Must-fail: thinning off (two kept files for one content); the newest copy removed instead of an older one.
  - Rough size: about 40k to 55k writer tokens, proof included.
