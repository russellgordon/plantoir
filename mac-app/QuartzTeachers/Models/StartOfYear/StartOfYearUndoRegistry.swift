import Foundation
import Observation

/// The undo the app holds for "Get Ready for the Start of the Year" (#96),
/// one per section, shared by every window on the working folder.
///
/// **Process-wide and in memory, so quitting ends it** — said in the sheet
/// (`StartOfYearWording.undoEndsWhenYouQuit`) and in doc 10. The backup made
/// before the change is the durable way back; this is the quick one.
///
/// **It ends early, on purpose** (the plan review's M1). A Mac app stays open
/// for weeks, and an undo three weeks later would put every untouched future
/// page back to visible ahead of a deploy nobody connected with it. So it
/// ends at the section's next deploy — started from any window of this app
/// (`deployStarted`), or the scheduled deploy that was set when the change was
/// made reaching its moment — and at the next visibility write in the section
/// from ANYWHERE, including an outside assistant or Obsidian, found by
/// comparing every page's visibility with how the change left it
/// (`stillOffered`). What this cannot see, stated: a deploy run by an outside
/// assistant in another process. The skip rule still holds then, and the
/// undo is always a sheet that lists what it would put back, never one click.
///
/// Three undo stores exist and none reaches another: this one, the assistant
/// window's `AssistChangeHistory` ("undo that"), and the one inside an outside
/// assistant's `--mcp-stdio` process (`undo_last_change`).
@Observable
@MainActor
final class StartOfYearUndoRegistry {

    // MARK: - Types

    /// One held undo.
    struct Entry {

        // MARK: - Stored properties

        let change: AssistChange
        let backupFileName: String

        /// Every page's visibility in the section as the change left it.
        let visibilityAfter: String

        /// The scheduled deploy that was set when the change was made.
        let scheduledDeploy: Date?
    }

    /// Why an undo is no longer offered.
    enum Ended: Equatable {
        case deployed
        case visibilityChanged
    }

    // MARK: - Stored properties

    static let shared: StartOfYearUndoRegistry = StartOfYearUndoRegistry()

    private var entries: [SectionWindowControllers.Key: Entry] = [:]

    // MARK: - Functions

    func record(_ entry: Entry, folderPath: String, courseCode: String, sectionNumber: Int) {
        entries[SectionWindowControllers.Key(
            folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
        )] = entry
    }

    /// The held undo for this section, if one is held and its scheduled
    /// deploy has not come round. Cheap: safe to ask while a menu draws.
    func entry(folderPath: String, courseCode: String, sectionNumber: Int, now: Date = Date()) -> Entry? {
        let key: SectionWindowControllers.Key = SectionWindowControllers.Key(
            folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
        )
        guard let entry = entries[key] else {
            return nil
        }
        if let moment = entry.scheduledDeploy, moment <= now {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry
    }

    func forget(folderPath: String, courseCode: String, sectionNumber: Int) {
        entries.removeValue(forKey: SectionWindowControllers.Key(
            folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
        ))
    }

    /// A deploy of this section started from this app: the undo ends.
    func deployStarted(folderPath: String, courseCode: String, sectionNumber: Int) {
        forget(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
    }

    /// Whether the held undo still stands once the section's pages have been
    /// read — nil when it does, or why it ended. Reads every page, so it is
    /// asked when the undo sheet opens, never while a menu draws.
    func whyItEnded(
        _ entry: Entry,
        forSection sectionNumber: Int,
        in course: Course,
        workspaceURL: URL?
    ) -> Ended? {
        let now: String = StartOfYearUndoRegistry.visibilitySnapshot(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        if now != entry.visibilityAfter {
            return .visibilityChanged
        }
        return nil
    }

    /// Every page's path and whether students see it, one line each, sorted.
    static func visibilitySnapshot(forSection sectionNumber: Int, in course: Course, workspaceURL: URL?) -> String {
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        var lines: [String] = []
        for page in graph.pages {
            lines.append(page.relativePath + "|" + (page.isVisibleToStudents ? "visible" : "hidden"))
        }
        lines.sort()
        return lines.joined(separator: "\n")
    }

    /// Starts from nothing — for tests.
    func forgetAll() {
        entries.removeAll()
    }
}
