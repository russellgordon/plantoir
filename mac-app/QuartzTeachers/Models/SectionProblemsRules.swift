import Foundation

/// What a row of a section's Problems record says, whether the section's
/// sidebar row is marked, and when the alert is raised — as pure functions
/// (#717). Each is `contracts/shared-rules.json` → `sectionProblems`
/// (`rowState`, `sectionMarker`, `alert`), whose cases
/// `SectionProblemsTests` runs here and Windows owes.
nonisolated enum SectionProblemsRules {

    /// What a row is showing.
    enum RowState: String, Equatable, Sendable {

        /// Found by this section's last build.
        case current

        /// Shown gone by a later build of ANOTHER section that shares the
        /// page — still this section's problem until its own next build,
        /// because its deployed site still carries the page (ruling 11).
        case fixedInTheSource
    }

    // MARK: - Stored properties

    /// `sectionProblems.rowState.clearsAcrossSections`: the kinds that
    /// depend on the page alone. Retyped and pinned by `SectionProblemsTests`.
    static let clearsAcrossSections: Set<String> = [
        "pageSettingsUnreadable",
        "printPdfNotFound",
        "figuresCouldNotBeDrawn",
        "swiftCouldNotBePrepared",
        "quizzesNotReady",
        "runnableCodeShownAsPlainCode",
        "quizzesReadDifferently",
        "geogebraSketchesNotReady",
    ]

    /// `sectionProblems.rowState.notAboutThePage`: reasons that say something
    /// about the machine, not the page.
    static let notAboutThePage: [String: Set<String>] = [
        "figuresCouldNotBeDrawn": ["tookTooLong", "engineMissing", "graphEngineMissing", "drawingEnded"],
        "swiftCouldNotBePrepared": ["notCompiled", "notDownloaded", "noRoom"],
        "geogebraSketchesNotReady": ["materialCouldNotBeFetched", "engineMissing"],
    ]

    /// The kinds only the site says (`sectionProblems.kinds` → `from: site`).
    static let saidByTheSite: Set<String> = [
        "runnableCodeShownAsPlainCode",
        "quizzesReadDifferently",
    ]

    // MARK: - Functions

    /// A row of `record`, given the records of the course's OTHER sections
    /// (`sectionProblems.rowState.rule`).
    static func state(
        of row: SectionProblemRow,
        in record: SectionProblemsRecord,
        others: [SectionProblemsRecord]
    ) -> RowState {
        if !clearsAcrossSections.contains(row.kind) {
            return .current
        }
        if let machineReasons = notAboutThePage[row.kind], machineReasons.contains(row.reason) {
            return .current
        }
        if row.page.isEmpty {
            return .current
        }
        guard let builtHere = record.builtAt else {
            return .current
        }
        // The LATEST other record that shows the page decides, never any
        // clean one (implementation review L1): a section clean at ten
        // proves nothing once another has broken the page again at eleven.
        guard let latest = latestShowing(row.page, among: others) else {
            return .current
        }
        if fixesThePage(latest, of: row, builtAfter: builtHere) {
            return .fixedInTheSource
        }
        return .current
    }

    /// Of `others`, the latest record whose pages include `page`.
    static func latestShowing(_ page: String, among others: [SectionProblemsRecord]) -> SectionProblemsRecord? {
        var latest: SectionProblemsRecord?
        for other in others {
            guard let builtThere = other.builtAt, other.pagesShown.contains(page) else {
                continue
            }
            if let current = latest, let currentTime = current.builtAt, currentTime >= builtThere {
                continue
            }
            latest = other
        }
        return latest
    }

    /// Whether that record shows `row`'s page with no problem of its kind,
    /// and is later than this one.
    static func fixesThePage(
        _ other: SectionProblemsRecord,
        of row: SectionProblemRow,
        builtAfter builtHere: Date
    ) -> Bool {
        guard let builtThere = other.builtAt, builtThere > builtHere else {
            return false
        }
        if !other.pagesShown.contains(row.page) {
            return false
        }
        if saidByTheSite.contains(row.kind) && !other.siteSaidComplete {
            return false
        }
        for otherRow in other.rows {
            if otherRow.kind == row.kind && otherRow.page == row.page {
                return false
            }
        }
        return true
    }

    /// `sectionProblems.sectionMarker`: THIS section's own record has a row,
    /// in either state.
    static func markerShows(_ record: SectionProblemsRecord?) -> Bool {
        guard let record else {
            return false
        }
        return !record.rows.isEmpty
    }

    /// `sectionProblems.alert`: the record found something new, and its
    /// alert has not been answered.
    static func alertIsDue(_ record: SectionProblemsRecord, answered: Set<String>) -> Bool {
        if !record.hasNewProblems {
            return false
        }
        return !answered.contains(record.alertKey)
    }

    /// The trail's line for a record whose set changed (`activityTrail.
    /// mustRecord` → "problems changed"): counts and kinds, never a page.
    static func trailLine(for record: SectionProblemsRecord) -> String {
        let occasion: String = record.occasion == "deploy" ? "deploy" : "preview"
        return "the \(occasion) found \(record.newIDs.count) new and \(record.goneIDs.count) fewer problems "
            + "(new: \(kindsNamed(in: record.newIDs)); gone: \(kindsNamed(in: record.goneIDs)))"
    }

    /// The answer's line, beside it.
    static func answerLine(_ answer: String) -> String {
        return "answered the alert about new problems: \(answer)"
    }

    /// Each kind among `ids` once, in the order first met; "none" for none.
    static func kindsNamed(in ids: [String]) -> String {
        var kinds: [String] = []
        for id in ids {
            let kind: String = SectionProblemsRecord.kind(ofID: id)
            if !kinds.contains(kind) {
                kinds.append(kind)
            }
        }
        if kinds.isEmpty {
            return "none"
        }
        return kinds.joined(separator: ", ")
    }
}
