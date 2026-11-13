import Foundation

/// Sharing a course's unit plans (#709): the rules the Planning tab's share
/// bar follows, with no network and no view.
///
/// The share itself is `deploy.sh <CODE> --plans …`, which runs the shared
/// `scripts/share_plan.py` (contracts/shared-rules.json → unitPlanning.share).
/// Nothing here decides what the Python decides: the bar READS what a share
/// left behind, one marker per school year
/// (`courses/<CODE>/.cloudflare_sites/plans-<year>.json`), and says it.
///
/// Every rule below is a case list in the contract, run by `PlanSharingTests`:
/// `modeCases` (is a share protected), `warningCases` (is the public-address
/// warning shown), and app-rules.json → `deployArguments.planShareCases`
/// (what the launcher is handed).
nonisolated enum PlanSharing {

    // MARK: - Stored properties

    /// The folder beside the course's settings that holds the markers.
    static let markerFolderName: String = ".cloudflare_sites"

    /// The section number a share's work lease is recorded under. A share is
    /// not a section's, and no section is numbered 0, so a section's own
    /// deploy is never refused by it and the course still reads as busy
    /// (Quit asks, Rename and Back Up wait), as review M7 asked.
    static let leaseSection: Int = 0

    /// The marker lines `share_plan.py` prints (unitPlanning.share.markers).
    static let sharedPrefix: String = "PLANTOIR_PLAN_SHARED:"
    static let refusedPrefix: String = "PLANTOIR_PLAN_REFUSED:"
    static let stoppedPrefix: String = "PLANTOIR_PLAN_STOPPED:"

    /// What the teacher chose on the share bar.
    enum Choice: String, CaseIterable {
        case shareOpen
        case shareProtected
        case shareAgain
        case removePassword
        case changePassword
        case addPassword
        case stop
    }

    /// What the share bar shows for a school year (unitPlanning.share
    /// .barCases). Never more than the site does (review H1).
    enum BarStatus: String {
        case notShared
        /// The last share did not finish: the plans may be open.
        case unfinished
        /// A Stop Sharing that was not confirmed: the address may still work.
        case stopping
        case protected
        case open
    }

    /// One school year's marker, as `share_plan.py` wrote it.
    struct Marker: Equatable {

        // MARK: - Stored properties

        /// The year the school year began in.
        var year: Int
        var address: String
        /// sending, shared or stopping; empty in a marker written before
        /// the state was kept, which reads as shared.
        var state: String
        /// What the teacher last asked for: "protected" or "open".
        var asked: String
        /// What the share proved. A protected share the address did not
        /// prove is not shown as protected.
        var isProtected: Bool
        var failClosed: Bool
        var answerKeysIncluded: Bool
        var answerKeysLeftOut: Int
        var lastShared: Date?
        var units: Int
        var oldCopies: Int

        // MARK: - Computed properties

        /// The school year as a teacher writes it: 2026-27.
        var yearLabel: String {
            return PlanSharing.yearLabel(year)
        }

        /// Whether the marker last asked for a password.
        var askedForProtection: Bool {
            return asked == "protected" || isProtected
        }
    }

    // MARK: - Functions

    /// The school year a day belongs to: the year it began, rolling over on
    /// 1 August (unitPlanning.share.schoolYear, `SchoolYear`).
    static func schoolYear(on day: CalendarDay) -> Int {
        return SchoolYear.startingYear(on: day)
    }

    static func yearLabel(_ year: Int) -> String {
        let next: Int = (year + 1) % 100
        let twoDigits: String = next < 10 ? "0\(next)" : "\(next)"
        return "\(year)-\(twoDigits)"
    }

    /// The marker file for one school year.
    static func markerURL(courseDirectory: URL, year: Int) -> URL {
        return courseDirectory
            .appendingPathComponent(markerFolderName, isDirectory: true)
            .appendingPathComponent("plans-\(year).json")
    }

    /// The year in a marker's file name, or nil for any other file: exactly
    /// `plans-<four digits>.json`, so a marker a reference copy moved aside
    /// (`plans-2025.previous-….json`) is not a year still shared.
    static func year(inMarkerName name: String) -> Int? {
        guard name.hasPrefix("plans-"), name.hasSuffix(".json") else {
            return nil
        }
        let middle: String = String(name.dropFirst(6).dropLast(5))
        guard middle.count == 4 else {
            return nil
        }
        for character in middle {
            if !character.isASCII || !character.isNumber {
                return nil
            }
        }
        return Int(middle)
    }

    /// Every school year this course shares, newest first.
    static func markers(courseDirectory: URL) -> [Marker] {
        let folder: URL = courseDirectory.appendingPathComponent(markerFolderName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        var found: [Marker] = []
        for name in names {
            guard let year = year(inMarkerName: name) else {
                continue
            }
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
                continue
            }
            if let marker = marker(from: data, year: year) {
                found.append(marker)
            }
        }
        found.sort { (first: Marker, second: Marker) -> Bool in
            return first.year > second.year
        }
        return found
    }

    /// One marker's contents, or nil when it is not a whole one (a share
    /// that stopped half way writes only its name).
    static func marker(from data: Data, year: Int) -> Marker? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let address = object["address"] as? String, !address.isEmpty else {
            return nil
        }
        var lastShared: Date?
        if let text = object["lastShared"] as? String {
            lastShared = ISO8601DateFormatter().date(from: text)
        }
        return Marker(
            year: year,
            address: address,
            state: object["state"] as? String ?? "",
            asked: object["asked"] as? String ?? ((object["protected"] as? Bool ?? false) ? "protected" : "open"),
            isProtected: object["protected"] as? Bool ?? false,
            failClosed: object["failClosed"] as? Bool ?? false,
            answerKeysIncluded: (object["answerKeys"] as? String) == "in",
            answerKeysLeftOut: object["answerKeysLeftOut"] as? Int ?? 0,
            lastShared: lastShared,
            units: object["units"] as? Int ?? 0,
            oldCopies: object["oldCopies"] as? Int ?? 0
        )
    }

    /// unitPlanning.share.barCases: what the bar shows for a school year's
    /// marker, nil when there is none.
    static func barStatus(for marker: Marker?) -> BarStatus {
        guard let marker = marker else {
            return .notShared
        }
        if marker.state == "sending" {
            return .unfinished
        }
        if marker.state == "stopping" {
            return .stopping
        }
        return marker.isProtected ? .protected : .open
    }

    /// Whether the bar says an older copy may still answer at its own
    /// address (review M2), until a later share deletes it.
    static func showsOldCopies(_ marker: Marker?) -> Bool {
        guard let marker = marker else {
            return false
        }
        return marker.oldCopies > 0
    }

    /// unitPlanning.share.modeCases: whether a share is protected, from what
    /// the year's marker last asked for (nil when there is none) and the flag.
    static func isProtected(markerAskedForProtection: Bool?, flag: String?) -> Bool {
        if flag == "--protect" {
            return true
        }
        if flag == "--remove-password" {
            return false
        }
        return markerAskedForProtection ?? false
    }

    /// unitPlanning.share.warningCases: whether the public-address warning
    /// comes before this choice. At the first share without a password, and
    /// when a password is removed; never when protected.
    static func warns(markerAskedForProtection: Bool?, choice: Choice) -> Bool {
        switch choice {
        case .removePassword:
            return true
        case .shareOpen:
            return markerAskedForProtection == nil
        default:
            return false
        }
    }

    /// The launcher's arguments for a choice (app-rules.json →
    /// deployArguments.planShareCases). Never a username or a password: the
    /// launcher asks for those in the console, and the Keychain keeps them.
    static func arguments(
        courseCode: String,
        choice: Choice,
        includeAnswerKeys: Bool,
        year: Int?,
        cloudflareAccountID: String
    ) -> [String] {
        var arguments: [String] = [courseCode, "--plans"]
        switch choice {
        case .shareOpen, .shareAgain:
            break
        case .shareProtected, .addPassword:
            arguments.append("--protect")
        case .changePassword:
            arguments.append("--protect")
            arguments.append("--change-password")
        case .removePassword:
            arguments.append("--remove-password")
        case .stop:
            arguments.append("--stop-sharing")
        }
        if includeAnswerKeys && (choice == .shareOpen || choice == .shareAgain || choice == .removePassword) {
            arguments.append("--include-answer-keys")
        }
        if let year = year {
            arguments.append("--year")
            arguments.append(String(year))
        }
        let identifier: String = cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identifier.isEmpty {
            arguments.append("--account")
            arguments.append(identifier)
        }
        return arguments
    }

    /// The sentence under a protected address about a flood of requests, or
    /// nil for an open share (unitPlanning.share.failClosed).
    static func floodSentence(for marker: Marker) -> String? {
        if !marker.isProtected {
            return nil
        }
        if marker.failClosed {
            return PlanSharingWording.floodClosed
        }
        return PlanSharingWording.floodOpen
    }

    /// The public-address warning, with the answer-key clause only when the
    /// teacher ticked Include Answer Keys.
    static func crawlerWarning(includingAnswerKeys: Bool) -> String {
        let clause: String = includingAnswerKeys ? PlanSharingWording.answerKeysClause : ""
        return PlanSharingWording.crawlerWarning.replacingOccurrences(of: "{answerKeysClause}", with: clause)
    }

    /// The Stop Sharing alert's message for one year's address.
    static func stopMessage(address: String) -> String {
        return PlanSharingWording.stopMessage.replacingOccurrences(of: "{address}", with: address)
    }

    /// The moment as both apps spell it in a kept file's name, as
    /// `DeployCommand` writes a section's (yyyy-MM-dd_HHmmss, local time).
    static func keptStamp(_ moment: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: moment)
    }

    /// Moves every school year's marker aside when a reference copy of the
    /// course is made (review M6), as `DeployCommand.releaseSite` does for a
    /// section's: renamed, never deleted, so the copy can never reach this
    /// year's plan site and the address is still on disk. Returns how many
    /// could not be moved.
    @discardableResult
    static func releasePlanMarkers(courseDirectory: URL, at moment: Date = Date()) -> Int {
        let folder: URL = courseDirectory.appendingPathComponent(markerFolderName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return 0
        }
        var notMoved: Int = 0
        for name in names {
            guard let year = year(inMarkerName: name) else {
                continue
            }
            let kept: URL = folder.appendingPathComponent("plans-\(year).previous-" + keptStamp(moment) + ".json")
            do {
                try FileManager.default.moveItem(at: folder.appendingPathComponent(name), to: kept)
            } catch {
                notMoved += 1
            }
        }
        return notMoved
    }
}

/// The two lists an open share prints before it asks (unitPlanning.share
/// .openShareLists): every file it will share and every file it leaves out,
/// read ONLY from the launcher's marker lines, never from the console's own.
nonisolated struct PlanShareLists: Equatable {

    // MARK: - Stored properties

    static let beginMarker: String = "PLANTOIR_PLAN_LISTS_BEGIN:"
    static let sharedMarker: String = "PLANTOIR_PLAN_LISTS_SHARED:"
    static let leftOutMarker: String = "PLANTOIR_PLAN_LISTS_LEFT_OUT:"
    static let endMarker: String = "PLANTOIR_PLAN_LISTS_END:"

    /// The question the lists come before, without its [y/N] (the console's
    /// question reader takes that off).
    static let question: String = "Share these files with anyone who has the address?"

    var shared: [String] = []
    var leftOut: [String] = []
    /// True once the end marker arrived.
    var isComplete: Bool = false

    // MARK: - Functions

    /// Reads marker lines in order into `lists`, starting afresh at a begin
    /// marker. Lines that are not one of the four are passed over.
    static func read(_ lines: [String], into lists: inout PlanShareLists?) {
        for line in lines {
            let trimmed: String = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == beginMarker {
                lists = PlanShareLists()
            } else if trimmed == endMarker {
                lists?.isComplete = true
            } else if trimmed.hasPrefix(sharedMarker + " ") {
                lists?.shared.append(String(trimmed.dropFirst(sharedMarker.count + 1)))
            } else if trimmed.hasPrefix(leftOutMarker + " ") {
                lists?.leftOut.append(String(trimmed.dropFirst(leftOutMarker.count + 1)))
            }
        }
    }

    /// Whether a question the console asks is the open share's question,
    /// which is answered only in the lists' own sheet (fix review H1).
    static func isTheListsQuestion(_ question: String) -> Bool {
        return question.trimmingCharacters(in: .whitespaces).hasPrefix(PlanShareLists.question)
    }
}

/// The share bar's words (contracts/shared-rules.json → unitPlanning.share
/// .words). Named by key in every test; `PlanSharingTests` compares each with
/// the contract, so a sentence is changed in both places or the suite fails.
nonisolated enum PlanSharingWording {

    // MARK: - Stored properties

    static let sharedThroughCloudflare: String = "Unit plans are shared as a small website of their own on Cloudflare Pages, one for each school year."
    static let netlifyTeacher: String = "Your class websites go to Netlify, but unit plans are shared through Cloudflare Pages, because Netlify's free plan cannot ask for a password. The first time, you will be asked for a Cloudflare token."
    static let protect: String = "Protect with a Username and Password"
    static let includeAnswerKeys: String = "Include Answer Keys"
    static let share: String = "Share Unit Plans"
    static let shareAgain: String = "Share Again"
    static let changePassword: String = "Change Password…"
    static let addPassword: String = "Add a Password…"
    static let removePassword: String = "Remove Password…"
    static let stopSharing: String = "Stop Sharing"
    static let copyLink: String = "Copy Link"
    static let withPassword: String = "Shared with a username and password."
    static let openToAnyone: String = "Open to anyone with the address."
    static let lastShared: String = "Last shared {when}."
    static let answerKeysLeftOut: String = "{n} answer key(s) left out. Protect the plans with a password, or tick Include Answer Keys, to share them."
    static let crawlerWarningTitle: String = "Share without a password?"
    static let crawlerWarning: String = "Anyone with the address can open these plans{answerKeysClause}. Plantoir asks search engines and AI crawlers not to read or keep them, but they can ignore that, so treat anything here as possibly searchable. To require a password, choose Protect with a Username and Password."
    static let answerKeysClause: String = ", including the answer keys you chose to include"
    static let shareAnyway: String = "Share Without a Password"
    static let floodClosed: String = "If someone floods this address with requests, Cloudflare closes the plans until midnight UTC rather than opening them."
    static let floodOpen: String = "Cloudflare did not accept the setting that keeps the plans closed if this address is flooded with requests. If that happened, anyone with the address could open the plans until midnight UTC. The address ends in random letters, so it is hard to guess."
    static let stopTitle: String = "Stop sharing the {year} unit plans?"
    static let stopMessage: String = "The address {address} stops working within a minute, and anyone you gave it to can no longer open the plans. Your plans stay on this Mac."
    static let stopFailed: String = "Plantoir could not stop sharing these plans, so the address still works. Try Stop Sharing again in a few minutes."
    static let notSharedHere: String = "This page is not shared at this address."
    static let earlierYear: String = "{year}: {address}"
    static let lastShareUnfinished: String = "The last share of these plans did not finish, so they may be open to anyone with the address. Share Again to finish it, or Stop Sharing."
    static let stopUnconfirmed: String = "Plantoir asked Cloudflare to stop sharing these plans, but the address still answers, so they may still be open. Try Stop Sharing again in a few minutes."
    /// unitPlanning.share.refusals.oldCopyStillThere, shown on the bar while
    /// the marker's oldCopies is above 0 (review M2).
    static let oldCopyStillThere: String = "These plans are shared as you asked, but an earlier copy could not be removed and may still open at its own address. Share Again to try once more."
    static let listsSheetTitle: String = "Share these files?"
    static let consoleSheetTitle: String = "Sharing unit plans"
    static let listsSharedHeading: String = "These files will be shared with anyone who has the address:"
    static let listsLeftOutHeading: String = "These files are left out:"
    static let listsNone: String = "(none)"
    static let listsByName: String = "Both lists are by file name only. Plantoir has not read the files, so an answer written inside a page or a PDF is shared with it."
    static let listsShareButton: String = "Share"
    static let courseBusy: String = "Another program is working on this course right now, so the plans were not shared. Share them again once it has finished."
    static let changePasswordNote: String = "A new password applies to this school year's plans once they are shared again; an earlier year keeps the password it was shared with."

    // MARK: - Computed properties

    /// Every word, by its contract key, for the test that compares them.
    static var byKey: [String: String] {
        return [
            "sharedThroughCloudflare": sharedThroughCloudflare,
            "netlifyTeacher": netlifyTeacher,
            "protect": protect,
            "includeAnswerKeys": includeAnswerKeys,
            "share": share,
            "shareAgain": shareAgain,
            "changePassword": changePassword,
            "addPassword": addPassword,
            "removePassword": removePassword,
            "stopSharing": stopSharing,
            "copyLink": copyLink,
            "withPassword": withPassword,
            "openToAnyone": openToAnyone,
            "lastShared": lastShared,
            "answerKeysLeftOut": answerKeysLeftOut,
            "crawlerWarningTitle": crawlerWarningTitle,
            "crawlerWarning": crawlerWarning,
            "answerKeysClause": answerKeysClause,
            "shareAnyway": shareAnyway,
            "floodClosed": floodClosed,
            "floodOpen": floodOpen,
            "stopTitle": stopTitle,
            "stopMessage": stopMessage,
            "stopFailed": stopFailed,
            "notSharedHere": notSharedHere,
            "earlierYear": earlierYear,
            "changePasswordNote": changePasswordNote,
            "courseBusy": courseBusy,
            "consoleSheetTitle": consoleSheetTitle,
            "lastShareUnfinished": lastShareUnfinished,
            "stopUnconfirmed": stopUnconfirmed,
        ]
    }
}
