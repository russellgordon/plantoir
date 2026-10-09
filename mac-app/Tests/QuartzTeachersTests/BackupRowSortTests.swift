import XCTest
@testable import QuartzTeachers

/// All Backups sorts by column (#457, the HIG sweep): newest first until a
/// header is clicked, then by Course, Made or Size, either way.
@MainActor
final class BackupRowSortTests: XCTestCase {

    // MARK: - Tests

    func testTheTableOpensNewestFirstAndSortsBySizeAndCourse() {
        let older: BackupItem = BackupRowSortTests.item("ICS3U", secondsAgo: 7200, name: "a")
        let newer: BackupItem = BackupRowSortTests.item("ADA1O", secondsAgo: 60, name: "b")
        let middle: BackupItem = BackupRowSortTests.item("MPM2D", secondsAgo: 3600, name: "c")
        let items: [BackupItem] = [older, newer, middle]
        let sizes: [String: Int64] = [older.id: 900, newer.id: 10]

        let newestFirst: [BackupRow] = BackupRow.rows(of: items, sizes: sizes, sortedBy: BackupRow.newestFirst)
        XCTAssertEqual(BackupRowSortTests.codes(newestFirst), ["ADA1O", "MPM2D", "ICS3U"])

        let bySizeLargestFirst: [BackupRow] = BackupRow.rows(
            of: items, sizes: sizes, sortedBy: [KeyPathComparator(\BackupRow.bytesForSorting, order: .reverse)]
        )
        XCTAssertEqual(BackupRowSortTests.codes(bySizeLargestFirst), ["ICS3U", "ADA1O", "MPM2D"], "an unmeasured backup sorts below the smallest")

        let byCourse: [BackupRow] = BackupRow.rows(of: items, sizes: sizes, sortedBy: [KeyPathComparator(\BackupRow.courseCode)])
        XCTAssertEqual(BackupRowSortTests.codes(byCourse), ["ADA1O", "ICS3U", "MPM2D"])

        let unsorted: [BackupRow] = BackupRow.rows(of: items, sizes: sizes, sortedBy: [])
        XCTAssertEqual(BackupRowSortTests.codes(unsorted), ["ICS3U", "ADA1O", "MPM2D"], "no sort order keeps the list's own order")
        XCTAssertEqual(newestFirst[0].id, newer.id, "a row is selected by its backup's own identifier")
    }

    // MARK: - Helpers

    static func item(_ code: String, secondsAgo: TimeInterval, name: String) -> BackupItem {
        return BackupItem(
            courseCode: code,
            backedUpAt: Date(timeIntervalSinceNow: -secondsAgo),
            fileURL: URL(fileURLWithPath: "/tmp/backups/\(name).zip"),
            maker: .teacher
        )
    }

    static func codes(_ rows: [BackupRow]) -> [String] {
        var result: [String] = []
        for row in rows {
            result.append(row.courseCode)
        }
        return result
    }
}
