# mac-3 (#899 Undo): Insert Class re-points an EARLIER class's link to a page it renames

Brief `vm-tools/briefs/2026-11-27-899-mac-3-insert-class-re-points-an-earlier-class.md`. Base `origin/issue/899-mac-2-insert-class-re-points-an-in-between-link` be78dc85a. `origin/dev` merged before proving and again before hand-back: "Already up to date" both times (dev 35b54c40a, mac-1, is already in the base; no merge commit). **`contracts/` touched (one `undo.rule.shadow` sentence, five `stackCases` rows, `stackCasesHow`): both gates.** Also done at the director's word: #1054 (access time in two test helpers), and review 3 of mac-2's LOW 1. LOW 2 is left (below).

## For PROGRESS

- `ClassInsertionPlanner.apply` step 1b: mac-2's loop over re-date-only classes is WIDENED, not copied: it walks every class page of the section as it stood (`classesBefore`) that the plan does not rename (re-date-only, or neither: an earlier class above all). One loop, one rule, mac-2's: its own text names a renamed page, re-pointed where it stands (only the last path part changed); through a hop inside the working folder, the hop re-pointed where it stands, once per `HopEntry` (a hop reached by an earlier and a later class is planned once); through a hop outside, its own link straight at the page's new place. Nothing written through it: an earlier class is in no `plan.moves`, so the dates loop never reaches it (`ClassPages.isTheFirstClassLeadingToItsFile` is unchanged and still gives a link reaching a class page no date).
- The example: Day 1 a link holding `Unit 1, Day 3.md`, room at Day 2: Day 1 now holds `Unit 1, Day 4.md` and leads (by identity) to the lesson now at Day 4; before, it led to old Day 2's lesson.
- #1054 (for, not fixes): `UndoRelinkTests.outsideNow` and `JournaledStepTests.timesUnder` compared access time and modification time; a scanner on the second Mac moves access time. Both now compare modification time, size and the SHA-256 of the bytes, never access time.
- Review 3 of mac-2, LOW 1: documentation 09's mac-2 sentence and mac-2's Windows item (its part-way item and test (b)) now say only the LIVE settle gives the item back over the step's own link; the pre-clean and recovery keep the step's link at the place and the item visible beside it, said (corrected in place in mac-2's notes, marked "corrected by mac-3").

## For documentation 12

W8b 22a (or a 22c after 22b: the director decides) builds the earlier-class re-point after 21b's one-place relink: "When Insert Class renames class pages, every other class page of the section the plan does not rename (only re-dated, or neither: an earlier class above all) whose link reaches a renamed class page is re-pointed in the same step by the same rules as a re-dated class: its own text when its text names the page; the in-between link where it stands when that link is inside the working folder (once however many classes reach it); its own link straight at the page's new place when the link in between is outside. Nothing written through it, no title and no date; Undo and Redo put every text back and forward with the step." Fixture: the linked-page course of the existing rows with Day 3 a plain page and Day 1 replaced by a link holding `Unit 1, Day 3.md` (or `../../elsewhere/hop.md`, hop.md holding `../section1/All Classes/Unit 1, Day 3.md`). Note for the test writer: Day 1's date is read through its link (the lesson's, 2026-09-14), so the plan dates old Day 2 at Day 3 2026-09-16 and old Day 3 at Day 4 2026-09-18 (the rows pin this). No trail event, `folding.moves` row, wording key or `file-formats` reason changed.

## What Windows must hold

Five `undo.stackCases` rows ("mac-3, Insert Class with an earlier class …") held by exact name under `Reason899W8bLinkedClassPage`; the constant gains "an earlier class whose link reaches a renamed class page is re-pointed in the same step, by the same rules (the mac's mac-3, …)" and names the two new calls. Checked by script: each name once in the contract and once in the ledger; no unescaped quote in the constant; parentheses 12 and 12. Each fails on Windows at its first call: `makeRoomWithAnEarlierClassLinkedToAClassItRenames` and `makeRoomWithAnEarlierClassLinkedThroughALinkInside` are unknown to Windows' stack replay. `UndoMakeRoomStepTests.cs`'s three `undo.rule.shadow` substrings are each present once (script).

## Must-fail lines

See `899-mac-3-mustfail.log` (filled below after the runs).

## Runs (`.dd/`)

1. run-0-built-with-fix (not a red run: the planner edit reached the build; kept as a log): 41 tests, 4 failures, all the tests' own fault (identity compared with the lesson's OLD file: a plain page's rename writes a new file; and a date pinned from the plain-Day-1 shape). Tests corrected, committed.
2. run-red (tests only, the planner as on the base): 41 tests, 8 failures in 4 tests (`testAnEarlierClassLinkedToAClassItRenamesIsRePointed` 3, `…ThroughAHopInsideRePointsTheHop` 2, `…ThroughAHopOutsideRePointsItsOwnLink` 2, the kill table 1). Green before: the shared-hop test (the later class already re-points the hop) and the plan-leaves test, as they guard.
3. run-green1: 161 tests, 1 failure (the new stackCases rows' placeholder dates; read off and set). run-green2: `UndoMakeRoomLinkedPageTests`, `MakeRoomForClassesTests`, `DateKeyByTheTargetsPlaceTests`, `UndoJournalContractTests`, `SharedRulesContractTests`, `ClassPlanningContractTests`, `ActivityTrailWiringTests`: 189 tests, 0 failures.
4. `python3 scripts/test_make_undo_traces.py`: 46 tests OK, traces current (nothing regenerated).

## Left for the next piece

- Review 3 of mac-2, LOW 2 (the item that will not MOVE stays under the hidden name, unsaid): not done, for the stop figure. What it needs: one trail line said where `UndoSwap.relinkWhereItStands` returns `.leftUnderTheStagedName` (and, once per stopped step, where recovery's tidy gets `.couldNotMove`), a test first that it is said and names the visible place. No existing sentence is true of it (the kept-item line says the item is kept under a visible name; the left-part-way line says the place could not be changed). A proposed sentence for Russell, with a held Windows ledger row as mac-2 did: "an item that was not Plantoir's, found where a link was being changed, could not be moved back yet; it belongs at <visible place>, and Plantoir will try again the next time it opens the course".

## For the director

- Noticed, not changed (out of scope): an earlier class that is a link to a later lesson has its date read through the link, so the dated plan treats Day 1 as meeting on the lesson's day (2026-09-14) and dates every class it renames one meeting later than beside a plain Day 1 (Day 4 2026-09-18, not 2026-09-16). Recommendation: the planner reads a linked class's place in the order by its own name, not the lesson's date, when the lesson is another class page of the section; a ruling first.
- Out of scope, not tested: class pages of other sections and non-class pages that link to a renamed class page.

## Self-check
