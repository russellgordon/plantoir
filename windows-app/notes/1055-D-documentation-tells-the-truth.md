# #1055 D: documentation tells the truth about symbolic links in course content

Branch `issue/1055-D-documentation-tells-the-truth`, from `origin/issue/1055-W4-windows-moves-no-link` ae50648b1; `origin/dev` merged before hand-back. Documents only: every file touched is Markdown under `documentation/` or `windows-app/` (`git diff --name-only ae50648b1..HEAD`).

## Sections marked (one line under the heading)

- 09: "U4b2: linked-page-written-through" (Kept by #1055); "U4b2: a-moved-link-is-judged-by-its-bytes" (M6); "U4b2: a-linked-section-folder-is-renamed" (M2 then M7); "U4b3: linked-class-page-moves-its-link" (M1); "U4b3 door: a place handed over within a step" (M5); "U4b3 relink: a link's text changed within a step" (M4); "U4b3 relink-5" (M1); "mac-1" (M3); "mac-2" (M1, M3); "#1048" (S1, first three paragraphs only).
- 09 "U4b, fourth part" NOT marked: read against the tree, its link paragraph (a folder that holds a link is listed with `link <sha> <path>` and renamed with the link inside, `UndoTreeListing.links`) is still true; a folder that IS a link is still refused there.
- 12: "What W7b2 and W8 take from U4b2-1" (Kept); "What W8 owes from U4b2-14" (M6, W4); "… U4b2-15" (M2, M7, W4); "What the Mac's U4b3 leaves for Windows" (all but the kept original); "What W8 pieces 5 and 6 did" (piece 6); "What W8b window A did" (piece 21); "What W8b 21b1 to 21b5 take from mac-1" (M3, W2); "What W8b 21b1 to 21b5 built" (W2); "What W8b window D did" (W3, W4; 21c stays).
- PROGRESS: the 2026-11-26 U4b2-11 to 15 heading, U4b2-14's and U4b2-15's lines; bracketed prefixes on the W8 pieces 5 and 6, W8b window A, window D, mac-1, mac-2 and 21b lines.
- Notes headers: `899-u4b2-1-linked-page-written-through.md` (Kept), `899-u4b3-review-fixes.md` (fixes 2 to 4 removed, fix 1's exclusive put-back stays). The brief's loop prints nothing.

## Sentences corrected in place (before, after)

- 09 #276: "…not asked about either — the build never writes through one" → "…not asked about either (#276)" (the build now writes the date and title through a symbolic link).
- 09 U4b2-1: "refused when that later class is a link, until the pieces that move a link …; Windows' Insert Class still goes ahead outside the door" → "refused … (…; no piece moves a link, #1055); Windows' Insert Class with the switch off goes ahead".
- 09 about 23267 (M7 review LOW 2): "a link only where this run moved a link (`Move.isALink`, L3)" → "a link never counts (L3; `Move.isALink` went in #1055 M7)".
- 12 W7b2-1 item and U4b2-1 item: a bold "Removed by #1055, M1 and M3" clause before the Mac's U4b3 clause (the Mac now refuses by the general guard).
- 12: the two "dead until W2 / until W4" sections replaced by "Symbolic links in course content (#1055)".
- 05 about 6289: "to say 'left linked'" → "(since #1055 S2 it is dated through the link)". 05's #275 paragraph (872) was already right (S2). 2573 (the freshness reader) left: not about writing.
- 04 614: "the page is a link to a file kept elsewhere" → "the page has a second name (a hard link)".
- PROGRESS: U4b2-15's line and M1's prefix now say the door's general guard; M1/S1/M2's summary sentence marked as replaced by the rule; "until W1" → W1 struck. W2, W3, W4 lines added.

## New sections

09 (end of the Undo part) and 12 (end of the Windows Undo part): "Symbolic links in course content (#1055)". Code named, each found by `git grep` on the base: Mac `JournaledStep.placeALinkLeadsTo`, `JournaledStep.remove`, `UndoItem.read`, `writePlainly`, `testAClassPageThatIsALinkCanBeCopied`, `UndoTreeReading`, the "cannot be judged as a pair" check in `SpecialFolderRenamer.swift`, `undo.wording.renameFolderNothingWasChanged`, `CourseConfiguration.fileALinkLeadsTo`, `UndoRecovery.keepPagesWhosePlaceIsTaken`, `shapeIsKnown`, `wholeOpsStandAlone`; Windows `UndoActionStep.WritePlainlyQuietly`, `AssistWorkspace.ApplyInsertClasses`, `UndoActionStep.MoveFolder`, `SpecialFolderRenamer.IsAPlaceToMove`, `SpecialNames.RenameFolderNothingWasChanged`, `CourseConfiguration.FileALinkLeadsTo`, `UndoRecovery.KeepPagesWhosePlaceIsTaken`, `UndoFormat.ShapeIsKnown`, `UndoStep.WholeOpsStandAlone`; shared `_replace_the_page_safely`, `_has_a_second_name`. Sentences: Mac Rename Folder from M2's notes and `SpecialFolderRenamer.swift` 777; Mac Insert Class from ORDER's reading of the code (not re-measured); Windows from W4's notes.

## The grep's remaining hits, and why each stays

Outside marked sections only: 09 1045 (`.merged_output`, the build's own link), 1319, 2866, 6767 and 12 1170, PROGRESS 1330 ("handed over" of a row, a window or a page: not links), 09 11238 (the build's own link), 12 3026 and 05 5998 (the build's own links), PROGRESS 1442 (a hard link in `assets`), PROGRESS 2444 and 09's "relinks no page" (page TEXT re-linking), PROGRESS's #1055 lines themselves (M3 to M6, W2, W4: they say what is gone). 06's 285 and 406 are the build's own links: left. 04's 419 and 2111: the build's own links, left.

## Left alone

`contracts/`, Help, release notes, code comments. Contract and code sentences found wrong, for their owners: `TodaysClassOnTheFrontPage.swift` 210 says the build never writes through a symbolic link front page (no longer true of the date and title).
