import CryptoKit
import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `referenceCourses.creating` and
/// `referenceCourses.importing.zips` (#572): a course made straight onto the
/// Reference Courses shelf from the New Course wizard, and a backup or
/// archive zip imported for reference, both beside a LIVE course of the same
/// code that no step may touch.
///
/// Every case is data from the contract. Setup itself is not run here (it
/// needs the website builder, and `scripts/test_setup_course_reference_staging.py`
/// drives the real one); a case's run is stood in for by writing what setup
/// writes into the staging folder, and the two halves of the act on either
/// side of it are the real ones.
@MainActor
final class ReferenceCreationTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    /// A throwaway working folder holding a LIVE ICS3U, and a trail of its
    /// own. Nothing here touches the real home folder.
    func prepareWorkingFolder() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-creation-\(UUID().uuidString)")
        workingFolderURL = rootURL.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        let live: URL = coursesDirectoryURL.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: live.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try Data("{\"course_code\": \"ICS3U\", \"section_numbers\": [1], \"deploy_target\": \"cloudflare_pages\"}\n".utf8)
            .write(to: live.appendingPathComponent("course_config.json"))
        try Data("---\ntitle: Live\npublish: true\n---\nTaught this year.\n".utf8)
            .write(to: live.appendingPathComponent("section1").appendingPathComponent("index.md"))

        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))
        let root: URL = rootURL
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousStore
                ReferenceLock.clearLock(at: root)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Wording

    func testTheSentencesAreTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(
            try ReferenceCreationTests.creatingRules()["wording"] as? [String: Any]
        )
        XCTAssertEqual(ReferenceCreationWording.toggleLabel, wording["toggleLabel"] as? String)
        XCTAssertEqual(ReferenceCreationWording.toggleCaption, wording["toggleCaption"] as? String)
        XCTAssertEqual(
            ReferenceCreationWording.noReadyMadePages(code: "{code}"), wording["noReadyMadePages"] as? String
        )
        XCTAssertEqual(
            ReferenceCreationWording.offerUnderTheRefusal(code: "{code}"), wording["offerUnderTheRefusal"] as? String
        )
        XCTAssertEqual(ReferenceCreationWording.offerButton, wording["offerButton"] as? String)
        XCTAssertEqual(ReferenceCreationWording.createButton, wording["createButton"] as? String)
        XCTAssertEqual(ReferenceCreationWording.creatingTitle, wording["creatingTitle"] as? String)
        XCTAssertEqual(
            ReferenceCreationWording.couldNotBeMade(code: "{code}"), wording["couldNotBeMade"] as? String
        )
        XCTAssertEqual(
            ReferenceCreationWording.pagesDidNotLand(code: "{code}"), wording["pagesDidNotLand"] as? String
        )
        XCTAssertEqual(ReferenceCreationWording.stopped, wording["stopped"] as? String)
        XCTAssertEqual(
            ReferenceCreationWording.newReferenceCourseMenuItem, wording["newReferenceCourseMenuItem"] as? String
        )

        let importWording: [String: Any] = try XCTUnwrap(
            try ReferenceCreationTests.referenceRules(["importing", "wording"])
        )
        XCTAssertEqual(
            ReferenceImportWording.zipCouldNotBeOpened(zip: "{zip}"), importWording["zipCouldNotBeOpened"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.zipIsNotSafeToOpen(zip: "{zip}"), importWording["zipIsNotSafeToOpen"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.zipHoldsNoCourse(zip: "{zip}"), importWording["zipHoldsNoCourse"] as? String
        )
    }

    /// The marker setup prints is the one this side looks for.
    func testThePagesMarkerIsTheOneSetupPrints() throws {
        let setupURL: URL = ReferenceCreationTests.repositoryURL()
            .appendingPathComponent("scripts/setup_course.py")
        let setup: String = try String(contentsOf: setupURL, encoding: .utf8)
        XCTAssertTrue(
            setup.contains("📖 \(ReferenceCreation.pagesInstalledMarker): "),
            "setup_course.py no longer prints the line ReferenceCreation.pagesLanded reads."
        )
    }

    // MARK: - When the choice is offered

    func testWhenTheChoiceIsOffered() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceCreationTests.creatingRules()["whenOffered"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "The contract's cases did not load.")
        for testCase in cases {
            let offered: ReferenceChoice = ReferenceChoice.offered(
                code: try XCTUnwrap(testCase["code"] as? String),
                hasReadyMadePages: try XCTUnwrap(testCase["hasReadyMadePages"] as? Bool),
                isClub: try XCTUnwrap(testCase["isClub"] as? Bool),
                takenByACourseHere: try XCTUnwrap(testCase["takenByACourseHere"] as? Bool),
                keepsForReference: try XCTUnwrap(testCase["keepsForReference"] as? Bool),
                cameForReference: try XCTUnwrap(testCase["cameForReference"] as? Bool)
            )
            XCTAssertEqual(
                ReferenceCreationTests.name(of: offered), testCase["expect"] as? String,
                "whenOffered: \(testCase)"
            )
        }
    }

    // MARK: - The code check

    func testTheCodeCheck() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceCreationTests.creatingRules()["codeCheck"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "The contract's cases did not load.")
        for testCase in cases {
            let typed: String = try XCTUnwrap(testCase["typed"] as? String)
            let existing: [String] = try XCTUnwrap(testCase["existingFolderNames"] as? [String])
            let keeps: Bool = try XCTUnwrap(testCase["keepsForReference"] as? Bool)
            let year: Int? = testCase["schoolYear"] as? Int
            var shelved: [ReferenceCourseRule.Shelved] = []
            for entry in try XCTUnwrap(testCase["shelved"] as? [[String: Any]]) {
                shelved.append(ReferenceCourseRule.Shelved(
                    displayCode: try XCTUnwrap(entry["displayCode"] as? String),
                    schoolYear: entry["schoolYear"] as? Int,
                    folderName: try XCTUnwrap(entry["folderName"] as? String)
                ))
            }
            let problem: String? = ReferenceCreation.courseCodeProblem(
                typed: typed,
                existingFolderNames: existing,
                keepsForReference: keeps,
                schoolYear: year,
                shelved: shelved
            )
            let code: String = CourseCodeRule.normalized(typed)
            var expected: String?
            switch testCase["expect"] as? String {
            case "alreadyTaken":
                expected = CourseCodeRule.Trouble.alreadyTaken(code).sentence
            case "codeAlreadyInThatYear", "codeAlreadyWithNoYear":
                expected = ReferenceCourseRule.Trouble.codeAlreadyInThatYear(code: code, schoolYear: year).sentence
            case "keptForPlantoir":
                expected = CourseCodeRule.Trouble.keptForPlantoir(code).sentence
            case "charactersThatAreNotAllowed":
                expected = CourseCodeRule.Trouble.charactersThatAreNotAllowed.sentence
            default:
                expected = nil
            }
            XCTAssertEqual(problem, expected, "codeCheck: \(testCase)")
            if let folderName = testCase["folderName"] as? String {
                XCTAssertEqual(
                    ReferenceCourseRule.proposedFolderName(forCode: code, schoolYear: year, existingFolderNames: existing),
                    folderName
                )
            }
        }
    }

    // MARK: - The settings written before setup runs

    func testTheSettingsWrittenBeforeSetupRuns() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceCreationTests.creatingRules()["settingsWritten"] as? [String: Any]
        )
        let wizard: [String: Any] = [
            "course_code": "ICS3U",
            "section_numbers": [1, 2],
            "prepopulate_example_content": false,
            "use_skeleton": true,
            "deploy_target": "cloudflare_pages",
            "deploy_folder_path": "/somewhere",
            "additional_deploy_targets": [["type": "netlify"]],
            "custom_domains": ["section1": "class.example.org"],
        ]
        let settings: CourseConfiguration = ReferenceCreation.referenceSettings(wizard, schoolYear: 2026)
        let expected: [String: Any] = try XCTUnwrap(rules["expectKeys"] as? [String: Any])
        for (key, value) in expected {
            let written: Any? = settings.values[key]
            XCTAssertNotNil(written, "\(key) was not written")
            if let flag = value as? Bool, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
                XCTAssertEqual(written as? Bool, flag, key)
            } else if let number = value as? Int {
                XCTAssertEqual(written as? Int, number, key)
            } else if let text = value as? String {
                XCTAssertEqual(written as? String, text, key)
            }
        }
        for key in try XCTUnwrap(rules["absentKeys"] as? [String]) {
            XCTAssertNil(settings.values[key], "\(key) should not be written")
        }
        let other: CourseConfiguration = ReferenceCreation.referenceSettings(wizard, schoolYear: nil)
        XCTAssertNil(other.values["reference_school_year"], "Other writes no year")
    }

    // MARK: - The act, end to end on either side of setup

    func testEveryWayTheActEnds() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceCreationTests.creatingRules()["sequence"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4, "The contract's cases did not load.")
        for testCase in cases {
            try prepareWorkingFolder()
            let liveURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U")
            let liveBefore: [String: String] = try ReferenceCreationTests.digest(of: liveURL)
            let shelvedBefore: [ReferenceCourseRule.Shelved] = [
                ReferenceCourseRule.Shelved(displayCode: "ICS3U", schoolYear: 2025, folderName: "ICS3U-2025"),
            ]

            let prepared: ReferenceCreation.Prepared = try ReferenceCreation.prepare(
                configuration: ["course_code": "ics3u", "section_numbers": [1, 2], "deploy_target": "cloudflare_pages"],
                schoolYear: 2026,
                coursesDirectoryURL: coursesDirectoryURL,
                existingFolderNames: ["ICS3U"],
                shelved: shelvedBefore
            )
            XCTAssertEqual(prepared.folderName, "ICS3U-2026")
            XCTAssertEqual(prepared.stagingName, ReferenceStaging.stagingName(for: "ICS3U-2026"))
            let staged: CourseConfiguration = try CourseConfiguration(
                contentsOf: prepared.stagingURL.appendingPathComponent("course_config.json")
            )
            XCTAssertTrue(staged.keptForReference, "The marker is written before setup runs.")
            XCTAssertTrue(
                ReferenceStaging.claimedStagingKeys.contains(
                    ReferenceStaging.claimKey(for: "ICS3U-2026", inCoursesDirectory: coursesDirectoryURL)
                ),
                "The staging folder is claimed for the length of the run."
            )

            let setup: String = try XCTUnwrap(testCase["setup"] as? String)
            var transcript: String = ""
            if setup == "succeeded" || setup == "succeededWithoutPages" {
                try ReferenceCreationTests.writeWhatSetupWrites(
                    into: prepared.stagingURL, withPages: setup == "succeeded"
                )
                if setup == "succeeded" {
                    transcript = "📖 Example content installed: 3 pages.\n✅ Course 'ICS3U' set up successfully"
                } else {
                    transcript = "✅ Course 'ICS3U' set up successfully"
                }
            }

            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            var said: String?
            do {
                let made: ReferenceCopier.Made = try ReferenceCreation.finish(
                    prepared,
                    setupSucceeded: setup == "succeeded" || setup == "succeededWithoutPages",
                    wasStopped: setup == "stopped",
                    transcript: transcript
                )
                XCTAssertEqual(made.folderName, "ICS3U-2026")
                XCTAssertEqual(made.displayCode, "ICS3U")
                XCTAssertEqual(made.schoolYear, 2026)
            } catch {
                said = error.localizedDescription
            }

            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let finalURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2026")
            let onTheShelf: Bool = try XCTUnwrap(expect["onTheShelf"] as? Bool)
            XCTAssertEqual(FileManager.default.fileExists(atPath: finalURL.path), onTheShelf, name)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: prepared.stagingURL.path),
                "\(name): the staging folder was left behind."
            )
            XCTAssertFalse(
                ReferenceStaging.claimedStagingKeys.contains(
                    ReferenceStaging.claimKey(for: "ICS3U-2026", inCoursesDirectory: coursesDirectoryURL)
                ),
                "\(name): the claim was not given back."
            )
            let lease: URL = ReferenceStaging.activityDirectory(inCoursesDirectory: coursesDirectoryURL)
                .appendingPathComponent(ReferenceStaging.leaseName(for: "ICS3U-2026"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: lease.path), "\(name): the lease was left.")
            XCTAssertEqual(
                try ReferenceCreationTests.digest(of: liveURL), liveBefore,
                "\(name): the live ICS3U was changed."
            )

            switch expect["said"] as? String {
            case "couldNotBeMade":
                XCTAssertEqual(said, ReferenceCreationWording.couldNotBeMade(code: "ICS3U"), name)
            case "pagesDidNotLand":
                XCTAssertEqual(said, ReferenceCreationWording.pagesDidNotLand(code: "ICS3U"), name)
            case "stopped":
                XCTAssertEqual(said, ReferenceCreationWording.stopped, name)
            default:
                XCTAssertNil(said, name)
            }

            if onTheShelf {
                let settings: CourseConfiguration = try CourseConfiguration(
                    contentsOf: finalURL.appendingPathComponent("course_config.json")
                )
                XCTAssertTrue(settings.keptForReference, "\(name): not marked.")
                XCTAssertEqual(settings.referenceSchoolYear, 2026)
                XCTAssertEqual(settings.values["deploy_target"] as? String, "local_folder")
                XCTAssertEqual(settings.values["course_code"] as? String, "ICS3U")
                let page: URL = finalURL.appendingPathComponent("Lessons").appendingPathComponent("Variables.md")
                XCTAssertTrue(ReferenceLock.isLocked(page), "\(name): the pages are not locked.")
            }

            // The trail keeps the line, not the event's name; each event's
            // line opens in its own words.
            let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
            let event: String = try XCTUnwrap(expect["trail"] as? String)
            var opening: String = "could not create ICS3U for reference as ICS3U-2026"
            if event == ActivityTrail.Event.courseCreatedForReference.rawValue {
                opening = "· created ICS3U for reference as ICS3U-2026 — 2026–27, 2 sections"
            } else {
                XCTAssertEqual(event, ActivityTrail.Event.courseCouldNotBeCreatedForReference.rawValue)
            }
            XCTAssertTrue(trail.contains(opening), "\(name): no '\(event)' line on the trail: \(trail)")
            if let said {
                XCTAssertTrue(trail.contains(said), "\(name): the trail line does not carry the sentence.")
            }
        }
    }

    /// The shelf rule refuses at the act as well as in the caption, and the
    /// refusal leaves nothing behind but a line.
    func testTheShelfRuleRefusesAtTheAct() throws {
        try prepareWorkingFolder()
        let shelved: [ReferenceCourseRule.Shelved] = [
            ReferenceCourseRule.Shelved(displayCode: "ICS3U", schoolYear: 2026, folderName: "ICS3U-2026"),
        ]
        XCTAssertThrowsError(try ReferenceCreation.prepare(
            configuration: ["course_code": "ICS3U"],
            schoolYear: 2026,
            coursesDirectoryURL: coursesDirectoryURL,
            existingFolderNames: ["ICS3U", "ICS3U-2026"],
            shelved: shelved
        )) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ReferenceCourseRule.Trouble.codeAlreadyInThatYear(code: "ICS3U", schoolYear: 2026).sentence
            )
        }
        let children: [String] = try FileManager.default.contentsOfDirectory(atPath: coursesDirectoryURL.path)
        XCTAssertEqual(children.sorted(), ["ICS3U"], "Something was left in courses/.")
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true)
                .contains("could not create ICS3U for reference — You already have a ICS3U")
        )
    }

    // MARK: - Zips

    func testTheZipNameAndListingRules() throws {
        let zips: [String: Any] = try XCTUnwrap(try ReferenceCreationTests.referenceRules(["importing", "zips"]))
        let namesCases: [[String: Any]] = try XCTUnwrap(zips["namesCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(namesCases.count, 6)
        for testCase in namesCases {
            let names: [String] = try XCTUnwrap(testCase["names"] as? [String])
            XCTAssertEqual(
                ReferenceZipSource.namesStayInside(names), try XCTUnwrap(testCase["stayInside"] as? Bool),
                "namesCases: \(names)"
            )
        }
        let listingCases: [[String: Any]] = try XCTUnwrap(zips["listingCases"] as? [[String: Any]])
        for testCase in listingCases {
            let lines: [String] = try XCTUnwrap(testCase["lines"] as? [String])
            XCTAssertEqual(
                ReferenceZipSource.listingHoldsALink(lines), try XCTUnwrap(testCase["holdsALink"] as? Bool),
                "listingCases: \(lines)"
            )
        }
    }

    func testEveryZipCase() async throws {
        let zips: [String: Any] = try XCTUnwrap(try ReferenceCreationTests.referenceRules(["importing", "zips"]))
        let cases: [[String: Any]] = try XCTUnwrap(zips["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "The contract's cases did not load.")
        for testCase in cases {
            try prepareWorkingFolder()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let kind: String = try XCTUnwrap(testCase["zip"] as? String)
            let zipURL: URL = try ReferenceCreationTests.makeZip(kind, under: rootURL.appendingPathComponent("made"))
            let zipBefore: Data = try Data(contentsOf: zipURL)
            let liveURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U")
            let liveBefore: [String: String] = try ReferenceCreationTests.digest(of: liveURL)
            let openParent: URL = rootURL.appendingPathComponent("opened")
            try FileManager.default.createDirectory(at: openParent, withIntermediateDirectories: true)

            let outcome: ReferenceZipSource.Outcome = ReferenceZipSource.openNow(zipURL, into: openParent)

            if testCase["expect"] as? String == "refused" {
                let zipName: String = zipURL.lastPathComponent
                var expected: String = ""
                switch testCase["said"] as? String {
                case "zipIsNotSafeToOpen":
                    expected = ReferenceImportWording.zipIsNotSafeToOpen(zip: zipName)
                case "zipHoldsNoCourse":
                    expected = ReferenceImportWording.zipHoldsNoCourse(zip: zipName)
                default:
                    expected = ReferenceImportWording.zipCouldNotBeOpened(zip: zipName)
                }
                XCTAssertEqual(outcome, .refused(expected), name)
                let leftOpen: [String] = try FileManager.default.contentsOfDirectory(atPath: openParent.path)
                XCTAssertEqual(leftOpen, [], "\(name): what was unpacked was left behind.")
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("escaped.txt").path),
                    "\(name): a file was written outside."
                )
            } else {
                guard case .opened(let courseFolderURL, let openedIntoURL) = outcome else {
                    XCTFail("\(name): not opened: \(outcome)")
                    continue
                }
                // Read as a lone course folder, exactly as the sheet reads it.
                let read: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
                    chosen: courseFolderURL,
                    workingFolderURL: workingFolderURL,
                    leavingBehind: ReferenceImporter.leftBehindNames
                )
                guard case .found(let source) = read else {
                    XCTFail("\(name): the opened course was refused")
                    continue
                }
                XCTAssertEqual(source.courses.count, 1, name)
                XCTAssertEqual(source.courses.first?.courseCode, testCase["courseCode"] as? String)
                XCTAssertEqual(source.tickedWhenOpened, [source.courses[0].id])

                let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
                    [ReferenceImporter.Request(course: source.courses[0], schoolYear: 2025)],
                    into: coursesDirectoryURL,
                    existingFolderNames: ["ICS3U"],
                    alreadyShelved: [],
                    from: zipURL,
                    progress: { _ in }
                )
                guard case .imported(let made) = outcomes.first else {
                    XCTFail("\(name): not imported: \(outcomes)")
                    continue
                }
                XCTAssertEqual(made.folderName, "ICS3U-2025")
                let landed: CourseConfiguration = try CourseConfiguration(
                    contentsOf: coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
                        .appendingPathComponent("course_config.json")
                )
                XCTAssertTrue(landed.keptForReference)
                XCTAssertEqual(landed.values["deploy_target"] as? String, "local_folder")
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
                            .appendingPathComponent(".netlify_sites").appendingPathComponent("section1.json").path
                    ),
                    "\(name): last year's site marker came along."
                )
                XCTAssertTrue(
                    ActivityTrail.store.activityText(includingPrompts: true)
                        .contains("imported ICS3U for reference from \(zipURL.lastPathComponent) as ICS3U-2025")
                )
                ReferenceZipSource.remove(openedIntoURL)
                XCTAssertFalse(FileManager.default.fileExists(atPath: openedIntoURL.path))
            }

            XCTAssertEqual(try Data(contentsOf: zipURL), zipBefore, "\(name): the zip was changed.")
            XCTAssertEqual(
                try ReferenceCreationTests.digest(of: liveURL), liveBefore,
                "\(name): the live ICS3U was changed."
            )
        }
    }

    // MARK: - Helpers

    static func name(of choice: ReferenceChoice) -> String {
        switch choice {
        case .notShown:
            return "notShown"
        case .toggle:
            return "toggle"
        case .offerUnderTheRefusal:
            return "offerUnderTheRefusal"
        case .noReadyMadePages:
            return "noReadyMadePages"
        }
    }

    static func repositoryURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func referenceRules(_ path: [String]) throws -> [String: Any]? {
        let url: URL = ReferenceCreationTests.repositoryURL().appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        var node: [String: Any] = try XCTUnwrap(all["referenceCourses"] as? [String: Any])
        for key in path {
            node = try XCTUnwrap(node[key] as? [String: Any], "No referenceCourses.\(key)")
        }
        return node
    }

    static func creatingRules() throws -> [String: Any] {
        return try XCTUnwrap(try ReferenceCreationTests.referenceRules(["creating"]))
    }

    /// Every file under a folder with its bytes' digest, and every folder.
    static func digest(of folderURL: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil))
        for case let entryURL as URL in walker {
            let relative: String = String(entryURL.path.dropFirst(folderURL.path.count))
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: entryURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                result[relative] = "folder"
            } else {
                let bytes: Data = try Data(contentsOf: entryURL)
                result[relative] = SHA256.hash(data: bytes).description
            }
        }
        return result
    }

    /// What the real setup leaves in the staging folder, in miniature.
    static func writeWhatSetupWrites(into stagingURL: URL, withPages: Bool) throws {
        let fileManager: FileManager = FileManager.default
        for section in ["section1", "section2"] {
            let folder: URL = stagingURL.appendingPathComponent(section)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("---\ntitle: Front\n---\n".utf8).write(to: folder.appendingPathComponent("index.md"))
        }
        let lessons: URL = stagingURL.appendingPathComponent("Lessons")
        try fileManager.createDirectory(at: lessons, withIntermediateDirectories: true)
        try Data("---\ntitle: Lessons\n---\n".utf8).write(to: lessons.appendingPathComponent("index.md"))
        if withPages {
            try Data("---\ntitle: Variables\n---\nA ready-made page.\n".utf8)
                .write(to: lessons.appendingPathComponent("Variables.md"))
        }
        try fileManager.createDirectory(
            at: stagingURL.appendingPathComponent("Media"), withIntermediateDirectories: true
        )
    }

    /// Makes one of the contract's zips with the system's own tools.
    static func makeZip(_ kind: String, under folderURL: URL) throws -> URL {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let source: URL = folderURL.appendingPathComponent("source-\(kind)")
        let course: URL = source.appendingPathComponent("ICS3U")
        try fileManager.createDirectory(at: course.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try Data("{\"course_code\": \"ICS3U\", \"section_numbers\": [1], \"deploy_target\": \"netlify\"}\n".utf8)
            .write(to: course.appendingPathComponent("course_config.json"))
        try Data("---\ntitle: Last year\n---\nA page.\n".utf8)
            .write(to: course.appendingPathComponent("section1").appendingPathComponent("index.md"))
        let markers: URL = course.appendingPathComponent(".netlify_sites")
        try fileManager.createDirectory(at: markers, withIntermediateDirectories: true)
        try Data("{\"site_id\": \"last-year\"}\n".utf8).write(to: markers.appendingPathComponent("section1.json"))

        let zipURL: URL = folderURL.appendingPathComponent("ICS3U_backup_2025-06-20_\(kind).zip")
        switch kind {
        case "backupOfALiveCourse":
            try ReferenceCreationTests.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", course.path, zipURL.path])
        case "holdsALink":
            try fileManager.createSymbolicLink(
                at: course.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc")
            )
            try ReferenceCreationTests.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", course.path, zipURL.path])
        case "twoFolders":
            try fileManager.createDirectory(
                at: source.appendingPathComponent("Another"), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: source.appendingPathComponent("Another").appendingPathComponent("a.md"))
            try ReferenceCreationTests.run("/usr/bin/ditto", ["-c", "-k", source.path, zipURL.path])
        case "folderWithoutSettings":
            try fileManager.removeItem(at: course.appendingPathComponent("course_config.json"))
            try ReferenceCreationTests.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", course.path, zipURL.path])
        case "climbsOut":
            // `zip`, run from inside the course, stores the name as typed:
            // ../escaped.txt.
            try Data("x".utf8).write(to: source.appendingPathComponent("escaped.txt"))
            try ReferenceCreationTests.run(
                "/usr/bin/zip", ["-q", zipURL.path, "course_config.json", "../escaped.txt"],
                in: course
            )
        default:
            try Data("not a zip at all".utf8).write(to: zipURL)
        }
        return zipURL
    }

    static func run(_ executable: String, _ arguments: [String], in folderURL: URL? = nil) throws {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let folderURL {
            process.currentDirectoryURL = folderURL
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(executable) \(arguments)")
    }
}
