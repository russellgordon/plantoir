import XCTest
@testable import QuartzTeachers

/// `contracts/app-rules.json` → `outsideAgents.setUp` (#855), run against
/// the code: every sentence key by key, every agent's facts field by field,
/// the state cases through `AssistantSetUpState.decide`, the child's
/// environment, and the quit words in `shared-rules.json`.
@MainActor
final class AssistantSetUpContractTests: XCTestCase {

    // MARK: - Functions

    static func contractsURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts")
    }

    static func read(_ file: String) throws -> [String: Any] {
        let data: Data = try Data(contentsOf: contractsURL().appendingPathComponent(file))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func setUpBlock() throws -> [String: Any] {
        let rules: [String: Any] = try read("app-rules.json")
        let outside: [String: Any] = try XCTUnwrap(rules["outsideAgents"] as? [String: Any])
        return try XCTUnwrap(outside["setUp"] as? [String: Any])
    }

    // MARK: - Tests

    /// Every sentence, key by key, both ways: a key in one place only fails.
    func testEverySentenceIsTheContractsKeyByKey() throws {
        let wording: [String: String] = try XCTUnwrap(try AssistantSetUpContractTests.setUpBlock()["wording"] as? [String: String])
        XCTAssertEqual(Set(wording.keys), Set(AssistantSetUpWording.everyKey.keys))
        for (key, sentence) in AssistantSetUpWording.everyKey {
            XCTAssertEqual(wording[key], sentence, key)
        }
    }

    /// CLAUDE.md rule 1: no sentence names the machinery, and none says free.
    func testNoSentenceNamesTheMachineryOrAPrice() {
        let forbidden: [String] = [
            "installer", "script", "terminal", "PATH", "shell", "binary", "signature",
            "CLI", "npm", "command line", "command-line", "free", "toolchain", "Docker", "container"
        ]
        for (key, sentence) in AssistantSetUpWording.everyKey {
            for word in forbidden {
                XCTAssertFalse(sentence.localizedCaseInsensitiveContains(word), "\(key) says \(word): \(sentence)")
            }
        }
    }

    /// Each agent's facts are the catalog's, in the pane's order.
    func testEveryAgentIsTheCatalogs() throws {
        let agents: [[String: Any]] = try XCTUnwrap(try AssistantSetUpContractTests.setUpBlock()["agents"] as? [[String: Any]])
        XCTAssertEqual(agents.count, AssistantSetUp.agents.count)
        for index in 0..<agents.count {
            let written: [String: Any] = agents[index]
            let agent: AssistantSetUpAgent = AssistantSetUp.agents[index]
            let recipe: SetUpRecipe = agent.recipe
            XCTAssertEqual(written["key"] as? String, agent.key)
            XCTAssertEqual(written["displayName"] as? String, agent.displayName)
            XCTAssertEqual(written["maker"] as? String, agent.maker)
            XCTAssertEqual(written["installerURL"] as? String, recipe.installerAddress.absoluteString)
            XCTAssertEqual(written["interpreter"] as? String, recipe.interpreter)
            XCTAssertEqual(written["allowedAddresses"] as? [String], recipe.allowedAddresses)
            XCTAssertEqual(written["reachabilityHosts"] as? [String], recipe.reachabilityHosts)
            XCTAssertEqual(written["extraEnvironment"] as? [String: String], recipe.extraEnvironment)
            XCTAssertEqual(written["removes"] as? [String], recipe.removes)
            XCTAssertEqual(written["keeps"] as? [String], recipe.keeps)
            XCTAssertEqual(written["signIn"] as? [String], agent.signInArguments)
            XCTAssertEqual(written["plansPage"] as? String, agent.plansPage.absoluteString)
            XCTAssertEqual(written["educationHelpAnchor"] as? String, agent.educationHelpAnchor)
            if let check = written["signedInCheck"] as? [String: Any] {
                XCTAssertEqual(check["arguments"] as? [String], agent.signedInCheckArguments)
                let code: Int = try XCTUnwrap(check["signedInExitCode"] as? Int)
                XCTAssertEqual(Int32(code), agent.signedInExitCode)
            } else {
                XCTAssertNil(agent.signedInCheckArguments, agent.key)
            }
            let programs: [[String: Any]] = try XCTUnwrap(written["programs"] as? [[String: Any]])
            XCTAssertEqual(programs.count, recipe.programs.count)
            for programIndex in 0..<programs.count {
                XCTAssertEqual(programs[programIndex]["path"] as? String, recipe.programs[programIndex].path)
                XCTAssertEqual(programs[programIndex]["identifier"] as? String, recipe.programs[programIndex].identifier)
                XCTAssertEqual(programs[programIndex]["team"] as? String, recipe.programs[programIndex].team)
                XCTAssertEqual(programs[programIndex]["required"] as? Bool, recipe.programs[programIndex].required)
            }
            // Every program Plantoir offers sits where the door looks first.
            XCTAssertTrue(recipe.programs[0].path.hasPrefix(".local/bin/"), agent.key)
            // The address and every redirect host are the maker's, over HTTPS.
            XCTAssertEqual(recipe.installerAddress.scheme, "https")
            XCTAssertTrue(SetUpRedirectGuard.follows(recipe.installerAddress, allowedAddresses: recipe.allowedAddresses), agent.key)
        }
        // The Copilot identity is #783's, not a second copy.
        XCTAssertEqual(AssistantSetUp.copilot.recipe.programs[0].identifier, CopilotLauncher.signedIdentifier)
        XCTAssertEqual(AssistantSetUp.copilot.recipe.programs[0].team, CopilotLauncher.signedTeam)
    }

    /// The menu items, the Help page and the limits.
    func testTheItemsAndLimitsAreTheContracts() throws {
        let block: [String: Any] = try AssistantSetUpContractTests.setUpBlock()
        XCTAssertEqual(block["menuItem"] as? String, AssistantSetUpWording.menuItem)
        XCTAssertEqual(block["helpMenuItem"] as? String, AssistantSetUpWording.helpMenuItem)
        XCTAssertEqual(block["helpAnchor"] as? String, AssistantSetUp.helpAnchor)
        let minutes: Int = try XCTUnwrap(block["longestRunMinutes"] as? Int)
        XCTAssertEqual(Int64(minutes), SetUpRunner.longestRunMinutes)
        let grace: Int = try XCTUnwrap(block["stopGraceSeconds"] as? Int)
        XCTAssertEqual(Int64(grace), SetUpRunner.stopGraceSeconds)
        XCTAssertEqual(block["quitGraceMilliseconds"] as? Int, SetUpRunner.quitGraceMilliseconds)
        XCTAssertEqual(block["profileFiles"] as? [String], SetUpRecord.profileFiles)
        let environment: [String: Any] = try XCTUnwrap(block["childEnvironment"] as? [String: Any])
        XCTAssertEqual(environment["names"] as? [String], SetUpRunner.childEnvironmentNames)
        XCTAssertEqual(environment["path"] as? String, SetUpRunner.childSearchPath)
        XCTAssertEqual(environment["lang"] as? String, SetUpRunner.childLanguage)
        let built: [String: String] = SetUpRunner.childEnvironment(
            home: "/h", user: "u", shell: "/bin/zsh", temporaryFolder: "/t", extra: [:]
        )
        XCTAssertEqual(Set(built.keys), Set(SetUpRunner.childEnvironmentNames))
    }

    /// `setUp.stateCases`, through the rule the pane draws from.
    func testEveryStateCase() throws {
        let block: [String: Any] = try AssistantSetUpContractTests.setUpBlock()
        let stateCases: [String: Any] = try XCTUnwrap(block["stateCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(stateCases["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 15)
        var seen: Set<String> = []
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["given"] as? [String: Any])
            let expect: String = try XCTUnwrap(testCase["expect"] as? String)
            seen.insert(expect)
            var recorded: SetUpRecordEntry.State? = nil
            if let text = given["recorded"] as? String {
                recorded = try XCTUnwrap(SetUpRecordEntry.State(rawValue: text), name)
            }
            let activity: AssistantSetUpState.Activity = try XCTUnwrap(
                AssistantSetUpState.Activity(rawValue: try XCTUnwrap(given["activity"] as? String)), name
            )
            var signIn: AssistantSetUpState.SignIn = .notAsked
            if let code = given["signIn"] as? Int {
                signIn = .finished(Int32(code))
            } else if (given["signIn"] as? String) == "windowOpen" {
                signIn = .windowOpen
            }
            let recordSetAside: Bool = try XCTUnwrap(given["recordSetAside"] as? Bool, name)
            let status: AssistantSetUpState.Status = try XCTUnwrap(
                AssistantSetUpState.Status(rawValue: try XCTUnwrap(given["status"] as? String)), name
            )
            let decided: AssistantSetUpState = AssistantSetUpState.decide(
                found: try XCTUnwrap(given["found"] as? Bool),
                recorded: recorded,
                activity: activity,
                lastOutcome: AssistantSetUpContractTests.outcome(named: given["lastOutcome"] as? String),
                signIn: signIn,
                status: status,
                hasSignedInCheck: try XCTUnwrap(given["hasSignedInCheck"] as? Bool),
                recordSetAside: recordSetAside
            )
            XCTAssertEqual(decided.rawValue, expect, name)
        }
        // Every state is reached by some case.
        for state in AssistantSetUpState.allCases {
            XCTAssertTrue(seen.contains(state.rawValue), "no case reaches \(state.rawValue)")
        }
    }

    /// An outcome from its contract name, with placeholder details.
    static func outcome(named name: String?) -> SetUpOutcome? {
        switch name {
        case "finished": return .finished
        case "noConnection": return .noConnection(host: "example.org")
        case "couldNotFetch": return .couldNotFetch(reason: "x")
        case "couldNotStart": return .couldNotStart
        case "exited": return .exited(status: 1)
        case "leftNothing": return .leftNothing(program: "x")
        case "notFromMaker": return .notFromMaker(program: "x")
        case "stopped": return .stopped
        case "tookTooLong": return .tookTooLong
        case "couldNotRecord": return .couldNotRecord
        default: return nil
        }
    }

    /// The quit words (`quittingWhileWorkIsUnderWay.whileAnAssistantIsSetUp`).
    func testTheQuitWordsAreTheContracts() throws {
        let shared: [String: Any] = try AssistantSetUpContractTests.read("shared-rules.json")
        let quit: [String: Any] = try XCTUnwrap(shared["quittingWhileWorkIsUnderWay"] as? [String: Any])
        let block: [String: Any] = try XCTUnwrap(quit["whileAnAssistantIsSetUp"] as? [String: Any])
        let words: [String: String] = try XCTUnwrap(block["words"] as? [String: String])
        XCTAssertEqual(words["settingUpOne"], QuitConfirmation.settingUpOne)
        XCTAssertEqual(words["settingUpSeveral"], QuitConfirmation.settingUpSeveral)
        XCTAssertEqual(words["message"], QuitConfirmation.settingUpMessage)
        // Its own first button (Russell, 2026-11-13 evening), by meaning and title.
        let buttons: [String: Any] = try XCTUnwrap(quit["buttons"] as? [String: Any])
        let titles: [String: String] = try XCTUnwrap(buttons["titles"] as? [String: String])
        XCTAssertEqual(titles["keepWorking"], QuitConfirmation.keepWorkingButton)
        XCTAssertEqual(titles["quitAnyway"], QuitConfirmation.quitAnywayButton)
        let byQuestion: [String: String] = try XCTUnwrap(buttons["firstButtonByQuestion"] as? [String: String])
        XCTAssertEqual(byQuestion["whileAnAssistantIsSetUp"], QuitConfirmation.finishSettingUpButton)
        let setUpButtons: [QuitConfirmation.Button] = QuitConfirmation.buttons(onlySettingUp: true)
        XCTAssertEqual(setUpButtons[0].title, QuitConfirmation.finishSettingUpButton)
        XCTAssertEqual(setUpButtons[0].choice, .keepWorking)
        XCTAssertEqual(setUpButtons[1].choice, .quitAnyway)
        XCTAssertEqual(QuitConfirmation.buttons(onlySettingUp: false)[0].title, QuitConfirmation.keepWorkingButton)
        XCTAssertEqual(
            QuitConfirmation.workUnderWay(publishes: [], previews: [], setUps: ["Codex"]),
            "setting up Codex"
        )
        XCTAssertEqual(
            QuitConfirmation.workUnderWay(publishes: [], previews: [], setUps: ["Codex", "Claude Code"]),
            "setting up 2 assistants"
        )
    }

    /// The rule this piece changed: the old key is gone, its successor says
    /// only when asked.
    func testNeverInstalledIsReplaced() throws {
        let rules: [String: Any] = try AssistantSetUpContractTests.read("app-rules.json")
        let outside: [String: Any] = try XCTUnwrap(rules["outsideAgents"] as? [String: Any])
        XCTAssertNil(outside["neverInstalled"])
        XCTAssertNotNil(outside["installedOnlyWhenAsked"] as? String)
    }
}
