import XCTest
@testable import QuartzTeachers

/// The deploy tokens in Plantoir ▸ Settings ▸ Deploying (#696):
/// `contracts/shared-rules.json` → `deployTokens` (`words`, `endDate.cases`,
/// `endDate.marker.cases`, `answerShape`, `trail.lines`), run rather than
/// retyped, and the pane's model driven through a stand-in launcher. The
/// launcher's own half is `scripts/test_deploy_tokens.py`.
@MainActor
final class DeployTokenTests: XCTestCase {

    // MARK: - Functions

    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("deployTokens")
    }

    static func instant(_ text: String) throws -> Date {
        return try XCTUnwrap(DeployTokenEndDate.instant(from: text), text)
    }

    /// A trail of the test's own, put back afterwards.
    func useATrailOfItsOwn() throws -> () -> String {
        let previous: ProblemReportStore = ActivityTrail.store
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deploy-token-trail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        ActivityTrail.store = ProblemReportStore(folderURL: folder)
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previous
            }
            try? FileManager.default.removeItem(at: folder)
        }
        return {
            return ActivityTrail.store.activityText(includingPrompts: true)
        }
    }

    // MARK: - Tests: the contract

    func testTheWordingIsTheContractsKeyByKey() throws {
        let words: [String: String] = try XCTUnwrap(try DeployTokenTests.section()["words"] as? [String: String])
        XCTAssertEqual(words, DeployTokenWording.everyKey)
    }

    func testTheTrailLinesAreTheContracts() throws {
        let trail: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["trail"] as? [String: Any])
        let lines: [String: String] = try XCTUnwrap(trail["lines"] as? [String: String])
        XCTAssertEqual(lines, DeployTokenPanel.trailLines)
    }

    func testEveryEndDateCase() throws {
        let endDate: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["endDate"] as? [String: Any])
        XCTAssertEqual(endDate["warningDays"] as? Int, DeployTokenEndDate.warningDays)
        let cases: [[String: Any]] = try XCTUnwrap(endDate["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let endsOn: String? = testCase["endsOn"] as? String
            let now: Date = try DeployTokenTests.instant(try XCTUnwrap(testCase["now"] as? String))
            let zone: TimeZone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(testCase["timeZone"] as? String)), name)
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let reading: DeployTokenEndDate.Reading = DeployTokenEndDate.reading(endsOn: endsOn, now: now, timeZone: zone)
            XCTAssertEqual(reading.state.rawValue, expect["state"] as? String, name)
            XCTAssertEqual(reading.localDate, expect["localDate"] as? String, name)
            XCTAssertEqual(reading.daysLeft, expect["daysLeft"] as? Int, name)
        }
    }

    func testEveryMarkerCase() throws {
        let endDate: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["endDate"] as? [String: Any])
        let marker: [String: Any] = try XCTUnwrap(endDate["marker"] as? [String: Any])
        XCTAssertEqual(marker["prefix"] as? String, DeployTokenEndReport.markerPrefix)
        let cases: [[String: Any]] = try XCTUnwrap(marker["cases"] as? [[String: Any]])
        for testCase in cases {
            let line: String = try XCTUnwrap(testCase["line"] as? String)
            let said: String?? = DeployTokenEndReport.endsOn(in: "before\n" + line + "\nafter")
            if let expect = testCase["expect"] as? [String: Any] {
                let wanted: String? = expect["endsOn"] as? String
                XCTAssertEqual(said, .some(wanted), line)
            } else {
                XCTAssertNil(said, line)
            }
        }
    }

    func testTheExampleAnswerParsesAndEveryProblemHasASentence() throws {
        let shape: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["answerShape"] as? [String: Any])
        let example: String = try XCTUnwrap(shape["example"] as? String)
        let answer: DeployTokenAnswer = try XCTUnwrap(DeployTokenAnswer.parse("noise\n" + example + "\n"))
        XCTAssertTrue(answer.saved)
        XCTAssertEqual(answer.endsOn, "2027-07-01T00:00:00Z")
        let problems: [String: String] = try XCTUnwrap(shape["problems"] as? [String: String])
        for destination in DeployTokenDestination.allCases {
            for key in problems.keys {
                let refused: DeployTokenAnswer = DeployTokenAnswer(
                    saved: false, answer: "refused", endsOn: nil, problem: key, unreachable: []
                )
                let sentence: String? = DeployTokenWording.sheetProblem(for: refused, destination: destination)
                if key == "tokenCannotReachSites" {
                    XCTAssertNil(sentence, "that one is the question, not a sentence")
                } else {
                    let said: String = try XCTUnwrap(sentence, key)
                    XCTAssertFalse(said.contains("{"), "\(key): \(said)")
                }
                let line: String = DeployTokenWording.statusLine(
                    for: refused, destination: destination, now: Date(), timeZone: TimeZone(identifier: "UTC")!
                )
                XCTAssertFalse(line.contains("{"), "\(key): \(line)")
            }
        }
    }

    func testTheStatusLinesForEachAnswer() throws {
        let utc: TimeZone = TimeZone(identifier: "UTC")!
        let now: Date = try DeployTokenTests.instant("2027-03-01T12:00:00Z")
        let english: Locale = Locale(identifier: "en_CA")
        func line(_ answer: String, _ endsOn: String? = nil, _ problem: String? = nil, _ destination: DeployTokenDestination = .cloudflare) -> String {
            return DeployTokenWording.statusLine(
                for: DeployTokenAnswer(saved: answer != "notSaved", answer: answer, endsOn: endsOn, problem: problem, unreachable: []),
                destination: destination, now: now, timeZone: utc, locale: english
            )
        }
        XCTAssertEqual(line("accepted", nil, nil, .netlify), DeployTokenWording.filled(DeployTokenWording.statusConnected, ["service": "Netlify"]))
        let date: String = DeployTokenWording.shownDate(try DeployTokenTests.instant("2027-07-01T00:00:00Z"), in: utc, locale: english)
        XCTAssertEqual(line("accepted", "2027-07-01T00:00:00Z"),
                       DeployTokenWording.filled(DeployTokenWording.statusConnectedEndsOn, ["service": "Cloudflare", "date": date]))
        let soon: String = DeployTokenWording.shownDate(try DeployTokenTests.instant("2027-03-20T00:00:00Z"), in: utc, locale: english)
        XCTAssertEqual(line("accepted", "2027-03-20T00:00:00Z"),
                       DeployTokenWording.filled(DeployTokenWording.statusConnectedEndsSoon, ["service": "Cloudflare", "date": soon]))
        XCTAssertEqual(line("notSaved"), DeployTokenWording.filled(DeployTokenWording.statusNotConnected, ["service": "Cloudflare"]))
        XCTAssertEqual(line("refused", nil, "tokenExpired"), DeployTokenWording.statusExpired)
        XCTAssertEqual(line("unheard"), DeployTokenWording.filled(DeployTokenWording.statusUnheard, ["service": "Cloudflare"]))
    }

    func testTheDeployScreenWarnsOnlyUnderThirtyDays() throws {
        let toronto: TimeZone = TimeZone(identifier: "America/Toronto")!
        let ends: String = "2027-07-01T00:00:00Z"
        XCTAssertNil(DeployTokenWording.deployScreenWarning(
            rememberedEndsOn: ends, now: try DeployTokenTests.instant("2027-05-31T16:00:00Z"), timeZone: toronto))
        let soon: String = try XCTUnwrap(DeployTokenWording.deployScreenWarning(
            rememberedEndsOn: ends, now: try DeployTokenTests.instant("2027-06-01T16:00:00Z"), timeZone: toronto))
        XCTAssertTrue(soon.hasPrefix("The Cloudflare token ends on "), soon)
        let ended: String = try XCTUnwrap(DeployTokenWording.deployScreenWarning(
            rememberedEndsOn: ends, now: try DeployTokenTests.instant("2027-07-02T00:00:00Z"), timeZone: toronto))
        XCTAssertTrue(ended.hasPrefix("The Cloudflare token ended on "), ended)
        XCTAssertNil(DeployTokenWording.deployScreenWarning(rememberedEndsOn: "", now: Date(), timeZone: toronto))
    }

    func testTheLaunchersArguments() throws {
        let mode: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["launcherMode"] as? [String: Any])
        XCTAssertNotNil(mode["arguments"] as? String)
        XCTAssertEqual(DeployTokenLauncher.arguments(action: "status", destination: .netlify, accountID: "0123456789abcdef0123456789abcdef"),
                       ["--token", "status", "--target", "netlify"])
        XCTAssertEqual(DeployTokenLauncher.arguments(action: "save", destination: .cloudflare, accountID: " 0123456789abcdef0123456789abcdef ", useAnyway: true),
                       ["--token", "save", "--target", "cloudflare", "--account", "0123456789abcdef0123456789abcdef", "--use-anyway"])
        XCTAssertEqual(DeployTokenLauncher.arguments(action: "remove", destination: .cloudflare, accountID: ""),
                       ["--token", "remove", "--target", "cloudflare"])
    }

    // MARK: - Tests: the pane's model

    func testANewTokenThatCannotReachTheWebsitesIsKeptOnlyWhenTheTeacherSaysSo() async throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .netlify)
        var calls: [(arguments: [String], input: String?)] = []
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        panel.runLauncher = { _, arguments, input in
            calls.append((arguments: arguments, input: input))
            if arguments.contains("--use-anyway") {
                return DeployTokenAnswer(saved: true, answer: "accepted", endsOn: nil, problem: nil, unreachable: [])
            }
            return DeployTokenAnswer(saved: false, answer: "accepted", endsOn: nil, problem: "tokenCannotReachSites", unreachable: ["ICS3U/2", "ICS3U/3"])
        }
        panel.isShowingChange = true
        await panel.save(pasted: "invented-token")
        XCTAssertEqual(panel.unreachablePlaces, ["ICS3U/2", "ICS3U/3"])
        XCTAssertTrue(panel.isShowingChange, "the sheet stays open behind the question")
        XCTAssertNil(panel.sheetProblem)

        let task: Task<Void, Never>? = panel.useTheNewTokenAnyway()
        XCTAssertFalse(panel.isAskingAboutUnreachable, "the question closes at once")
        await task?.value
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].arguments.contains("--use-anyway"))
        XCTAssertEqual(calls[1].input, "invented-token")
        XCTAssertFalse(panel.isShowingChange)
        XCTAssertTrue(trail().contains("changed the Netlify token, though it cannot reach 2 class website(s)"), trail())
        XCTAssertFalse(trail().contains("invented-token"), "the token never reaches the trail")
    }

    func testKeepMyOldTokenChangesNothing() async throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .cloudflare)
        var calls: Int = 0
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        panel.runLauncher = { _, _, _ in
            calls += 1
            return DeployTokenAnswer(saved: false, answer: "accepted", endsOn: nil, problem: "tokenCannotReachSites", unreachable: ["MPM2D/3"])
        }
        panel.isShowingChange = true
        await panel.save(pasted: "invented-token")
        panel.keepTheOldToken()
        XCTAssertEqual(calls, 1, "nothing more is asked")
        XCTAssertFalse(panel.isShowingChange)
        XCTAssertNil(panel.useTheNewTokenAnyway(), "nothing is held after Keep")
        XCTAssertTrue(trail().contains("kept the old Cloudflare token: the new one cannot reach 1 class website(s)"), trail())
    }

    func testARefusedTokenKeepsTheSheetOpenWithItsReason() async throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .cloudflare)
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        panel.runLauncher = { _, _, _ in
            return DeployTokenAnswer(saved: false, answer: "refused", endsOn: nil, problem: "tokenCannotUseAccount", unreachable: [])
        }
        panel.isShowingChange = true
        await panel.save(pasted: "invented-token")
        XCTAssertTrue(panel.isShowingChange)
        XCTAssertEqual(panel.sheetProblem, DeployTokenWording.problemTokenCannotUseAccount)
        XCTAssertTrue(trail().contains("a new Cloudflare token was not saved: tokenCannotUseAccount"), trail())
    }

    func testALauncherThatDoesNotAnswerIsReadAsCouldNotBeChecked() async throws {
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .netlify)
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        panel.runLauncher = { _, _, _ in
            return nil
        }
        await panel.check()
        XCTAssertEqual(panel.status, .answered(DeployTokenPanel.notAnswered))
        XCTAssertFalse(panel.hasSavedToken)
    }

    func testNoWorkingFolderSaysSo() async throws {
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .netlify)
        panel.findWorkingFolder = {
            return nil
        }
        await panel.check()
        XCTAssertEqual(panel.status, .noWorkingFolder)
        XCTAssertEqual(panel.statusLine(), DeployTokenWording.statusNoWorkingFolder)
    }

    // MARK: - Tests: the runner, against a stand-in launcher

    /// The real runner, with a stand-in deploy.sh that answers with what it
    /// was given: the token arrives on standard input, never in the
    /// arguments.
    func testTheRunnerHandsTheTokenOverOnStandardInputOnly() async throws {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deploy-token-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        let script: String = """
        #!/bin/bash
        given="$(cat)"
        arguments="$*"
        if [[ "$arguments" == *invented* ]]; then echo '{"saved":false,"answer":"unheard","endsOn":null,"problem":"inArguments","unreachable":[]}'; exit 0; fi
        if [[ "$given" == "invented-token" ]]; then echo '{"saved":true,"answer":"accepted","endsOn":null,"problem":null,"unreachable":[]}'; exit 0; fi
        echo '{"saved":false,"answer":"refused","endsOn":null,"problem":"tokenRefused","unreachable":[]}'
        """
        try script.write(to: folder.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8)
        let answer: DeployTokenAnswer? = await DeployTokenLauncher.run(
            workingFolder: folder,
            arguments: DeployTokenLauncher.arguments(action: "save", destination: .netlify, accountID: ""),
            input: "invented-token"
        )
        XCTAssertEqual(answer?.saved, true)
        XCTAssertEqual(answer?.problem, nil)
    }

    // MARK: - Tests: the scan

    /// The pane and the Deploy screen say nothing about tokens that is not a
    /// `DeployTokenWording` sentence, and nothing names the machinery.
    func testThePaneNamesNoMachinery() throws {
        let views: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
        let files: [String] = [
            "Views/Settings/DeployTokenRows.swift",
            "Views/Section/DeployTokenEndNoticeView.swift",
            "Models/DeployTokens/DeployTokenWording.swift",
        ]
        var sentences: [String] = []
        for value in DeployTokenWording.everyKey.values {
            sentences.append(value)
        }
        for value in DeployTokenPanel.trailLines.values {
            sentences.append(value)
        }
        for sentence in sentences {
            for word in ["Keychain", "keychain", "launcher", "script", "deploy.sh", "JSON"] {
                XCTAssertFalse(sentence.contains(word), "\(word) in \(sentence)")
            }
        }
        for file in files {
            let text: String = try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("Text(\"Connected"), "\(file) spells a status line itself")
        }
    }
}
