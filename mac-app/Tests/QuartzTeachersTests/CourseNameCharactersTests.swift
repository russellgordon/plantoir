import XCTest
@testable import QuartzTeachers

/// A course's name is cleaned of control characters where it is read, and
/// every line the app writes on the breadcrumb trail is cleaned and then
/// redacted (#780). Every case here is `contracts/shared-rules.json` →
/// `courseNameCharacters`; Windows runs the same rows through its own rule.
///
/// Strings are compared SCALAR BY SCALAR, never with `==`: Swift's `==` on a
/// `String` treats canonically equivalent text as equal, so "é" written as one
/// code point and as "e" plus a combining accent would compare equal and a
/// rule that changed one into the other would pass.
@MainActor
final class CourseNameCharactersTests: XCTestCase {

    // MARK: - Stored properties

    private var rule: [String: Any] = [:]
    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: CourseNameCharactersTests.repositoryRoot().appendingPathComponent("contracts/shared-rules.json"))
            ) as? [String: Any]
        )
        rule = try XCTUnwrap(rules["courseNameCharacters"] as? [String: Any])

        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course-name-characters-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - The rule

    /// Every case, and the rule applied twice changes nothing more.
    func testEveryCaseCleansAsTheContractSays() throws {
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 41)
        XCTAssertEqual(rule["idempotent"] as? Bool, true)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let raw: String = try XCTUnwrap(testCase["raw"] as? String, name)
            let expect: String = try XCTUnwrap(testCase["expect"] as? String, name)
            let cleaned: String = CourseName.cleaned(raw)
            XCTAssertEqual(scalars(of: cleaned), scalars(of: expect), name)
            XCTAssertEqual(scalars(of: CourseName.cleaned(cleaned)), scalars(of: cleaned), "twice: \(name)")
        }
    }

    /// The two lists in the contract are exactly what the predicates answer,
    /// for every code point in the Basic Multilingual Plane; above it, the
    /// rule touches nothing.
    func testTheRangesAreTheContractsRanges() throws {
        let spacedOut: [ClosedRange<UInt32>] = try ranges(named: "spacedOut")
        let removed: [ClosedRange<UInt32>] = try ranges(named: "removed")
        var value: UInt32 = 0
        while value <= 0xFFFF {
            if let scalar = Unicode.Scalar(value) {
                XCTAssertEqual(
                    OneLineText.isSpacedOut(scalar), isInside(value, spacedOut),
                    String(format: "spacedOut U+%04X", value)
                )
                XCTAssertEqual(
                    OneLineText.isRemoved(scalar), isInside(value, removed),
                    String(format: "removed U+%04X", value)
                )
            }
            value += 1
        }
        for supplementary in [UInt32(0x1F469), 0xE0067, 0xE0100, 0x10FFFF] {
            let scalar: Unicode.Scalar = try XCTUnwrap(Unicode.Scalar(supplementary))
            XCTAssertFalse(OneLineText.isSpacedOut(scalar))
            XCTAssertFalse(OneLineText.isRemoved(scalar))
        }
    }

    /// Each code point the contract keeps on purpose comes through untouched.
    func testWhatIsKeptOnPurposeIsKept() throws {
        let kept: [[String: Any]] = try XCTUnwrap(rule["keptOnPurpose"] as? [[String: Any]])
        XCTAssertFalse(kept.isEmpty)
        for entry in kept {
            let hex: String = try XCTUnwrap(entry["codePoint"] as? String)
            let value: UInt32 = try XCTUnwrap(UInt32(hex, radix: 16))
            let scalar: Unicode.Scalar = try XCTUnwrap(Unicode.Scalar(value))
            var text: String = "A"
            text.unicodeScalars.append(scalar)
            text.append("B")
            XCTAssertEqual(scalars(of: CourseName.cleaned(text)), scalars(of: text), hex)
        }
    }

    // MARK: - Where the name is read

    /// A name on disk holding a NUL, a line break and an override reads
    /// cleaned, and a name set through Course Settings is stored cleaned.
    func testTheNameIsCleanedWhereItIsRead() throws {
        let fileURL: URL = scratchFolderURL.appendingPathComponent("course_config.json")
        let json: String = #"{"course_code": "SPH3U", "course_name": "Phys\u0000ics\n11\u202e"}"#
        try Data(json.utf8).write(to: fileURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        XCTAssertEqual(scalars(of: configuration.courseName), scalars(of: "Phys ics 11"))

        configuration.courseName = "A\nB\u{0}"
        let stored: String = try XCTUnwrap(configuration.values["course_name"] as? String)
        XCTAssertEqual(scalars(of: stored), scalars(of: "A B "))
    }

    /// The outside door's greeting is its command line's last argument. A
    /// NUL, a line break or an override in the course name never reaches it.
    func testTheDoorsGreetingCarriesNoControlFromTheName() throws {
        let fileURL: URL = scratchFolderURL.appendingPathComponent("course_config.json")
        let json: String = #"{"course_code": "SPH3U", "course_name": "Phys\u0000ics\n\u202eGrade 11"}"#
        try Data(json.utf8).write(to: fileURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        let greeting: String = ClaudeCodeLauncher.greeting(
            courseCode: "SPH3U", courseName: configuration.courseName
        )
        for scalar in greeting.unicodeScalars {
            XCTAssertFalse(OneLineText.isSpacedOut(scalar), String(format: "U+%04X in the greeting", scalar.value))
            XCTAssertFalse(OneLineText.isRemoved(scalar), String(format: "U+%04X in the greeting", scalar.value))
        }
        XCTAssertTrue(greeting.contains("(Phys ics Grade 11)"), greeting)
    }

    /// Every place in the app that reads or writes `course_name` goes through
    /// the rule: the getter and setter, and any other line naming the key
    /// says `CourseName.cleaned(` on the same line.
    func testEveryReadAndWriteOfTheKeyGoesThroughTheRule() throws {
        let sources: URL = CourseNameCharactersTests.repositoryRoot().appendingPathComponent("mac-app/QuartzTeachers")
        let enumerator: FileManager.DirectoryEnumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        )
        var linesNamingTheKey: Int = 0
        var unclean: [String] = []
        for case let url as URL in enumerator {
            if url.pathExtension != "swift" {
                continue
            }
            let text: String = try String(contentsOf: url, encoding: .utf8)
            var number: Int = 0
            for line in text.components(separatedBy: "\n") {
                number += 1
                if !line.contains("\"course_name\"") {
                    continue
                }
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    continue
                }
                linesNamingTheKey += 1
                if url.lastPathComponent == "CourseConfiguration.swift" {
                    continue
                }
                if !line.contains("CourseName.cleaned(") {
                    unclean.append("\(url.lastPathComponent):\(number): \(line)")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(linesNamingTheKey, 6)
        XCTAssertEqual(unclean, [], "a read or write of course_name that does not clean it")
        let configurationSource: String = try String(
            contentsOf: sources.appendingPathComponent("Models/CourseConfiguration.swift"), encoding: .utf8
        )
        XCTAssertTrue(configurationSource.contains("get { return CourseName.cleaned(stringValue(forKey: \"course_name\")) }"))
        XCTAssertTrue(configurationSource.contains("set { values[\"course_name\"] = CourseName.cleaned(newValue) }"))
    }

    /// Any Save writes the name cleaned, not only a Save that edited it: a
    /// file whose name holds a NUL, saved after an unrelated setting changed,
    /// holds the cleaned name afterwards.
    func testAnySaveWritesTheNameCleaned() throws {
        let fileURL: URL = scratchFolderURL.appendingPathComponent("course_config.json")
        let json: String = #"{"course_code": "SPH3U", "course_name": "Phys\u0000ics\u202e 11", "footer_html": ""}"#
        try Data(json.utf8).write(to: fileURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        configuration.values["footer_html"] = "<p>Room 204</p>"
        try configuration.write(to: fileURL)
        let written: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: fileURL)) as? [String: Any]
        )
        let name: String = try XCTUnwrap(written["course_name"] as? String)
        XCTAssertEqual(scalars(of: name), scalars(of: "Phys ics 11"))
        XCTAssertEqual(written["footer_html"] as? String, "<p>Room 204</p>")
    }

    /// The New Course window cleans the name before it trims it, so a name
    /// that is only a line break gets the default.
    func testTheNewCourseWindowCleansBeforeItTrims() {
        let defaultName: String = WizardWording.panelWords(isClub: false).defaultSiteName
        XCTAssertEqual(NewCourseWizardView.nameToWrite(typed: "\n", isClub: false), defaultName)
        XCTAssertEqual(NewCourseWizardView.nameToWrite(typed: "\u{0}\u{202E}", isClub: false), defaultName)
        XCTAssertEqual(
            scalars(of: NewCourseWizardView.nameToWrite(typed: "Physics 11\u{0}", isClub: false)),
            scalars(of: "Physics 11")
        )
    }

    /// The New Course window cleans the name before it writes it.
    func testTheNewCourseWindowWritesTheNameCleaned() throws {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "SPH3U", prepopulatesExampleContent: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "SPH3U", name: "Physics\n\u{202E}11"
        )
        let written: String = try XCTUnwrap(configuration["course_name"] as? String)
        XCTAssertEqual(scalars(of: written), scalars(of: "Physics 11"))
    }

    /// #707's unit-plan names collapse white space after the same rule, so a
    /// NUL or an override in a plan's name is gone from the greeting too.
    func testAUnitPlanNameMeetsTheSameRule() {
        XCTAssertEqual(scalars(of: UnitPlans.oneLine("Forces\u{0}and\u{202E} Motion\n")), scalars(of: "Forces and Motion"))
        XCTAssertEqual(scalars(of: UnitPlans.oneLine("  Waves \t and\r\nSound ")), scalars(of: "Waves and Sound"))
    }

    // MARK: - The trail

    /// Each `trailLines` case through the writer the app uses, read back from
    /// the file: cleaned, then redacted, and one line unless it is the
    /// assistant's turn record.
    func testEveryTrailLineCaseIsWrittenAsTheContractSays() throws {
        let trail: [String: Any] = try XCTUnwrap(rule["trailLines"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(trail["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 14)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let line: String = try XCTUnwrap(testCase["line"] as? String, name)
            let keepsLineBreaks: Bool = try XCTUnwrap(testCase["keepsLineBreaks"] as? Bool, name)
            let written: [String] = try XCTUnwrap(testCase["written"] as? [String], name)

            let folder: URL = scratchFolderURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let store: ProblemReportStore = ProblemReportStore(folderURL: folder)
            store.appendActivityLine(line, keepingLineBreaks: keepsLineBreaks)
            let onDisk: String = try String(
                contentsOf: folder.appendingPathComponent(ProblemReportStore.activityFileName), encoding: .utf8
            )
            XCTAssertEqual(scalars(of: onDisk), scalars(of: written.joined(separator: "\n") + "\n"), name)
        }
    }

    /// Redacting a line again changes nothing, which is what lets the trail
    /// writer redact both before and after it cleans.
    func testRedactingTwiceChangesNothing() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: CourseNameCharactersTests.repositoryRoot().appendingPathComponent("contracts/shared-rules.json"))
            ) as? [String: Any]
        )
        let redaction: [String: Any] = try XCTUnwrap(rules["problemReportRedaction"] as? [String: Any])
        let again: [String: Any] = try XCTUnwrap(redaction["redactedAgainCases"] as? [String: Any])
        let cases: [[String: String]] = try XCTUnwrap(again["cases"] as? [[String: String]])
        XCTAssertFalse(cases.isEmpty)
        for testCase in cases {
            let input: String = try XCTUnwrap(testCase["input"])
            let expect: String = try XCTUnwrap(testCase["expect"])
            XCTAssertEqual(LogRedactor.redacting(input), expect, input)
        }
    }

    /// The turn record is one line whatever the model put in an argument's
    /// name, because it is written with its line breaks kept.
    func testATurnRecordIsOneLine() {
        let record: AssistTurnRecord = AssistTurnRecord(
            at: Date(timeIntervalSince1970: 1_786_000_000), courseCode: "ICS3U", sectionNumber: 1,
            toolName: "publish_pages", argumentNames: ["course\n2026-11-12 09:00:00 · forged"],
            seconds: 1.0, completionTokens: nil, stoppedAtGate: false
        )
        XCTAssertFalse(record.lines.contains("\n"), record.lines)
        XCTAssertTrue(record.lines.contains("chose publish_pages(course 2026-11-12 09:00:00 · forged)"), record.lines)
    }

    /// `ActivityTrail.note` keeps line breaks only for a whole-line record.
    func testOnlyAWholeLineRecordKeepsItsLineBreaks() throws {
        ActivityTrail.note(.assistantAsked, "first\nsecond", wholeLine: true)
        ActivityTrail.note(.taskStarted, "ICS3U/1 · started \"Day 1\nforged\"")
        let onDisk: String = try String(
            contentsOf: scratchFolderURL.appendingPathComponent(ProblemReportStore.activityFileName), encoding: .utf8
        )
        let lines: [String] = onDisk.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4, onDisk)
        XCTAssertEqual(lines[0], "first")
        XCTAssertEqual(lines[1], "second")
        XCTAssertTrue(lines[2].hasSuffix(" · ICS3U/1 · started \"Day 1 forged\""), lines[2])
        XCTAssertEqual(lines[3], "")
    }

    /// The teacher's sentence is one line behind the marker, so a report
    /// with the prompts left out leaves out every word of it.
    func testTheTeachersSentenceStaysBehindItsMarker() throws {
        let trail: [String: Any] = try XCTUnwrap(rule["trailLines"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(trail["promptCases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let prompt: String = try XCTUnwrap(testCase["prompt"] as? String, name)
            let askedLine: String = try XCTUnwrap(testCase["askedLine"] as? String, name)

            let record: String = AssistTurnRecord.askedLines(
                prompt: prompt, courseCode: "ICS3U", sectionNumber: 1,
                at: Date(timeIntervalSince1970: 1_786_000_000),
                timeZone: TimeZone(identifier: "UTC") ?? TimeZone.current
            )
            let folder: URL = scratchFolderURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let store: ProblemReportStore = ProblemReportStore(folderURL: folder)
            store.appendActivityLine(record, keepingLineBreaks: true)
            let onDisk: String = try String(
                contentsOf: folder.appendingPathComponent(ProblemReportStore.activityFileName), encoding: .utf8
            )
            let lines: [String] = onDisk.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 3, name)
            XCTAssertEqual(scalars(of: lines[1]), scalars(of: askedLine), name)

            let withoutPrompts: String = store.activityText(includingPrompts: false)
            XCTAssertFalse(withoutPrompts.contains("tomorrow"), "\(name): \(withoutPrompts)")
        }
    }

    // MARK: - Functions

    nonisolated private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func scalars(of text: String) -> [UInt32] {
        var values: [UInt32] = []
        for scalar in text.unicodeScalars {
            values.append(scalar.value)
        }
        return values
    }

    private func ranges(named key: String) throws -> [ClosedRange<UInt32>] {
        let pairs: [[String]] = try XCTUnwrap(rule[key] as? [[String]], key)
        var result: [ClosedRange<UInt32>] = []
        for pair in pairs {
            XCTAssertEqual(pair.count, 2, key)
            let low: UInt32 = try XCTUnwrap(UInt32(pair[0], radix: 16), key)
            let high: UInt32 = try XCTUnwrap(UInt32(pair[1], radix: 16), key)
            result.append(low...high)
        }
        return result
    }

    private func isInside(_ value: UInt32, _ ranges: [ClosedRange<UInt32>]) -> Bool {
        for range in ranges {
            if range.contains(value) {
                return true
            }
        }
        return false
    }
}
