import XCTest
@testable import QuartzTeachers

/// Sharing a course's unit plans (#709): the share bar's rules, its words,
/// the launcher's arguments and the trail, every one from the contract
/// (contracts/shared-rules.json → unitPlanning.share; app-rules.json →
/// deployArguments.planShareCases; activityTrail.mustRecord). The shared
/// Python's half is scripts/test_unit_plan_site.py, test_share_plan.py and
/// test_deploy_sh_plans.py.
@MainActor
final class PlanSharingTests: XCTestCase {

    // MARK: - Stored properties

    private var previousStore: ProblemReportStore = ActivityTrail.store
    private var scratchFolderURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        scratchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-sharing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL.appendingPathComponent("trail"))
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        try? FileManager.default.removeItem(at: scratchFolderURL)
    }

    // MARK: - Functions

    private static func contract(_ name: String) throws -> [String: Any] {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts", isDirectory: true)
        let data: Data = try Data(contentsOf: contracts.appendingPathComponent(name + ".json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func share() throws -> [String: Any] {
        let planning: [String: Any] = try XCTUnwrap(try contract("shared-rules")["unitPlanning"] as? [String: Any])
        return try XCTUnwrap(planning["share"] as? [String: Any])
    }

    private static func cases(_ key: String) throws -> [[String: Any]] {
        let section: [String: Any] = try XCTUnwrap(try share()[key] as? [String: Any])
        return try XCTUnwrap(section["cases"] as? [[String: Any]])
    }

    /// A case's `marker`: true, false, or JSON null.
    private static func markerValue(_ testCase: [String: Any]) -> Bool? {
        return testCase["marker"] as? Bool
    }

    private func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Tests: the contract's words and cases

    func testEveryWordIsTheContractsOwn() throws {
        let words: [String: String] = try XCTUnwrap(try PlanSharingTests.share()["words"] as? [String: String])
        XCTAssertEqual(Set(words.keys), Set(PlanSharingWording.byKey.keys))
        for (key, value) in PlanSharingWording.byKey {
            XCTAssertEqual(words[key], value, key)
        }
    }

    func testTheWordsNameNoMachinery() {
        for (key, value) in PlanSharingWording.byKey {
            if key == "netlifyTeacher" {
                // The one sentence that names the Cloudflare token the
                // launcher asks for, as the deploy sheet's own steps do.
                continue
            }
            for word in ["token", "worker", " api", "script", "container", "docker"] {
                XCTAssertFalse(value.lowercased().contains(word), "\(key) says \(word)")
            }
        }
    }

    func testEveryModeCase() throws {
        for testCase in try PlanSharingTests.cases("modeCases") {
            let flag: String? = testCase["flag"] as? String
            XCTAssertEqual(
                PlanSharing.isProtected(markerAskedForProtection: PlanSharingTests.markerValue(testCase), flag: flag),
                testCase["protected"] as? Bool,
                "\(testCase)"
            )
        }
    }

    func testEveryWarningCase() throws {
        for testCase in try PlanSharingTests.cases("warningCases") {
            let choice: PlanSharing.Choice = try XCTUnwrap(PlanSharing.Choice(rawValue: try XCTUnwrap(testCase["choice"] as? String)))
            XCTAssertEqual(
                PlanSharing.warns(markerAskedForProtection: PlanSharingTests.markerValue(testCase), choice: choice),
                testCase["warn"] as? Bool,
                "\(testCase)"
            )
        }
    }

    func testEveryPlanShareArgumentCase() throws {
        let deployArguments: [String: Any] = try XCTUnwrap(try PlanSharingTests.contract("app-rules")["deployArguments"] as? [String: Any])
        let section: [String: Any] = try XCTUnwrap(deployArguments["planShareCases"] as? [String: Any])
        let planCases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(planCases.count, 8)
        for testCase in planCases {
            let choice: PlanSharing.Choice = try XCTUnwrap(PlanSharing.Choice(rawValue: try XCTUnwrap(testCase["choice"] as? String)))
            let arguments: [String] = PlanSharing.arguments(
                courseCode: try XCTUnwrap(testCase["course"] as? String),
                choice: choice,
                includeAnswerKeys: testCase["includeAnswerKeys"] as? Bool ?? false,
                year: testCase["year"] as? Int,
                cloudflareAccountID: testCase["account"] as? String ?? ""
            )
            XCTAssertEqual(arguments, testCase["expect"] as? [String], "\(testCase)")
        }
    }

    func testTheArgumentsNeverCarryAPassword() {
        for choice in PlanSharing.Choice.allCases {
            let arguments: [String] = PlanSharing.arguments(
                courseCode: "SNC2D", choice: choice, includeAnswerKeys: true, year: 2026, cloudflareAccountID: ""
            )
            for argument in arguments {
                XCTAssertFalse(argument.contains(":"), "an argument shaped like username:password")
            }
        }
    }

    // MARK: - Tests: the markers

    /// unitPlanning.share.barCases: the bar never says more than the site
    /// does (review H1), and says when an older copy may still answer (M2).
    func testEveryBarCase() throws {
        for testCase in try PlanSharingTests.cases("barCases") {
            var marker: PlanSharing.Marker?
            if let object = testCase["marker"] as? [String: Any] {
                let data: Data = try JSONSerialization.data(withJSONObject: object)
                marker = PlanSharing.marker(from: data, year: 2026)
            }
            XCTAssertEqual(PlanSharing.barStatus(for: marker).rawValue, testCase["bar"] as? String, "\(testCase)")
            XCTAssertEqual(PlanSharing.showsOldCopies(marker), testCase["oldCopiesLine"] as? Bool, "\(testCase)")
        }
    }

    func testTheInterruptionCasesNameOnlyBarsTheBarKnows() throws {
        for testCase in try PlanSharingTests.cases("interruptionCases") {
            let bar: String = try XCTUnwrap(testCase["bar"] as? String)
            XCTAssertNotNil(PlanSharing.BarStatus(rawValue: bar), bar)
        }
    }

    func testTheOldCopySentenceIsTheContractsRefusal() throws {
        let refusals: [String: Any] = try XCTUnwrap(try PlanSharingTests.share()["refusals"] as? [String: Any])
        XCTAssertEqual(refusals["oldCopyStillThere"] as? String, PlanSharingWording.oldCopyStillThere)
    }

    func testOnlyAYearsOwnMarkerIsRead() {
        XCTAssertEqual(PlanSharing.year(inMarkerName: "plans-2026.json"), 2026)
        XCTAssertNil(PlanSharing.year(inMarkerName: "plans-2026.previous-2026-11-12_101010.json"))
        XCTAssertNil(PlanSharing.year(inMarkerName: "plans-26.json"))
        XCTAssertNil(PlanSharing.year(inMarkerName: "section1.json"))
    }

    func testEveryYearIsReadNewestFirstAndAHalfWrittenMarkerIsNot() throws {
        let course: URL = scratchFolderURL.appendingPathComponent("SNC2D", isDirectory: true)
        let folder: URL = course.appendingPathComponent(".cloudflare_sites", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let whole: String = """
            {"name": "snc2d-plans-2026-27-x-abcd1234", "subdomain": "snc2d-plans-2026-27-x-abcd1234.pages.dev",
             "address": "https://snc2d-plans-2026-27-x-abcd1234.pages.dev/", "year": 2026, "asked": "protected",
             "protected": true, "failClosed": false, "answerKeys": "in", "answerKeysLeftOut": 0,
             "lastShared": "2026-11-12T20:00:00Z", "units": 3, "oldCopies": 0}
            """
        try whole.write(to: folder.appendingPathComponent("plans-2026.json"), atomically: true, encoding: .utf8)
        try whole.replacingOccurrences(of: "2026-27", with: "2025-26")
            .write(to: folder.appendingPathComponent("plans-2025.json"), atomically: true, encoding: .utf8)
        try #"{"name": "x", "subdomain": "x.pages.dev", "year": 2027}"#
            .write(to: folder.appendingPathComponent("plans-2027.json"), atomically: true, encoding: .utf8)
        let markers: [PlanSharing.Marker] = PlanSharing.markers(courseDirectory: course)
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers.first?.year, 2026)
        XCTAssertEqual(markers.first?.units, 3)
        XCTAssertEqual(markers.first?.yearLabel, "2026-27")
        let first: PlanSharing.Marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(PlanSharing.floodSentence(for: first), PlanSharingWording.floodOpen)
        var closed: PlanSharing.Marker = first
        closed.failClosed = true
        XCTAssertEqual(PlanSharing.floodSentence(for: closed), PlanSharingWording.floodClosed)
        closed.isProtected = false
        XCTAssertNil(PlanSharing.floodSentence(for: closed))
    }

    func testAReferenceCopyMovesEveryYearsMarkerAside() throws {
        let course: URL = scratchFolderURL.appendingPathComponent("SNC2D", isDirectory: true)
        let folder: URL = course.appendingPathComponent(".cloudflare_sites", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "{}".write(to: folder.appendingPathComponent("plans-2026.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: folder.appendingPathComponent("plans-2025.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: folder.appendingPathComponent("section1.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(PlanSharing.releasePlanMarkers(courseDirectory: course), 0)
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(names.contains("plans-2026.json"))
        XCTAssertFalse(names.contains("plans-2025.json"))
        XCTAssertTrue(names.contains("section1.json"), "a section's marker is releaseSite's, not this")
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(PlanSharing.markers(courseDirectory: course).isEmpty)
    }

    // MARK: - Tests: the trail

    func testTheThreeEventsAreTheContracts() throws {
        let trail: [String: Any] = try XCTUnwrap(try PlanSharingTests.contract("shared-rules")["activityTrail"] as? [String: Any])
        let required: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        var names: [String] = []
        for entry in required {
            names.append(entry["event"] as? String ?? "")
        }
        for event in [ActivityTrail.Event.unitPlansShared, .unitPlanShareRefused, .unitPlanSharingStopped, .unitPlanPasswordChanged] {
            XCTAssertTrue(names.contains(event.rawValue), event.rawValue)
        }
    }

    /// Through the real runner, as the share sheet runs it: the lines reach
    /// the trail without the address, and never the console.
    func testARunRecordsEachMarkerWithoutTheAddress() throws {
        let runner: ScriptRunner = ScriptRunner()
        let address: String = "https://snc2d-plans-2026-27-gordon-k3x9qa8m.pages.dev/"
        runner.receiveOutput("PLANTOIR_PLAN_SHARED: SNC2D 2026 \(address) protected:yes failClosed:yes answerKeys:in units:3 oldCopies:0\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_SHARED: AP+CALC 2026 \(address) protected:no failClosed:yes answerKeys:out units:1 oldCopies:1\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_REFUSED: SNC2D checkFound 4\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_STOPPED: SNC2D 2025 \(address) failed\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_STOPPED: SNC2D 2024 \(address) unconfirmed\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_SHARED: MPM2D 2026 \(address) protected:no failClosed:yes answerKeys:out units:2 oldCopies:0 documents:5 heldBack:2\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_PASSWORD_SAVED: SNC2D 2026 waiting\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_PASSWORD_SAVED: MPM2D 2026 notShared\r\n")
        XCTAssertFalse(runner.transcript.displayText.contains("PLANTOIR_PLAN_"))
        let trail: String = trailText()
        XCTAssertFalse(trail.contains("k3x9qa8m"), "the address reached the trail")
        XCTAssertTrue(trail.contains(
            "SNC2D · unit plans for 2026-27 shared to Cloudflare Pages, 3 units, with a password, the plans close if flooded"
        ), trail)
        XCTAssertTrue(trail.contains(
            "AP CALC · unit plans for 2026-27 shared to Cloudflare Pages, 1 unit, open to anyone with the link, "
                + "answer keys left out, an earlier copy could not be removed"
        ), trail)
        XCTAssertTrue(trail.contains("SNC2D · unit plans not shared: 4 thing(s) in them needed fixing first"), trail)
        XCTAssertTrue(trail.contains("SNC2D · stopped sharing the 2025-26 unit plans (failed, so the address still works)"), trail)
        XCTAssertTrue(trail.contains("SNC2D · stopped sharing the 2024-25 unit plans (not confirmed, so the address may still work)"), trail)
        XCTAssertTrue(trail.contains(
            "MPM2D · unit plans for 2026-27 shared to Cloudflare Pages, 2 units, open to anyone with the link, "
                + "answer keys left out, 5 document(s) shared and 2 held back"
        ), trail)
        XCTAssertTrue(trail.contains("SNC2D · new password saved for the 2026-27 unit plans, not in use until they are shared again"), trail)
        XCTAssertTrue(trail.contains("MPM2D · new password saved for the 2026-27 unit plans, nothing shared yet"), trail)
        XCTAssertEqual(runner.planPasswordSaved, "notShared", "the last line the run printed")
    }

    func testALineThatIsNotAMarkersShapeReportsNothing() {
        XCTAssertTrue(PlanShareReport.lines(in: "PLANTOIR_PLAN_SHARED: SNC2D 2026 https://x/ protected:yes\n").isEmpty)
        XCTAssertTrue(PlanShareReport.lines(in: "PLANTOIR_PLAN_REFUSED: /Users/somebody/x checkFound 1\n").isEmpty)
        XCTAssertTrue(PlanShareReport.lines(in: "PLANTOIR_PLAN_REFUSED: SNC2D aKeyNobodyKnows\n").isEmpty)
    }

    func testEveryRefusalKeyTheContractNamesHasAReason() throws {
        let refusals: [String: Any] = try XCTUnwrap(try PlanSharingTests.share()["refusals"] as? [String: Any])
        for key in refusals.keys {
            if key == "notToAFolder" || key == "netlifyNever" || key == "oldCopyStillThere" {
                // Said by the launcher before anything runs, or alongside a
                // share that went ahead: no refusal marker carries them.
                continue
            }
            XCTAssertNotNil(PlanShareReport.reasons[key], key)
        }
    }

    // MARK: - Tests: the lists before every share (#709, #833)

    func testTheListsSheetsWordsAndMarkersAreTheContracts() throws {
        let section: [String: Any] = try XCTUnwrap(try PlanSharingTests.share()["openShareLists"] as? [String: Any])
        XCTAssertEqual(section["sheetTitle"] as? String, PlanSharingWording.listsSheetTitle)
        XCTAssertEqual(section["byName"] as? String, PlanSharingWording.listsByName)
        XCTAssertEqual(section["shareButton"] as? String, PlanSharingWording.listsShareButton)
        for key in ["question", "questionProtected"] {
            let question: String = try XCTUnwrap(section[key] as? String)
            XCTAssertTrue(PlanShareLists.isTheListsQuestion(
                ScriptRunner.separateDefaultAnswer(from: question.trimmingCharacters(in: .whitespaces)).question
            ), key)
        }
        let markers: [String: Any] = try XCTUnwrap(section["markers"] as? [String: Any])
        XCTAssertEqual(markers["begin"] as? String, PlanShareLists.beginMarker)
        XCTAssertEqual(markers["document"] as? String, PlanShareLists.documentMarker)
        XCTAssertEqual(markers["end"] as? String, PlanShareLists.endMarker)
        XCTAssertNil(markers["shared"], "the #709 lines are not printed since #833")
    }

    /// The tables show what the launcher printed: its marker lines, read
    /// through the real runner, and none of it reaches the console.
    func testTheSheetsRowsAreTheLaunchersMarkerLines() throws {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("PLANTOIR_PLAN_LISTS_BEGIN: 2026 protected:no tick:yes ownFiles:14\r\nThese files will be shared with anyone who has the address:\r\n")
        runner.receiveOutput("   • unit/pdfs/Quiz 1, Part A.pdf\r\n")
        runner.receiveOutput(#"PLANTOIR_PLAN_LISTS_DOCUMENT: {"place": "unit/pdfs/Quiz 1, Part A.pdf", "name": "Quiz 1, Part A.pdf", "unit": "unit", "unitOrder": 0, "folder": "pdfs", "kind": "PDF", "answerKey": null, "movable": true, "start": "shared"}"# + "\r\n")
        runner.receiveOutput(#"PLANTOIR_PLAN_LISTS_DOCUMENT: {"place": "unit/Answer Keys/R\u00e9ponses.pdf", "name": "R\u00e9ponses.pdf", "unit": "unit", "unitOrder": 0, "folder": "Answer Keys", "kind": "PDF", "answerKey": "folder", "movable": true, "start": "notShared"}"# + "\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_LISTS_DOCUMENT: not a row\r\n")
        runner.receiveOutput("PLANTOIR_PLAN_LISTS_END:\r\nShare these files with anyone who has the address? [y/N]: ")
        let lists: PlanShareLists = try XCTUnwrap(runner.planShareLists)
        XCTAssertTrue(lists.isComplete)
        XCTAssertEqual(lists.year, 2026)
        XCTAssertFalse(lists.isProtected)
        XCTAssertTrue(lists.answerKeysTicked)
        XCTAssertEqual(lists.ownFiles, 14)
        XCTAssertEqual(lists.documents.count, 2)
        XCTAssertEqual(lists.documents[1].name, "Réponses.pdf")
        XCTAssertEqual(lists.documents[1].answerKey, "folder")
        XCTAssertEqual(lists.documents[1].start, .notShared)
        XCTAssertFalse(runner.transcript.displayText.contains("PLANTOIR_PLAN_LISTS"))
    }

    /// The share's question is answered only in the tables' sheet: the
    /// plain question alert and the credential sheet never take it.
    func testTheListsQuestionCanOnlyBeAnsweredInTheListsSheet() {
        for line in ["Share these files with anyone who has the address? [y/N]:",
                     "Share these files with anyone who has the address and the password? [y/N]:"] {
            let asked = ScriptRunner.separateDefaultAnswer(from: line)
            XCTAssertTrue(PlanShareLists.isTheListsQuestion(asked.question), line)
            XCTAssertNil(CredentialRequest.matching(asked.question))
        }
        let runner: ScriptRunner = ScriptRunner()
        runner.isAwaitingInput = true
        runner.isAskingAboutPlanShareLists = true
        XCTAssertEqual(TaskProgressView.questionSurface(for: runner), .planShareLists)
        runner.pendingCredentialRequest = CredentialRequest.unitPlanPassword
        XCTAssertEqual(TaskProgressView.questionSurface(for: runner), .planShareLists)
        runner.isAskingAboutPlanShareLists = false
        runner.pendingCredentialRequest = nil
        XCTAssertEqual(TaskProgressView.questionSurface(for: runner), .plainQuestion)
        XCTAssertFalse(PlanShareLists.isTheListsQuestion("Fix course code to 'ICS3O'?"))
    }

    // MARK: - Tests: the credential requests

    func testTheAppSendsAPlansPasswordExactlyAsTyped() {
        XCTAssertEqual(CredentialRequestSheet.answerToSend("  spaced password  ", for: CredentialRequest.unitPlanPassword),
                       "  spaced password  ")
        XCTAssertEqual(CredentialRequestSheet.answerToSend("  abc  ", for: CredentialRequest.cloudflareToken), "abc")
        XCTAssertEqual(CredentialRequestSheet.answerToSend(" science ", for: CredentialRequest.unitPlanUsername), "science")
    }

    func testThePlansQuestionsAreTheirOwnRequests() {
        XCTAssertEqual(CredentialRequest.matching("Choose a username for these unit plans: ")?.name, "unitPlanUsername")
        XCTAssertEqual(CredentialRequest.matching("Choose a password for these unit plans (8 to 64 characters): ")?.name, "unitPlanPassword")
        XCTAssertEqual(CredentialRequest.matching("Please choose a password of 8 to 64 letters, digits, spaces or symbols: ")?.isSecret, true)
        XCTAssertEqual(CredentialRequest.unitPlanUsername.isSecret, false)
        XCTAssertEqual(CredentialRequest.matching("Paste Cloudflare token: ")?.name, "cloudflareToken")
    }
}
