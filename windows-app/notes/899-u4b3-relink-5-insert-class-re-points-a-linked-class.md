# #899 U4b3 relink-5: Insert Class re-points a later class linked to a class page (Mac)

Branch `issue/899-u4b3-linked-class-page-moves-its-link`, from e7794b6d8 (origin/dev 96a3d2b73 already merged in; origin/dev had not moved when proving). `contracts/` touched: both gates.

Built to the director's order of 2026-11-26 (Russell's answer to "Held for Russell" 2: the IN-BETWEEN link is re-pointed; when it is outside the working folder, the class's own link is re-pointed straight at the lesson's new name). Relink-4's "For the director" 1 (a relink with `from == to` does not work through the door) means the in-between-inside case is left exactly as refused today; see "Left for the next piece".

## For PROGRESS

- Insert Class (Make Room, Duplicate Class) walks each later class that is a link once, before anything is planned (`ClassInsertionPlanner.classPagePlaces`, `reachOfALinkedClass`, enum `LinkedClassReach`, struct `ClassPagePlace`), each hop by its own `lstat` identity, the first class page of the section reached deciding:
  1. its own text names a class page the plan renames: renamed AND re-pointed in one relinking move (`JournaledStep.relinkLink`), text = old text with only the last path part replaced (`textAfterTheMove`); nothing written through it;
  2. it reaches such a page only through a link that is not a class page, OUTSIDE the working folder: the class's own link re-pointed straight at the page's new place (`relativeText`, from the link's folder; in practice the file name), the outside link untouched;
  3. same through a link INSIDE the working folder: still refused, `cannotTellNow`, as before (the only refusal left, with one more arrangement of the same kind: a class the plan only re-dates whose link reaches a renamed page);
  4. it reaches a class page the plan leaves (an earlier class, directly or through hops): moved as itself (`moveLink`), text kept;
  5. anything else: as before (moved as itself and dated through, or a broken link renamed with nothing written).
  No date and no title is written through cases 1, 2 and 4 (the dates loop skips them).
- The page below a re-pointed link fills the place it leaves with a write and a removal: relink-4's proven shape.
- `undo.rule.shadow`'s refusal sentence replaced (the three Windows substrings each still once, checked by script); `stackCasesHow` gains the two calls, the turned-round call and the key `laterLinks`; the refusal row removed, six rows added.

## For documentation 12

W8b piece 22a (after 21b, the Windows relink door, and 22): Insert Class's four link cases on Windows.
- Walk each later class that is a link (never followed past what each hop names): each hop is the place the link before it names (relative text against that link's folder), compared by its own `lstat`-style identity (file ID of the place itself, not its target) against every class page of the section as it stands; at most 32 hops; the link's own place ends the walk (leads nowhere). The first class page met decides.
- Renamed page named by the class's own text: one relinking move from the old name to the new name, the new text the old text with only its last path part replaced by the page's new file name; no title, no date through it.
- Renamed page reached only through a non-class-page link outside the working folder: one relinking move whose new text is the page's new place relative to the link's folder (the file name, both being in the section's class folder).
- Same, but the in-between link is inside the working folder: refused before anything changes, the refusal given before U4b3 ("cannot tell now" naming the class's file). Also refused: a class the plan only re-dates whose link reaches a renamed page.
- A class page the plan leaves: the link moved as itself, its text kept, nothing written through it.
- Rows held under `Reason899W8bLinkedClassPage`: the six "U4b3 relink-5, …" stackCases rows. Each fails on Windows today because its call (`makeRoomWithALaterClassLinkedToAClassItRenames`, `makeRoomWithALaterClassLinkedToALinkedClass`, and the turned-round `makeRoomWithALaterClassLinkedToAnEarlierClass`) and the key `laterLinks` are unknown to Windows' replay. The removed refusal row's name is in neither file (script).

## Must-fail lines

RED 5 of 5 (`899-u4b3-relink-5-mustfail.log`): M1 the refusal put back (10 red: testStackCases and every turned-round or new test); M2 case 1 moved as itself (testStackCases and six case-1 tests); M3 a link to a class page dated through (testStackCases and eight, both the earlier-class link and the re-pointed one); M4 hops judged only at the chain's end (testStackCases, review C's probe, two more); M5 Python model with a plain link move for the relink (the two "undone and redone" rows). Tests were written with the behaviour, not run red before it; M1 stands for "seen failing first" (every new or turned-round test red with the refusal in place).

## Runs

- run-r5-first: UndoMakeRoomLinkedPageTests 25 of 25.
- run-r5-mf1 to mf4 (above).
- run-r5-docs: the 14 classes that read `09-mac-app.md` as text, SharedRulesContractTests and UndoWriterScanTests: 188, 0 failures (UndoWriterScanTests' counts unchanged: no new writing call).
- run-r5-second: UndoMakeRoomLinkedPageTests, MakeRoomForClassesTests, UndoRelinkTests, UndoHandedOverPlaceTests, JournaledStepTests, UndoJournalContractTests, SharedRulesContractTests, UndoWriterScanTests: 209, 0 failures. `python3 scripts/test_make_undo_traces.py`: 40, OK; traces not stale.

## Left for the next piece

The door piece (relink-4's "For the director" 1: a relinking move with `from == to`, readable, judged at one place, swapped by one atomic rename over the old link). Then Insert Class must, in `ClassInsertionPlanner.apply`:
- In the rename loop, for `reach == .aRenamedPageThrough(link: hop, newPlace:)` with `isInside(workingFolder, hop)`: rename the class's link as itself (`step.moveLink(spelledAsItsNewPlace(rename.fromURL, beside: rename.toURL), to: rename.toURL, linkSha:)`, its text kept) and re-point the hop where it stands: `step.relinkLink(hop, to: hop, textAfter:)` with `textAfter` = the hop's text with only its last path part replaced by `newPlace.lastPathComponent` (the same rule as case 1; `textAfterTheMove(of: hop, reach: .aRenamedPageByItsOwnText(newName:))`). Plan each hop once even if two classes reach it.
- For a class the plan only re-dates whose link reaches a renamed page: `relinkLink(place, to: place, textAfter:)` with case 1's or case 2's text.
- Remove both arrangements from `firstLinkThatCannotBeMoved` (then delete it and the refusal block at the top of `apply`), and `undo.rule.shadow`'s sentence that begins "Two arrangements are still refused before anything changes", with the doc 09 sentence that begins "Two arrangements still refuse".
- Tests: turn `UndoMakeRoomLinkedPageTests.testALinkReachingARenamedPageThroughALinkInsideIsStillRefused` round (Day 5 holds `../../elsewhere/hop.md` unchanged, hop.md holds `../section1/All Classes/Unit 1, Day 4.md`, nothing written through either, Undo/Redo exact, a kill at every swap whole); add a re-date-only case if a numbered-course plan can produce one.
- Rows: there is no refusal row for these two today (the removed row was the direct case); add stackCases rows for the in-between-inside case (undone; undone and redone), a call such as `makeRoomWithALaterClassLinkedThroughALinkInside` and a key reading hop.md's text, held under `Reason899W8bLinkedClassPage`, plus the door's own `checkCases`/`recoveryCases` rows under `Reason899W8RelinkedLink`.

## For the director

1. Known limit, not built (brief's out of scope): an EARLIER class's link to a page Insert Class renames keeps its text and then leads to the page now at that name.
2. Known limit, held: two later classes linked to one file keep only the last date written.
3. Edge, not built: a re-pointed link's page whose own rename could not be done (its new name taken by a page not in the plan) leaves the link re-pointed at that taken name. It needs a foreign page at the renamed page's new name, which is normally the re-pointed link's own old place (handed over), so it should not arise in a plan the planner makes; noted only.
4. Relink-4's deviation (b) (a page MOVED into a place an out-leading link leaves) was not reached: Insert Class still fills every place with a write and a removal (`testARePointedLinkBesideALinkLeadingOutWritesOnlyTheOneDateOutside` passes in that shape).

## Self-check

1 to 6 (NIGHT3): own classes only through `xlock.sh`, no gate, no Windows, no UI tests, no window (NO-MAIN-SCREEN), must-fail recorded, notes written. 7: the house-style grep over the added Swift lines is empty; `ClassPagePlace` has its MARK section; the enum has no members needing one. 8: no riding lows. 9: switch off, rename record untouched. 10: every new row is in the Mac replay (two new calls, the key `laterLinks`) and the Python model, and held by exact name (script: each name once in each file).
