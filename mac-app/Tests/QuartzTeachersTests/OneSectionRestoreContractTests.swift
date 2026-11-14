import XCTest
@testable import QuartzTeachers

/// Runs `contracts/course-management.json` → `backups.restoreOneSection`
/// (#897, piece C): when Restore from Backup… offers one section, what counts
/// as the same naming, the files outside the section, and every sentence.
/// Windows runs the same cases against its own code.
final class OneSectionRestoreContractTests: XCTestCase {

    // MARK: - Functions

    /// Every `offerCases` case, through `OneSectionRestore.offeredSection`.
    @MainActor
    func testEveryOfferCase() throws {
        let block: [String: Any] = try OneSectionRestoreContractTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["offerCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8, "offerCases has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let makerName: String = try XCTUnwrap(testCase["maker"] as? String)
            let makerSection: Int? = testCase["makerSection"] as? Int
            var maker: BackupMaker = .teacher
            if makerName == "menu" {
                maker = .menu(sectionNumber: try XCTUnwrap(makerSection, name))
            } else if makerName == "assistant" {
                maker = .assistant(sectionNumber: try XCTUnwrap(makerSection, name))
            }
            let offered: Int? = OneSectionRestore.offeredSection(
                maker: maker,
                sectionExistsNow: try XCTUnwrap(testCase["sectionExistsNow"] as? Bool, name),
                keptForReference: try XCTUnwrap(testCase["keptForReference"] as? Bool, name),
                renameUnfinished: try XCTUnwrap(testCase["renameUnfinished"] as? Bool, name),
                backupHasTheSection: try XCTUnwrap(testCase["backupHasTheSection"] as? Bool, name),
                namingSameAsNow: try XCTUnwrap(testCase["namingSameAsNow"] as? Bool, name)
            )
            XCTAssertEqual(offered, testCase["offered"] as? Int, name)
        }
    }

    /// Every `namingCases` case, through `OneSectionRestore.Naming`.
    @MainActor
    func testEveryNamingCase() throws {
        let block: [String: Any] = try OneSectionRestoreContractTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["namingCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12, "namingCases has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let live: [String: Any] = try XCTUnwrap(testCase["live"] as? [String: Any], name)
            let backup: [String: Any] = try XCTUnwrap(testCase["backup"] as? [String: Any], name)
            let liveNaming: OneSectionRestore.Naming = OneSectionRestore.Naming(
                configuration: CourseConfiguration(values: live, lastSavedData: Data())
            )
            let backupNaming: OneSectionRestore.Naming = OneSectionRestore.Naming(
                configuration: CourseConfiguration(values: backup, lastSavedData: Data())
            )
            let difference: OneSectionRestore.NamingDifference? = liveNaming.difference(fromBackup: backupNaming)
            XCTAssertEqual(difference == nil, try XCTUnwrap(testCase["same"] as? Bool, name), name)
            var expected: OneSectionRestore.NamingDifference?
            if let named = testCase["difference"] as? String {
                expected = named == "folders" ? .folders : .classPages
                XCTAssertTrue(named == "folders" || named == "classPages", "\(name): \(named)")
            }
            XCTAssertEqual(difference, expected, name)
        }
    }

    /// The list of files outside the section is the contract's, in order,
    /// with the same treatment.
    @MainActor
    func testTheFilesOutsideTheSectionAreTheContractsList() throws {
        let block: [String: Any] = try OneSectionRestoreContractTests.block()
        let entries: [[String: Any]] = try XCTUnwrap(block["filesOutsideTheSection"] as? [[String: Any]])
        var contractList: [OneSectionRestore.OutsideFile] = []
        for entry in entries {
            let treatmentName: String = try XCTUnwrap(entry["treatment"] as? String)
            contractList.append(OneSectionRestore.OutsideFile(
                pathTemplate: try XCTUnwrap(entry["path"] as? String),
                isFolder: try XCTUnwrap(entry["folder"] as? Bool),
                treatment: try XCTUnwrap(OneSectionRestore.Treatment(rawValue: treatmentName), treatmentName)
            ))
        }
        XCTAssertEqual(OneSectionRestore.filesOutsideTheSection, contractList)
    }

    /// Every sentence, rendered by the mac with sample values, equals the
    /// contract's template filled with the same values.
    @MainActor
    func testEverySentenceIsTheContractsTemplate() throws {
        let block: [String: Any] = try OneSectionRestoreContractTests.block()
        let wording: [String: Any] = try XCTUnwrap(block["wording"] as? [String: Any])
        let when: String = "November 13, 2026 at 8:15 PM"
        let madeBy: String = BackupMaker.menu(sectionNumber: 2).description
        let keptAt: String = "courses/_backups/ICS3U/Section 2 as it was before a restore, 2026-11-13_201500"
        func filled(_ key: String, count: Int = 0, reason: String = "") throws -> String {
            let template: String = try XCTUnwrap(wording[key] as? String, key)
            return template
                .replacingOccurrences(of: "{CODE}", with: "ICS3U")
                .replacingOccurrences(of: "{N}", with: "2")
                .replacingOccurrences(of: "{MADE_BY}", with: madeBy)
                .replacingOccurrences(of: "{WHEN}", with: when)
                .replacingOccurrences(of: "{COUNT}", with: String(count))
                .replacingOccurrences(of: "{REASON}", with: reason)
                .replacingOccurrences(of: "{KEPT}", with: keptAt)
        }

        XCTAssertEqual(OneSectionRestoreWording.title(course: "ICS3U"), try filled("title"))
        XCTAssertEqual(OneSectionRestoreWording.message(section: 2, madeBy: madeBy, when: when), try filled("message"))
        XCTAssertEqual(OneSectionRestoreWording.restoreSectionButton(section: 2), try filled("restoreSectionButton"))
        XCTAssertEqual(OneSectionRestoreWording.restoreWholeCourseButton, try filled("restoreWholeCourseButton"))
        XCTAssertEqual(OneSectionRestoreWording.doneTitle(section: 2, course: "ICS3U"), try filled("doneTitle"))
        XCTAssertEqual(OneSectionRestoreWording.namingChanged(section: 2, course: "ICS3U"), try filled("namingChanged"))
        XCTAssertEqual(OneSectionRestoreWording.sectionNotInCourse(section: 2, course: "ICS3U"), try filled("sectionNotInCourse"))
        XCTAssertEqual(OneSectionRestoreWording.busy(section: 2, course: "ICS3U"), try filled("busy"))
        XCTAssertEqual(OneSectionRestoreWording.leftAsItWas(section: 2, reason: "disk full"), try filled("leftAsItWas", reason: "disk full"))
        XCTAssertEqual(OneSectionRestoreWording.stoppedPartWay(section: 2, keptAt: keptAt), try filled("stoppedPartWay"))
        XCTAssertEqual(OneSectionRestoreWording.stoppedPartWayArchived, try filled("stoppedPartWayArchived"))
        XCTAssertEqual(OneSectionRestoreWording.stoppedPartWayNothingToOpen(section: 2), try filled("stoppedPartWayNothingToOpen"))
        XCTAssertEqual(OneSectionRestoreWording.foldersChanged(section: 2, course: "ICS3U"), try filled("foldersChanged"))
        XCTAssertEqual(OneSectionRestoreWording.notMadeForThisSection(section: 2), try filled("notMadeForThisSection"))
        XCTAssertEqual(
            CourseRestorer.Problem.sectionRestoreStoppedPartWay(2, keptAt: nil, archived: true).localizedDescription,
            try filled("stoppedPartWayNothingToOpen") + " " + filled("stoppedPartWayArchived")
        )
        XCTAssertEqual(OneSectionRestoreWording.renameUnfinished(section: 2, course: "ICS3U"), try filled("renameUnfinished"))
        // The two routes' joins, as doneJoin says.
        XCTAssertEqual(
            CourseRestorer.Problem.sectionRestoreStoppedPartWay(2, keptAt: keptAt, archived: true).localizedDescription,
            try filled("stoppedPartWay") + " " + filled("stoppedPartWayArchived")
        )
        XCTAssertEqual(
            CourseRestorer.Problem.sectionRestoreStoppedPartWay(2, keptAt: keptAt, archived: false).localizedDescription,
            try filled("stoppedPartWay")
        )

        let plain: OneSectionRestore.Outcome = OneSectionRestore.Outcome(
            pagesNotPutBack: 0, pagesNotSaved: 0, pagesMadeSinceHidden: 0, websiteRecordDiffers: false
        )
        XCTAssertEqual(OneSectionRestoreWording.done(section: 2, when: when, outcome: plain), try filled("done"))

        let ones: OneSectionRestore.Outcome = OneSectionRestore.Outcome(
            pagesNotPutBack: 1, pagesNotSaved: 1, pagesMadeSinceHidden: 1, websiteRecordDiffers: true
        )
        let expectedOnes: String = try filled("done") + "\n\n" + filled("hiddenSinceOne") + "\n\n"
            + filled("notPutBackOne") + "\n\n" + filled("notSavedOne") + "\n\n" + filled("websiteUnchanged")
        XCTAssertEqual(OneSectionRestoreWording.done(section: 2, when: when, outcome: ones), expectedOnes)

        let many: OneSectionRestore.Outcome = OneSectionRestore.Outcome(
            pagesNotPutBack: 3, pagesNotSaved: 2, pagesMadeSinceHidden: 4, websiteRecordDiffers: false
        )
        let expectedMany: String = try filled("done") + "\n\n" + filled("hiddenSinceMany", count: 4) + "\n\n"
            + filled("notPutBackMany", count: 3) + "\n\n" + filled("notSavedMany", count: 2)
        XCTAssertEqual(OneSectionRestoreWording.done(section: 2, when: when, outcome: many), expectedMany)
    }

    /// The folders the restore never gives a key are the contract's list of
    /// folders Quartz never publishes, which the build reads too.
    @MainActor
    func testTheFoldersNeverPublishedAreTheContractsList() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let fences: [String: Any] = try XCTUnwrap(all["geogebraFences"] as? [String: Any])
        let files: [String: Any] = try XCTUnwrap(fences["files"] as? [String: Any])
        let notPublished: [String: Any] = try XCTUnwrap(files["notPublished"] as? [String: Any])
        XCTAssertEqual(OneSectionRestore.foldersNeverPublished, try XCTUnwrap(notPublished["folders"] as? [String]))
    }

    private static func block() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/course-management.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let backups: [String: Any] = try XCTUnwrap(all["backups"] as? [String: Any])
        return try XCTUnwrap(backups["restoreOneSection"] as? [String: Any], "No backups.restoreOneSection")
    }
}
