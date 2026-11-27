import Foundation

/// Where the app keeps its list, and how the list reaches the trail.
///
/// The one file of `Models/Undo/` that knows about the rest of the app
/// (`RealHome`, `ActivityTrail`), so every other file there compiles on its
/// own: the U1 harness builds them without the app.
nonisolated enum UndoJournalLocation {

    // MARK: - Stored properties

    /// A test points the list somewhere of its own (an unwritable place, to
    /// prove a failing list never touches the action). Nil in the app.
    nonisolated(unsafe) static var folderOverride: URL?

    // MARK: - Computed properties

    /// `Library/Application Support/Plantoir/undo` under the home
    /// `RealHome.forFiles` answers: the real one in the app, the `--state-dir`
    /// folder in a UI-tested app, the throwaway home under the unit suite.
    static var folderURL: URL {
        if let folderOverride {
            return folderOverride
        }
        return RealHome.forFiles
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Plantoir", isDirectory: true)
            .appendingPathComponent("undo", isDirectory: true)
    }

    // MARK: - Functions

    /// The app's list, with its trail lines connected.
    static func standardJournal() -> UndoJournal {
        UndoTrail.install()
        return UndoJournal(folderURL: folderURL)
    }
}

/// The trail lines U1 writes (`activityTrail.mustRecord`). Counts and
/// codes only: the journal holds page text, the trail never does.
nonisolated enum UndoTrail {

    // MARK: - Stored properties

    /// Set once, the first time the app's list is made (the core review's M7:
    /// it used to be set again on every publish).
    nonisolated(unsafe) private static var installed: Bool = false

    private static let guardLock: NSLock = NSLock()

    // MARK: - Functions

    static func install() {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        if installed {
            return
        }
        installed = true
        UndoTrailHook.interruptedLine = { course, section, phase, putBack, inTheWay in
            ActivityTrail.note(
                .undoRolledBack,
                UndoTrail.interruptedLine(course: course, section: section, phase: phase, putBack: putBack, inTheWay: inTheWay)
            )
        }
        UndoTrailHook.couldNotRecordLine = { action, course, section, change, why in
            ActivityTrail.note(
                .undoCouldNotRecordAStep,
                UndoTrail.couldNotRecordLine(action: action, course: course, section: section, change: change, why: why)
            )
        }
        UndoTrailHook.foundAFolderSetAsideLine = { course, section, place, hiddenName, keptAs, changes in
            ActivityTrail.note(
                .undoFoundAFolderSetAside,
                UndoTrail.foundAFolderSetAsideLine(course: course, section: section, place: place, hiddenName: hiddenName, keptAs: keptAs, changes: changes)
            )
        }
        UndoTrailHook.keptAPageLine = { course, section, place, keptAs in
            ActivityTrail.note(
                .undoKeptAPageUnderAVisibleName,
                UndoTrail.keptAPageLine(course: course, section: section, place: place, keptAs: keptAs)
            )
        }
        UndoTrailHook.setAsideByARestoreLine = { course, section, phase, files, stillJudged, closed in
            ActivityTrail.note(
                .undoSetAsideByARestore,
                UndoTrail.setAsideByARestoreLine(
                    course: course, section: section, phase: phase, files: files, stillJudged: stillJudged, closed: closed
                )
            )
        }
        UndoTrailHook.rolledBackLine = { course, section, phase, files in
            ActivityTrail.note(
                .undoRolledBack,
                UndoTrail.rolledBackLine(course: course, section: section, phase: phase, files: files)
            )
        }
        UndoTrailHook.couldNotPutBackLine = { course, section, phase, leftPartWay, keptOriginals in
            ActivityTrail.note(
                .undoCouldNotPutBack,
                UndoTrail.couldNotPutBackLine(course: course, section: section, phase: phase, leftPartWay: leftPartWay, keptOriginals: keptOriginals)
            )
        }
        UndoTrailHook.keptAnOriginalLine = { course, section, phase, keptOriginals, noLongerInTheList in
            ActivityTrail.note(
                .undoKeptAnOriginal,
                UndoTrail.keptAnOriginalLine(
                    course: course, section: section, phase: phase,
                    keptOriginals: keptOriginals, noLongerInTheList: noLongerInTheList
                )
            )
        }
        UndoTrailHook.keptWhatItReplacedLine = { course, section, isUndo, keptOriginals, keptOfWhatItHoldsNow, putBackFromAKeptOriginal, pagesOfTheStep in
            ActivityTrail.note(
                .undoKeptWhatItReplaced,
                UndoTrail.keptWhatItReplacedLine(
                    course: course, section: section, isUndo: isUndo,
                    keptOriginals: keptOriginals, keptOfWhatItHoldsNow: keptOfWhatItHoldsNow,
                    putBackFromAKeptOriginal: putBackFromAKeptOriginal, pagesOfTheStep: pagesOfTheStep
                )
            )
        }
        UndoTrailHook.leftNewestLine = { course, section, isUndo, refusal in
            ActivityTrail.note(
                .undoRefusedForAChangeLeftPartWay,
                UndoTrail.leftNewestLine(course: course, section: section, isUndo: isUndo, refusal: refusal)
            )
        }
    }

    /// `ICS3U/1 · the undo list could not put back 2 files left part way by
    /// a change that stopped, because what it needs to put them back is no
    /// longer in the list, and cleared the list. What “A.md” held before is
    /// kept beside it as the hidden file “.A.md.plantoir-undo-4-apply-orig”.`
    /// One sentence per kept original; none when nothing is kept.
    static func couldNotPutBackLine(course: String, section: Int?, phase: UndoPhase, leftPartWay: Int, keptOriginals: [String]) -> String {
        var line: String = UndoTrail.prefix(course: course, section: section)
        let counted: String = leftPartWay == 1 ? "1 file" : "\(leftPartWay) files"
        line += "the undo list could not put back \(counted) left part way by \(UndoTrail.what(phase)) that stopped, "
        line += "because what it needs to put \(leftPartWay == 1 ? "it" : "them") back is no longer in the list, and cleared the list."
        for kept in keptOriginals {
            line += " What \(JournaledStepError.placeName(ofKept: kept)) held before is kept beside it as the hidden file “\(kept)”."
        }
        return line
    }

    /// `ICS3U/1 · the undo list settled a change that stopped. What “A.md”
    /// held before is kept beside it as the hidden file
    /// “.A.md.plantoir-undo-4-apply-orig”, because it differs from what the
    /// list recorded.` For a kept original in `noLongerInTheList` (its bytes
    /// exactly what the list recorded) the reason is `because the list no
    /// longer holds a copy of it.` (the first review of U3c, LOW 2).
    static func keptAnOriginalLine(
        course: String, section: Int?, phase: UndoPhase, keptOriginals: [String], noLongerInTheList: [String] = []
    ) -> String {
        var line: String = UndoTrail.prefix(course: course, section: section)
        line += "the undo list settled \(UndoTrail.what(phase)) that stopped."
        for kept in keptOriginals {
            let because: String = noLongerInTheList.contains(kept)
                ? "because the list no longer holds a copy of it"
                : "because it differs from what the list recorded"
            line += " What \(JournaledStepError.placeName(ofKept: kept)) held before is kept beside it as the hidden file “\(kept)”, \(because)."
        }
        return line
    }

    /// `ICS3U/1 · Undo put back “A.md” from what was kept beside it, but the
    /// list could not keep a copy of all it needs for this change, so what
    /// it could not keep stays beside the page, and the next Undo or Redo of
    /// this change uses it. What “A.md” held a moment before is kept beside
    /// it as the hidden file “.A.md.plantoir-undo-4-undo-orig”.` A kept
    /// original it put back whose bytes the list would not take is said as
    /// `What “A.md” holds now is kept beside it as the hidden file “…”.`
    /// Nothing is said to be withheld or cleared: the step stays on the
    /// list with both directions offered (Russell's ruling of 2026-11-20,
    /// night; the second review of U3c, MEDIUM and LOW 1).
    static func keptWhatItReplacedLine(
        course: String, section: Int?, isUndo: Bool, keptOriginals: [String], keptOfWhatItHoldsNow: [String] = [],
        putBackFromAKeptOriginal: [String]? = nil, pagesOfTheStep: [String] = []
    ) -> String {
        // Each kept file is given by its path in the working folder, so two
        // pages with the same name in two sections are two pages (the
        // part-two review of U4b, LOW 4). A bare hidden name stands for a
        // page at the top of the working folder. `pagesOfTheStep` is every
        // page the step changes, by path: a named page whose file name
        // another of them shares is named by its path, even when that other
        // page is not named here (U4b2-4 review 1, LOW 1).
        var everyKept: [String] = []
        for kept in keptOriginals {
            everyKept.append(kept)
        }
        for kept in keptOfWhatItHoldsNow {
            everyKept.append(kept)
        }
        var pages: [String] = []
        for kept in everyKept {
            let page: String = UndoTrail.pageOfKept(kept)
            if !pages.contains(page) {
                pages.append(page)
            }
        }
        var pagesThatCouldBeMistaken: [String] = []
        for page in pages {
            pagesThatCouldBeMistaken.append(page)
        }
        for page in pagesOfTheStep {
            if !pagesThatCouldBeMistaken.contains(page) {
                pagesThatCouldBeMistaken.append(page)
            }
        }
        let which: String = isUndo ? "Undo" : "Redo"
        // Said "from what was kept beside it" of a page only when it was:
        // an Undo or a Redo whose content came from the list, and whose
        // outgoing bytes the list would not take
        // (`storeWhatTheOtherDirectionNeeds`, U4a), put the page back from
        // the list (the U4a sweep, LOW 1), decided page by page (U4b part
        // one's review, LOW 1), each page by its place in the working
        // folder, never by its name alone (the part-two review, LOW 4).
        // Nil: every page named was.
        var fromTheList: [String] = []
        var fromKept: [String] = []
        for page in pages {
            let named: String = UndoTrail.nameOnTheLine(page, among: pagesThatCouldBeMistaken, course: course)
            if putBackFromAKeptOriginal == nil || putBackFromAKeptOriginal?.contains(page) == true {
                fromKept.append(named)
            } else {
                fromTheList.append(named)
            }
        }
        var line: String = UndoTrail.prefix(course: course, section: section)
        if pages.isEmpty {
            line += "\(which) put back a page"
        } else if fromKept.isEmpty {
            line += "\(which) put back \(fromTheList.joined(separator: ", "))"
        } else if fromTheList.isEmpty {
            line += "\(which) put back \(fromKept.joined(separator: ", ")) from what was kept beside it"
        } else {
            line += "\(which) put back \(fromTheList.joined(separator: ", ")), and put back "
            line += "\(fromKept.joined(separator: ", ")) from what was kept beside it"
        }
        line += ", but the list could not keep a copy of all it needs for this change, "
        line += "so what it could not keep stays beside the page, and the next Undo or Redo of this change uses it."
        for kept in keptOriginals {
            let named: String = UndoTrail.nameOnTheLine(UndoTrail.pageOfKept(kept), among: pagesThatCouldBeMistaken, course: course)
            let hidden: String = (kept as NSString).lastPathComponent
            line += " What \(named) held a moment before is kept beside it as the hidden file “\(hidden)”."
        }
        for kept in keptOfWhatItHoldsNow {
            let named: String = UndoTrail.nameOnTheLine(UndoTrail.pageOfKept(kept), among: pagesThatCouldBeMistaken, course: course)
            let hidden: String = (kept as NSString).lastPathComponent
            line += " What \(named) holds now is kept beside it as the hidden file “\(hidden)”."
        }
        return line
    }

    /// The page a kept file stands beside, by its place in the working
    /// folder: the kept file's folder plus the page's name.
    /// `courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig` gives
    /// `courses/ICS3U/Section 1/index.md`; a bare hidden name gives the
    /// page's name alone.
    static func pageOfKept(_ kept: String) -> String {
        let hidden: String = (kept as NSString).lastPathComponent
        let folder: String = (kept as NSString).deletingLastPathComponent
        let pageName: String = UndoSwap.placeOfStagedName(hidden) ?? hidden
        if folder.isEmpty {
            return pageName
        }
        return folder + "/" + pageName
    }

    /// A page as the line names it, quoted: by its file name (“index.md”),
    /// or, when another page in `pages` has the same file name, by its path
    /// inside the course (“Section 1/index.md”), so the two are told apart.
    /// A page not under `courses/<course>/` (at the top of the working
    /// folder, in another course, or with no course given) is then named by
    /// its whole path in the working folder (U4b2-4 review 1, LOW 3). Names
    /// that differ only in capitals are different names.
    static func nameOnTheLine(_ page: String, among pages: [String], course: String) -> String {
        let pageName: String = (page as NSString).lastPathComponent
        var sharesItsName: Bool = false
        for other in pages {
            if other != page && (other as NSString).lastPathComponent == pageName {
                sharesItsName = true
            }
        }
        if !sharesItsName {
            return "“" + pageName + "”"
        }
        let coursePrefix: String = "courses/" + course + "/"
        if !course.isEmpty && page.hasPrefix(coursePrefix) {
            return "“" + String(page.dropFirst(coursePrefix.count)) + "”"
        }
        return "“" + page + "”"
    }

    /// `ICS3U/1 · Undo was refused: a change that stopped part way could not
    /// be put back yet, because courses/ICS3U/Section 1/Classes/A.md is in
    /// use by another program. The list is kept, and the next Undo tries
    /// again.`
    static func leftNewestLine(course: String, section: Int?, isUndo: Bool, refusal: UndoRefusal) -> String {
        let which: String = isUndo ? "Undo" : "Redo"
        var why: String
        switch refusal {
        case .fileIsInUse(let path):
            why = "\(path) is in use by another program"
        case .cannotTellNow(let path):
            why = "\(path) could not be read just now"
        case .couldNotWrite(let path):
            why = "nothing could be written beside \(path) (the disk may be full)"
        case .changedSince(let path, _):
            why = "\(path) changed while it was being put back"
        case .contentMissing(let path):
            why = "what it needs for \(path) is no longer in the list"
        case .notReadable:
            why = "it holds something this version cannot read"
        }
        return UndoTrail.prefix(course: course, section: section)
            + "\(which) was refused: a change that stopped part way could not be put back yet, because \(why). "
            + "The list is kept, and the next \(which) tries again."
    }

    /// `ICS3U/1 · `, `ICS3U · `, or nothing when there is no course.
    static func prefix(course: String, section: Int?) -> String {
        if course.isEmpty {
            return ""
        }
        var line: String = course
        if let section {
            line += "/\(section)"
        }
        return line + " · "
    }

    /// "a change", "an undo" or "a redo": the work that stopped.
    static func what(_ phase: UndoPhase) -> String {
        switch phase {
        case .begin:
            return "a change"
        case .undoing:
            return "an undo"
        case .redoing:
            return "a redo"
        }
    }

    /// `ICS3U/1 · the undo list could not record publishPages: the list was
    /// busy. The change went ahead (the list is not in use yet).`, or, by
    /// what became of the change (written only once that is known, the U3
    /// sweep, finding 2), "Nothing was changed.", "The change stopped part
    /// way; what a file held before is kept beside it." or "The change was
    /// made; its record is finished at the next chance."
    static func couldNotRecordLine(action: String, course: String, section: Int?, change: UndoUnrecordedChange, why: String) -> String {
        var line: String = ""
        if !course.isEmpty {
            line = course
            if let section {
                line += "/\(section)"
            }
            line += " · "
        }
        line += "the undo list could not record \(action): \(why). "
        switch change {
        case .wentAhead:
            line += "The change went ahead (the list is not in use yet)."
        case .nothingWasChanged:
            line += "Nothing was changed."
        case .stoppedPartWay:
            line += "The change stopped part way; what a file held before is kept beside it."
        case .madeButNotClosed:
            line += "The change was made; its record is finished at the next chance."
        }
        return line
    }

    /// `ICS3U/1 · the undo list put back 2 files left part way by a change
    /// that stopped, found 1 changed by hand since, and cleared the list`.
    static func interruptedLine(course: String, section: Int?, phase: UndoPhase, putBack: Int, inTheWay: Int) -> String {
        let counted: String = inTheWay == 1 ? "1 file" : "\(inTheWay) files"
        return rolledBackLine(course: course, section: section, phase: phase, files: putBack)
            + ", found \(counted) changed by hand since, and cleared the list"
    }

    /// `ICS3U/1 · the undo list puts the folder courses/ICS3U/made back in
    /// its place; it changed while a change that stopped had set it aside
    /// (1 file added)`, or `… keeps the folder courses/ICS3U/made, set
    /// aside by a change that stopped, as courses/ICS3U/made (kept by Undo),
    /// because something else now holds courses/ICS3U/made`. Written just
    /// before the rename, so it says what is being done.
    static func foundAFolderSetAsideLine(course: String, section: Int?, place: String, hiddenName: String, keptAs: String?, changes: String) -> String {
        var line: String = course
        if let section {
            line += "/\(section)"
        }
        if let keptAs {
            return line + " · the undo list keeps the folder \(place), set aside by a change that stopped, as \(keptAs), because something else now holds \(place)"
        }
        return line + " · the undo list puts the folder \(place) back in its place; it changed while a change that stopped had set it aside (\(changes))"
    }

    /// `ICS3U/1 · the undo list keeps the page courses/ICS3U/section1/Unit
    /// 1, Day 3.md, removed or moved away by a change that stopped, as
    /// courses/ICS3U/section1/Unit 1, Day 3 (kept by Undo).md, because
    /// something else now holds courses/ICS3U/section1/Unit 1, Day 3.md`.
    /// Written just before the rename. Never page text.
    static func keptAPageLine(course: String, section: Int?, place: String, keptAs: String) -> String {
        var line: String = course
        if let section {
            line += "/\(section)"
        }
        return line + " · the undo list keeps the page \(place), removed or moved away by a change that stopped, as \(keptAs), because something else now holds \(place)"
    }

    /// `ICS3U/1 · the undo list set aside a change that stopped part way
    /// (3 files), because a restore replaced its files; it is not judged
    /// again`; `… set aside 2 files of a change that stopped part way,
    /// because a restore replaced them; 1 other file of it will be settled
    /// as before`; or, when the list could not be reached, `ICS3U · the
    /// undo list could not be reached when a restore replaced files of the
    /// course, so any change left part way in it is still open`.
    static func setAsideByARestoreLine(course: String, section: Int?, phase: UndoPhase, files: Int, stillJudged: Int, closed: Bool) -> String {
        var line: String = course
        if let section {
            line += "/\(section)"
        }
        if !closed {
            return line + " · the undo list could not be reached when a restore replaced files of the course, so any change left part way in it is still open"
        }
        let counted: String = files == 1 ? "1 file" : "\(files) files"
        if stillJudged > 0 {
            let rest: String = stillJudged == 1 ? "1 other file" : "\(stillJudged) other files"
            return line + " · the undo list set aside \(counted) of \(what(phase)) that stopped part way, because a restore replaced them; \(rest) of it will be settled as before"
        }
        return line + " · the undo list set aside \(what(phase)) that stopped part way (\(counted)), because a restore replaced its files; it is not judged again"
    }

    /// `ICS3U/1 · the undo list put back 2 files left part way by a change
    /// that stopped`.
    static func rolledBackLine(course: String, section: Int?, phase: UndoPhase, files: Int) -> String {
        var line: String = course
        if let section {
            line += "/\(section)"
        }
        let counted: String = files == 1 ? "1 file" : "\(files) files"
        let what: String
        switch phase {
        case .begin:
            what = "a change"
        case .undoing:
            what = "an undo"
        case .redoing:
            what = "a redo"
        }
        return line + " · the undo list put back \(counted) left part way by \(what) that stopped"
    }
}
