import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `referenceCourses`: the marker, the
/// school years, the uniqueness rule and the neutralisation.
///
/// Every case here is DATA rather than a literal in a test, so Windows runs
/// the identical case when it implements its own half. The one thing this file
/// never does is retype a sentence: the sentences are named.
@MainActor
final class ReferenceCourseTests: XCTestCase {

    // MARK: - The marker

    func testAbsentMeansNotAReferenceCourse() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        XCTAssertEqual(rules["markerKey"] as? String, "kept_for_reference")
        XCTAssertEqual(rules["absentMeansFalse"] as? Bool, true)

        let ordinary: CourseConfiguration = ReferenceCourseTests.configuration(values: [
            "course_code": "ICS3U",
        ])
        XCTAssertFalse(ordinary.keptForReference, "A course that says nothing is a course a teacher can deploy.")

        let saysFalse: CourseConfiguration = ReferenceCourseTests.configuration(values: [
            "course_code": "ICS3U", "kept_for_reference": false,
        ])
        XCTAssertFalse(saysFalse.keptForReference)

        let reference: CourseConfiguration = ReferenceCourseTests.configuration(values: [
            "course_code": "ICS3U", "kept_for_reference": true,
        ])
        XCTAssertTrue(reference.keptForReference)
    }

    func testTheMarkerRoundTripsThroughTheFile() throws {
        let configuration: CourseConfiguration = ReferenceCourseTests.configuration(values: [
            "course_code": "ICS3U",
        ])
        configuration.keptForReference = true
        configuration.referenceSchoolYear = 2025

        let folder: URL = try ReferenceCourseTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL: URL = folder.appendingPathComponent("course_config.json")
        try configuration.write(to: fileURL)

        let readBack: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        XCTAssertTrue(readBack.keptForReference)
        XCTAssertEqual(readBack.referenceSchoolYear, 2025)
    }

    func testClearingTheSchoolYearRemovesTheKeyRatherThanWritingNull() throws {
        let configuration: CourseConfiguration = ReferenceCourseTests.configuration(values: [
            "course_code": "ICS3U", "kept_for_reference": true, "reference_school_year": 2025,
        ])
        configuration.referenceSchoolYear = nil
        XCTAssertNil(configuration.values["reference_school_year"],
                     "A course filed under no year writes the same file it always did.")
    }

    // MARK: - What a teacher reads

    func testDisplayCodeEqualsTheFolderNameForEveryCourseATeacherTeaches() throws {
        let course: Course = ReferenceCourseTests.course(
            folderName: "ICS3U", values: ["course_code": "ICS3U"]
        )
        XCTAssertEqual(course.displayCode, course.code)

        // The dangerous shape: a live course whose config disagrees with its
        // folder. Identity still wins, because nothing but a reference course
        // is allowed to disagree.
        let disagreeing: Course = ReferenceCourseTests.course(
            folderName: "ICS3U", values: ["course_code": "MCV4U"]
        )
        XCTAssertEqual(disagreeing.displayCode, "ICS3U")
        XCTAssertFalse(disagreeing.isKeptForReference)
    }

    func testAReferenceCourseShowsItsRealCode() throws {
        let course: Course = ReferenceCourseTests.course(
            folderName: "ICS3U-2025",
            values: ["course_code": "ICS3U", "kept_for_reference": true, "reference_school_year": 2025]
        )
        XCTAssertEqual(course.code, "ICS3U-2025", "Identity is the folder name and does not move.")
        XCTAssertEqual(course.displayCode, "ICS3U")
        XCTAssertTrue(course.isKeptForReference)
    }

    func testAReferenceCourseWithNoRecordedCodeFallsBackToItsFolder() throws {
        let course: Course = ReferenceCourseTests.course(
            folderName: "ICS3U-2025", values: ["kept_for_reference": true]
        )
        XCTAssertEqual(course.displayCode, "ICS3U-2025",
                       "A row labelled with nothing at all is worse than one labelled with the folder.")
    }

    // MARK: - The school year

    func testTheYearLabelIsTheContractsLabel() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let block: [String: Any] = try XCTUnwrap(rules["schoolYearLabel"] as? [String: Any])
        for testCase in try XCTUnwrap(block["cases"] as? [[String: Any]]) {
            let startingYear: Int = try XCTUnwrap(testCase["startingYear"] as? Int)
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            XCTAssertEqual(
                SchoolYear.label(forStartingYear: startingYear), expected,
                "The label for \(startingYear) — including the EN DASH, which is what keeps the two apps agreeing."
            )
        }
    }

    func testTheYearsOfferedAreTheContractsYears() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let block: [String: Any] = try XCTUnwrap(rules["schoolYearsOffered"] as? [String: Any])
        XCTAssertEqual(block["floor"] as? Int, SchoolYear.earliestStartingYear)
        XCTAssertEqual(block["rollsOverInMonth"] as? Int, SchoolYear.rolloverMonth)

        for testCase in try XCTUnwrap(block["cases"] as? [[String: Any]]) {
            let day: CalendarDay = try XCTUnwrap(
                CalendarDay(text: try XCTUnwrap(testCase["today"] as? String))
            )
            let expected: [Int] = try XCTUnwrap(testCase["expect"] as? [Int])
            XCTAssertEqual(
                SchoolYear.offeredStartingYears(on: day), expected,
                "The years offered on \(day.text), newest first."
            )
        }
    }

    func testAStoredYearReadsAsTheContractSays() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let block: [String: Any] = try XCTUnwrap(rules["schoolYearRead"] as? [String: Any])
        for testCase in try XCTUnwrap(block["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let day: CalendarDay = try XCTUnwrap(
                CalendarDay(text: try XCTUnwrap(testCase["today"] as? String))
            )
            var values: [String: Any] = ["course_code": "ICS3U", "kept_for_reference": true]
            if testCase["storedIsAbsent"] as? Bool != true {
                values["reference_school_year"] = try XCTUnwrap(testCase["storedValue"])
            }
            let course: Course = ReferenceCourseTests.course(folderName: "ICS3U-2025", values: values)
            XCTAssertEqual(course.schoolYear(on: day), testCase["expect"] as? Int, name)
        }
    }

    func testACourseATeacherTeachesIsInNoYearGroup() throws {
        let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-20"))
        let live: Course = ReferenceCourseTests.course(
            folderName: "ICS3U", values: ["course_code": "ICS3U", "reference_school_year": 2025]
        )
        XCTAssertNil(live.schoolYear(on: day),
                     "A course being taught sits in no year group, whatever a stray key says.")
    }

    // MARK: - One code per group

    func testTheUniquenessRuleIsTheContractsRule() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let block: [String: Any] = try XCTUnwrap(rules["codeUniqueWithinAGroup"] as? [String: Any])
        for testCase in try XCTUnwrap(block["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var shelf: [ReferenceCourseRule.Shelved] = []
            for entry in try XCTUnwrap(testCase["shelf"] as? [[String: Any]]) {
                let code: String = try XCTUnwrap(entry["code"] as? String)
                let year: Int? = entry["year"] as? Int
                let folderName: String = (entry["folderName"] as? String)
                    ?? ReferenceCourseRule.proposedFolderName(
                        forCode: code, schoolYear: year, existingFolderNames: []
                    )
                shelf.append(
                    ReferenceCourseRule.Shelved(displayCode: code, schoolYear: year, folderName: folderName)
                )
            }
            let placing: [String: Any] = try XCTUnwrap(testCase["placing"] as? [String: Any])
            let trouble: ReferenceCourseRule.Trouble? = ReferenceCourseRule.trouble(
                placing: try XCTUnwrap(placing["code"] as? String),
                inYear: placing["year"] as? Int,
                among: shelf,
                ignoring: testCase["ignoringFolderName"] as? String
            )
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            if expected == "refused" {
                XCTAssertNotNil(trouble, name)
                XCTAssertFalse(trouble?.sentence.isEmpty ?? true, "\(name): a refusal says why, in a sentence.")
            } else {
                XCTAssertNil(trouble, name)
            }
        }
    }

    // MARK: - The folder name

    func testTheProposedFolderNameSurvivesBeingNormalisedAgain() {
        // The launchers upper-case their course argument before building
        // `courses/<CODE>`, so a proposal that changes under `normalized` is a
        // folder they would look for and not find.
        var proposals: [String] = []
        proposals.append(ReferenceCourseRule.proposedFolderName(
            forCode: "ICS3U", schoolYear: 2025, existingFolderNames: []
        ))
        proposals.append(ReferenceCourseRule.proposedFolderName(
            forCode: "ada1o", schoolYear: nil, existingFolderNames: []
        ))
        proposals.append(ReferenceCourseRule.proposedFolderName(
            forCode: "MADW-09", schoolYear: 2025, existingFolderNames: []
        ))
        proposals.append(ReferenceCourseRule.proposedFolderName(
            forCode: "ROBOTICS", schoolYear: 2025, existingFolderNames: []
        ))
        for proposal in proposals {
            XCTAssertEqual(CourseCodeRule.normalized(proposal), proposal, proposal)
            XCTAssertNil(
                CourseCodeRule.trouble(proposal, existingCodes: []),
                "\(proposal) has to be a name a course could actually be called."
            )
        }
    }

    func testTheProposedFolderNameStepsAsideForOneAlreadyThere() {
        let first: String = ReferenceCourseRule.proposedFolderName(
            forCode: "ICS3U", schoolYear: 2025, existingFolderNames: ["ICS3U"]
        )
        XCTAssertEqual(first, "ICS3U-2025")
        let second: String = ReferenceCourseRule.proposedFolderName(
            forCode: "ICS3U", schoolYear: 2025, existingFolderNames: ["ICS3U", "ICS3U-2025"]
        )
        XCTAssertNotEqual(second, "ICS3U-2025")
        XCTAssertNil(CourseCodeRule.trouble(second, existingCodes: ["ICS3U", "ICS3U-2025"]))
    }

    // MARK: - Nowhere to deploy to

    func testNeutralisingLeavesNowhereToDeployTo() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let block: [String: Any] = try XCTUnwrap(rules["neutralises"] as? [String: Any])

        let configuration: CourseConfiguration = ReferenceCourseTests.configuration(values: [
            "course_code": "ICS3U",
            "deploy_target": "netlify",
            "additional_deploy_targets": [["type": "local_folder", "path": "/tmp/somewhere"]],
            "custom_domains": ["sections": ["section1": "ics3u.example.org"]],
        ])
        configuration.neutraliseForReference()

        for entry in try XCTUnwrap(block["keys"] as? [[String: Any]]) {
            let key: String = try XCTUnwrap(entry["key"] as? String)
            let becomes: String = try XCTUnwrap(entry["becomes"] as? String)
            if becomes == "removed" {
                XCTAssertNil(configuration.values[key], "\(key) is removed, not emptied.")
                continue
            }
            XCTAssertEqual(configuration.values[key] as? String, becomes, key)
        }

        // And the part that matters: every shipped version of the app refuses
        // this, because a folder deploy with no folder is already a refusal.
        XCTAssertNotNil(
            CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath),
            "An older Plantoir has to refuse this too — that is the whole point of neutralising."
        )
        XCTAssertEqual(configuration.allDeployDestinations.count, 1)
    }

    // MARK: - The sentences, and what is never locked

    func testTheSentenceIsTheContractsSentence() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let wording: [String: Any] = try XCTUnwrap(rules["wording"] as? [String: Any])
        let template: String = try XCTUnwrap(wording["staysAsItIs"] as? String)
        XCTAssertEqual(
            ReferenceWording.staysAsItIs(course: "{course}"), template,
            "The app and the contract have to say the same sentence, or Windows implements a different one."
        )
    }

    /// Rule 1, asked of the sentences themselves: nothing a teacher reads
    /// names the machinery. "Locked" is allowed — it is Finder's own word for
    /// what they will see on the file.
    func testNoSentenceNamesTheMachinery() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let wording: [String: Any] = try XCTUnwrap(rules["wording"] as? [String: Any])
        let forbidden: [String] = [
            "chflags", "immutable", "flag", "permission", "chmod", "symlink",
            "container", "script", "toolchain", "docker", "launchd", "plist",
        ]
        for (key, value) in wording {
            guard let sentence = value as? String, key != "machineryCheck", key != "rule" else {
                continue
            }
            for word in forbidden {
                XCTAssertFalse(
                    sentence.lowercased().contains(word),
                    "referenceCourses.wording.\(key) says “\(word)”: \(sentence)"
                )
            }
        }
    }

    func testWhatIsNeverLockedIsWhatTheContractNames() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let frozen: [String: Any] = try XCTUnwrap(rules["frozen"] as? [String: Any])
        var named: Set<String> = []
        for entry in try XCTUnwrap(frozen["neverLocked"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(entry["name"] as? String)
            XCTAssertNotNil(entry["why"] as? String, "\(name) is left writable for a reason; say it.")
            named.insert(name)
        }
        XCTAssertEqual(
            named, ReferenceLock.neverLocked,
            "Every name here is something that has to be WRITTEN while the course is open — a locked "
            + "copy of any of them breaks something a reference course is promised to do."
        )
    }

    // MARK: - Helpers

    private static func rules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["referenceCourses"] as? [String: Any],
                             "No referenceCourses in shared-rules.json")
    }

    private static func configuration(values: [String: Any]) -> CourseConfiguration {
        return CourseConfiguration(values: values, lastSavedData: Data())
    }

    private static func course(folderName: String, values: [String: Any]) -> Course {
        return Course(
            code: folderName,
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("courses").appendingPathComponent(folderName),
            configuration: ReferenceCourseTests.configuration(values: values)
        )
    }

    private static func temporaryFolder() throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reference-course-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
