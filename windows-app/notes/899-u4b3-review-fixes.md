Fixes 2 to 4 removed by #1055 (2026-11-27), M1 and S1, and fix 1's handed-over LOW by M5: Insert Class has no link pre-pass, retitles no link and dates a class under its own page's key; fix 1's exclusive put-back (`UndoSwap.putBackAKeptOriginal`) stays.

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

# Second fix round: Insert Class never refuses because of where a link leads (2026-11-26)

Brief `vm-tools/briefs/2026-11-26-899-u4b3-never-refuses.md`, from 0f3e01404. `origin/dev` (06e067fbe) merged in first: dc161321d (conflict in `NamedGapLedger.cs`: dev's W8-6 wording of `Reason899W8U4b2LinkedFolder` and `Reason899W8U4b` kept, this branch's `Reason899W8HandedOverPlace` and `Reason899W8bLinkedClassPage` kept beside them; dev's removal of the U4b checkCases rows Windows now runs kept). Checked again before handing back: still current, no second merge needed. Documentation 12 merged cleanly.

## For PROGRESS

- Step 1 DONE (850fd1c4d): fix 3's refusal removed. A later class whose link leads nowhere is moved as itself (`ClassInsertionPlanner.isALinkToNothing`), its text byte for byte; nothing else is written for it: no date (the dates loop skips it), never a write through it, so no file appears where it points. Found on the way: the step finds the place a link leaves by its spelling, and the folder lister names `/private/var/...` where the plan names `/var/...`; `standardizedFileURL` drops `/private` only from a path that leads somewhere, so for a broken link the two spellings stayed apart and the class below was written THROUGH the link (to the place outside), the step could not be named, and the shadow path then lost Day 2's lesson. Fixed by spelling the link's `from` from its `to`'s folder (`spelledAsItsNewPlace`). The pre-pass no longer refuses a broken link.
- Step 2 STOPPED (ddad3c1fa): re-pointing needs a door change (below). Fix 2's refusal stands for that one arrangement only, and is now judged hop by hop (review C, MEDIUM 1): `leadsToAClassPage` compares the `lstat` identity of the place each hop names (a link or a file) with every class page as it stands, so Day 4 holding `Unit 1, Day 3.md` is refused when Day 3 is itself a link elsewhere. The end-of-chain comparison is the last hop of the same walk. `ResolvedFile.ofAPlainFile` replaced by `ofThePlace`.
- Step 3 DONE, in the two commits above: `undo.rule.shadow` (the broken-link sentence; the refusal sentence now says hop by hop, that it is the one arrangement still refused, Russell's ruling, and why it stands; review C LOW 2: `createdSection<N>` "for a file anywhere else: a course-level page, a page in another section's folder, or a file outside the course", checked against `AssistPageVisibility.isSectionLocal`, which is true only under this section's folder); `stackCasesHow` (the new call); stackCases rows; the refusal row's `why`; the Python model; documentation 09 and 12.
- Step 4: the loose phase check in `testAFileWrittenWhereAPageWasRemovedSurvivesRecovery` now pins `interrupted` (this commit). The contract recovery row for fix 1's state was NOT added: see "For the director", item 2.

## Rows

- Added, held under `Reason899W8bLinkedClassPage` (names checked by script, each once, byte for byte; reason sentence now names the call and says a link leading nowhere is renamed, never refused): "U4b3, Insert Class renaming a later class that is a link leading nowhere: one step, the link renamed as itself and nothing made where it points; undone, the link back at its old name with the same target" and "U4b3, Insert Class renaming a later class that is a link leading nowhere: undone and redone, the link renamed again with the same target and still nothing made where it points" (call `makeRoomWithALaterClassThatIsABrokenLink`; `linkedPage` `old|new, ../../elsewhere/Unit 1, Day 3.md, gone`, so a file made where it points fails the row). Each fails on Windows today: the call is unknown there.
- Changed: the same-section refusal row's `why` only (its name unchanged).

## For documentation 12

W8b piece 22, in documentation 12's W7b2-1 bullet: a later class that is a link leading nowhere is moved as itself, never refused, nothing written for it or through it; compare the link's place and the class below's write by ONE spelling of the folder, or the class below is written through the broken link. A link to a class page of the section is refused, each hop by the volume and file id of the place it names, until a door piece can change a link's text.

## Must-fail lines (RED 4 of 4)

1. Step 1, the refusal put back (`continue` to `return place` in the pre-pass): `testABrokenLinkedLaterClassIsRenamedAndNothingIsWrittenThroughIt` fails, "refused(cannotTellNow …)" (run-s1-mf1). Restored.
2. Step 1, the respelling removed (`step.moveLink(rename.fromURL, …)`): the same test fails, "0 is not equal to 1 - one step", `[wentAhead]`, Day 3 unreadable (run-s1-mf2). Restored.
3. Step 1, broken links not moved (`isABrokenLink` forced false): `testStackCases` fails on both new rows; the unit test fails (run-s1-mf3). Restored.
4. Step 2, hops compared only at the end of the chain: `testALaterClassLinkedToAClassPageThatIsItselfALinkIsRefused` fails "Insert Class went ahead", "nothing changed", "no step recorded" (run-s2-mf1). Restored.

Seen failing first: run-s1-red (the broken-link test refused), run-s2-red (review C's probe went ahead). `git diff` clean after each restore (each restore is a copy of the file saved before the sabotage).

## Runs (`.dd/`)

run-s1-red, run-s1-dbg to dbg5 (the spelling fault, temporary prints, removed), run-s1-green2, run-s1-mf1, run-s1-mf2, run-s1-set (90/90: UndoMakeRoomLinkedPageTests, UndoHandedOverPlaceTests, JournaledStepTests, MakeRoomForClassesTests, testStackCases, testRecoveryCases), run-s1-mf3, run-s2-red, run-s2-green, run-s2-mf1, run-s2-set (91/91), run-s4-probe to probe3, run-s4-green (40/40). `python3 scripts/test_make_undo_traces.py`: 38 OK, traces not stale.

## For the director

1. **Step 2 needs a door piece: a link's text changed within a step.** What exists: `opKinds.move` carries exactly one `linkSha`, the same on both sides, so a link's move can never change the text it holds; `UndoTreeReading.make` refuses a listing holding a link ("a link is moved, never written from a blob"); `writeFile` reads a link at its path as not a file (changed since). No op or pair of ops writes a link. Smallest piece: let a link's `move` carry an optional `linkShaAfter` (the SHA-256 of the new text, with both texts in `blobs`), judged by `linkSha` at `from` going forward and by `linkShaAfter` at `to` going back, made as "make the new link beside `to`, rename it in exclusively, remove the old link", with recovery judging each side by its own sha; `UndoFormat.ShapeIsKnown` on both platforms; checkCases for both sides; stackCases and recoveryCases at every swap. Then Insert Class: the hop whose text names a class page the plan renames is re-pointed (relative text recomputed from the link's new folder), nothing written through it; a link reaching a class page the plan does NOT rename (Day 3 linked to Day 1) needs no re-point and could simply be renamed with nothing written: buildable today without the door change, but left refused as the brief says (one arrangement, one ruling). Recommendation: the door piece first, then both together.
2. **Review C LOW 1, the recovery row for fix 1's state, is not added, because the state it would pin looks wrong.** Probed as a recoveryCases row (`beforeALinksMove`, `beforeSwap:2`, `handEdit: handedOverPlace`): recovery interrupts the step (names Day 3 and Day 2), never writes over the file at Day 3, takes the copy at Day 4 away, and leaves the removed page "Three." ONLY in a hidden kept original (`.Unit 1, Day 3.md.plantoir-undo-1-apply-orig`) with NO trail line naming it (`keptOriginalsBeside` wants one "could not put back" line; there are none). A folder in the same position is kept under a visible name with a line (Russell's ruling on U2). Pinning it would hand Windows a lesson hidden with nothing said. Options: (a, recommended) recovery that cannot put a kept original back over a taken place names it on the trail as `keptOriginalsBeside` rows require (or keeps it under a visible name as a folder is), then the row; (b) pin as it stands. Older than this round (door-3).
3. **Known limit, not built:** two later classes linked to one file keep only the last date written (review C LOW 3); part of the shared-file question already held.
4. **Spelling, wider than Insert Class:** `JournaledStep.key` (`standardizedFileURL.path`) spells a broken link's place `/private/var/...` and every other place `/var/...`; any caller mixing a lister's URL with a built one can miss a planned link move. Only Insert Class's link move is respelled here. Teachers' folders are under the home folder, where this does not arise; tests in temporary folders do.

## Self-check

House style grep over added Swift lines: empty; `ResolvedFile` keeps its MARK sections. Switch off, rename record untouched. Every new row is in the Mac's replay and held by exact name. The Windows clause test's three substrings each occur once in the clause (checked by script).
