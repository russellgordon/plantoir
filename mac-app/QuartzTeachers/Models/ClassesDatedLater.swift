import Foundation

/// Class pages students can see that are dated after the NEXT class day
/// (#475): a lesson put up early by mistake, caught before it goes out.
///
/// Russell, 2026-10-07: "Catch class pages … that are published with a date in
/// the future. Flag for decision at publish time … Offer to unpublish these
/// class pages using a checklist in a dialog."
///
/// **The rule lives in the contract**, `class-planning.json` →
/// `futureDatedClasses`, with its cases; this is the mac's reading of it, and
/// `FutureDatedClassesTests` runs the cases through the real readers on real
/// files. In short:
///
/// - **A class page** is a page in the section's class folders
///   (`ClassFolder`, folder MEMBERSHIP — so a club's "Week 5" counts and a
///   "Unit 2, Day 3" outside them does not), never a folder's `index.md`.
/// - **The next class day** is the earliest date strictly after today among
///   the section's class pages, published or not. Tomorrow's class is the one
///   a teacher publishes the evening before on purpose — "publish tomorrow's
///   class", then Deploy, is the commonest thing anybody does in Plantoir — so
///   it is never asked about. Counting hidden pages too means a lesson for the
///   14th published by mistake is still caught when the 9th is hidden.
/// - **Flagged:** a class page students can see (as the built site reads it,
///   and a flag the app cannot read counts as visible — the mild mistake)
///   dated after that day. Nothing after today: nothing flagged.
/// - **Kept:** a page the teacher already said to leave published, at the
///   date it had then, is not asked about again. Re-dated since, it is.
///
/// The date is the day as WRITTEN in `created` (`sectionIndexPointer.
/// dateCases.why`), never converted to this Mac's zone: the class on
/// `2026-10-09T00:30+1300` is the 9th's class wherever the Mac is.
///
/// `nonisolated` for the pure half: `ScheduledDeploy.runScheduled` asks it
/// off the main actor (the reading half is `@MainActor`, as the graph is).
nonisolated enum ClassesDatedLater {

    // MARK: - Types

    /// One class page, as the rule sees it.
    struct Page: Equatable, Sendable {

        // MARK: - Stored properties

        /// Where it is in the course folder, without `.md` — the links
        /// checklist's own `place` (`file-formats.json` → `linksChecklistOffer.
        /// rowKeys.place`): a name, never anything written on the page.
        let place: String

        /// Its file name without `.md`: what the teacher sees in Obsidian.
        let title: String

        /// Whether students meet it on the built site.
        let isVisible: Bool

        /// The day its `created` names, as written; nil when it has none.
        let date: CalendarDay?
    }

    /// A class the teacher is asked about.
    struct Flagged: Equatable, Hashable, Identifiable, Sendable {

        // MARK: - Stored properties

        let place: String
        let title: String
        let date: CalendarDay

        // MARK: - Computed properties

        var id: String {
            return place
        }
    }

    /// One page the teacher said to leave published, with the date it had
    /// when they said so.
    struct Kept: Equatable, Sendable {

        // MARK: - Stored properties

        let place: String

        /// `yyyy-MM-dd`.
        let date: String
    }

    /// `file-formats.json` → `laterClassesKept`: what the teacher left
    /// published when asked, per section.
    ///
    /// Remembered so a teacher who posts a week ahead on purpose is not asked
    /// at every Deploy — and so an assistant working from another app, which
    /// is refused while a later class is waiting on an answer, can deploy
    /// once it has been given. Asked again only when the page's date changes:
    /// a class moved to another day is a different question.
    struct KeptRecord: Equatable, Sendable {

        // MARK: - Stored properties

        /// UTC, `yyyy-MM-ddTHH:mm:ssZ`.
        var answeredAt: String

        var kept: [Kept]

        // MARK: - Functions

        static func fileURL(courseDirectory: URL, section: Int) -> URL {
            return courseDirectory
                .appendingPathComponent(".publish_state")
                .appendingPathComponent("section\(section).later-classes-kept.json")
        }

        /// The record on disk, or nil when there is none or it cannot be read
        /// — which costs the question once more, nothing else.
        static func read(courseDirectory: URL, section: Int) -> KeptRecord? {
            let url: URL = fileURL(courseDirectory: courseDirectory, section: section)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = object["kept"] as? [[String: Any]] else {
                return nil
            }
            var kept: [Kept] = []
            for row in rows {
                if let place = row["place"] as? String, let date = row["date"] as? String {
                    kept.append(Kept(place: place, date: date))
                }
            }
            let answeredAt: String = (object["answeredAt"] as? String) ?? ""
            return KeptRecord(answeredAt: answeredAt, kept: kept)
        }

        /// Written with a rename, so a reader never meets half a file. Last
        /// writer wins between two windows; the worst outcome is being asked
        /// once more.
        func write(courseDirectory: URL, section: Int) throws {
            let url: URL = KeptRecord.fileURL(courseDirectory: courseDirectory, section: section)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            var rows: [[String: Any]] = []
            for entry in kept {
                rows.append(["place": entry.place, "date": entry.date])
            }
            let object: [String: Any] = [
                "version": 1,
                "answeredAt": answeredAt,
                "kept": rows
            ]
            let data: Data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        }

        /// Adds `pages` to what is already kept — replacing a page's older
        /// date, so the record never holds one page twice — and stamps the
        /// answer with `moment`.
        static func adding(_ pages: [Flagged], to existing: KeptRecord?, at moment: Date = Date()) -> KeptRecord {
            var kept: [Kept] = []
            for entry in existing?.kept ?? [] {
                var replaced: Bool = false
                for page in pages where page.place == entry.place {
                    replaced = true
                }
                if !replaced {
                    kept.append(entry)
                }
            }
            for page in pages {
                kept.append(Kept(place: page.place, date: page.date.text))
            }
            return KeptRecord(answeredAt: KeptRecord.stamp(moment), kept: kept)
        }

        /// UTC, `yyyy-MM-ddTHH:mm:ssZ`, in the Gregorian calendar whatever
        /// this Mac's own calendar is.
        static func stamp(_ moment: Date) -> String {
            let formatter: DateFormatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            return formatter.string(from: moment)
        }
    }

    // MARK: - Functions

    /// The next class day after `today`: the earliest date strictly after it
    /// among `classPages`, published or not. Nil when no class is dated after
    /// today.
    static func nextClassDay(after today: CalendarDay, among classPages: [Page]) -> CalendarDay? {
        var earliest: CalendarDay? = nil
        for page in classPages {
            guard let date = page.date, date > today else {
                continue
            }
            if let soFar = earliest, soFar <= date {
                continue
            }
            earliest = date
        }
        return earliest
    }

    /// The rule (`futureDatedClasses.rule`): the class pages students can see
    /// dated after the next class day, less any the teacher kept at that
    /// date — by date, then title.
    ///
    /// `classPages` are the section's class pages and nothing else; which
    /// pages those are is `ClassFolder`'s question, asked by the caller.
    static func flagged(classPages: [Page], today: CalendarDay, kept: [Kept]) -> [Flagged] {
        var found: [Flagged] = []
        guard let nextDay = nextClassDay(after: today, among: classPages) else {
            return found
        }
        for page in classPages {
            guard page.isVisible, let date = page.date, date > nextDay else {
                continue
            }
            var keptAtThisDate: Bool = false
            for entry in kept where entry.place == page.place && entry.date == date.text {
                keptAtThisDate = true
            }
            if keptAtThisDate {
                continue
            }
            found.append(Flagged(place: page.place, title: page.title, date: date))
        }
        found.sort { first, second in
            if first.date != second.date {
                return first.date < second.date
            }
            return first.title.lowercased() < second.title.lowercased()
        }
        return found
    }

    /// Where a page is in the course folder, without `.md`.
    static func place(of fileURL: URL, courseDirectory: URL) -> String {
        let full: String = fileURL.standardizedFileURL.path
        let root: String = courseDirectory.standardizedFileURL.path + "/"
        var within: String = fileURL.lastPathComponent
        if full.hasPrefix(root) {
            within = String(full.dropFirst(root.count))
        }
        if within.lowercased().hasSuffix(".md") {
            within = String(within.dropLast(3))
        }
        return within
    }

    /// The section's class pages, read from disk the way the rule needs them.
    @MainActor
    static func classPages(forSection sectionNumber: Int, in course: Course) -> [Page] {
        var pages: [Page] = []
        for page in AssistSectionGraph.classPages(forSection: sectionNumber, in: course) {
            pages.append(Page(
                place: place(of: page.fileURL, courseDirectory: course.directoryURL),
                title: page.title,
                isVisible: page.isVisibleToStudents,
                date: page.date
            ))
        }
        return pages
    }

    /// What would be asked about for one section today, read from disk: the
    /// class pages and the kept record. Empty for a course kept for
    /// reference, which is never deployed.
    @MainActor
    static func flagged(forSection sectionNumber: Int, in course: Course, today: CalendarDay) -> [Flagged] {
        if course.isKeptForReference {
            return []
        }
        let kept: KeptRecord? = KeptRecord.read(courseDirectory: course.directoryURL, section: sectionNumber)
        return flagged(
            classPages: classPages(forSection: sectionNumber, in: course),
            today: today,
            kept: kept?.kept ?? []
        )
    }

    /// The same question asked about a set of HIDDEN pages a teacher is about
    /// to publish (Section ▸ Publish Pages…): which of `picked` would be
    /// flagged once they are visible. The next class day is the section's own,
    /// counted over every class page as it is.
    @MainActor
    static func flagged(
        ifPublishing picked: [URL], forSection sectionNumber: Int, in course: Course, today: CalendarDay
    ) -> [Flagged] {
        if course.isKeptForReference {
            return []
        }
        var pickedPlaces: Set<String> = []
        for url in picked {
            pickedPlaces.insert(place(of: url, courseDirectory: course.directoryURL))
        }
        var pages: [Page] = []
        for page in classPages(forSection: sectionNumber, in: course) {
            let willBeVisible: Bool = page.isVisible || pickedPlaces.contains(page.place)
            pages.append(Page(place: page.place, title: page.title, isVisible: willBeVisible, date: page.date))
        }
        let kept: KeptRecord? = KeptRecord.read(courseDirectory: course.directoryURL, section: sectionNumber)
        var found: [Flagged] = []
        let everyFlagged: [Flagged] = flagged(classPages: pages, today: today, kept: kept?.kept ?? [])
        for page in everyFlagged where pickedPlaces.contains(page.place) {
            found.append(page)
        }
        return found
    }

    /// Remembers `pages` as kept for `sectionNumber`. A record that cannot
    /// be written costs the question once more at the next Deploy.
    @MainActor
    static func keep(_ pages: [Flagged], forSection sectionNumber: Int, in course: Course) {
        if pages.isEmpty {
            return
        }
        let existing: KeptRecord? = KeptRecord.read(courseDirectory: course.directoryURL, section: sectionNumber)
        let record: KeptRecord = KeptRecord.adding(pages, to: existing)
        try? record.write(courseDirectory: course.directoryURL, section: sectionNumber)
    }

    /// The trail's words for pages that went out unasked — a scheduled
    /// deploy, which has nobody to ask: places, at most ten, the rest
    /// counted (`LinksChecklistPublisher.publishedLine`'s shape). Places are
    /// names, never anything written on a page.
    static func placesLine(_ pages: [Flagged]) -> String {
        var named: [String] = []
        for page in pages {
            if named.count == 10 {
                break
            }
            named.append(page.place)
        }
        var line: String = named.joined(separator: "; ")
        if pages.count > named.count {
            line += "; and \(pages.count - named.count) more"
        }
        return line
    }
}
