import XCTest
@testable import QuartzTeachers

/// U4a of #899: the three Course Settings actions recorded from the real
/// code into `undo-action-steps.json`, after the daily page actions.
extension UndoActionStepsTests {

    // MARK: - Functions

    /// `saveCourseSettings` (several members, `graded_folders` absent
    /// before: the first Marks tick), `addFolder` (one `createTree`, its
    /// pages' moment fixed) and `setSchoolYear` (one `editJSON`).
    func recordTheCourseSettingsActions() async throws -> [Recorded] {
        var recorded: [Recorded] = []

        let saveRoot: URL = try UndoActionStepsTests.settingsRoot()
        let saved: Course = try CourseSettingsGestureScript.makeCourse(in: saveRoot)
        recorded.append(try await record("saveCourseSettings", root: saveRoot) {
            saved.configuration.gradedFolders = ["Tests"]
            saved.configuration.hiddenItems = ["Media"]
            CourseSettingsView(course: saved).save()
        })

        let folderRoot: URL = try UndoActionStepsTests.settingsRoot()
        let added: Course = try CourseSettingsGestureScript.makeCourse(in: folderRoot)
        recorded.append(try await record("addFolder", root: folderRoot) {
            let outcome: FolderScaffold.Outcome = CourseSettingsView(course: added).createFoldersOnDisk(
                named: "Labs", scope: .shared, created: "2026-09-08T07:00:00.000-0400"
            )
            XCTAssertEqual(outcome.foldersCreated, 1)
        })

        let yearRoot: URL = try UndoActionStepsTests.settingsRoot()
        let filed: Course = try CourseSettingsGestureScript.makeCourse(in: yearRoot)
        recorded.append(try await record("setSchoolYear", root: yearRoot) {
            let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-11-20"))
            XCTAssertNil(SetSchoolYearSheet.write(2025, to: filed, on: day))
        })

        return recorded
    }

    /// An empty working folder of its own, removed when the test ends.
    static func settingsRoot() throws -> URL {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-action-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        TemporaryFolders.removeWhenThisTestEnds(root)
        return root
    }
}
