import Foundation

/// "Close Obsidian to open {course}?" (#995, D21): asked before Plantoir
/// closes Obsidian to add a course it has never seen to Obsidian's list.
///
/// Obsidian keeps that list in memory while it runs and writes it back
/// whole when it quits, so a course can be added only while Obsidian is
/// closed. Until #995 a running Obsidian was simply quit, with every course
/// open in it, and nobody was asked (Russell's ruling Q13 on #975: never
/// without asking, and the button that goes ahead says Obsidian will be
/// closed). The words and the rule are `contracts/shared-rules.json` →
/// `obsidianNeverClosedUnasked`.
struct ObsidianClosingRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let folder: URL
    var page: URL? = nil

    // MARK: - Computed properties

    var id: String {
        return course.code + "|" + folder.path
    }
}

/// The words of the question, and the go-ahead button the add-ons offer
/// shows when its yes closes Obsidian.
nonisolated enum ObsidianClosingWording {

    // MARK: - Stored properties

    static let title: String = "Close Obsidian to open {course}?"
    static let message: String = "Obsidian has not opened {course} before. It can add a course to its list only while it is closed, so Plantoir closes Obsidian, adds {course}, and opens it again."
    static let closesLabel: String = "Closes"
    static let closesValue: String = "Obsidian, with every course open in it"
    static let opensAgainLabel: String = "Opens again"
    static let opensAgainValue: String = "{course}, and everything else Obsidian had open"
    static let keptLabel: String = "Kept"
    static let keptValue: String = "Everything you have written"

    /// The question's two buttons.
    static let closeAndOpen: String = "Close Obsidian and Open"
    static let cancel: String = "Cancel"

    /// The add-ons offer's yes, in place of "Add Them", whenever that yes
    /// closes Obsidian: the course is open in it, or Plantoir cannot tell.
    static let offerAddClosingObsidian: String = "Close Obsidian and Add Them"

    // MARK: - Functions

    static func titleText(course: String) -> String {
        return filling(title, course: course)
    }

    /// The sentence, then the three facts a line each, as the add-ons
    /// offer gives them (#834's shape: one sentence and labelled facts).
    static func messageText(course: String) -> String {
        var lines: [String] = [filling(message, course: course), ""]
        lines.append(closesLabel + ": " + filling(closesValue, course: course))
        lines.append(opensAgainLabel + ": " + filling(opensAgainValue, course: course))
        lines.append(keptLabel + ": " + filling(keptValue, course: course))
        return lines.joined(separator: "\n")
    }

    static func filling(_ sentence: String, course: String) -> String {
        return sentence.replacingOccurrences(of: "{course}", with: course)
    }
}

/// What each answer to the question leaves on the trail (#995):
/// `contracts/shared-rules.json` → `obsidianNeverClosedUnasked.trail`.
nonisolated enum ObsidianClosingTrail {

    // MARK: - Types

    enum Outcome: String, CaseIterable, Sendable {
        case opened
        case cancelled
        case notNeeded
        case didNotClose
        case notAdded
    }

    // MARK: - Functions

    static func line(_ outcome: Outcome, course: String) -> String {
        switch outcome {
        case .opened:
            return course + " · closed Obsidian to add the course to its list, and opened it"
        case .cancelled:
            return course + " · chose Cancel: Obsidian was not closed and the course did not open"
        case .notNeeded:
            return course + " · opened in Obsidian without closing it: by the answer, Obsidian had quit or knew the course"
        case .didNotClose:
            return course + " · Obsidian did not close, so the course was not added to its list and did not open"
        case .notAdded:
            return course + " · Obsidian closed, but the course could not be added to its list, so it did not open"
        }
    }
}

/// When Open in Obsidian has to ask before it goes on (#995).
enum ObsidianClosingRule {

    // MARK: - Functions

    /// Whether handing Obsidian this file means closing it first: Obsidian
    /// is running and no vault in its list holds the file. Closed, Obsidian
    /// reads its list fresh when the link starts it, so nothing is asked.
    /// A list that cannot be read holds nothing, so it asks: the safe
    /// direction, since the other way closes Obsidian unasked.
    static func mustAsk(targetPath: String, obsidianRunning: Bool, registryData: Data?) -> Bool {
        if !obsidianRunning {
            return false
        }
        return !FolderActions.folderIsInRegisteredVault(targetPath, registryData: registryData)
    }
}
