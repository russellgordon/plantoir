import XCTest
@testable import QuartzTeachers

/// Fix with Claude… and Fix with Codex… on a section's Problems tab (#717,
/// part two).
///
/// The rules are `contracts/app-rules.json` → `outsideAgents.fixWith`, walked
/// here as data: `buttonCases` (which button is shown, whether they can be
/// pressed, what is handed over and what is left out) and `greetingCases`
/// (the opening message for none, one, two, ten and eleven rows, and the
/// length bound); every sentence and number pinned key by key; the real
/// "fixed in the source" rule leaving a ticked row out; the message reaching
/// the assistant through the shell exactly; the trail line; and the view's
/// half by a source scan.
@MainActor
final class FixWithAssistantTests: XCTestCase {

    // MARK: - The contract's words

    /// Every sentence piece, both titles, the skill table and the three
    /// bounds are the contract's, as written.
    func testTheWordsAndNumbersAreTheContracts() throws {
        let fixWith: [String: Any] = try FixWithAssistantTests.fixWith()

        var titles: [String: String] = [:]
        for button in try XCTUnwrap(fixWith["buttons"] as? [[String: Any]]) {
            titles[try XCTUnwrap(button["key"] as? String)] = try XCTUnwrap(button["title"] as? String)
        }
        XCTAssertEqual(titles.count, FixWithAssistant.Assistant.allCases.count)
        for assistant in FixWithAssistant.Assistant.allCases {
            XCTAssertEqual(assistant.buttonTitle, titles[assistant.rawValue], assistant.rawValue)
        }

        let pieces: [String: String] = try XCTUnwrap(fixWith["fixGreeting"] as? [String: String])
        let swiftPieces: [String: String] = [
            "openingOne": FixWithAssistant.openingOne,
            "openingSeveral": FixWithAssistant.openingSeveral,
            "rowWithAPage": FixWithAssistant.rowWithAPage,
            "rowWithoutAPage": FixWithAssistant.rowWithoutAPage,
            "sharedPage": FixWithAssistant.sharedPage,
            "rowSeparator": FixWithAssistant.rowSeparator,
            "more": FixWithAssistant.more,
            "afterTheRows": FixWithAssistant.afterTheRows,
            "planFirst": FixWithAssistant.planFirst,
            "closing": FixWithAssistant.closing,
        ]
        XCTAssertEqual(swiftPieces, pieces)

        XCTAssertEqual(fixWith["skillForKind"] as? [String: String], FixWithAssistant.skillForKind)
        XCTAssertEqual(fixWith["otherwiseSkill"] as? String, FixWithAssistant.otherwiseSkill)
        XCTAssertEqual(fixWith["mostRowsInThePrompt"] as? Int, FixWithAssistant.mostRowsInThePrompt)
        XCTAssertEqual(fixWith["greetingMaxCharacters"] as? Int, FixWithAssistant.greetingMaxCharacters)
        XCTAssertEqual(fixWith["pagePlaceMaxCharacters"] as? Int, FixWithAssistant.pagePlaceMaxCharacters)
        XCTAssertEqual(FixWithAssistant.mostRowsInThePrompt, 10, "the ruling's number")
    }

    /// Every skill named is one the app writes into the working folder, and
    /// every kind the table can show is answered — by its own skill or by
    /// the one the others defer to. A kind named in the table that is not a
    /// kind at all would be a skill nobody is ever sent to.
    func testEverySkillExistsAndEveryKindIsAnswered() throws {
        let skillsFolder: URL = FixWithAssistantTests.repositoryRoot()
            .appendingPathComponent("support/agent_guidance/skills")
        var skills: [String] = [FixWithAssistant.otherwiseSkill]
        for (_, skill) in FixWithAssistant.skillForKind {
            skills.append(skill)
        }
        for skill in skills {
            let page: URL = skillsFolder.appendingPathComponent(skill).appendingPathComponent("SKILL.md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: page.path), "\(skill) is not a skill the app carries")
        }

        let problems: [String: Any] = try SharedRulesContractTests.section("sectionProblems")
        var kinds: Set<String> = []
        for kind in try XCTUnwrap(problems["kinds"] as? [[String: Any]]) {
            kinds.insert(try XCTUnwrap(kind["kind"] as? String))
        }
        XCTAssertEqual(kinds.count, 16)
        for (kind, _) in FixWithAssistant.skillForKind {
            XCTAssertTrue(kinds.contains(kind), "\(kind) is not a sectionProblems kind")
        }
        XCTAssertEqual(FixWithAssistant.skill(forKind: "figuresCouldNotBeDrawn"), "plantoir-math-graphs")
        XCTAssertEqual(FixWithAssistant.skill(forKind: "linksIntoHiddenPages"), FixWithAssistant.otherwiseSkill)
    }

    // MARK: - The contract's cases

    /// `fixWith.buttonCases`: shown per assistant installed (hidden, never
    /// greyed), never on a reference course; enabled while a ticked row is
    /// still this section's problem — a ticked row fixed in the source is
    /// LEFT OUT. MUST FAIL if `handover` counts a fixed-in-the-source row,
    /// or `buttonIsShown` ignores the reference course.
    func testButtonCases() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try FixWithAssistantTests.fixWith()["buttonCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let reference: Bool = try XCTUnwrap(testCase["keptForReference"] as? Bool)

            var rows: [SectionProblemRow] = []
            var ticked: Set<String> = []
            var fixed: Set<String> = []
            var index: Int = 0
            for given in try XCTUnwrap(testCase["rows"] as? [[String: Any]]) {
                index += 1
                let id: String = "row\(index)"
                rows.append(SectionProblemRow(id: id, kind: "figuresCouldNotBeDrawn", page: "Unit 1/Graphs"))
                if try XCTUnwrap(given["ticked"] as? Bool) {
                    ticked.insert(id)
                }
                if (given["state"] as? String) == SectionProblemsRules.RowState.fixedInTheSource.rawValue {
                    fixed.insert(id)
                }
            }
            let handover: FixWithAssistant.Handover = FixWithAssistant.handover(
                rows: rows,
                isTicked: { (rowID: String) -> Bool in
                    return ticked.contains(rowID)
                },
                stateOf: { (row: SectionProblemRow) -> SectionProblemsRules.RowState in
                    return fixed.contains(row.id) ? .fixedInTheSource : .current
                }
            )

            XCTAssertEqual(
                FixWithAssistant.buttonIsShown(
                    assistantIsInstalled: try XCTUnwrap(testCase["claudeInstalled"] as? Bool),
                    courseIsKeptForReference: reference
                ),
                expect["claudeShown"] as? Bool, name
            )
            XCTAssertEqual(
                FixWithAssistant.buttonIsShown(
                    assistantIsInstalled: try XCTUnwrap(testCase["codexInstalled"] as? Bool),
                    courseIsKeptForReference: reference
                ),
                expect["codexShown"] as? Bool, name
            )
            XCTAssertEqual(handover.hasRows, expect["enabled"] as? Bool, name)
            XCTAssertEqual(handover.rows.count, expect["handedOver"] as? Int, name)
            XCTAssertEqual(handover.unticked, expect["unticked"] as? Int, name)
            XCTAssertEqual(handover.fixedInTheSource, expect["fixedInTheSource"] as? Int, name)
        }
    }

    /// `fixWith.greetingCases`: no message for nothing, the exact message for
    /// one and two rows, ten named, an eleventh counted, and long pages
    /// stopping the message at `greetingMaxCharacters`. MUST FAIL if the
    /// cap, the length bound, the shared-page rule or the skill per kind
    /// goes.
    func testGreetingCases() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try FixWithAssistantTests.fixWith()["greetingCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        var sawTen: Bool = false
        var sawEleven: Bool = false
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let rows: [SectionProblemRow] = try FixWithAssistantTests.rows(of: testCase)
            let greeting: FixWithAssistant.Greeting? = FixWithAssistant.greeting(
                rows: rows,
                courseCode: try XCTUnwrap(testCase["course"] as? String),
                courseName: try XCTUnwrap(testCase["courseName"] as? String),
                sectionNumber: try XCTUnwrap(testCase["section"] as? Int),
                occasion: try XCTUnwrap(testCase["occasion"] as? String)
            )
            guard let expect = testCase["expect"] as? [String: Any] else {
                XCTAssertNil(greeting, name)
                continue
            }
            let made: FixWithAssistant.Greeting = try XCTUnwrap(greeting, name)
            XCTAssertEqual(made.rowsNamed, expect["rowsNamed"] as? Int, name)
            XCTAssertEqual(made.rowsNotNamed, expect["rowsNotNamed"] as? Int, name)
            if let text = expect["text"] as? String {
                XCTAssertEqual(made.text, text, name)
            }
            if let most = expect["atMostCharacters"] as? Int {
                XCTAssertLessThanOrEqual(made.text.count, most, name)
                XCTAssertLessThanOrEqual(made.text.utf16.count, most, "\(name): as Windows counts")
            }
            if let has = expect["textHas"] as? String {
                XCTAssertTrue(made.text.contains(has), "\(name)\n\(made.text)")
            }
            XCTAssertFalse(made.text.contains("\n"), "\(name): one line")
            XCTAssertFalse(made.text.contains("\""), "\(name): greetingCarriesNoDoubleQuotes")
            XCTAssertTrue(made.text.contains(ClaudeCodeLauncher.howITeachGreetingSentence), name)
            if rows.count == 10 && made.rowsNamed == 10 {
                sawTen = true
            }
            if rows.count == 11 && made.rowsNamed == 10 && made.rowsNotNamed == 1 {
                sawEleven = true
            }
        }
        XCTAssertTrue(sawTen, "a case names ten rows")
        XCTAssertTrue(sawEleven, "a case counts an eleventh")
    }

    /// Rule 1: the message is the teacher's own words in their terminal, and
    /// names no machinery. "Claude" and "Codex" are the products' names, as
    /// in Revise With ▸, and appear only on the buttons.
    func testTheMessageAndTheButtonsNameNoMachinery() throws {
        let row: SectionProblemRow = try XCTUnwrap(SectionProblemRow([
            "id": "r", "kind": "figuresCouldNotBeDrawn", "page": "Unit 1/Graphs", "prompt": "a figure",
        ]))
        let greeting: FixWithAssistant.Greeting = try XCTUnwrap(FixWithAssistant.greeting(
            rows: [row], courseCode: "MPM2D", courseName: "", sectionNumber: 1, occasion: "preview"
        ))
        let machineryWords: [String] = [
            "toolchain", "script", "docker", "container", "token", "model", "terminal", "mcp", "claude", "codex",
        ]
        let lowered: String = greeting.text.lowercased()
        for word in machineryWords {
            XCTAssertFalse(lowered.contains(word), "the message says \(word): \(greeting.text)")
        }
        for assistant in FixWithAssistant.Assistant.allCases {
            let title: String = assistant.buttonTitle.lowercased()
            for word in ["toolchain", "script", "docker", "container", "token", "model", "terminal"] {
                XCTAssertFalse(title.contains(word), title)
            }
        }
    }

    // MARK: - The real rule

    /// A ticked row on a shared page that another section's LATER build
    /// shows clean is left out, through `SectionProblemsRules.state` itself
    /// rather than a state the test names.
    func testARowFixedInTheSourceIsLeftOutThroughTheRealRule() throws {
        let broken: SectionProblemRow = SectionProblemRow(
            id: "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1", kind: "figuresCouldNotBeDrawn", page: "Unit 1/Graphs"
        )
        let other: SectionProblemRow = SectionProblemRow(
            id: "quizzesNotReady|Unit 2/Check|1", kind: "quizzesNotReady", page: "Unit 2/Check"
        )
        let here: SectionProblemsRecord = FixWithAssistantTests.record(
            section: 1, builtAt: "2026-11-01T10:00:00Z", rows: [broken, other], pagesShown: ["Unit 1/Graphs", "Unit 2/Check"]
        )
        let later: SectionProblemsRecord = FixWithAssistantTests.record(
            section: 2, builtAt: "2026-11-01T11:00:00Z", rows: [], pagesShown: ["Unit 1/Graphs"]
        )
        let handover: FixWithAssistant.Handover = FixWithAssistant.handover(
            record: here, others: [later], isTicked: { (_: String) -> Bool in
                return true
            }
        )
        XCTAssertEqual(handover.rows, [other])
        XCTAssertEqual(handover.fixedInTheSource, 1)

        let alone: FixWithAssistant.Handover = FixWithAssistant.handover(
            record: here, others: [], isTicked: { (_: String) -> Bool in
                return true
            }
        )
        XCTAssertEqual(alone.rows.count, 2, "with no later build elsewhere both are this section's")
    }

    /// A page under `section<N>/` is the section's own; everything else is
    /// shared by every section.
    func testWhichPagesAreSharedByEverySection() {
        XCTAssertTrue(FixWithAssistant.isSharedByEverySection("Unit 1/Graphs"))
        XCTAssertTrue(FixWithAssistant.isSharedByEverySection("sections/Overview"))
        XCTAssertTrue(FixWithAssistant.isSharedByEverySection("section/Overview"))
        XCTAssertTrue(FixWithAssistant.isSharedByEverySection("section12"))
        XCTAssertFalse(FixWithAssistant.isSharedByEverySection("section1/Class 3"))
        XCTAssertFalse(FixWithAssistant.isSharedByEverySection("section12/Unit 1/Class 3"))
        XCTAssertFalse(FixWithAssistant.isSharedByEverySection(""))
    }

    // MARK: - Through the doors

    /// Both doors send the Fix message in place of the plain greeting, as the
    /// last argument; with none they send the plain greeting as before.
    func testBothDoorsSendTheMessageTheyAreGiven() throws {
        let message: String = "I'm a teacher: fix \"this\" please"
        let codexScript: String = try CodexLauncher.prepareSession(
            workspacePath: "/Users/teacher/Teaching", courseCode: "FIX_CODEX_TEST", courseName: "",
            codexPath: "/opt/homebrew/bin/codex", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            greeting: message
        )
        let claudeScript: String = try ClaudeCodeLauncher.prepareSession(
            workspacePath: "/Users/teacher/Teaching", courseCode: "FIX_CLAUDE_TEST", courseName: "",
            claudePath: "/usr/local/bin/claude", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            greeting: message
        )
        let plainScript: String = try ClaudeCodeLauncher.prepareSession(
            workspacePath: "/Users/teacher/Teaching", courseCode: "FIX_PLAIN_TEST", courseName: "",
            claudePath: "/usr/local/bin/claude", serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir"
        )
        defer {
            for path in [codexScript, claudeScript, plainScript] {
                try? FileManager.default.removeItem(atPath: path)
            }
            for code in ["FIX_CLAUDE_TEST", "FIX_PLAIN_TEST"] {
                if let folder = try? ClaudeCodeLauncher.supportDirectory() {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent("mcp-\(code).json"))
                }
            }
        }
        let sent: String = ClaudeCodeLauncher.escapeForShell("I'm a teacher: fix 'this' please")
        XCTAssertTrue(try String(contentsOfFile: codexScript, encoding: .utf8).hasSuffix(" " + sent))
        XCTAssertTrue(try String(contentsOfFile: claudeScript, encoding: .utf8).hasSuffix(" " + sent))
        let plain: String = ClaudeCodeLauncher.escapeForShell(
            ClaudeCodeLauncher.greeting(courseCode: "FIX_PLAIN_TEST", courseName: "")
        )
        XCTAssertTrue(try String(contentsOfFile: plainScript, encoding: .utf8).hasSuffix(" " + plain))
    }

    /// The message arrives at the assistant EXACTLY — a TeX error's
    /// backslash, a dollar sign, a backtick and an apostrophe included — by
    /// running the script the Claude door wrote against a stub that records
    /// what it was given.
    func testTheMessageSurvivesTheShell() throws {
        let stubFolder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fix-stub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stubFolder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: stubFolder)
        }
        let argumentsFile: URL = stubFolder.appendingPathComponent("arguments")
        let stubPath: URL = stubFolder.appendingPathComponent("claude")
        let stub: String = """
        #!/bin/sh
        printf '%s\\0' "$@" > '\(argumentsFile.path)'
        """
        try stub.write(to: stubPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubPath.path)

        let row: SectionProblemRow = try XCTUnwrap(SectionProblemRow([
            "id": "r", "kind": "figuresCouldNotBeDrawn", "page": "Unit 1/Teacher's $HOME `graphs`",
            "prompt": "“Unit 1”, diagram 1, line 13: \\foo isn't a command LaTeX knows here; costs $5 or `x` {section}",
        ]))
        let greeting: FixWithAssistant.Greeting = try XCTUnwrap(FixWithAssistant.greeting(
            rows: [row], courseCode: "MPM2D", courseName: "Grade 10", sectionNumber: 1, occasion: "preview"
        ))
        let scriptPath: String = try ClaudeCodeLauncher.writeLauncherScript(
            workspacePath: stubFolder.path,
            courseCode: "FIX_SHELL_TEST",
            claudePath: stubPath.path,
            configPath: "/tmp/config.json",
            prompt: greeting.text
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let raw: String = try String(contentsOf: argumentsFile, encoding: .utf8)
        var arrived: [String] = raw.components(separatedBy: "\0")
        if arrived.last == "" {
            arrived.removeLast()
        }
        XCTAssertEqual(arrived.last, greeting.text)
    }

    // MARK: - The trail

    /// "asked an assistant to fix problems": the event is the contract's, and
    /// its line says which assistant, how many and of what kinds, how many
    /// the message named and how many were left out — and never a page.
    func testTheTrailLineNamesTheAssistantAndCountsNeverAPage() throws {
        let trail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        var template: String = ""
        for entry in try XCTUnwrap(trail["mustRecord"] as? [[String: Any]]) {
            if (entry["event"] as? String) == ActivityTrail.Event.askedAnAssistantToFixProblems.rawValue {
                template = try XCTUnwrap(entry["line"] as? String)
            }
        }
        XCTAssertFalse(template.isEmpty, "the event is in activityTrail.mustRecord")

        var rows: [SectionProblemRow] = []
        for index in 1...12 {
            rows.append(try XCTUnwrap(SectionProblemRow([
                "id": "r\(index)", "kind": index == 12 ? "quizzesNotReady" : "figuresCouldNotBeDrawn",
                "page": "Unit 1/Secret Page \(index)", "prompt": "problem \(index)",
            ])))
        }
        let handover: FixWithAssistant.Handover = FixWithAssistant.Handover(rows: rows, unticked: 2, fixedInTheSource: 1)
        let greeting: FixWithAssistant.Greeting = try XCTUnwrap(FixWithAssistant.greeting(
            rows: rows, courseCode: "MPM2D", courseName: "", sectionNumber: 1, occasion: "preview"
        ))

        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fix-trail-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }
        FixWithAssistant.noteOnTheTrail(
            assistant: .codex, handover: handover, greeting: greeting, courseCode: "MPM2D", sectionNumber: 1
        )
        let written: String = ActivityTrail.store.activityText(includingPrompts: true)

        let expected: String = template
            .replacingOccurrences(of: "{course}", with: "MPM2D")
            .replacingOccurrences(of: "{section}", with: "1")
            .replacingOccurrences(of: "{assistant}", with: "Codex")
            .replacingOccurrences(of: "{count} problem(s)", with: "12 problems")
            .replacingOccurrences(of: "{kinds}", with: "figuresCouldNotBeDrawn, quizzesNotReady")
            .replacingOccurrences(of: "{named}", with: "10")
            .replacingOccurrences(of: "{unticked}", with: "2")
            .replacingOccurrences(of: "{fixed}", with: "1")
        XCTAssertTrue(written.contains(expected), "\(expected)\n\(written)")
        XCTAssertFalse(written.contains("Secret Page"), "never a page")
        XCTAssertTrue(
            FixWithAssistant.trailLine(
                assistant: .claude,
                handover: FixWithAssistant.Handover(rows: [rows[0]], unticked: 0, fixedInTheSource: 0),
                greeting: greeting
            ).hasPrefix("asked Claude to fix 1 problem (")
        )
    }

    // MARK: - The view

    /// The view's half, read from its source: presence is the app-level
    /// answer (no disk read while the table draws), the buttons are hidden
    /// per assistant and on a reference course, disabled with nothing to
    /// hand over, Revise With's refusal is made at the click, the door is
    /// given the message, and the trail line is written only once it opened.
    func testTheViewShowsHidesAndOpensAsTheRuleSays() throws {
        let view: String = try FixWithAssistantTests.readSource("QuartzTeachers/Views/Section/ProblemsTableView.swift")
        XCTAssertFalse(view.contains(".isAvailable"), "never asked on the disk while the table draws")
        XCTAssertTrue(view.contains("presence.claudeIsInstalled"))
        XCTAssertTrue(view.contains("presence.codexIsInstalled"))
        XCTAssertTrue(view.contains("courseIsKeptForReference: course.isKeptForReference"))
        XCTAssertTrue(view.contains(".disabled(!handover.hasRows)"))
        let fix: String = try FixWithAssistantTests.body(of: "func fix(with assistant:", in: view)
        XCTAssertTrue(fix.contains("workspace.reviseRefusal(item: item"), "Revise With's refusal at the click")
        XCTAssertTrue(fix.contains("greeting: greeting.text"))
        let opened: Range<String.Index> = try XCTUnwrap(fix.range(of: "if opened {"))
        let noted: Range<String.Index> = try XCTUnwrap(fix.range(of: "FixWithAssistant.noteOnTheTrail("))
        XCTAssertLessThan(opened.lowerBound, noted.lowerBound, "the line is written once the door opened")
    }

    // MARK: - Helpers

    static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func fixWith() throws -> [String: Any] {
        let url: URL = repositoryRoot().appendingPathComponent("contracts/app-rules.json")
        let rules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let outsideAgents: [String: Any] = try XCTUnwrap(rules["outsideAgents"] as? [String: Any])
        return try XCTUnwrap(outsideAgents["fixWith"] as? [String: Any], "No outsideAgents.fixWith")
    }

    /// A greeting case's rows: `rows` as given, then `manyRows` made by
    /// `greetingCasesHow`'s rule.
    static func rows(of testCase: [String: Any]) throws -> [SectionProblemRow] {
        var rows: [SectionProblemRow] = []
        var index: Int = 0
        for given in (testCase["rows"] as? [[String: Any]]) ?? [] {
            index += 1
            var object: [String: Any] = given
            object["id"] = "row\(index)"
            rows.append(try XCTUnwrap(SectionProblemRow(object)))
        }
        if let many = testCase["manyRows"] as? [String: Any] {
            let count: Int = try XCTUnwrap(many["count"] as? Int)
            let length: Int = try XCTUnwrap(many["promptCharacters"] as? Int)
            for number in 1...count {
                var prompt: String = try XCTUnwrap(many["prompt"] as? String)
                    .replacingOccurrences(of: "{n}", with: String(number))
                while prompt.count < length {
                    prompt.append("x")
                }
                let page: String = try XCTUnwrap(many["page"] as? String)
                    .replacingOccurrences(of: "{n}", with: String(number))
                rows.append(try XCTUnwrap(SectionProblemRow([
                    "id": "many\(number)", "kind": try XCTUnwrap(many["kind"] as? String), "page": page, "prompt": prompt,
                ])))
            }
        }
        return rows
    }

    static func record(
        section: Int,
        builtAt: String,
        rows: [SectionProblemRow],
        pagesShown: [String]
    ) -> SectionProblemsRecord {
        return SectionProblemsRecord(
            course: "MPM2D", section: section, buildId: "B\(section)",
            builtAt: SectionProblemsRecord.date(builtAt), occasion: "preview",
            rows: rows, pagesShown: pagesShown, newIDs: [], goneIDs: [],
            siteSaidComplete: true, alertKey: "B\(section)"
        )
    }

    static func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The text of the function starting at `signature`, to its closing brace
    /// at the same indent.
    static func body(of signature: String, in source: String) throws -> String {
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: signature), signature)
        var lineStart: String.Index = start.lowerBound
        while lineStart > source.startIndex && source[source.index(before: lineStart)] != "\n" {
            lineStart = source.index(before: lineStart)
        }
        var indent: String = ""
        for character in source[lineStart..<start.lowerBound] {
            if character != " " {
                break
            }
            indent.append(character)
        }
        let rest: Substring = source[start.lowerBound...]
        guard let end = rest.range(of: "\n" + indent + "}\n") else {
            return String(rest)
        }
        return String(rest[..<end.upperBound])
    }
}
