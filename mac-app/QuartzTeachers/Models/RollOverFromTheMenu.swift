import Foundation

/// Section ▸ Roll Over to a New Year… (#897 piece B): the one rule that
/// decides what its sheet asks about the website, and what its call sends.
///
/// The built-in assistant asks the website question in words, and its
/// window sends `website: "new"` or `"same"` once the teacher says one of
/// two sentences. The menu asks it in its sheet, with nothing chosen, and
/// sends the answer in the same argument, so the tool code is the same code.
/// The question is asked ONLY where there is a website to keep or leave
/// (the plan review's amendment 12): a section never deployed, or one that
/// deploys only to a folder, has no address students saved, and asking it
/// there led the old plan to answer "had not been deployed anywhere yet" to
/// every teacher who deploys to a folder. In the contract as
/// `shared-rules.json` → `subjectMenus.rollOverSheet`.
nonisolated enum RollOverFromTheMenu {

    // MARK: - Types

    /// What the sheet says about the website.
    enum Website: String, CaseIterable, Sendable {
        /// A marker for the section is on disk (any destination type, the
        /// legacy one included, an unreadable one included): the question,
        /// with nothing chosen.
        case asked
        /// No marker, and the course deploys to a web host: there is no
        /// website yet. No question; the call sends "new".
        case notDeployedYet
        /// No marker, and the course deploys only to a folder: there is no
        /// address to keep or replace. No question; the call sends "same".
        case deploysToAFolder
    }

    /// The teacher's answer to the question, as the call spells it.
    enum Answer: String, CaseIterable, Sendable {
        case keepTheSameWebsite = "same"
        case startANewWebsite = "new"
    }

    /// What the sheet holds while the teacher chooses: the website rule's
    /// answer for this section, the answer chosen (none to begin with: the
    /// question guesses neither, Russell's 2026-09-08 decision), and the
    /// dates line.
    struct Choice: Equatable, Sendable {

        // MARK: - Stored properties

        var website: Website = .asked
        var answer: Answer?
        var datesLine: String = ""
        var datesAreOld: Bool = false

        // MARK: - Computed properties

        /// What the call carries, or nil while it cannot be sent.
        var websiteSent: String? {
            return RollOverFromTheMenu.websiteSent(website, answer: answer)
        }
    }

    // MARK: - Functions

    /// The rule, over its two facts.
    static func website(sectionIsPinned: Bool, hasAHostedDestination: Bool) -> Website {
        if sectionIsPinned {
            return .asked
        }
        if hasAHostedDestination {
            return .notDeployedYet
        }
        return .deploysToAFolder
    }

    /// The rule, read from the disk and the course's settings: the markers
    /// through `DeployCommand.sectionIsPinned` (the URLs `releaseSite`
    /// walks), the destinations through `allDeployDestinations`.
    @MainActor
    static func website(forSection sectionNumber: Int, in course: Course) -> Website {
        var hosted: Bool = false
        for destination in course.configuration.allDeployDestinations where destination.type != "local_folder" {
            hosted = true
        }
        return website(
            sectionIsPinned: DeployCommand.sectionIsPinned(forSection: sectionNumber, in: course),
            hasAHostedDestination: hosted
        )
    }

    /// The sheet's choice as it opens: the website rule, no answer, and the
    /// dates line from the section's class dates on file (empty when there
    /// are none; the sheet asks for them before it opens).
    @MainActor
    static func choice(forSection sectionNumber: Int, in course: Course, today: CalendarDay) -> Choice {
        var choice: Choice = Choice()
        choice.website = website(forSection: sectionNumber, in: course)
        let timetable: SectionTimetable? = try? SectionTimetableStore.read(forSection: sectionNumber, in: course, today: today)
        var dates: [CalendarDay] = timetable?.dates ?? []
        dates.sort()
        if let first = dates.first, let last = dates.last {
            choice.datesLine = AssistWording.menuRollOverDates(
                first: first.text, last: last.text, noun: course.configuration.classNoun
            )
            choice.datesAreOld = datesAreOld(last: last, today: today)
        }
        return choice
    }

    /// What the call's `website` carries, or nil while the sheet cannot be
    /// sent: the question is up and unanswered. Never anything but "new" or
    /// "same", so the window's "say one of two sentences" answer
    /// (`rolloverWebsiteNotDecided`) can never reach a menu sheet.
    static func websiteSent(_ website: Website, answer: Answer?) -> String? {
        switch website {
        case .asked:
            return answer?.rawValue
        case .notDeployedYet:
            return Answer.startANewWebsite.rawValue
        case .deploysToAFolder:
            return Answer.keepTheSameWebsite.rawValue
        }
    }

    /// Whether the dates on file end before today: most likely last year's,
    /// the commonest silent failure (a rollover onto them re-dates nothing
    /// and still sets last year's record aside).
    static func datesAreOld(last: CalendarDay?, today: CalendarDay) -> Bool {
        guard let last else {
            return false
        }
        return last < today
    }

    /// The trail line's counts for a rollover from the menu: which way the
    /// website went, never a page's title.
    static func counts(_ website: Website, answer: Answer?) -> String {
        switch website {
        case .asked:
            if answer == .startANewWebsite {
                return "website: new"
            }
            if answer == .keepTheSameWebsite {
                return "website: kept"
            }
            return "website: not chosen"
        case .notDeployedYet:
            return "website: not deployed yet"
        case .deploysToAFolder:
            return "website: deploys to a folder"
        }
    }
}
