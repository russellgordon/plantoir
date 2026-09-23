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

        // And STRICTLY: a real JSON boolean and nothing else. `as? Bool` on
        // the `NSNumber` these decode to says TRUE for 1 and 1.0, which is
        // how the app came to freeze a course every launcher would deploy.
        for truthy in ["1", "1.0", "\"true\"", "\"yes\"", "2"] {
            let data: Data = Data(
                "{\"course_code\": \"ICS3U\", \"kept_for_reference\": \(truthy)}".utf8
            )
            let decoded: [String: Any] = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let configuration: CourseConfiguration = CourseConfiguration(
                values: decoded, lastSavedData: data
            )
            XCTAssertFalse(
                configuration.keptForReference,
                "\(truthy) is not a JSON boolean, so it must not freeze and lock a course"
            )
        }
    }

    /// **The app is the FOURTH reader of the marker**, and these are the same
    /// rows `scripts/test_reference_course.py` runs against `deploy.sh`,
    /// `deploy.ps1` and the shared Python.
    ///
    /// It exists because the app and the three launchers disagreed, in both
    /// directions at once: `"kept_for_reference": 1` read TRUE here —
    /// `JSONSerialization` hands back an `NSNumber`, and `NSNumber`
    /// conditionally bridges to `Bool` for 0 and 1 — so the app FROZE AND
    /// LOCKED a course, with no way back to live, that every launcher then
    /// deployed.
    func testTheAppReadsTheMarkerTheWayTheContractSays() throws {
        let rules: [String: Any] = try ReferenceCourseTests.rules()
        let agreement: [String: Any] = try XCTUnwrap(rules["markerAgreement"] as? [String: Any])
        let rows: [[String: Any]] = try XCTUnwrap(agreement["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 22, "The agreement table has lost rows.")

        let folder: URL = try ReferenceCourseTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let configURL: URL = folder.appendingPathComponent("course_config.json")

        var checked: Int = 0
        for row in rows {
            let name: String = try XCTUnwrap(row["name"] as? String)
            guard let text = row["configText"] as? String else {
                // The rows about a missing, unreadable or directory-shaped
                // settings file are about READING rather than about the
                // marker; the launchers own those.
                continue
            }
            var data: Data = Data(text.utf8)
            if row["bom"] as? Bool == true {
                data = Data([0xEF, 0xBB, 0xBF]) + data
            }
            try data.write(to: configURL)
            if row["unreadable"] as? Bool == true {
                // The launchers own this row — they fail CLOSED on it. What
                // the app does is worth pinning anyway: it cannot open the
                // course at all, so it is not in the sidebar and nothing is
                // frozen.
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o000], ofItemAtPath: configURL.path
                )
                defer {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o644], ofItemAtPath: configURL.path
                    )
                }
                if FileManager.default.isReadableFile(atPath: configURL.path) {
                    continue
                }
                XCTAssertNil(try? CourseConfiguration(contentsOf: configURL), name)
                continue
            }
            checked += 1

            // Stated on every row rather than inferred: the app and the
            // launchers are allowed to differ in ONE direction, so a default
            // would hide exactly the rows worth reading.
            let expected: Bool = try XCTUnwrap(
                row["appReadsAsReference"] as? Bool,
                "\(name) does not say what the app reads it as"
            )
            guard let configuration = try? CourseConfiguration(contentsOf: configURL) else {
                // Malformed JSON: the app cannot open the course at all, so
                // it reads as no course rather than as a reference course.
                XCTAssertFalse(expected, "\(name): the app cannot read this file at all")
                continue
            }
            XCTAssertEqual(configuration.keptForReference, expected, name)

            // The INVARIANT: wherever the app says reference, every launcher
            // must refuse. The reverse is allowed — refusing publishes
            // nothing and freezes nothing.
            if configuration.keptForReference {
                XCTAssertEqual(
                    row["expect"] as? String, "refused",
                    "\(name): the app would freeze and lock this course and a launcher would deploy it"
                )
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 18, "Most rows carry a settings file to read.")
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
        XCTAssertEqual(
            ReferenceWording.staysAsItIs(course: "{course}"),
            wording["staysAsItIs"] as? String,
            "The app and the contract have to say the same sentence, or Windows implements a different one."
        )
        XCTAssertEqual(ReferenceWording.pagesAreLocked, wording["pagesAreLocked"] as? String)
        XCTAssertEqual(
            ReferenceWording.obsidianOpensThemForReading,
            wording["obsidianOpensThemForReading"] as? String
        )
        XCTAssertNil(
            wording["aCopyTakenOutStaysLocked"],
            "Retired 2026-09-22: Plantoir's own copy feature unlocks what it copies, so the hand-copy sentence went."
        )
        XCTAssertEqual(
            ReferenceWording.neverDeployed(course: "{course}"),
            wording["neverDeployed"] as? String
        )
        XCTAssertEqual(
            ReferenceWording.copyIsASnapshot(course: "{course}"),
            wording["copyIsASnapshot"] as? String
        )
        XCTAssertEqual(ReferenceWording.groupTitle, wording["groupTitle"] as? String)
        XCTAssertEqual(ReferenceWording.keepACopyMenuItem, wording["keepACopyMenuItem"] as? String)
        XCTAssertEqual(
            ReferenceWording.setSchoolYearMenuItem, wording["setSchoolYearMenuItem"] as? String
        )
        XCTAssertEqual(
            ReferenceCourseRule.Trouble.codeAlreadyInThatYear(code: "{code}", schoolYear: nil).sentence,
            wording["codeAlreadyWithNoYear"] as? String
        )
        XCTAssertEqual(
            ReferenceWording.couldNotSetSchoolYear(course: "{course}"),
            wording["couldNotSetSchoolYear"] as? String,
            "The one sentence of this feature a Windows reader could not get as data."
        )
    }

    /// The calm note claims no more than the measurements support.
    ///
    /// It may not say the pages CANNOT be changed — the lock is per-Mac, and
    /// a folder in iCloud Drive has it cleared while files upload — and it
    /// may not promise the teacher will be TOLD when an edit fails, because
    /// what Obsidian does with a locked page could not be measured.
    func testTheCalmNotePromisesNoMoreThanIsTrue() {
        let note: String = ReferenceWording.pagesAreLocked.lowercased()
        for overclaim in ["cannot", "can't", "never be changed", "impossible", "error", "warning"] {
            XCTAssertFalse(note.contains(overclaim), "The note says “\(overclaim)”: \(note)")
        }
        XCTAssertTrue(note.contains("locked"))
        // The Obsidian sentence says what was MEASURED (2026-09-23) and no
        // more: reading view, a could-not-save notice, the page unchanged.
        let obsidian: String = ReferenceWording.obsidianOpensThemForReading.lowercased()
        XCTAssertTrue(obsidian.contains("for reading"))
        XCTAssertTrue(obsidian.contains("stays as it was"))
        for overclaim in ["cannot", "never", "impossible", "error", "warning", "locked"] {
            XCTAssertFalse(obsidian.contains(overclaim), "The Obsidian sentence says “\(overclaim)”: \(obsidian)")
        }
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
        XCTAssertTrue(
            ReferenceLock.isNeverLocked("something.tmp"),
            "Anything half-written is left alone, whatever its name — a locked .tmp is an atomic "
            + "write nobody can finish OR clean up."
        )
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
