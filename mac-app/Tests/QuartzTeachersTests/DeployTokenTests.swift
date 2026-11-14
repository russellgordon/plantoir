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

    /// Every trail line this piece writes reaches the disk as it was
    /// written (the Fable sweep's F1). The trail is redacted on the way in,
    /// so a line the redactor rewrites is a line the problem report carries
    /// changed: the old keptOld line put a colon straight after "token",
    /// lost its next word to the labelled-secret rule and read as if a
    /// token had been written down. Each line is filled with realistic
    /// invented values and handed to the redactor itself, so this follows
    /// the redactor's rules as they change rather than restating them. The
    /// five events' example lines in `activityTrail.mustRecord` are checked
    /// the same way.
    func testEveryTrailLineReachesTheDiskUnchanged() throws {
        let shape: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["answerShape"] as? [String: Any])
        let problemKeys: [String: String] = try XCTUnwrap(shape["problems"] as? [String: String])
        var problems: [String] = ["notAnswered", "unheard", "refused", "notSent"]
        for key in problemKeys.keys.sorted() {
            problems.append(key)
        }
        let kinds: [DeployTokenPanel.TrailLine] = [.changed, .changedAnyway, .removed, .refused, .keptOld]
        var filledLines: [String] = []
        for destination in DeployTokenDestination.allCases {
            for kind in kinds {
                for problem in problems {
                    for count in [1, 12] {
                        let line: String = DeployTokenPanel.trailLine(
                            kind, destination: destination, problem: problem, count: count
                        )
                        filledLines.append(line)
                    }
                }
            }
        }
        let sources: [DeployTokenEndReport.Source] = [.settings, .deploy, .scheduledDeploy]
        let endDates: [String?] = [
            "2027-07-01T00:00:00Z",
            "2027-07-01T04:00:00.000-04:00",
            "2026-12-31T23:59:59.123456789+05:30",
            nil,
        ]
        for source in sources {
            for endsOn in endDates {
                filledLines.append(DeployTokenEndReport.trailLine(endsOn: endsOn, source: source))
            }
        }

        let contractURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: contractURL)) as? [String: Any]
        )
        let activityTrail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let mustRecord: [[String: Any]] = try XCTUnwrap(activityTrail["mustRecord"] as? [[String: Any]])
        let events: [ActivityTrail.Event] = [
            .deployTokenChanged, .deployTokenRemoved, .deployTokenChangeRefused,
            .deployTokenKeptOld, .deployTokenEndDateLearned,
        ]
        var eventNames: Set<String> = []
        for event in events {
            eventNames.insert(event.rawValue)
        }
        var examplesFound: Int = 0
        for entry in mustRecord {
            guard let event = entry["event"] as? String, eventNames.contains(event) else {
                continue
            }
            let example: String = try XCTUnwrap(entry["line"] as? String, event)
            filledLines.append(example)
            examplesFound += 1
        }
        XCTAssertEqual(examplesFound, events.count, "each of the five events has its example line")

        for line in filledLines {
            XCTAssertFalse(line.contains("{"), "filled: \(line)")
            XCTAssertEqual(LogRedactor.redacting(line), line, "the redactor rewrites this trail line")
            XCTAssertEqual(
                ProblemReportStore.safeTrailLine(line, keepingLineBreaks: false), line,
                "the trail writer rewrites this trail line"
            )
        }
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
        panel.settings = AppSettings(defaults: TestDefaults.make())
        panel.status = .answered(DeployTokenAnswer(saved: true, answer: "accepted", endsOn: nil, problem: nil, unreachable: []))
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
        XCTAssertTrue(trail().contains(DeployTokenPanel.trailLine(.keptOld, destination: .cloudflare, count: 1)), trail())
    }

    func testARefusedTokenKeepsTheSheetOpenWithItsReason() async throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .cloudflare)
        panel.settings = AppSettings(defaults: TestDefaults.make())
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

    /// Review M2: a launcher that gave no answer says nothing about whether a
    /// token is saved. MUST-FAIL on ee9007303, which said "It is still saved."
    func testALauncherThatDoesNotAnswerHasItsOwnSentences() async throws {
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .netlify)
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        panel.runLauncher = { _, _, _ in
            return nil
        }
        await panel.check()
        XCTAssertEqual(panel.status, .answered(DeployTokenAnswer.notAnswered))
        XCTAssertFalse(panel.hasSavedToken)
        XCTAssertEqual(panel.statusLine(), DeployTokenWording.filled(DeployTokenWording.statusNotAnswered, ["service": "Netlify"]))
        XCTAssertEqual(
            DeployTokenWording.sheetProblem(for: DeployTokenAnswer.notAnswered, destination: .netlify),
            DeployTokenWording.problemNotAnswered
        )
    }

    /// Review W2: Cancel waits while a save is under way, so a save never
    /// lands behind a closed sheet. MUST-FAIL on ee9007303, whose Cancel
    /// closed the sheet at once.
    func testCancelWaitsWhileASaveIsUnderWay() async throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .netlify)
        panel.settings = AppSettings(defaults: TestDefaults.make())
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        var release: CheckedContinuation<Void, Never>? = nil
        panel.runLauncher = { _, _, _ in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                release = continuation
            }
            return DeployTokenAnswer(saved: true, answer: "accepted", endsOn: nil, problem: nil, unreachable: [])
        }
        panel.isShowingChange = true
        let saving: Task<Void, Never> = Task { @MainActor in
            await panel.save(pasted: "invented-token")
        }
        while release == nil {
            await Task.yield()
        }
        XCTAssertTrue(panel.isSaving)
        panel.cancelChange()
        XCTAssertTrue(panel.isShowingChange, "Cancel waits while the token is being checked")
        release?.resume()
        await saving.value
        XCTAssertFalse(panel.isShowingChange, "the sheet closes on the save it showed")
        XCTAssertEqual(panel.statusLine(), DeployTokenWording.filled(DeployTokenWording.statusConnected, ["service": "Netlify"]))
        XCTAssertTrue(trail().contains("changed the Netlify token"), trail())
    }

    /// Review M7: with no token saved before the change there is no old one
    /// to keep. MUST-FAIL on ee9007303, which offered Keep My Old Token and
    /// wrote "kept the old token".
    func testDontSaveItWhenNoTokenWasSavedBefore() async throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let panel: DeployTokenPanel = DeployTokenPanel(destination: .netlify)
        panel.settings = AppSettings(defaults: TestDefaults.make())
        panel.findWorkingFolder = {
            return URL(fileURLWithPath: "/nonexistent-working-folder")
        }
        panel.status = .answered(DeployTokenAnswer(saved: false, answer: "notSaved", endsOn: nil, problem: nil, unreachable: []))
        panel.runLauncher = { _, _, _ in
            return DeployTokenAnswer(saved: false, answer: "accepted", endsOn: nil, problem: "tokenCannotReachSites", unreachable: ["ICS3U/2"])
        }
        panel.isShowingChange = true
        await panel.save(pasted: "invented-token")
        XCTAssertEqual(panel.keepButtonTitle, DeployTokenWording.dontSaveNewToken)
        panel.keepTheOldToken()
        XCTAssertFalse(trail().contains("kept the old"), trail())
        XCTAssertTrue(trail().contains("a new Netlify token was not saved: tokenCannotReachSites"), trail())

        panel.status = .answered(DeployTokenAnswer(saved: true, answer: "accepted", endsOn: nil, problem: nil, unreachable: []))
        panel.isShowingChange = true
        await panel.save(pasted: "invented-token")
        XCTAssertEqual(panel.keepButtonTitle, DeployTokenWording.keepOldToken)
    }

    /// Review I4: the end date the Deploy screen warns from goes on the trail
    /// when it changes, with what read it, and only then. MUST-FAIL on
    /// ee9007303, which kept it silently.
    func testANewEndDateIsKeptAndWrittenOnTheTrailOnce() throws {
        let trail: () -> String = try useATrailOfItsOwn()
        let settings: AppSettings = AppSettings(defaults: TestDefaults.make())
        DeployTokenEndReport.keep(endsOn: "2027-07-01T00:00:00Z", source: .deploy, in: settings)
        XCTAssertEqual(settings.cloudflareTokenEndsOn, "2027-07-01T00:00:00Z")
        let learned: String = DeployTokenEndReport.trailLine(endsOn: "2027-07-01T00:00:00Z", source: .deploy)
        XCTAssertEqual(learned, "The Cloudflare token's end date is now 2027-07-01T00:00:00Z, as a deploy read it")
        XCTAssertTrue(trail().contains(learned), trail())
        let before: String = trail()
        DeployTokenEndReport.keep(endsOn: "2027-07-01T00:00:00Z", source: .scheduledDeploy, in: settings)
        XCTAssertEqual(trail(), before, "the same date read again writes nothing")
        DeployTokenEndReport.keep(endsOn: nil, source: .settings, in: settings)
        XCTAssertEqual(settings.cloudflareTokenEndsOn, "")
        XCTAssertTrue(trail().contains("The Cloudflare token has no end date, as Settings ▸ Deploying read it"), trail())
    }

    /// Review I5: both runners hand a deploy's output to the end-date
    /// report, each naming what read it.
    func testBothRunnersHandTheirOutputToTheEndDateReport() throws {
        let app: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
        let runner: String = try String(contentsOf: app.appendingPathComponent("Scripting/ScriptRunner.swift"), encoding: .utf8)
        XCTAssertTrue(runner.contains("DeployTokenEndReport.remember(from: text, source: .deploy)"))
        let scheduled: String = try String(contentsOf: app.appendingPathComponent("Models/ScheduledDeploy.swift"), encoding: .utf8)
        XCTAssertTrue(scheduled.contains("DeployTokenEndReport.remember(from: text, source: .scheduledDeploy)"))
    }

    /// Review I5: the Deploy screen's warning is only for a course that
    /// deploys to Cloudflare Pages.
    func testTheDeployScreenWarnsOnlyForACourseThatDeploysToCloudflare() throws {
        let toronto: TimeZone = TimeZone(identifier: "America/Toronto")!
        let soon: Date = try DeployTokenTests.instant("2027-06-01T16:00:00Z")
        let netlifyOnly: [CourseConfiguration.DeployDestination] = [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
        ]
        let both: [CourseConfiguration.DeployDestination] = [
            CourseConfiguration.DeployDestination(type: "netlify", path: ""),
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: ""),
        ]
        XCTAssertNil(SectionDetailView.deployTokenEndWarning(
            destinations: netlifyOnly, rememberedEndsOn: "2027-07-01T00:00:00Z", now: soon, timeZone: toronto))
        let warning: String = try XCTUnwrap(SectionDetailView.deployTokenEndWarning(
            destinations: both, rememberedEndsOn: "2027-07-01T00:00:00Z", now: soon, timeZone: toronto))
        XCTAssertTrue(warning.contains(DeployTokenWording.deployingSettingsOnThisPlatform), warning)
    }

    /// Review W5: the shared words carry the platform placeholders, and the
    /// mac fills them with its own. MUST-FAIL on ee9007303, whose words said
    /// "this Mac" and the Mac's menu path in the shared contract.
    func testThePlatformPlaceholdersAreTheContractsAndAreFilled() throws {
        let placeholders: [String: Any] = try XCTUnwrap(try DeployTokenTests.section()["placeholders"] as? [String: Any])
        let settingsPath: [String: String] = try XCTUnwrap(placeholders["deployingSettings"] as? [String: String])
        XCTAssertEqual(settingsPath["mac"], DeployTokenWording.deployingSettingsOnThisPlatform)
        XCTAssertTrue(DeployTokenWording.problemCouldNotSave.contains(MachineWord.placeholder))
        XCTAssertTrue(DeployTokenWording.deployScreenEnded.contains(DeployTokenWording.deployingSettingsPlaceholder))
        for (key, sentence) in DeployTokenWording.everyKey {
            XCTAssertFalse(sentence.contains("Mac"), "\(key) names the Mac in a shared sentence")
            XCTAssertFalse(sentence.contains("Plantoir ▸ Settings"), "\(key) names the Mac's menu path in a shared sentence")
            let filled: String = DeployTokenWording.filled(sentence, [:])
            XCTAssertFalse(filled.contains(MachineWord.placeholder), key)
            XCTAssertFalse(filled.contains(DeployTokenWording.deployingSettingsPlaceholder), key)
        }
        let couldNotSave: String = try XCTUnwrap(DeployTokenWording.sheetProblem(
            for: DeployTokenAnswer(saved: false, answer: "accepted", endsOn: nil, problem: "couldNotSave", unreachable: []),
            destination: .netlify))
        XCTAssertTrue(couldNotSave.hasSuffix("could not be saved on this Mac. Nothing was changed."), couldNotSave)
    }

    /// The question names a course's unit plans as unit plans, not as a
    /// section called "plans-2026".
    func testThePlacesAreNamedForATeacher() {
        XCTAssertEqual(DeployTokenWording.place("ICS3U/2"),
                       DeployTokenWording.filled(DeployTokenWording.placeSection, ["course": "ICS3U", "section": "2"]))
        XCTAssertEqual(DeployTokenWording.place("MPM2D/plans-2026"),
                       DeployTokenWording.filled(DeployTokenWording.placeUnitPlans, ["course": "MPM2D", "year": "2026"]))
    }

    /// Review M1: a token Cloudflare still accepts after its end date says
    /// so, not "less than 30 days from now".
    func testAnAcceptedTokenPastItsEndDateSaysItHasPassed() throws {
        let utc: TimeZone = TimeZone(identifier: "UTC")!
        let english: Locale = Locale(identifier: "en_CA")
        let line: String = DeployTokenWording.statusLine(
            for: DeployTokenAnswer(saved: true, answer: "accepted", endsOn: "2027-07-01T00:00:00Z", problem: nil, unreachable: []),
            destination: .cloudflare, now: try DeployTokenTests.instant("2027-07-05T00:00:00Z"), timeZone: utc, locale: english
        )
        let date: String = DeployTokenWording.shownDate(try DeployTokenTests.instant("2027-07-01T00:00:00Z"), in: utc, locale: english)
        XCTAssertEqual(line, DeployTokenWording.filled(DeployTokenWording.statusConnectedEnded, ["service": "Cloudflare", "date": date]))
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

    /// No sentence the pane, the sheet or the Deploy screen shows names the
    /// machinery, by the contract's own list (`userFacingLabelWords.forbidden`,
    /// review I5), and the token store is never named either.
    func testThePaneNamesNoMachinery() throws {
        let forbidden: [String] = try UserFacingLabelWordsTests.forbiddenWords()
        XCTAssertFalse(forbidden.isEmpty)
        for (key, sentence) in DeployTokenWording.everyKey {
            let said: String = DeployTokenWording.filled(sentence, [:])
            XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: said, from: forbidden), [], key)
            XCTAssertFalse(said.lowercased().contains("keychain"), key)
        }
        for (key, sentence) in DeployTokenPanel.trailLines {
            XCTAssertFalse(sentence.lowercased().contains("keychain"), key)
        }
    }
}
