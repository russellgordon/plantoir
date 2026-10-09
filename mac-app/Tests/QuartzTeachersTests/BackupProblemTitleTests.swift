import XCTest
@testable import QuartzTeachers

/// A backup, restore or deletion problem names the act that failed in its
/// alert's title (#457, the HIG sweep), never "Could not do that".
@MainActor
final class BackupProblemTitleTests: XCTestCase {

    // MARK: - Tests

    func testEachActIsNamed() {
        XCTAssertEqual(BackupProblemTitle.backingUp("ICS3U"), "Could not back up ICS3U")
        XCTAssertEqual(BackupProblemTitle.restoring("ICS3U"), "Could not restore ICS3U")
        XCTAssertEqual(BackupProblemTitle.deletingBackups(count: 1), "Could not delete the backup")
        XCTAssertEqual(BackupProblemTitle.deletingBackups(count: 3), "Could not delete the backups")
        XCTAssertEqual(BackupProblemTitle.deletingArchive, "Could not delete the archive")
    }

    /// Every place the model reports a problem names the act on the line
    /// before, and the sidebar's alert shows that title.
    func testEveryProblemIsTitledWhereItIsSet() throws {
        let model: String = try String(
            contentsOf: UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers/Models/WorkspaceModel.swift"),
            encoding: .utf8
        )
        let lines: [String] = TextFieldStyleScanTests.codeWithoutComments(model).components(separatedBy: "\n")
        var set: Int = 0
        var problems: [String] = []
        for index in lines.indices {
            let line: String = lines[index].trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix("backupProblem = ") || line == "backupProblem = nil" {
                continue
            }
            set += 1
            let previous: String = index > 0 ? lines[index - 1].trimmingCharacters(in: .whitespaces) : ""
            if !previous.hasPrefix("backupProblemTitle = ") {
                problems.append("WorkspaceModel.swift:" + String(index + 1))
            }
        }
        XCTAssertGreaterThanOrEqual(set, 8, "the scan found only \(set) places")
        XCTAssertEqual(problems, [], "each backup problem names its act")
        let sidebar: String = try String(
            contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("SidebarView.swift"), encoding: .utf8
        )
        XCTAssertTrue(sidebar.contains(".alert(workspace.backupProblemTitle, isPresented: backupProblemBinding)"))
        XCTAssertFalse(sidebar.contains("\"Could not do that\""))
    }
}
