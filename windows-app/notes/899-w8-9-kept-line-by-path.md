# #899 W8-9: the kept line tells same-named pages apart (Windows #949, the mac's U4b2-4), 2026-11-26

Branch `issue/899-w8-9-kept-line-by-path`, from `origin/dev` 4f228c923 (that is the merge of `dev` before proving; nothing newer when handed back unless "Runs" names a second merge).

## For PROGRESS

- W8-9: the trail line `undo kept what it replaced` now decides "from what was kept beside it" of each page by its path in the working folder, as the mac's U4b2-4 does. `UndoDoor.SayWhatItKept` keys each kept file as `<page's folder>/<hidden name>` (the op's path as spelled, `/`-separated; a page at the top gives the bare name), skips one only when that whole path is listed, and passes the pages put back from a kept original (every use's `Path`, whole) and every op's path to `UndoTrail.KeptWhatItReplacedWords`. The words name a page by its file name, or, when another page of the step shares the name, by its path inside `courses/<course>/`, or by its whole path when outside that or with no course. The hidden file is always its bare name, and the line's file list (`UndoTrailLine.Kept`) stays the bare names.
- Names, pages and the course prefix are compared by ONE function, `UndoTrail.SameSpelling`: Unicode form C, then ordinal. Capitals differ.
- The U4b2-4 stack case passes on Windows; `Reason899W4cKeptLineByPath` and its row are gone from the ledger. The stack replay learned the key `keptWhatItReplacedSays` and the calls `wholeFileStepOnTwoPagesNamedIndex`, `firstIndexAfterContentGoneAndCannotBeStored`, `secondIndexBeforeContentGoneAndCannotBeStored`, `keepTheOriginalOfTheSecondIndex`.
- New test class `UndoKeptLineByPathTests` (9 facts).

## For documentation 12

- "What W4c owes from U4b2-4": built by W8-9 (2026-11-26). Items 1 to 6 as written; item 7's held row is gone with its reason. Add: the prefix `courses/<course>/` is matched as the path's first two parts, each by `UndoTrail.SameSpelling` (form C, then ordinal), and the rest of the path is quoted as the path spells it (never re-normalised), so a page whose name is in form D is named in form D.
- "What W4c and W8 owe from U4b2-6", last bullet: built by W8-9 (`UndoTrail.SameSpelling`).
- Lesson 6 (one function per rule): the course prefix is NOT an "at or inside" decision about carrying, so it does not call `UndoOp.PartInside` (which is case-insensitive). It is a naming rule the mac makes case-exact (`hasPrefix`), and documentation 12's item 4 says "the prefix is compared exactly (ordinal)". The one function for the kept line's comparisons is `UndoTrail.SameSpelling`.

## Tests that failed first

- The four door-level facts (`TwoPagesWithOneNameAreNamedByTheirPathsAndTheWayEachCameBack`, `APagePutBackFromTheListIsNeverSaidToComeFromWhatWasKept`, `TwoKeptFilesWithOneNameInTwoFoldersAreBothListed`, `APageAtTheTopOfTheWorkingFolderIsNamedByItsPathThere`) call only the door, so they compile on the product as it was. The five words-level facts call the new `KeptWhatItReplacedWords` overload, which did not exist, so on the old product they could not compile (red as a build error, not as an assertion). The product's old behaviour is therefore shown red by the must-fail rows 1 and 2, which put back the old keying and the old "every page" rule one at a time; see "Must-fail lines".

## Must-fail lines

(filled from the PC run; see "Runs")

## Runs

(filled from the PC run)

## Riding lows

- Night25-4 sweep LOW 4 (brief): the ledger comment that named "the reason then named Reason899W4c" now says it is the constant now named `Reason899U4aContentGone`, and records the U4b2-4 row and `Reason899W4cKeptLineByPath` going, in the same commit as the constant's removal.
- The three review files named by the director (`2026-11-26-899-w8-11-13-review-1.md`, `2026-11-26-899-w8-7-8-review-1.md`, `2026-11-26-day26-6-sweep.md`): none of their lows sits in code or documentation this piece touches (`UndoDoor.SayWhatItKept`, `UndoTrail`'s kept line, `UndoStackContractTests`' replay, the ledger row and comment). W8-7-8 L4 (`StagedLeftovers` in `UndoTestSupport.cs`) is in a file this piece does not change; W8-11-13 LOW 6 and sweep LOW 1/3 are in PROGRESS.md and documentation 12, which a writer does not edit. None fixed here.

## Self-check

NIGHT3-COMMON:
1. Broke each fix and watched its test fail: the four must-fail rows (see above).
2. No timed waits: none added.
3. Failure-path sentences: the line is written only after a finished Undo or Redo whose list could not take everything; its words now say of each page the way it came back, and name each so two pages with one name are told apart. No other sentence names what changed (grep of `windows-app` for `KeptWhatItReplacedWords`, `SayWhatItKept`).
4. `dev` merged before proving: the branch starts at `origin/dev` 4f228c923.
5. No number tuned by trial: none.
6. Contract cases run from the JSON (the stack case, `keptWhatItReplacedSays` read by key); no `contracts/` or `mac-app/` change.

W7b2 COMMON 7 to 10: 7 n/a (no fixture row; the stack row is green and gone, see 11). 8 n/a (no writer moved). 9 the riding low is fixed (above). 10 n/a (no action converted).

W8 COMMON:
11. The one held row passes and is out of the ledger; the constant is gone; no other reason sentence named `keptWhatItReplacedSays` or the four calls (grep of `NamedGapLedger.cs`).
12. `keptWhatItReplacedSays` is carried by one case only in `stackCases` (and none in `recoveryCases` or `checkCases`), read in Python from the contract; no held row carries it.
13. One function per rule: every comparison of the kept line's names, pages, kept paths and the course prefix calls `UndoTrail.SameSpelling`.
14. No run left going, no lock left held, no lock removed that this run did not take (the run script removes the lock only when `owner.txt` names this run).

## Left for the next piece

Nothing.

## For the director

Nothing parked.
