import XCTest

/// A first publish's two questions, through the real window (#125, folded
/// into #154): the teacher's surname, then the website address.
///
/// **Stubbed, and the stub's words are the contract's.** `deploy.sh` is
/// replaced by a script this test writes, whose prompts are read from
/// `contracts/app-rules.json` → `credentialPrompts.cases` — the same strings
/// the app's matcher is tested against — and printed in `deploy.py`'s
/// `prompt()` shape (`text [default]: `, no newline). None of deploy.py's
/// explanation prose is copied: the app matches none of it, and a copy would
/// drift. The field labels asserted are the contract's
/// `credentialRequests.requests[].fieldLabel`, found by the request's name.
///
/// **What it proves**, one assertion each:
/// 1. the surname is asked once, in the credential sheet, with the Surname
///    field — and the next sheet is the website address, not a second surname;
/// 2. the address arrives filled in with exactly the default the launcher
///    offered;
/// 3. what the teacher TYPED is what reaches the launcher, not the default;
/// 4. a second section is asked only the address (see its comment for what
///    that does and does not prove);
/// 5. Cancel on a question with no cancel option stops the publish: the
///    launcher's process is gone, the window says Cancelled, and nothing
///    was answered for that section;
/// 6. the trail names which questions were asked and never the answers.
///
/// Launched through `IsolatedLaunch`, so the trail read in 6 is the
/// redirected one and nothing reaches the teacher's own. Not opt-in: it
/// needs no model and takes under a minute.
final class NewSiteDialogUITests: XCTestCase {

    // MARK: - Stored properties

    private var deployPIDFileURL: URL?

    // MARK: - Setting up and tearing down

    /// Stops at the first failure: each step drives the next, so a red step
    /// otherwise cascades into minutes of timeouts that bury the one line
    /// that says what broke.
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        if let deployPIDFileURL {
            StubLaunchers.reap(pidFileURL: deployPIDFileURL, expectingNamePrefix: "bash")
        }
        deployPIDFileURL = nil
        super.tearDown()
    }

    // MARK: - The test

    func testAFirstPublishAsksOnceFillsInTheAddressAndCancelStopsIt() throws {
        let contract: CredentialContract = try CredentialContract.read()
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        for section in [1, 2] {
            let publicURL: URL = fixtureURL
                .appendingPathComponent("courses/EXC2O/.merged_output/section\(section)/public")
            try FileManager.default.createDirectory(at: publicURL, withIntermediateDirectories: true)
            try "<html></html>".write(
                to: publicURL.appendingPathComponent("index.html"), atomically: true, encoding: .utf8
            )
        }
        let stub: StubDeploy = try StubDeploy.write(in: fixtureURL, contract: contract)
        deployPIDFileURL = stub.pidFileURL

        let launch: IsolatedLaunch = try IsolatedLaunch.launch(workspace: fixtureURL)
        let application: XCUIApplication = launch.application

        // 1 — Section 1: the surname, once.
        select(section: 1, in: application)
        application.buttons["deployButton"].click()
        let sheet: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "credentialSheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "No credential sheet: the surname question was not recognised.")
        XCTAssertTrue(
            sheet.staticTexts[contract.surnameFieldLabel].exists,
            "The first sheet is not the \(contract.surnameFieldLabel) one."
        )
        let field: XCUIElement = sheet.descendants(matching: .any).matching(identifier: "credentialField").firstMatch
        field.click()
        field.typeText("Testerson")
        sheet.buttons["credentialSendButton"].click()

        // The next sheet is the website address — not a second surname.
        let addressLabel: XCUIElement = application.staticTexts[contract.siteNameFieldLabel]
        XCTAssertTrue(
            addressLabel.waitForExistence(timeout: 20),
            "The website address was never asked for after the surname."
        )
        XCTAssertFalse(
            application.staticTexts[contract.surnameFieldLabel].exists,
            "The surname was asked a second time."
        )

        // 2 — the address arrives filled in with exactly what was offered.
        let offered: String = try stub.offeredDefault(forSection: 1)
        XCTAssertEqual(offered, StubDeploy.expectedDefault(section: 1, surname: "testerson"))
        let addressField: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "credentialField").firstMatch
        XCTAssertEqual(addressField.value as? String, offered, "The address was not filled in with the launcher's default.")

        // 3 — what was typed reaches the launcher, not the default.
        addressField.click()
        addressField.typeKey("a", modifierFlags: .command)
        addressField.typeKey(.delete, modifierFlags: [])
        addressField.typeText("typed-address-154")
        application.buttons["credentialSendButton"].click()
        let answered: Bool = StateDirectoryUITests.waitUntil(seconds: 10) {
            return stub.answers().contains("section1=typed-address-154")
        }
        XCTAssertTrue(answered, "The launcher never received the typed address. It had: \(stub.answers())")
        XCTAssertFalse(stub.answers().contains("section1=" + offered), "The launcher received the default instead.")
        let firstFinished: Bool = StateDirectoryUITests.waitUntil(seconds: 20) {
            return application.buttons["deployButton"].isEnabled
        }
        XCTAssertTrue(firstFinished, "Section 1's publish never finished.")

        // 4 — Section 2: the address only. Remembering the surname is
        // deploy.py's (verify-deploy.sh covers it) and this stub's, which
        // saved it; what THIS proves is that the app never asks for one on
        // its own — the first sheet is whatever the launcher asked.
        select(section: 2, in: application)
        application.buttons["deployButton"].click()
        XCTAssertTrue(
            application.staticTexts[contract.siteNameFieldLabel].waitForExistence(timeout: 20),
            "Section 2 was not asked for its website address."
        )
        XCTAssertFalse(
            application.staticTexts[contract.surnameFieldLabel].exists,
            "Section 2 was asked for the surname."
        )

        // 5 — Cancel stops it. The address question offers no cancel option,
        // so Cancel has to stop the task itself.
        let deployPID: Int32 = try stub.recordedProcessID()
        application.descendants(matching: .any).matching(identifier: "credentialSheet").firstMatch
            .buttons["Cancel"].click()
        XCTAssertTrue(
            application.descendants(matching: .any).matching(identifier: "cancelledNotice").firstMatch
                .waitForExistence(timeout: 10),
            "The window never said the publish was cancelled."
        )
        let stubEnded: Bool = StateDirectoryUITests.waitUntil(seconds: 10) {
            let name: String? = StubLaunchers.nameOfRunningProcess(deployPID)
            return name == nil || !(name ?? "").lowercased().hasPrefix("bash")
        }
        XCTAssertTrue(stubEnded, "The launcher (pid \(deployPID)) was still running after Cancel.")
        XCTAssertFalse(stub.answers().contains("section2="), "Section 2 was answered despite Cancel.")

        // 6 — the trail names the questions, never the answers.
        let trail: [String] = launch.trailLines()
        var surnameLines: Int = 0
        var namesSurname: Bool = false
        var namesAddress: Bool = false
        var carriesAnAnswer: [String] = []
        for line in trail {
            if line.contains(contract.surnameFieldLabel) {
                namesSurname = true
                surnameLines += 1
            }
            if line.contains(contract.siteNameFieldLabel) {
                namesAddress = true
            }
            if line.contains("Testerson") || line.contains("testerson") || line.contains("typed-address-154") {
                carriesAnAnswer.append(line)
            }
        }
        XCTAssertTrue(namesSurname, "The trail never said the \(contract.surnameFieldLabel) was asked for.")
        // Once: the surname was asked once, so it was published once. A
        // question published twice is a second sheet over the first.
        XCTAssertEqual(surnameLines, 1, "The surname question was published \(surnameLines) times.")
        XCTAssertTrue(namesAddress, "The trail never said the \(contract.siteNameFieldLabel) was asked for.")
        XCTAssertEqual(carriesAnAnswer, [], "The trail recorded an answer.")

        application.typeKey("q", modifierFlags: .command)
    }

    // MARK: - Functions

    private func select(section: Int, in application: XCUIApplication) {
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 20))
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section \(section)"]
        if !sectionRow.exists {
            courseRow.click()
            application.typeKey(.rightArrow, modifierFlags: [])
        }
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 10), "Section \(section) is not in the sidebar.")
        sectionRow.click()
    }
}

/// The strings this test takes from the contract rather than retyping.
struct CredentialContract {

    // MARK: - Stored properties

    let surnamePrompt: String
    let siteNamePrompt: String
    let surnameFieldLabel: String
    let siteNameFieldLabel: String

    // MARK: - Functions

    static func read() throws -> CredentialContract {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/app-rules.json")
        let parsed: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let prompts: [String: Any] = try XCTUnwrap(parsed["credentialPrompts"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(prompts["cases"] as? [[String: Any]])
        let requestsBlock: [String: Any] = try XCTUnwrap(parsed["credentialRequests"] as? [String: Any])
        let requests: [[String: Any]] = try XCTUnwrap(requestsBlock["requests"] as? [[String: Any]])
        return CredentialContract(
            surnamePrompt: try firstPrompt(expecting: "teacherSurname", in: cases),
            siteNamePrompt: try firstPrompt(expecting: "siteName", in: cases),
            surnameFieldLabel: try fieldLabel(named: "teacherSurname", in: requests),
            siteNameFieldLabel: try fieldLabel(named: "siteName", in: requests)
        )
    }

    static func firstPrompt(expecting name: String, in cases: [[String: Any]]) throws -> String {
        for item in cases {
            if item["expectRequest"] as? String == name, let prompt = item["prompt"] as? String {
                return prompt
            }
        }
        throw XCTSkip("contracts/app-rules.json has no credentialPrompts case for \(name)")
    }

    static func fieldLabel(named name: String, in requests: [[String: Any]]) throws -> String {
        for request in requests {
            if request["name"] as? String == name, let label = request["fieldLabel"] as? String {
                return label
            }
        }
        throw XCTSkip("contracts/app-rules.json has no credentialRequests entry named \(name)")
    }
}

/// A `deploy.sh` that asks deploy.py's two first-publish questions and
/// writes down what it was told.
struct StubDeploy {

    // MARK: - Stored properties

    let pidFileURL: URL
    let stateURL: URL

    // MARK: - Functions

    static func expectedDefault(section: Int, surname: String) -> String {
        let year: Int = Calendar.current.component(.year, from: Date())
        return "exc2o-s\(section)-\(year)-\(surname)"
    }

    static func write(in fixtureURL: URL, contract: CredentialContract) throws -> StubDeploy {
        let pidFileURL: URL = fixtureURL.appendingPathComponent("stub-deploy.pid")
        let stateURL: URL = fixtureURL.appendingPathComponent("stub-state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        // deploy.py's `prompt()` writes `text [default]: `; the contract
        // holds the text with its colon, as a teacher's terminal shows it
        // without a default.
        var siteQuestion: String = contract.siteNamePrompt.trimmingCharacters(in: .whitespaces)
        if siteQuestion.hasSuffix(":") {
            siteQuestion = String(siteQuestion.dropLast())
        }
        let surnameQuestion: String = contract.surnamePrompt.trimmingCharacters(in: .whitespaces)

        let script: String = """
        #!/bin/bash
        # Written by NewSiteDialogUITests. $1 is the course, $2 the section.
        echo $$ > \(shellQuoted(pidFileURL.path))
        state=\(shellQuoted(stateURL.path))
        section="$2"
        echo "Ensuring container is running"
        if [ ! -f "$state/surname" ]; then
            printf '%s ' \(shellQuoted(surnameQuestion))
            read -r surname
            printf '%s' "$surname" > "$state/surname"
        fi
        surname="$(tr '[:upper:]' '[:lower:]' < "$state/surname")"
        default="exc2o-s${section}-$(date +%Y)-${surname}"
        printf '%s' "$default" > "$state/default-section${section}"
        printf '%s [%s]: ' \(shellQuoted(siteQuestion)) "$default"
        read -r site
        echo "section${section}=${site}" >> "$state/answers"
        echo "Published (stub)"
        exit 0
        """
        let stubURL: URL = fixtureURL.appendingPathComponent("deploy.sh")
        try script.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)
        return StubDeploy(pidFileURL: pidFileURL, stateURL: stateURL)
    }

    func offeredDefault(forSection section: Int) throws -> String {
        return try String(
            contentsOf: stateURL.appendingPathComponent("default-section\(section)"), encoding: .utf8
        )
    }

    func answers() -> String {
        return (try? String(contentsOf: stateURL.appendingPathComponent("answers"), encoding: .utf8)) ?? ""
    }

    func recordedProcessID() throws -> Int32 {
        let text: String = try String(contentsOf: pidFileURL, encoding: .utf8)
        return try XCTUnwrap(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func shellQuoted(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
