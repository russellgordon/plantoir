# U4b3 review fixes (#899), 2026-11-26

Branch `issue/899-u4b3-linked-class-page-moves-its-link`, from 26559c3b7. `origin/dev` merged in at the start: already up to date (no merge commit); the second merge is named under "Runs".

## For PROGRESS

- Fix 1 (review A, MEDIUM 1): a removed page is put back EXCLUSIVELY (`UndoSwap.putBackAKeptOriginal`, used by `reverse()` and by `swapAFile`'s own put-back): a file written at the emptied place since is never replaced; the swap answers `notPutBack` and leaves both for recovery, as a move's reversal does. Review A's LOW 1 also fixed: a handed-over filler move refused because its place is taken names that place (`UndoSwap.placeIsLeftEarlier`), not its `from`.
- Fixes 2 and 3 (review B, MEDIUM 1 and 2), one commit: `ClassInsertionPlanner.firstLinkThatCannotBeMoved` refuses, before anything changes, a later class whose link leads to another class page of the same section, or a link leading nowhere, with the refusal Insert Class gave before part 2 (`JournaledStepError.refused(.cannotTellNow)`, said as Foundation's "The file “Unit 1, Day N.md” couldn’t be saved.", naming the link's page). Committed together because the code is one pre-pass; each has its own must-fail below.
- Fix 4 (Russell's rulings of 2026-11-26, through the director): a linked later class is never retitled (the title is written only for a plain class page); the moved date is written into the linked file under the key the FILE's own place calls for: `created` for a file inside `section<N>/`, `createdSection<N>` for a course-level file (every other date line left byte for byte). The link is resolved link by link (`ClassInsertionPlanner.fileALinkLeadsTo`) and `AssistPageVisibility.isSectionLocal` is asked of the file reached.
- Lows: `isALinkToAFile` and `planNumbered` each carry their own doc comment (B LOW 1); `everything(under:)` records links as links (B LOW 2), so the kill-at-every-swap recovery test now checks links too (it passes). B LOW 3 (stack rows check only `linkedPage`) left as the brief allows. B LOW 5 done in the clause.

## How "a class page of this section" is judged (fix 2)

By resolved identity: `stat` through the link (any number of links) gives a device and inode; each class page of the section (`ClassPages.list(forSection:)`) that is itself a plain file (`lstat`) gives its own; equal pair = refused. Never by name or path spelling. A class page that is itself a link is skipped as a candidate (its file is not a class page; if its file IS one, that page's own entry catches it). Two class pages linking to the same library file are NOT refused (that is the shared-file question the director holds). Places checked: every rename's from and to, every move's page, every new page.

## Other plain renames or replaces in `reverse()` and its helpers (fix 1)

- `.file` with a kept original and a replacement (an edit): still a plain `rename` over the target. It replaces the content this swap itself put there; if another program wrote over that content between the swap and a later refusal, its write is lost. Pre-existing (U3), not a handed-over case; left, for the director.
- `.file` with no kept original (a new file taken back): `removeItem` of whatever is at the place, without checking it is the swap's own content. Same shape (a file written over the new page since would be removed). Pre-existing; left, for the director.
- `.moveHere`, `.makeTree`, `.takeTree` already use `renameExclusively`. `.setExternal` writes a preference, not a file.

## Sentences changed in contracts/ (all in `shared-rules.json` unless named)

- `undo.rule.shadow`: "and the new title and the moved date the action writes go into that file, as every write through a link does (U4b3, Russell's ruling of 2026-11-26, option (a));" became "and the moved date the action writes goes into that file, as every write through a link does, under the key the FILE's own place calls for (`created` for a file inside this section's folder, `createdSection<N>` for this section only for a course-level page, every other date line left as it is); a title is never written into a file a link leads to (Russell's rulings of 2026-11-26: \"Shared pages never have day 'x' titles in them\", and the date is the created setting of the section the class was added for);". "Undo puts the link's name and the page's title and date back as one step," became "Undo puts the link's name and the file's date back as one step,". Added after "...is not renamed, as before.": two sentences, the same-section link refused as before U4b3 (naming the new stackCases row), and the dangling link refused the same way, never skipped, nothing written through it.
- stackCases: row renamed "…undone and redone, the link moved again with the same target and this section's date written into the file it leads to again, its title kept" (was "…and the title and date written into the file it leads to again"); its `linkedPage` now `redatedForThisSection` (was `retitledAndRedated`); the first row's `why` now says only the date, under the key its place calls for. New row "U4b3, Insert Class with a later class that is a link to another class page of the same section: refused before anything changes, nothing on the list" (call `makeRoomWithALaterClassLinkedToAnEarlierClass`, expectLast `cannotTellNow`).
- `stackCasesHow`: the call's step says "the fourth meeting date written into the file it leads to as `createdSection1:` (a course-level page: this section's key), its title never written"; `redatedForThisSection` defined; the new call described.
- `NamedGapLedger.cs`: the renamed row and the new row under `Reason899W8bLinkedClassPage` (three rows now, names checked by script, each once, byte for byte); the reason says "never retitled, but for the moved date written into it under the key its own place calls for" and names the new call. Each fails on Windows today: the calls are unknown there.
- Python model (`scripts/test_make_undo_traces.py`): `linked_redated()`, the new call; 38 tests OK, traces not stale.
- Documentation 09 ("U4b3: linked-class-page-moves-its-link") and 12 (the W7b2-1 "Shadow, a later class that is a symbolic link" bullet) say the same.

## Re-date (read, not changed)

`SectionReDatePlanner.swift` lines 301 to 302 and 318 to 319 take `move.isSectionLocal`, set at lines 170, 193 and 231 from `page.isSectionLocal`, which `AssistSectionGraph.swift` lines 255 to 257 computes as `AssistPageVisibility.isSectionLocal(pageAt: pageURL, …)` with `pageURL` the page's place as listed, that is the LINK's place (`standardizedFileURL` does not resolve links). So for a linked class page in the section's folder Re-date uses plain `created` even when the file it leads to is a course-level page: the same fault, not fixed here.

## Held for Russell

- The refusal sentence for a dangling later class (fix 3) is the one fix 2 restores, Foundation's "The file “Unit 1, Day 3.md” couldn’t be saved." It is true (nothing was saved, and that file is why) but does not say why. No new sentence was written.

## For documentation 12

W8b piece 22: as in documentation 12's bullet. In short: never write a title through a link; the date key from the file reached (resolve link by link, `IsSectionLocal` of the file); refuse before anything changes a later class whose link reaches another class page of the section (volume and file id) or nothing.

## Must-fail lines (RED 4 of 4; also `899-u4b3-review-fixes-mustfail.log`)

1. Fix 1: `putBackAKeptOriginal` with its exclusive branch removed: `testAFileWrittenWhereAPageWasRemovedIsNeverWrittenOver`, `…WhereTheUndoTookAPageAwayIsNeverWrittenOver`, `…WasRemovedSurvivesRecovery` fail (3 of 40). Restored.
2. Fix 2: the class-page identity loop removed: the three same-section tests fail (9 failures of 13). Restored.
3. Fix 3: the dangling guard made `continue`: `testADanglingLinkedLaterClassIsRefusedAndNothingChanges` fails (4 failures). Restored.
4. Fix 4: the key forced to `created`: 9 failures of 18, including `testALinkToACourseLevelPageMovesOnlyThisSectionsDate`. Restored. The title half was seen red on the code before fix 4 (`run-f4-red`: 9 of 16, `testALinkedClassKeepsItsOwnTitleAndTakesTheNewDate` among them; the "Unit 1, Day 4" style title test passes on both, as the written title equals it: a guard, not a must-fail).

`git diff` clean after each restore.

## Runs (`.dd/`)

run-f1-red (3 failures of 40, first), run-green1, run-green2 (40/40), run-mf1, run-mf2, run-mf3, run-green3 (82/82 with stackCases and recoveryCases), run-f4-red, run-f4b-red, run-green4 (96/96: UndoHandedOverPlaceTests, UndoMakeRoomLinkedPageTests, JournaledStepTests, UndoWriterScanTests, MakeRoomForClassesTests, testStackCases, testRecoveryCases), run-mf4.

## Self-check

House style grep over added Swift lines: empty; MARK sections in `ResolvedFile`. Switch off, rename record kept (untouched). Every new or changed row is in the Mac's replay and held by exact name.

## Left for the next piece

The two pre-existing put-back shapes above; Re-date's key for a linked page; review B LOW 3.
