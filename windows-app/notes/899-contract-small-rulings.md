# #899 Piece A: contract small rulings (2026-11-26)

Branch `issue/899-contract-small-rulings`, off `origin/dev` 0e12bc8ac.

## For PROGRESS

- Ruling 3 of 2026-11-26: Russell confirmed `keptOnWindows.hiddenItems` ("To see it, open View in File Explorer and turn on Hidden items."). The "awaiting Russell's confirmation" notes are gone from `contracts/class-planning.json` (`keptOnWindows.why`), documentation 12's W7b2-9 section and `899-w7b2-9-kept-file-alert.md`; each now says he confirmed it on 2026-11-26. The sentence is unchanged.
- Ruling 9 of 2026-11-26: Windows says its own `keptGone`, `todaysClassOnTheFrontPage.keptOnWindows.keptGone`: "“{kept}” is no longer there, so the folder was not opened." It replaces the mac's `wording.keptGone` ("… so there is nothing to show.") on Windows only, because Windows' button opens the folder and the file stays hidden. The mac's key and code are unchanged. `TodaysClassOnTheFrontPage.KeptGoneSentence` says it.
- `contracts/README.md`: `actionTraces` is 162 traces (counted from `undo-traces.json` by script: 162; 27 steps in `undo-action-steps.json`, six each), not 120. The same stale "~120" in `UndoTraceContractTests.cs`'s summary now reads "the action traces (162 today)". Documentation 12's U3 hand-over paragraph ("120 traces made from those steps", "20 steps") is a dated record of U3 and is left as it was.
- `plainWordsCheck` now names the scope of its exception: a name in `plainWordsExceptions` is taken out only of the one sentence its `in` names (today `keptOnWindows.hiddenItems`, said on Windows alone), and every other sentence, the mac's included, is checked whole. That is what the two tests do: Windows' `NoKeptAlertSentenceSaysATechnicalWord` removes "File Explorer" only from the sentence whose key equals `in`; the mac's `testNoSentenceSaysATechnicalWord` applies no exception. The six quoted words both tests look for are unchanged. No behaviour change.

## For documentation 12

In the W7b2-9 section ("The words read the contract … The two Windows words are new keys beside `wording`"): there are now three Windows keys beside `wording`. Add:

- `keptOnWindows.keptGone`: "“{kept}” is no longer there, so the folder was not opened." (Russell's ruling 9 of 2026-11-26). Said in place of `wording.keptGone` when a kept file is gone by the time Open Folder is pressed; `KeptGoneSentence` is pinned against it by `TheSentencesAreTheContracts`, and `TheGoneAlertSaysItsSentenceWithOkAlone`, `AKeptFileGoneByThePressIsSaidAndNothingIsOpened` and `OnlyOpenFolderOpensAndAGoneFileShowsTheGoneAlert` read it. `TheSentencesAreTheContracts` also pins `keptOnWindows`' key set (`hiddenItems`, `showKept`, `keptGone`, `why`). `wording.keptGone` stays in that test's accounted-for list, as `wording.showKept` does, because Windows replaces it with its own key.

## Must-fail lines

Tests first: the contract and the four Windows test sites were changed and committed (the first commit) before the code; run against the old `KeptGoneSentence`, see "Runs".

## Runs

See the hand-back; filled in below.

## Left for the next piece

Nothing.

## For the director

Nothing parked.
