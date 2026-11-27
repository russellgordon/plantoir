# #1046, #1050, #1052: test reliability (2026-11-27)

One branch, `issue/1046-1050-1052-test-reliability`, three distinct issues, one
commit each. Mac only: no product behaviour a teacher can see changed, so no
HIG section applies and nothing goes in `contracts/`.

## #1046: `WebPreviewControllerTests.testShowFreshBuildLoadsEvenWhenTheAddressWasAlreadyRequested`

**Cause.** The test judged the controller's decision to load by waiting, on a
fixed 5 s poll and two 6 s `wait(for:)`s, for WebKit to begin each navigation.
A load from `WebPreviewController` reaches WebKit only in the completion of
`websiteDataStore.removeData(ofTypes:modifiedSince:)` (the caches are emptied
first, by design), and that completion is a round trip to WebKit's own
process, delivered on the main thread. Anything that holds either back for
six seconds, such as another build running on the same Mac (gate `g-d26-2`),
failed the test at its first wait with nothing wrong in the preview. Nothing
in the product is racy: whether to load is the controller's decision alone,
made synchronously, and the test was measuring how fast WebKit answered.

**Change.** `WebPreviewController` counts the loads it asks for
(`appLoadsAskedFor`, `@ObservationIgnored`, incremented in
`loadIgnoringEverythingCached` beside `ledger.appLoadBegan()`), and the test
asserts the count after each call: first request 1, repeated request still 1,
`showFreshBuild` 2, the mounting view's `loadIfNeeded` after it still 2. No
wait of any kind remains; the old `pollUntil` (which used
`DispatchQueue.main.asyncAfter`) and `NavigationStartRecorder` are gone.

**Proof.** Not reproduced by load: 20 runs under 36 busy loops, 30 runs and 8
whole-class runs beside a looping clean build plus 4 busy loops, all green on
the old test. Reproduced by a forced ordering: the main actor held for 6.5 s
just after the first `loadIfNeeded` (`Task { @MainActor in usleep(6_500_000) }`)
failed the old test 3 of 3 with the gate's own line, "Asynchronous wait
failed ... first navigation". The same hold on the new test: 3 of 3 green.
Then 30 of 30 green in a row (see "Runs").

**Windows.** No same test or fault: Windows' preview tests are source tests
(`PreviewNavigationSourceTests.cs`) and nothing there waits on WebView2. No
follow-up.

## #1050: `LayoutAndSmallBehaviourTests.testTheBoxInTheVerbSheetTakesTheFocusAndTabLeavesIt`

**Cause.** `SheetHost` (the test host that presents a SwiftUI view as a real,
off-screen sheet) set `presentation.isShown = true` and then turned the run
loop for a fixed 0.6 s, after which the test read `window.attachedSheet`.
SwiftUI hangs the sheet on a later turn of the run loop, and how much later
depends on what else the main thread has queued. In gate `g-d27-1` (4375
tests, the screen in use) it took longer than 0.6 s once, and the test found
no sheet: it failed at 1.53 s, the length of a normal run, which is the fixed
pump running out, not a hang. No earlier test in the class leaves anything
behind that stops the sheet: each `SheetHost` makes its own parent window,
and the same test passed every time it ran alone or with its whole class.

**Change.** `SheetHost.init` now waits for the event itself: it turns the run
loop in short slices until `window.attachedSheet` is there, then gives the
same 0.6 s settle as before so the other ten `SheetHost` users (#621 sizing,
`PageTablesSheetTests`) see exactly what they saw. A 30 s bound only stops a
sheet that never opens from holding the suite; the caller's
`XCTUnwrap(host.sheet)` then fails. It prints how long the sheet took
("SheetHost: the sheet was hung from its window 0.09 s after it was asked
for"), so a slow one is visible in a gate log. The product (`SectionVerbSheet`,
`ClassDatesTextView`) was not at fault and is unchanged.

**Proof.** Not reproduced by load (same runs as #1046, the verb-sheet test in
each, all green). Reproduced by a forced ordering: a main-actor hold of 0.7 s
just after `isShown = true` failed the old host 1 of 3 with the gate's own
line, "XCTUnwrap failed ... the verb sheet did not open". Deterministically:
the sheet asked for 0.8 s late (a run-loop `Timer` setting `isShown`) failed
the old host and passed the new one (see "Runs"). Then 30 of 30 green in a
row.

**Windows.** No same test or fault: Windows has no off-screen sheet host; its
dialogs are not tested this way. No follow-up.

## #1052: `verify.sh` ran a written list of Python tests

**Cause.** Step 0.5 ran each `scripts/test_*.py` by name; nothing noticed a
file that was not named, so 17 files ran on Windows only, and six more
(`test_marking_*.py`) were named only through a loop variable. The gate was
green on a tree where `test_make_undo_traces.py` failed.

**Change.** At the end of step 0.5 a discovery runs every `scripts/test_*.py`
whose file name is not written on a non-comment line of `verify.sh` (the
file reads its own text, so a test run by name anywhere, the image runs
included, keeps its own pass line and is not run twice). Each one found must
pass; a file needing python-frontmatter exits 77 on a Mac without it and
fails there on purpose, since it belongs in the image's runs. The marking
loop now names its files whole. `not_run_on_this_mac`, the named skip list
with a reason beside each entry (as Windows' `NotRunHere`), is empty: every
file passed on this Mac. The header no longer says the list is written by
hand.

**Proof.** Step 0.5 alone (the lock and terminal check left out, nothing
else changed): 141 pass, 0 fail; the discovery ran the 17 files that were
named nowhere (test_make_undo_traces.py among them), all green; the six
marking files ran by name. Must-fail: a planted `scripts/test_zz_mustfail_1052.py`
that exits 1 gave "FAIL scripts/test_zz_mustfail_1052.py, found by the
discovery of every scripts/test_*.py (#1052)" and `FAILED=true`; removed, the
discovery was green again. The whole `verify.sh` was not run (COMMON: a
writer never runs it); the director's gate does.

**Windows.** Nothing to do: Windows already discovers the files.

## Runs

- `run-repro1.log`: old code, the two tests 20 times each under 36 busy loops: 40 of 40 green.
- `run-repro2.log`: old code, 30 times each beside a looping clean build and 4 busy loops: 60 of 60 green.
- `run-repro3.log`: old code, both whole classes 8 times beside the build: 168 of 168 green.
- `run-forced-old.log`: old code, main actor held 6.5 s in #1046's test: RED 3 of 3, line 50 "Asynchronous wait failed".
- `run-forced-old-1050.log`: old host, main actor held 0.7 s after `isShown`: RED 1 of 3, line 301 "the verb sheet did not open".
- `run-forced-new.log`: new code, the same two holds: 6 of 6 green.
- `run-forced-old-1050-late.log`: old host, the sheet asked for 0.8 s late by a run-loop `Timer`: RED 3 of 3, "the verb sheet did not open". `run-forced-new-1050.log`: new host, same: 3 of 3 green (the sheet hung 0.88 to 0.91 s after it was asked for).
- `run-final-30.log`: committed fix, both tests 30 times in a row: 60 of 60 green.
- `run-classes.log`: WebPreviewControllerTests, LayoutAndSmallBehaviourTests, PageTablesSheetTests (the other SheetHost user), PreviewStartPageTests (reads WebPreviewController.swift as source): 59 tests, 0 failures.
- Merges of `origin/dev`: before proving, already up to date (base 35b54c40a); before handing back, again up to date (origin/dev still 35b54c40a).

## For the director

- `contracts/` not touched; `scripts/` not touched (only `verify.sh` at the root).
- Self-check: no `DispatchQueue`, `map`, `filter`, `reduce` or `$0` in the
  changed Swift (the one `DispatchQueue` that was there, in the old test, is
  removed); MARK sections kept; no timed wait added (the 0.6 s settle in
  `SheetHost` is the one that was there, now after the event).
