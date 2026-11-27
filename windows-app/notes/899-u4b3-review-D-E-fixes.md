# #899 U4b3, third fix round: reviews D and E, the two MEDIUMs (2026-11-26)

Branch `issue/899-u4b3-linked-class-page-moves-its-link`, from 651692841. Commits: fix 1 03033c410, fix 2 4af7595af, lows and these notes after. `origin/dev` 96a3d2b73 was already in the branch; no new merge was made.

## For PROGRESS

- Fix 1 (review D, MEDIUM): recovery of a killed relink removes at most ONE just-made link. Two chained relinks (op0 Day 5 to Day 6, op1 Day 4 to Day 5, op1's new text op0's old) no longer lose Day 5's link.
- Fix 2 (review E, MEDIUM): the `[[old name]]` rewrite of Insert Class (and Duplicate Class) visits each file once, at its own place. A moved or re-pointed link is listed at neither of its names, so review E's probe goes ahead instead of refusing "cannot tell now" at Day 5.

## Fix 1: what was built, and where it departs from the brief

`UndoRecovery.removeTheLinksJustMade` and the Python `remove_the_links_just_made` now work like this:
- They read every relinking op in the work's own swap order: index order going forward, reversed for an Undo.
- An op is a candidate when both of its links stand, each holding its own side's text.
- A candidate is passed over when its just-made side is the side ANOTHER relink starts the work from (going forward that relink's `from`, for an Undo its `to`) and that other relink's end side does not yet hold its end text. The link there is the other op's own, not moved yet.
- Of the candidates left, the LAST in swap order is the one whose swap was in flight. Only its just-made link is removed.
- Every other op is then judged by `fileStates` as a finished or unstarted relink.

**The departure, said plainly.** The brief's invariant says the op in flight is known "from what the journal recorded of the step's progress (which ops had closed)". **The journal records no such thing.** Its phases are per step (`begun`, `undoing`, `redoing`, ...), and no line is written inside a step (review D says so too). Adding a per-op line would change the journal's format, contracts and Windows, which is a piece of its own.

So the rule above uses the folder plus the swap order. The probe showed why that matters. The old rule also removed Day 5's link at `beforeSwap(0)`: Day 5's original link holds op1's new text, so op1 looks "both standing" before anything moved. The pass-over clause is what prevents that.

The rule does not tell apart a kill inside op0's swap from one inside op1's: at `relinkRenamedIn` the folder reads the same in both. Either way it removes Day 5's link, and every link of the step is left standing exactly once, at one side or the other. Recovery then settles the step whole, which the tests prove at every stop point.

Review D's LOW 1 ("made by this swap" rests on equal text alone) has the same root as this fault. It is narrowed (one link at most, never one another relink starts from) but NOT closed: the evidence is still equal text plus order. Closing it needs per-op progress in the journal. See "For the director".

Tests:
- `UndoRelinkTests.testTwoChainedRelinksKilledAtAnyMomentLoseNoLink`: every stop point (`beforeSwap`, `relinkStaged`, `relinkRenamedIn`, for both swaps), apply, Undo and Redo, 18 kills reached. After recovery the links are exactly as before or exactly as after, nothing is staged, and no phase is left in flight or interrupted.
- Python `test_recovery_cases_with_a_relink` extended to the `chained` shape (10 rows).
- Three recoveryCases rows, `withARelink: chained` (call `relinkTwoChainedLinks`, files read on Day 4 to Day 6): step `relinkRenamedIn:1` rolledBack; step `beforeSwap:0` failed; undo `relinkRenamedIn:0` done. `recoveryCasesHow` says what `chained` means. The Mac replay count goes from 79 to 82.
- All three rows are held under `Reason899W8RelinkedLink`, names matched byte for byte by script (count 1 each). They fail on Windows because its replay knows neither the key `withARelink` nor the stop point `relinkRenamedIn` (the reason sentence already names both).

## Fix 2: what was built

`JournaledStep.markdownFiles` no longer adds each link move's `to`. A link the step moves or re-points is listed at neither name. The page it leads to is rewritten at its own (new) name when it is one of the pages listed (`ClassPages.pagesOfSection`: the section's own folder and every course-level page), and never through the link.

Tests:
- `UndoMakeRoomLinkedPageTests.testARePointedLessonsWikiLinkIsRewrittenAtItsOwnPage` (review E's probe). Before the fix it was refused with `cannotTellNow`, naming Day 5. Now it goes ahead as one step: Day 4 holds `[[Unit 1, Day 3]]` once, Day 5 is re-pointed at `Unit 1, Day 4.md`, one new page, Undo and Redo exact.
- `testDuplicateClassRewritesARePointedLessonsWikiLinkAtItsOwnPage`. **It passed on the old door too**: Duplicate Class did not reach review E's refusal in this arrangement. Review E's "reaches Duplicate Class too" was found by reading the code, not by running it, and I did not have time to find out why it does not reproduce. The test pins the outcome. It is not a must-fail.
- `testALinkedPageOutsideTheClassPagesIsRewrittenOnceAtItsOwnPlace` (renamed from `testALinkedPageThatNamesItselfIsRewrittenOnceThroughTheLink`) covers a moved, not re-pointed, link to a course-level file holding `[[Unit 1, Day 3]]`.
  - **Released code (461ee3943)** replaced the link with a plain copy at Day 4 and rewrote that copy. The course-level file was itself one of `pagesOfSection`, so it was rewritten at its own place too.
  - **Kept now:** the file is rewritten once, at its own place, and no op of the step writes Day 4. This also passed on the old door: there the write at Day 4 resolved to the file's own place. The test pins that this is kept.
- `JournaledStepTests.testAWriteAtThePlaceALinkMoveLeavesIsRecordedAsANewFile`: its two listings no longer include Day 4.
- Documentation 09: the sentence "the `[[link]]` rewrite reaches it the same way, once" now says what the rewrite does.

## Small items

- Review E LOW 1: done. The clause and documentation 09 now say the two refusals were "added in U4b3 until the door can change a link's text where it stands", not "as before U4b3".
- Review E LOW 2: done. The clause and documentation 09 now say "not a class page of this section".
- Review E LOW 3: done. The clause now says "does not refuse ... except in the two arrangements named below".
- Review D LOW 4: done. The opening of `opKinds.move` (file-formats.json) now names the pair `linkShaBefore` and `linkShaAfter` as the alternative to "exactly one of sha, listingSha and linkSha".

## Must-fail lines

- M4 (fix 1, Swift): the new chained test run against the old `removeTheLinksJustMade` gave 7 failures, for example `chained-apply-beforeSwap(0): links [Optional("Unit 1, Day 1.md"), nil, nil]` and `chained-redo-relinkRenamedIn(1)` phase `interrupted`. Restored; the run was green after.
- M5 (fix 1, Python): the old `remove_the_links_just_made` gave 2 failures in `test_recovery_cases_with_a_relink` (`'interrupted' != 'rolledBack'` and `'interrupted' != 'failed'`). Restored; OK.
- M6 (fix 2, Swift): the old `markdownFiles` gave `testARePointedLessonsWikiLinkIsRewrittenAtItsOwnPage` failing with the caught error `refused(cannotTellNow(... Unit 1, Day 5.md))`, and 2 failures in JournaledStepTests (the listings). Restored; green.
- Sabotage was done by putting HEAD's file back and then copying the fixed file back from the scratchpad. `git diff` was clean against each commit afterwards.

## Runs (all through xlock.sh, main Mac, unit classes only)

- `UndoRelinkTests` (15), `UndoJournalContractTests` (19), `UndoWriterScanTests`, `UndoHandedOverPlaceTests` (6), `JournaledStepTests` (27), `UndoMakeRoomLinkedPageTests` (28), `UndoMakeRoomStepTests`, `DuplicateAsNextClassTests`: 155 tests, 0 failures.
- After the lows: `UndoOpKindsTests`, `FileFormatsContractTests`, `UndoJournalContractTests`, `UndoMakeRoomStepTests` and `UndoMakeRoomLinkedPageTests`: 97 tests, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 40 tests OK. The committed traces are what the generator writes.

## Left for the next piece

- Review D LOW 3 (the kept-page trail line is written before the rename, and is untrue if the rename fails) and LOW 2 (a failed relink reports "in use" where "changed since" is the truth): left as the brief says.
- Why the Duplicate Class arrangement does not reach review E's refusal on the old door (see Fix 2).
- A link in the section that the step does NOT move (an earlier class that is a link) is still listed by `markdownFiles` and written at its own name, through the link, as in released code. Not changed here.

## For the director

- Per-op progress in the journal. The invariant as briefed ("known from what the journal recorded ... which ops had closed") cannot be met: no such record exists. Options, my recommendation first:
  1. Accept the order-and-pass-over rule built here. Every link stays standing exactly once and the step settles whole at every stop point tested.
  2. A new piece that writes a per-op progress line inside a step. That is a format change for both platforms, and it would also close review D's LOW 1.

## For documentation 12

Windows' recovery of a relinking step must remove at most one link:
- Read the relinks in the work's swap order (index order for an apply or a Redo, reversed for an Undo).
- Take as candidates those with both links standing, each holding its own text.
- Drop a candidate whose just-made side (`to` going forward, `from` for an Undo) is the side another relink starts from (`from` going forward, `to` for an Undo) while that other relink's end side does not hold its end text.
- Remove the just-made link of the LAST candidate left.

The `[[old name]]` rewrite of Insert Class never lists a moved or re-pointed link at either name. The page it leads to is rewritten at its own place when it is one of the section's pages.

## Self-check

House style: in the added Swift, no GCD, map, filter, reduce or `$0`; tests are in existing MARK sections. The rename record is still kept and the switch is still off. The new contract rows are in the Mac replay and held for Windows by exact name. Review lows: three of review E's and review D's LOW 4 are fixed; review D's LOW 1 is narrowed, not closed; LOW 2 and LOW 3 are left.
