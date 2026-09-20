import XCTest
@testable import QuartzTeachers

/// The quiet clean-up that ends a stopped preview's container-side
/// processes instead of orphaning them.
final class PreviewStopperTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAStopRunsTheLauncherAndCleansUpAfterItself() async throws {
        let fileManager: FileManager = FileManager.default
        let folder: URL = fileManager.temporaryDirectory
            .appendingPathComponent("preview-stopper-\(UUID().uuidString)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: folder)
        }
        // A stand-in launcher that simply succeeds.
        let script: URL = folder.appendingPathComponent("preview.sh")
        try Data("exit 0\n".utf8).write(to: script)

        PreviewStopper.stopSectionProcesses(courseCode: "ICS3U", sectionNumber: 1, workspaceURL: folder)
        XCTAssertEqual(PreviewStopper.running.count, 1, "The stop process is held while it runs")

        // The termination handler prunes the list when the process ends.
        var waitsLeft: Int = 100
        while !PreviewStopper.running.isEmpty && waitsLeft > 0 {
            try await Task.sleep(for: .milliseconds(50))
            waitsLeft -= 1
        }
        XCTAssertTrue(PreviewStopper.running.isEmpty, "A finished stop process is let go")
    }

    @MainActor
    func testAMissingLauncherIsAQuietNoOp() {
        let before: Int = PreviewStopper.running.count
        PreviewStopper.stopSectionProcesses(
            courseCode: "ICS3U",
            sectionNumber: 1,
            workspaceURL: URL(fileURLWithPath: "/no/such/folder/anywhere")
        )
        XCTAssertEqual(PreviewStopper.running.count, before,
                       "Without the launcher there is nothing to run")
    }

    // MARK: - What reaches the trail

    /// The launcher says how many processes it ended, and that number used to
    /// go to the null device.
    ///
    /// It is the only thing that separates "there was nothing left to stop"
    /// from "a build was still running and was ended" — the two competing
    /// explanations when a teacher reports that their publish stopped
    /// halfway. It began mattering when the sweep started ending a mid-flight
    /// BUILD and its driver rather than only a preview server.
    func testTheCountIsReadOutOfWhatTheLauncherPrinted() {
        XCTAssertEqual(PreviewStopper.countReclaimed(in: "✅ Stopped 4 process(es).\n"), 4)
        XCTAssertEqual(PreviewStopper.countReclaimed(in: "✅ Stopped 0 process(es).\n"), 0)
        XCTAssertEqual(
            PreviewStopper.countReclaimed(
                in: "🧹 Stopping preview processes for ADA1O section 1…\n"
                    + "✅ Stopped 12 process(es).\n"),
            12,
            "the count must be found on its own line, not on the first line printed"
        )
    }

    /// The two silences are different facts and must stay different.
    ///
    /// "Nothing to stop — no container is running for this folder" means the
    /// sweep never ran; "Stopped 0" means it ran and found nothing. A line
    /// claiming zero for the first would be a line that is not true.
    func testNothingIsRecordedWhenTheLauncherDidNotSweep() {
        XCTAssertNil(PreviewStopper.countReclaimed(
            in: "✅ Nothing to stop — no container is running for this folder.\n"))
        XCTAssertNil(PreviewStopper.countReclaimed(in: ""))
        XCTAssertNil(PreviewStopper.countReclaimed(
            in: "⚠️ Cannot stop preview processes: the build recipe is incomplete.\n"))
    }

    @MainActor
    func testTheReclaimedCountReachesTheTrailInATeachersWords() {
        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stopper-trail-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }

        PreviewStopper.noteWhatWasReclaimed(
            "✅ Stopped 3 process(es).\n", courseCode: "ICS3U", sectionNumber: 2
        )
        PreviewStopper.noteWhatWasReclaimed(
            "✅ Stopped 1 process(es).\n", courseCode: "ICS3U", sectionNumber: 2
        )
        PreviewStopper.noteWhatWasReclaimed(
            "✅ Nothing to stop — no container is running for this folder.\n",
            courseCode: "ICS3U", sectionNumber: 2
        )

        let trailText: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trailText.contains("ICS3U/2 · reclaimed 3 leftover website-builder processes"),
            "the trail does not name the course, the section and the count: \(trailText)"
        )
        XCTAssertTrue(
            trailText.contains("ICS3U/2 · reclaimed 1 leftover website-builder process"),
            "one process is not \"1 processes\": \(trailText)"
        )
        var written: Int = 0
        for line in trailText.components(separatedBy: "\n")
        where line.contains("reclaimed") {
            written += 1
        }
        XCTAssertEqual(written, 2, "a sweep that never ran must leave no line at all")
        XCTAssertFalse(
            trailText.contains("process(es)"),
            "the launcher's own wording reached the trail; it says what happened in a "
                + "teacher's words, not a script's"
        )
    }
}
