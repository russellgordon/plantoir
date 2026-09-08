import XCTest
@testable import QuartzTeachers

/// The line a teacher's restore leaves behind, and the contract filter that
/// lets either platform propose an event without reddening the other.
///
/// **Why these are together.** They arrived together, as one request from
/// Windows on 2026-09-07 (`MAC-HANDOFF.md`), and separating them would hide
/// what the piece is: the mac adopting `section restored`, and the mac's
/// contract test learning the `appliesOn` key it had never needed while the
/// only platform-scoped event was its own.
final class SectionRestoredTrailTests: XCTestCase {

    // MARK: - What the line says

    /// Named rather than quoted — `AssistSectionRestore.trailLine` is the one
    /// copy of the sentence, so rewording it does not have to be done twice.
    @MainActor
    func testTheLineNamesTheCopyItCameFrom() {
        let line: String = AssistSectionRestore.trailLine(
            backupFileName: "ICS3U_backup_2026-09-07-1200_assistant-section1.zip"
        )
        XCTAssertTrue(
            line.contains("ICS3U_backup_2026-09-07-1200_assistant-section1.zip"),
            "which copy it came from is what makes the line worth having: \(line)"
        )
        XCTAssertTrue(
            line.contains("when this conversation started"),
            "and it has to say WHAT was put back, for somebody reading it months later: \(line)"
        )
    }

    /// The trail carries the course, the section and the file name — and
    /// nothing a teacher wrote. `carries` in the contract says "never a page",
    /// and a file name is the one piece of the backup that is safe to name.
    @MainActor
    func testTheLineSaysNothingAboutWhatIsOnAPage() {
        let line: String = AssistSectionRestore.trailLine(
            backupFileName: "ICS3U_backup_2026-09-07-1200_assistant-section1.zip"
        )
        XCTAssertFalse(line.contains(".md"), "no page is named: \(line)")
        XCTAssertFalse(line.contains("/"), "and no path either, only the file's own name: \(line)")
    }

    // MARK: - It is recorded only once the restore has happened

    /// A restore that refused must leave NO line. A trail saying a section was
    /// put back when it was not is worse than silence: it is the one record
    /// somebody would trust next week, and it would send them looking for a
    /// change that never happened.
    @MainActor
    func testARefusedRestoreWritesNothing() throws {
        let workingFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingFolderURL, withIntermediateDirectories: true)

        let scratchFolderURL: URL = workingFolderURL.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: workingFolderURL)
        }

        // A session nobody has held a conversation in has no backup, so the
        // restore refuses — the same path as a conversation that only READ.
        let session: AssistSession = AssistSession(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: workingFolderURL
        )
        session.restoreSection()

        XCTAssertFalse(
            ActivityTrail.store.activityText(includingPrompts: true).contains(
                ActivityTrail.Event.sectionRestored.rawValue
            ),
            "a refused restore must not claim on the trail that it happened"
        )
        XCTAssertTrue(
            session.restoreNotes.contains { note in return note.isProblem },
            "and the teacher is told, in the conversation, that nothing was put back"
        )
    }

    // MARK: - The platform filter

    /// An entry with no `appliesOn` belongs to both platforms.
    @MainActor
    func testAnEventWithNoPlatformBelongsToBoth() {
        XCTAssertTrue(SharedRulesContractTests.macMustRecord(["event": "task started"]))
    }

    /// The case that exists in the contract today.
    @MainActor
    func testAMacOnlyEventIsRequiredOfTheMac() {
        XCTAssertTrue(SharedRulesContractTests.macMustRecord([
            "event": "built site moved out of the working folder",
            "appliesOn": ["mac"],
        ]))
    }

    /// The case this filter was added for: a windows-only event must NOT hold
    /// the mac suite red. There is none in the contract as this is written —
    /// `section restored` dropped its `appliesOn` when the mac adopted it —
    /// which is exactly why this is pinned here rather than left to the data.
    @MainActor
    func testAWindowsOnlyEventIsNotRequiredOfTheMac() {
        XCTAssertFalse(SharedRulesContractTests.macMustRecord([
            "event": "something only Windows can do",
            "appliesOn": ["windows"],
        ]))
    }

    /// Named on both is required of both — the filter must not read "has an
    /// appliesOn" as "belongs to somebody else".
    @MainActor
    func testAnEventNamingBothPlatformsIsRequired() {
        XCTAssertTrue(SharedRulesContractTests.macMustRecord([
            "event": "named on both",
            "appliesOn": ["mac", "windows"],
        ]))
    }

    /// A malformed `appliesOn` must not quietly excuse the mac from an event.
    /// Silently dropping a requirement is the failure this whole list exists
    /// to prevent, so anything that is not a list of platform names is treated
    /// as "belongs to both" and the equality assertion then says so out loud.
    @MainActor
    func testAnUnreadablePlatformListStillRequiresTheEvent() {
        XCTAssertTrue(SharedRulesContractTests.macMustRecord([
            "event": "badly written",
            "appliesOn": "windows",
        ]))
    }
}
