import Foundation

/// At Preview, the offer to show today's class on the section's front page
/// (#397).
///
/// Russell: "A convenience feature – I often forget to update that transclude
/// each day." A section's front page (`section<N>/index.md`) shows one class,
/// and when a class is published in Obsidian nothing moves that line: the
/// assistant's publishes do (`SectionIndexPointer`), a hand edit of
/// `publish:` does not. So when the teacher presses Preview and today's class
/// is published but the front page still shows an older one, the section
/// window ASKS — it never moves the line on its own.
///
/// **The rule lives in the contract**, `class-planning.json` →
/// `todaysClassOnTheFrontPage`, with its cases; this is the mac's reading of
/// it. It reuses the pointer three ways rather than keeping copies: the line
/// is the one `SectionIndexPointer.classLine` finds, two classes on one day
/// are split by `SectionIndexPointer.comesLater`, and Yes writes through
/// `SectionIndexPointer.repointing`.
///
/// **Only the Preview BUTTON asks** (`SectionDetailView.pressPreview`). Every
/// other way into a preview — the assistant, Start of the Year, Course
/// Settings, a repair's rebuild — goes through `startPreview()`, which never
/// asks: a question nobody may be watching must not hold up a preview.
enum TodaysClassOnTheFrontPage {

    // MARK: - Types

    /// The question, as it will be put to the teacher.
    struct Offer: Equatable, Identifiable {

        // MARK: - Stored properties

        /// Today's class — a file name, which is what the line will name.
        let classTitle: String

        /// The class the front page shows now, by its file name.
        let shownTitle: String

        let courseCode: String
        let sectionNumber: Int

        /// The day the question is about. Yes and Not Today are decided for
        /// THIS day, never for whatever day it is when the answer comes — an
        /// answer given after midnight is about the question that was asked.
        let day: CalendarDay

        /// "class", or "meeting" for a club.
        let noun: ClassNoun

        // MARK: - Computed properties

        var id: String {
            return "\(courseCode)/\(sectionNumber)/\(day.text)/\(classTitle)"
        }
    }

    /// What the rule decided, before it is dressed as an `Offer`.
    struct Decision: Equatable {

        // MARK: - Stored properties

        let todaysClass: String
        let shown: String
    }

    /// What pressing Show on Front Page came to.
    enum Outcome: Equatable {
        /// The line now names today's class.
        case shown(from: String, to: String)
        /// The page already shows today's class — the teacher changed it
        /// while the question was up. Nothing was written.
        case alreadyRight
        /// Something else changed while the question was up — another class,
        /// no class, the page itself, or the section became busy — so the
        /// answer no longer fits the question. Nothing was written.
        case noLongerOffered
        /// The write failed. Nothing was changed.
        case couldNotSave
    }

    /// Not Today, remembered (`file-formats.json` → `frontPageNotToday`): for
    /// one section, one calendar day and one class. A record for another day
    /// or another class does not stop the question, so it never needs
    /// clearing — a class published later the same day is a new question.
    struct NotToday: Equatable {

        // MARK: - Stored properties

        /// `yyyy-MM-dd`, the teacher's calendar day.
        let day: String

        /// The class offered, by file name.
        let classTitle: String

        // MARK: - Functions

        static func fileURL(courseDirectory: URL, section: Int) -> URL {
            return courseDirectory
                .appendingPathComponent(".publish_state")
                .appendingPathComponent("section\(section).front-page-not-today.json")
        }

        static func read(courseDirectory: URL, section: Int) -> NotToday? {
            guard let data = try? Data(contentsOf: fileURL(courseDirectory: courseDirectory, section: section)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let day = object["day"] as? String,
                  let classTitle = object["class"] as? String else {
                return nil
            }
            return NotToday(day: day, classTitle: classTitle)
        }

        /// Written with a rename, so a reader never meets half a file. Last
        /// writer wins between two windows; the worst outcome is being asked
        /// once more.
        func write(courseDirectory: URL, section: Int) throws {
            let url: URL = NotToday.fileURL(courseDirectory: courseDirectory, section: section)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let object: [String: Any] = [
                "version": 1,
                "day": day,
                "class": classTitle
            ]
            let data: Data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        }

        /// Whether this record answers the question about `classTitle` today.
        func stops(classTitle offered: String, on today: CalendarDay) -> Bool {
            return day == today.text && classTitle == offered
        }
    }

    // MARK: - Functions

    /// The rule (`todaysClassOnTheFrontPage.rule`), on what has been read. Nil
    /// means no question.
    ///
    /// `classPages` are the section's class pages; `frontPageText` is the
    /// whole front page.
    static func decide(
        classPages: [AssistSectionPage],
        frontPageText: String,
        today: CalendarDay,
        naming: ClassPageNaming,
        notToday: NotToday?
    ) -> Decision? {
        // (1) Today's class: certainly visible, dated today as written. Two
        // on one day are split by the pointer's own tie-break.
        var todays: AssistSectionPage?
        var todaysNumbers: UnitDay?
        for page in classPages {
            if !page.isVisibleToStudents || !page.visibilityIsCertain {
                continue
            }
            guard let day = page.date, day == today else {
                continue
            }
            let numbers: UnitDay? = UnitDay(pageTitle: page.title, naming: naming)
            if todays != nil && !SectionIndexPointer.comesLater(numbers, than: todaysNumbers) {
                continue
            }
            todays = page
            todaysNumbers = numbers
        }
        guard let todaysClass = todays else {
            return nil
        }

        // (4) Not Today, for this class, today.
        if let notToday, notToday.stops(classTitle: todaysClass.title, on: today) {
            return nil
        }

        // (2) The line: found exactly as the pointer finds it.
        var classTitles: Set<String> = []
        var pagesByTitle: [String: AssistSectionPage] = [:]
        for page in classPages {
            classTitles.insert(page.lowercasedTitle)
            pagesByTitle[page.lowercasedTitle] = page
        }
        guard let line = SectionIndexPointer.classLine(in: frontPageText, classTitles: classTitles),
              let shown = pagesByTitle[line.name.lowercased()] else {
            return nil
        }

        // (3) Already right: a class students can see, dated today or later.
        if shown.isVisibleToStudents && shown.visibilityIsCertain, let shownDay = shown.date, shownDay >= today {
            return nil
        }
        return Decision(todaysClass: todaysClass.title, shown: shown.title)
    }

    /// Whether a front page can be written at all: an ordinary file — not a
    /// symbolic link or a Finder alias, which the build never writes through
    /// either (#276) — and not locked.
    static func frontPageCanBeWritten(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey, .isRegularFileKey]) else {
            return false
        }
        if values.isSymbolicLink == true || values.isAliasFile == true || values.isRegularFile != true {
            return false
        }
        return !ReferenceLock.isLocked(url)
    }

    /// The question for one section of `course`, read from disk, or nil.
    ///
    /// Reads the class pages only (`AssistSectionGraph.classPages`), never
    /// the whole section: this runs on every press of Preview.
    static func offer(forSection sectionNumber: Int, in course: Course, today: CalendarDay) -> Offer? {
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: sectionNumber, in: course)
        if !frontPageCanBeWritten(indexURL) {
            return nil
        }
        guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return nil
        }
        guard let decision = decide(
            classPages: AssistSectionGraph.classPages(forSection: sectionNumber, in: course),
            frontPageText: text,
            today: today,
            naming: course.configuration.classPageNaming,
            notToday: NotToday.read(courseDirectory: course.directoryURL, section: sectionNumber)
        ) else {
            return nil
        }
        return Offer(
            classTitle: decision.todaysClass,
            shownTitle: decision.shown,
            courseCode: course.code,
            sectionNumber: sectionNumber,
            day: today,
            noun: course.configuration.classNoun
        )
    }

    /// Show on Front Page: read the page AGAIN, decide again for the day the
    /// question was asked, and write only the class that was asked about.
    ///
    /// The teacher may have edited the page in Obsidian, published another
    /// class, or hidden this one while the question was up; the answer was to
    /// the question on screen, and writing a different class than the one
    /// named would be a change nobody agreed to.
    static func show(_ offer: Offer, in course: Course) -> Outcome {
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: offer.sectionNumber, in: course)
        if !frontPageCanBeWritten(indexURL) {
            return .noLongerOffered
        }
        guard let before = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return .noLongerOffered
        }
        let classPages: [AssistSectionPage] = AssistSectionGraph.classPages(
            forSection: offer.sectionNumber, in: course
        )
        // Not Today is not consulted: the teacher has just said Yes.
        guard let decision = decide(
            classPages: classPages, frontPageText: before, today: offer.day,
            naming: course.configuration.classPageNaming, notToday: nil
        ) else {
            if showsTodaysClass(before, classPages: classPages, today: offer.day) {
                return .alreadyRight
            }
            return .noLongerOffered
        }
        if decision.todaysClass != offer.classTitle {
            return .noLongerOffered
        }
        var classTitles: Set<String> = []
        var todaysClass: AssistSectionPage?
        for page in classPages {
            classTitles.insert(page.lowercasedTitle)
            if page.title == offer.classTitle {
                todaysClass = page
            }
        }
        guard let page = todaysClass else {
            return .noLongerOffered
        }
        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: offer.sectionNumber, in: course),
            forSection: offer.sectionNumber
        )
        guard let result = SectionIndexPointer.repointing(
            before, at: page, classTitles: classTitles, createdTail: tail
        ) else {
            return .noLongerOffered
        }
        guard (try? result.text.write(to: indexURL, atomically: true, encoding: .utf8)) != nil else {
            return .couldNotSave
        }
        // Read back: the page on disk must now name the class.
        guard let after = try? String(contentsOf: indexURL, encoding: .utf8),
              let line = SectionIndexPointer.classLine(in: after, classTitles: classTitles),
              line.name == page.title else {
            return .couldNotSave
        }
        return .shown(from: decision.shown, to: page.title)
    }

    /// Whether the page's class line names a class dated `today` that
    /// students can see — the "already right" answer to a question that has
    /// gone away.
    static func showsTodaysClass(_ text: String, classPages: [AssistSectionPage], today: CalendarDay) -> Bool {
        var classTitles: Set<String> = []
        for page in classPages {
            classTitles.insert(page.lowercasedTitle)
        }
        guard let line = SectionIndexPointer.classLine(in: text, classTitles: classTitles) else {
            return false
        }
        for page in classPages where page.lowercasedTitle == line.name.lowercased() {
            if page.isVisibleToStudents && page.visibilityIsCertain, let day = page.date, day >= today {
                return true
            }
        }
        return false
    }

    /// The trail's words for an outcome, or for Not Today
    /// (`shared-rules.json` → `activityTrail.mustRecord`). File names only —
    /// never anything written on a page.
    static func trailLine(for outcome: Outcome, offer: Offer) -> (event: ActivityTrail.Event, what: String) {
        switch outcome {
        case .shown(let from, let to):
            return (.putTodaysClassOnTheFrontPage, "put today's class on the front page — \(to) in place of \(from)")
        case .alreadyRight:
            return (.frontPageLeftAsItWas, leftAsItWasLine(reason: "already showed today's class", offer: offer))
        case .noLongerOffered:
            return (.frontPageLeftAsItWas, leftAsItWasLine(reason: "it changed while the teacher was asked", offer: offer))
        case .couldNotSave:
            return (.frontPageLeftAsItWas, leftAsItWasLine(reason: "could not be saved", offer: offer))
        }
    }

    static func notTodayTrailLine(offer: Offer) -> String {
        return leftAsItWasLine(reason: "Not Today", offer: offer)
    }

    private static func leftAsItWasLine(reason: String, offer: Offer) -> String {
        return "left the front page as it was — \(reason): \(offer.classTitle) offered, it showed \(offer.shownTitle)"
    }
}
