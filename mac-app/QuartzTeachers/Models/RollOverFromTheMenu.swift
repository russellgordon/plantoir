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
        /// The course deploys to Cloudflare, and a record this section keeps
        /// there (its own, or one set aside by an earlier rollover) already
        /// holds the name a new website started now would get. A Cloudflare
        /// website is named for the course, the section and the CALENDAR
        /// year, and deploying reuses a website of that name, so a "new"
        /// website in September onto a section first deployed in February
        /// would replace February's (the implementation review's W1). The
        /// deploy path's fix is GitHub #915; until then the sheet does not
        /// offer a new website it cannot start. No question; the call sends
        /// "same", and the sheet, the plan and the finished line say why
        /// (`wording.menuRollOverANewWebsiteWouldReuseItsAddress`).
        case aNewWebsiteWouldReuseItsAddress
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

    /// The rule, over its three facts. A website that a new one would
    /// replace comes first: no answer to the question would be true then.
    static func website(
        sectionIsPinned: Bool,
        hasAHostedDestination: Bool,
        aNewWebsiteWouldReuseItsAddress: Bool
    ) -> Website {
        if aNewWebsiteWouldReuseItsAddress {
            return .aNewWebsiteWouldReuseItsAddress
        }
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
    /// walks), the destinations through `allDeployDestinations`, and the
    /// Cloudflare names this section's records hold against `today`'s year.
    @MainActor
    static func website(forSection sectionNumber: Int, in course: Course, today: CalendarDay) -> Website {
        var hosted: Bool = false
        var onCloudflare: Bool = false
        for destination in course.configuration.allDeployDestinations where destination.type != "local_folder" {
            hosted = true
            if destination.type == "cloudflare_pages" {
                onCloudflare = true
            }
        }
        var wouldReuse: Bool = false
        if onCloudflare {
            wouldReuse = aNewWebsiteWouldReuseItsAddress(
                keptNames: cloudflareNamesKept(forSection: sectionNumber, in: course),
                courseCode: course.code,
                section: sectionNumber,
                year: today.year
            )
        }
        return website(
            sectionIsPinned: DeployCommand.sectionIsPinned(forSection: sectionNumber, in: course),
            hasAHostedDestination: hosted,
            aNewWebsiteWouldReuseItsAddress: wouldReuse
        )
    }

    /// Whether the course deploys only to folders, so "the same website as
    /// last year" would be untrue of it whatever markers an old host left.
    @MainActor
    static func deploysOnlyToAFolder(_ course: Course) -> Bool {
        for destination in course.configuration.allDeployDestinations where destination.type != "local_folder" {
            return false
        }
        return true
    }

    /// The name `deploy.py`'s `suggest_pages_name` gives a NEW Cloudflare
    /// website, without the surname it may add: the course, the section and
    /// the calendar year, cleaned as `sanitize_pages_name` cleans it.
    static func cloudflareNameStem(courseCode: String, section: Int, year: Int) -> String {
        let code: String = courseCode.isEmpty ? "course" : courseCode
        return cleanedCloudflareName("\(code)-s\(section)-\(year)")
    }

    /// `sanitize_pages_name`, character for character: lower case, spaces and
    /// underscores to hyphens, anything else outside a to z, 0 to 9 and the
    /// hyphen to a hyphen, runs of hyphens to one, none at either end, at
    /// most 58 characters.
    static func cleanedCloudflareName(_ name: String) -> String {
        var hyphenated: String = ""
        for character in name.lowercased() {
            let isLetter: Bool = character >= "a" && character <= "z"
            let isDigit: Bool = character >= "0" && character <= "9"
            if isLetter || isDigit {
                hyphenated.append(character)
            } else if hyphenated.hasSuffix("-") == false {
                hyphenated.append("-")
            }
        }
        var trimmed: String = hyphenated
        while trimmed.hasPrefix("-") {
            trimmed.removeFirst()
        }
        while trimmed.hasSuffix("-") {
            trimmed.removeLast()
        }
        if trimmed.count > 58 {
            trimmed = String(trimmed.prefix(58))
            while trimmed.hasSuffix("-") {
                trimmed.removeLast()
            }
        }
        if trimmed.isEmpty {
            return "class-site"
        }
        return trimmed
    }

    /// Whether a new Cloudflare website started in `year` would be given a
    /// name one of `keptNames` already holds: the stem itself, or the stem
    /// and a surname. (A surname is the one part of the name the app does not
    /// keep, so any surname counts; a teacher whose surname changed during
    /// the year is told the website is kept when a new one could have been
    /// made, which errs toward the website students already use.)
    static func aNewWebsiteWouldReuseItsAddress(
        keptNames: [String], courseCode: String, section: Int, year: Int
    ) -> Bool {
        let stem: String = cloudflareNameStem(courseCode: courseCode, section: section, year: year)
        for name in keptNames {
            if name == stem || name.hasPrefix(stem + "-") {
                return true
            }
        }
        return false
    }

    /// The `name` in each of this section's Cloudflare records: the one
    /// deploying reads (`.cloudflare_sites/section<N>.json`) and every one a
    /// rollover set aside beside it (`section<N>.previous-<stamp>.json`).
    /// A record that cannot be read gives no name.
    static func cloudflareNamesKept(forSection sectionNumber: Int, in course: Course) -> [String] {
        let folder: URL = course.directoryURL.appendingPathComponent(".cloudflare_sites")
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let current: String = "section\(sectionNumber).json"
        let setAsidePrefix: String = "section\(sectionNumber).previous-"
        var names: [String] = []
        for entry in entries {
            let isCurrent: Bool = entry == current
            let isSetAside: Bool = entry.hasPrefix(setAsidePrefix) && entry.hasSuffix(".json")
            if !isCurrent && !isSetAside {
                continue
            }
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(entry)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["name"] as? String,
                  !name.isEmpty else {
                continue
            }
            names.append(name)
        }
        return names
    }

    /// The sheet's choice as it opens: the website rule, no answer, and the
    /// dates line from the section's class dates on file (empty when there
    /// are none; the sheet asks for them before it opens).
    @MainActor
    static func choice(forSection sectionNumber: Int, in course: Course, today: CalendarDay) -> Choice {
        var choice: Choice = Choice()
        choice.website = website(forSection: sectionNumber, in: course, today: today)
        let timetable: SectionTimetable? = try? SectionTimetableStore.read(forSection: sectionNumber, in: course, today: today)
        var dates: [CalendarDay] = timetable?.dates ?? []
        dates.sort()
        if let first = dates.first, let last = dates.last {
            // Written as the re-date's plan writes a day, so the sheet and the
            // card that follows it read alike: "2026-09-08 (Tuesday)".
            choice.datesLine = AssistWording.menuRollOverDates(
                first: "\(first.text) (\(first.weekdayName))",
                last: "\(last.text) (\(last.weekdayName))",
                noun: course.configuration.classNoun
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
        case .deploysToAFolder, .aNewWebsiteWouldReuseItsAddress:
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
    /// website went, never a page's title. Read from what the call SENT,
    /// which the sheet never leaves unanswered, so every count it can write
    /// is one `activityTrail.mustRecord` lists.
    static func counts(_ website: Website, sent: String) -> String {
        switch website {
        case .asked:
            if sent == Answer.startANewWebsite.rawValue {
                return "website: new"
            }
            return "website: kept"
        case .notDeployedYet:
            return "website: not deployed yet"
        case .deploysToAFolder:
            return "website: deploys to a folder"
        case .aNewWebsiteWouldReuseItsAddress:
            return "website: kept, a new one would have the same address"
        }
    }
}
