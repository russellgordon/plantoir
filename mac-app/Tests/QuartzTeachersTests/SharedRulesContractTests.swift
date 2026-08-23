import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` — five rule sets that both apps need and
/// neither platform owns.
///
/// Two of them sit on top of machinery that could not be less alike: launchd
/// against Task Scheduler, AppKit against WinUI. That is the argument for
/// writing the RULES down rather than the implementation — what must be
/// refused, matched or stripped does not change with the machinery that does
/// it, and a Windows session reading "we refuse a section that has never been
/// deployed" does not need to know what a plist is.
@MainActor
final class SharedRulesContractTests: XCTestCase {

    // MARK: - What a scheduled deploy refuses, and in what order

    /// Everything a deploy running at 06:30 would ASK is asked now, while
    /// somebody is awake. The ORDER matters as much as the list: the first
    /// match is what the teacher is told.
    func testScheduledDeploysRefuseWhatTheContractSays() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("scheduledDeployRefusals")
        let now: Date = Date(timeIntervalSince1970: 1_786_000_000)

        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = testCase["given"] as? [String: Any] ?? [:]

            let root: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("scheduled-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let course: Course = try makeCourse(
                in: root,
                target: given["target"] as? String,
                folderPath: (given["folderProblem"] as? Bool == true)
                    ? root.appendingPathComponent("no-such-folder").path
                    : root.path,
                hasDeployedBefore: given["hasDeployedBefore"] as? Bool ?? true,
                additionalTarget: given["additionalTarget"] as? String,
                additionalFolderPath: (given["additionalFolderProblem"] as? Bool == true)
                    ? root.appendingPathComponent("no-such-additional-folder").path
                    : root.path,
                additionalTargetHasDeployedBefore: given["additionalTargetHasDeployedBefore"] as? Bool ?? true
            )

            let when: Date = (given["whenIsInThePast"] as? Bool == true)
                ? now.addingTimeInterval(-3600)
                : now.addingTimeInterval(3600)

            let problem: String? = ScheduledDeploy.problem(
                course: course,
                sectionNumber: 1,
                when: when,
                now: now,
                cloudflareAccountID: given["cloudflareAccountID"] as? String ?? "",
                locale: Locale(identifier: "en_CA")
            )

            guard let expected = testCase["expectRefusal"] as? String else {
                XCTAssertNil(problem, "\(name): nothing should be wrong — it said \"\(problem ?? "")\"")
                continue
            }
            let said: String = try XCTUnwrap(problem, "\(name): should have been refused as \(expected)")
            XCTAssertEqual(
                SharedRulesContractTests.name(ofRefusal: said), expected,
                "\(name): refused, but not for the reason the contract names — it said \"\(said)\""
            )
        }
    }

    // MARK: - What the sidebar's filter shows

    func testTheSidebarFilterMatchesAsTheContractSays() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("sidebarFilter")
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("filter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        // A working folder is recognised by its launchers; stubs are enough,
        // and nothing here ever runs one.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for launcher in ["preview.sh", "deploy.sh", "setup.sh"] {
            try "#!/bin/bash\n".write(
                to: root.appendingPathComponent(launcher), atomically: true, encoding: .utf8
            )
        }
        for entry in try XCTUnwrap(section["courses"] as? [[String: String]]) {
            try makeCourseFolder(
                code: try XCTUnwrap(entry["code"]), name: try XCTUnwrap(entry["name"]), in: root
            )
        }
        workspace.chooseWorkspace(at: root)

        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            workspace.filterText = try XCTUnwrap(testCase["filter"] as? String)
            var shown: [String] = []
            for course in workspace.filteredCourses {
                shown.append(course.code)
            }
            XCTAssertEqual(
                shown.sorted(), (try XCTUnwrap(testCase["expect"] as? [String])).sorted(),
                "filter “\(workspace.filterText)”"
            )
        }
    }

    // MARK: - What is stripped from the launchers' output

    func testTheTranscriptStripsWhatTheContractSays() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("transcriptStripping")
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let input: String = try XCTUnwrap(testCase["input"] as? String)
            XCTAssertEqual(
                TranscriptBuilder.strippingControlSequences(from: input),
                try XCTUnwrap(testCase["expect"] as? String),
                "input \(input.debugDescription)"
            )
        }
    }

    // MARK: - What is taken out of a problem report

    /// The redaction rules, run against the same cases the Windows suite
    /// runs. Both halves matter: what goes, and what STAYS — a redactor that
    /// swallowed the image tag or the site address would produce reports
    /// nobody could diagnose anything from.
    func testProblemReportRedactionMatchesTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("problemReportRedaction")
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let input: String = try XCTUnwrap(testCase["input"] as? String)
            XCTAssertEqual(
                LogRedactor.redacting(input),
                try XCTUnwrap(testCase["expect"] as? String),
                "input \(input.debugDescription)"
            )
        }
    }

    /// The phrases left behind are named in the contract rather than
    /// described, so that a report reads identically on both platforms and
    /// neither side has to copy a string out of prose.
    func testTheRedactionPlaceholdersAreTheOnesInTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("problemReportRedaction")
        let placeholders: [String: Any] = try XCTUnwrap(section["placeholders"] as? [String: Any])
        XCTAssertEqual(placeholders["token"] as? String, LogRedactor.removedToken)
        XCTAssertEqual(placeholders["email"] as? String, LogRedactor.removedEmail)
        XCTAssertEqual(placeholders["account"] as? String, LogRedactor.removedAccount)
        XCTAssertEqual(placeholders["person"] as? String, LogRedactor.removedPersonPath)
        XCTAssertEqual(section["secretLength"] as? Int, LogRedactor.secretLength)
    }

    // MARK: - Following links

    /// The rules themselves are DATA here; the behaviour they describe is run
    /// against a real course in `AssistToolRunnerTests`, which reads the same
    /// two flags. Splitting it that way is deliberate: a synthetic page graph
    /// can be built to agree with whatever it is asked, and the thing worth
    /// testing is what happens to files on disk.
    @MainActor
    func testFollowingLinksIsDescribedWithItsReasons() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("followingLinks")

        let publishing: [String: Any] = try XCTUnwrap(section["publishing"] as? [String: Any])
        XCTAssertEqual(publishing["takesLinkedPages"] as? Bool, true)
        XCTAssertEqual(publishing["transitive"] as? Bool, true)
        XCTAssertEqual(publishing["disclosedInThePlan"] as? Bool, true)
        XCTAssertNotNil(publishing["why"] as? String)

        let unpublishing: [String: Any] = try XCTUnwrap(section["unpublishing"] as? [String: Any])
        XCTAssertEqual(unpublishing["aReferrerCountsOnlyWhenVisible"] as? Bool, true)
        XCTAssertNotNil(unpublishing["why"] as? String)

        XCTAssertEqual(
            (section["theOrderIsLoadBearing"] as? [String: Any])?["value"] as? Bool, true
        )
    }

    /// The kinds the sweep must never reach, each with the reason it is
    /// exempt — a list of exemptions nobody explained is a list nobody can
    /// safely change.
    @MainActor
    func testTheExclusionsTheContractNamesAreExplained() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("followingLinks")
        let kinds: [[String: Any]] = try XCTUnwrap(
            section["neverTakenDownByFollowingLinks"] as? [[String: Any]]
        )
        XCTAssertFalse(kinds.isEmpty)
        for kind in kinds {
            XCTAssertNotNil(kind["kind"] as? String)
            XCTAssertNotNil(kind["why"] as? String, "\(kind) has no reason")
        }
        var described: String = ""
        for kind in kinds {
            described += ((kind["kind"] as? String) ?? "") + " "
        }
        let all: String = described.lowercased()
        XCTAssertTrue(all.contains("key links"))
        XCTAssertTrue(all.contains("index.md"))
        XCTAssertTrue(all.contains("curriculum"))
    }

    // MARK: - Asking before the assistant changes anything

    @MainActor
    func testTheConfirmationSettingFollowsTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("assistantConfirmation")
        let defaults: UserDefaults = TestDefaults.make()
        let settings: AppSettings = AppSettings(defaults: defaults)

        if section["defaultsToOn"] as? Bool == true {
            XCTAssertTrue(settings.assistantAsksBeforeChanging)
        }

        let mentioned: [String: Any] = try XCTUnwrap(section["mentionedAfter"] as? [String: Any])
        let after: Int = try XCTUnwrap(mentioned["plansAccepted"] as? Int)
        XCTAssertEqual(AssistPlanMode.plansBeforeMentioningTheSetting, after)

        if section["sameOnBothAssistants"] as? [String: Any] != nil {
            for tier in AssistModelTier.allCases {
                let gate: AssistPlanMode = AssistPlanMode(
                    tier: tier, settings: AppSettings(defaults: TestDefaults.make())
                )
                XCTAssertTrue(gate.isOn, "\(tier) should ask by default")
                for _ in 0..<after {
                    gate.recordAccepted()
                }
                XCTAssertTrue(gate.shouldOfferToStop, "\(tier) was never told the setting exists")
                gate.stopAsking()
                XCTAssertFalse(gate.isOn, "\(tier) refused to be turned off")
            }
        }

        if (mentioned["appWide"] as? Bool) == true {
            let shared: UserDefaults = TestDefaults.make()
            let first: AssistPlanMode = AssistPlanMode(
                tier: .large, settings: AppSettings(defaults: shared)
            )
            first.recordAccepted()
            let second: AssistPlanMode = AssistPlanMode(
                tier: .large, settings: AppSettings(defaults: shared)
            )
            XCTAssertEqual(second.plansAccepted, 1, "The count reset when the window did")
        }
    }

    // MARK: - What a page is called

    /// Every case the contract lists, run against the real rule.
    ///
    /// The cases are the shapes a real course actually contains: a folder
    /// landing page with a title, one without, one whose title is the word
    /// that must never be shown, and two ordinary pages.
    @MainActor
    func testAPageIsNamedTheWayTheContractSays() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("pageNaming")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        let neverShown: String = try XCTUnwrap(section["neverShown"] as? String)

        for entry in cases {
            let file: String = try XCTUnwrap(entry["file"] as? String)
            let expected: String = try XCTUnwrap(entry["shown"] as? String)

            var pageText: String = "---\npublish: true\n---\n\nSome words.\n"
            if let declared = entry["frontmatterTitle"] as? String {
                pageText = "---\ntitle: \(declared)\npublish: true\n---\n\nSome words.\n"
            }

            let shown: String = AssistSectionGraph.displayName(
                forPageAt: URL(fileURLWithPath: "/courses/ADA1O/" + file), in: pageText
            )
            XCTAssertEqual(shown, expected, "\(file)")
            XCTAssertNotEqual(shown.lowercased(), neverShown.lowercased(),
                              "\(file) is shown to a teacher as “\(neverShown)”")
        }
    }

    /// The label may change; the IDENTITY may not. Wikilinks resolve by file
    /// name, so a page must still be findable by the name a teacher typed.
    @MainActor
    func testRenamingWhatIsShownDidNotChangeHowLinksResolve() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("pageNaming")
        let rule: [String: Any] = try XCTUnwrap(
            section["identityIsSeparateFromLabel"] as? [String: Any]
        )
        guard rule["value"] as? Bool == true else {
            return
        }
        let page: AssistSectionPage = AssistSectionPage(
            title: "index",
            displayTitle: "Portfolios",
            fileURL: URL(fileURLWithPath: "/courses/ADA1O/Portfolios/index.md"),
            relativePath: "courses/ADA1O/Portfolios/index.md",
            isSectionLocal: false,
            isVisibleToStudents: true,
            date: nil,
            linkedTitles: ["journal checklist"],
            classFolderNames: ["All Classes"],
            pathWithinSection: "Portfolios/index.md"
        )
        let graph: AssistSectionGraph = AssistSectionGraph(
            courseCode: "ADA1O", sectionNumber: 1, pages: [page]
        )
        XCTAssertNotNil(graph.page(titled: "index"),
                        "A link written [[index]] must still find the file called index")
        XCTAssertEqual(graph.page(titled: "index")?.displayTitle, "Portfolios")
    }

    // MARK: - Which assistant runs on this machine

    /// The three choices, their labels, and which of them name a rung.
    ///
    /// The list matters as much as the labels: dropping "Choose for me" and
    /// storing a resolved answer instead is the change that looks like a
    /// simplification and quietly freezes today's tier ladder into every
    /// teacher's preferences.
    @MainActor
    func testTheChoicesAreTheOnesTheContractLists() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("assistantModelChoice")
        let choices: [[String: Any]] = try XCTUnwrap(section["choices"] as? [[String: Any]])

        var keys: [String] = []
        for entry in choices {
            let key: String = try XCTUnwrap(entry["key"] as? String)
            keys.append(key)
            let choice: AssistModelChoice = try XCTUnwrap(
                AssistModelChoice(rawValue: key), "No choice called \(key)"
            )
            XCTAssertEqual(choice.label, entry["label"] as? String)
            XCTAssertEqual(choice.namedTier != nil, entry["namesATier"] as? Bool)
        }

        var known: [String] = []
        for choice in AssistModelChoice.allCases {
            known.append(choice.rawValue)
        }
        XCTAssertEqual(known.sorted(), keys.sorted())

        let fallback: String = try XCTUnwrap(section["defaultChoice"] as? String)
        XCTAssertEqual(AppSettings(defaults: TestDefaults.make()).assistantModelChoice.rawValue, fallback)
    }

    /// "Choose for me" keeps meaning choose for me: it resolves differently on
    /// different machines rather than naming a rung.
    func testTheAutomaticChoiceResolvesAtThePointOfUse() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("assistantModelChoice")
        let rule: [String: Any] = try XCTUnwrap(section["automaticResolvesAtPointOfUse"] as? [String: Any])
        guard rule["value"] as? Bool == true else {
            return
        }
        XCTAssertNil(AssistModelChoice.automatic.namedTier)
        XCTAssertNotEqual(
            AssistModelChoice.automatic.resolved(for: SharedRulesContractTests.machine(gigabytes: 8)),
            AssistModelChoice.automatic.resolved(for: SharedRulesContractTests.machine(gigabytes: 48))
        )
    }

    /// The comfort line, the caution it produces, and the promise that the
    /// automatic choice can never trip it.
    func testTheCautionFollowsTheFractionInTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("assistantModelChoice")
        let fraction: [String: Any] = try XCTUnwrap(section["comfortFraction"] as? [String: Any])
        let denominator: Int64 = Int64(try XCTUnwrap(fraction["denominator"] as? Int))

        let small: AssistHardwareBudget = SharedRulesContractTests.machine(gigabytes: 8)
        XCTAssertEqual(small.comfortableResidentBytes, small.physicalMemoryBytes / denominator)

        let caution: String = try XCTUnwrap(AssistModelChoice.larger.caution(for: small))
        XCTAssertTrue(caution.contains(small.memoryDescription))
        XCTAssertTrue(caution.contains(AssistModelTier.large.memoryDescription))

        for gigabytes in [4, 8, 16, 32, 48, 128] as [Int64] {
            XCTAssertNil(
                AssistModelChoice.automatic.caution(for: SharedRulesContractTests.machine(gigabytes: gigabytes)),
                "\(gigabytes) GB: the automatic ladder picked something it then warned about"
            )
        }
    }

    /// Both costs, on both rungs, and no model named anywhere the panel can
    /// put a sentence on screen.
    @MainActor
    func testWhatThePanelSaysFollowsTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("assistantModelChoice")
        let guidance: [String: Any] = try XCTUnwrap(section["guidance"] as? [String: Any])

        for tier in AssistModelTier.allCases {
            if guidance["mustNameDownloadSize"] as? Bool == true {
                XCTAssertTrue(tier.sizeGuidance.contains(tier.downloadDescription), "\(tier)")
            }
            if guidance["mustNameMemoryWhileWorking"] as? Bool == true {
                XCTAssertTrue(tier.sizeGuidance.contains(tier.memoryDescription), "\(tier)")
            }
        }

        let naming: [String: Any] = try XCTUnwrap(section["namesNoModel"] as? [String: Any])
        guard naming["value"] as? Bool == true else {
            return
        }
        let jargon: [String] = try XCTUnwrap(naming["jargon"] as? [String])

        var shown: [String] = []
        for gigabytes in [8, 48] as [Int64] {
            let machine: AssistHardwareBudget = SharedRulesContractTests.machine(gigabytes: gigabytes)
            for choice in AssistModelChoice.allCases {
                shown.append(choice.label)
                shown.append(choice.detail(for: machine))
                if let caution = choice.caution(for: machine) {
                    shown.append(caution)
                }
            }
            let panel: AssistModelLibrary = AssistModelLibrary(
                budget: machine, settings: AppSettings(defaults: TestDefaults.make())
            )
            shown.append(panel.whatHappensNext)
        }
        for tier in AssistModelTier.allCases {
            shown.append(tier.choiceLabel)
            shown.append(tier.sizeGuidance)
        }

        for sentence in shown {
            let lowered: String = sentence.lowercased()
            for word in jargon {
                XCTAssertFalse(lowered.contains(word), "\"\(sentence)\" says '\(word)' to a teacher")
            }
        }
    }

    /// Removing one: refused while an assistant is open, naming the section —
    /// and allowed for the rung currently chosen.
    @MainActor
    func testRemovingFollowsTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("assistantModelChoice")
        let removal: [String: Any] = try XCTUnwrap(section["removal"] as? [String: Any])

        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-contract-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        AssistModelStore.directoryOverride = folder
        AssistModelStores.reset()
        defer {
            AssistModelStores.reset()
            AssistModelStore.directoryOverride = nil
            try? FileManager.default.removeItem(at: folder)
        }

        let tier: AssistModelTier = .large
        let file: URL = folder.appendingPathComponent(tier.fileName)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle: FileHandle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(tier.downloadBytes))
        try handle.close()

        let panel: AssistModelLibrary = AssistModelLibrary(
            budget: SharedRulesContractTests.machine(gigabytes: 48),
            settings: AppSettings(defaults: TestDefaults.make())
        )

        if removal["refusedWhileAnyAssistantWindowIsOpen"] as? Bool == true {
            AssistActivity.begin(folderPath: "/tmp/contract", courseCode: "ICS3U", sectionNumber: 2)
            defer { AssistActivity.end(folderPath: "/tmp/contract", courseCode: "ICS3U", sectionNumber: 2) }
            XCTAssertFalse(panel.mayRemove(tier))
            if removal["messageNamesTheSectionToClose"] as? Bool == true {
                let reason: String = try XCTUnwrap(panel.reasonItCannotBeRemoved(tier))
                XCTAssertTrue(reason.contains("ICS3U"), reason)
                XCTAssertTrue(reason.contains("Section 2"), reason)
            }
        }

        if removal["theCurrentlyChosenOneMayBeRemoved"] as? Bool == true {
            XCTAssertEqual(panel.chosenTier, tier, "This test only means something for the chosen rung")
            XCTAssertTrue(panel.mayRemove(tier))
            panel.remove(tier)
            XCTAssertFalse(panel.isDownloaded(tier))
        }
    }

    /// A machine of a given size, for the rules above.
    private static func machine(gigabytes: Int64) -> AssistHardwareBudget {
        return AssistHardwareBudget(
            physicalMemoryBytes: gigabytes * 1_073_741_824,
            coreCount: 8,
            performanceCoreCount: 4
        )
    }

    // MARK: - What the trail must record

    /// The standing requirement, as a gate rather than as a paragraph.
    ///
    /// This is the test that makes "every new or changed feature leaves a
    /// line" mean something. Adding an event to the contract turns the mac
    /// suite red until the mac records it; dropping one the app still emits
    /// turns it red the other way. A prose rule in a handoff document gets
    /// read once; this gets read every run.
    func testTheTrailRecordsEveryEventTheContractRequires() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        let required: [[String: Any]] = try XCTUnwrap(section["mustRecord"] as? [[String: Any]])

        var wanted: [String] = []
        for entry in required {
            wanted.append(try XCTUnwrap(entry["event"] as? String))
            // An event nobody explained is an event nobody can implement.
            XCTAssertNotNil(entry["carries"] as? String, "\(entry) has no 'carries'")
            XCTAssertNotNil(entry["why"] as? String, "\(entry) has no 'why'")
        }
        wanted.sort()

        var recorded: [String] = ActivityTrail.eventKeys
        recorded.sort()

        XCTAssertEqual(
            recorded, wanted,
            "The trail and the contract disagree. Add the event to ActivityTrail.Event, "
            + "or to contracts/shared-rules.json, whichever is behind."
        )
    }

    /// The teacher's own words are behind a fixed prefix so a report can drop
    /// them without parsing anything — both apps must use the same one.
    func testThePromptMarkerIsTheOneInTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        let marker: [String: Any] = try XCTUnwrap(section["promptMarker"] as? [String: Any])
        XCTAssertEqual(marker["prefix"] as? String, AssistTurnRecord.promptMarker)
    }

    // MARK: - The dialog that asks what to send

    /// The question about the local AI assistant is only asked when there is
    /// something to ask about, and the note then says one of three things.
    func testTheReportDialogAsksAboutPromptsOnlyWhenTheContractSays() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("problemReportDialog")

        XCTAssertEqual(
            section["includePromptsLabel"] as? String,
            ProblemReportPresenter.includePromptsLabel
        )
        XCTAssertEqual(section["supportEmail"] as? String, ProblemReportBuilder.supportEmail)

        for testCase in try XCTUnwrap(section["askAboutPromptsWhen"] as? [[String: Any]]) {
            let hasPrompts: Bool = try XCTUnwrap(testCase["trailHasPromptLines"] as? Bool)
            let store: ProblemReportStore = try SharedRulesContractTests.storeWithTrail(
                includingAPrompt: hasPrompts
            )
            XCTAssertEqual(
                store.hasAssistantPrompts,
                try XCTUnwrap(testCase["expect"] as? String) == "ask",
                "prompt lines present: \(hasPrompts)"
            )
        }
    }

    /// Never used it, used it and kept it back, used it and sent it — three
    /// different things to be told.
    func testTheNoteSaysWhichOfTheThreeStatesApplies() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("problemReportDialog")
        let states: [[String: Any]] = try XCTUnwrap(section["promptStates"] as? [[String: Any]])
        XCTAssertEqual(states.count, 3)

        XCTAssertEqual(
            ProblemReportBuilder.promptState(hasAny: false, including: false), .none
        )
        XCTAssertEqual(
            ProblemReportBuilder.promptState(hasAny: false, including: true), .none
        )
        XCTAssertEqual(
            ProblemReportBuilder.promptState(hasAny: true, including: false), .excluded
        )
        XCTAssertEqual(
            ProblemReportBuilder.promptState(hasAny: true, including: true), .included
        )
    }

    /// A trail with, or without, a line carrying something the teacher typed.
    private static func storeWithTrail(includingAPrompt: Bool) throws -> ProblemReportStore {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dialog-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.appendActivityLine("2026-08-16 07:06:40 · started preview.sh COMP 1")
        if includingAPrompt {
            store.appendActivityLine(
                "2026-08-16 07:07:00 · COMP/1 · chose check_section(course, section)\n"
                + AssistTurnRecord.promptMarker + "What will students see?"
            )
        }
        return store
    }

    // MARK: - The working-folder path bar

    /// Only the crumb LIST is testable here — the gestures and the menu live
    /// in a view. The contract carries all four so Windows has the whole
    /// picture; this pins the half a test can reach.
    func testThePathBarListsEveryAncestor() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("workingFolderPathBar")
        let ancestors: [String: Any] = try XCTUnwrap(section["ancestorPaths"] as? [String: Any])

        for testCase in try XCTUnwrap(ancestors["cases"] as? [[String: Any]]) {
            let path: String = try XCTUnwrap(testCase["path"] as? String)
            XCTAssertEqual(
                FinderPathBarView.ancestorPaths(for: URL(fileURLWithPath: path)),
                try XCTUnwrap(testCase["expect"] as? [String]), path
            )
        }

        // And the two actions really are two different things, which is the
        // part Windows is missing — one reveals, one opens.
        let actions: [[String: Any]] = try XCTUnwrap(section["actions"] as? [[String: Any]])
        var named: [String] = []
        for action in actions {
            named.append(try XCTUnwrap(action["action"] as? String))
        }
        XCTAssertTrue(named.contains("reveal"), "\(named)")
        XCTAssertTrue(named.contains("open"), "\(named)")
    }

    // MARK: - What counts as a curriculum expectation

    func testCurriculumPagesAreRecognisedAsTheContractSays() throws {
        let rules: [String: Any] = try SharedRulesContractTests.section("curriculumRules")
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curriculum-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let course: Course = try makeCourse(in: root, target: nil, folderPath: root.path,
                                            hasDeployedBefore: true)

        let pages: [String: Any] = try XCTUnwrap(rules["isCurriculumPage"] as? [String: Any])
        for testCase in try XCTUnwrap(pages["cases"] as? [[String: Any]]) {
            let path: String = try XCTUnwrap(testCase["path"] as? String)
            let url: URL = course.directoryURL.appendingPathComponent("section1").appendingPathComponent(path)
            XCTAssertEqual(
                AssistCurriculumMentions.isCurriculum(pageAt: url, in: course),
                testCase["expect"] as? Bool, path
            )
        }

        let codes: [String: Any] = try XCTUnwrap(rules["isExpectationCode"] as? [String: Any])
        for testCase in try XCTUnwrap(codes["cases"] as? [[String: Any]]) {
            let code: String = try XCTUnwrap(testCase["code"] as? String)
            XCTAssertEqual(
                AssistCurriculumMentions.isExpectationCode(code), testCase["expect"] as? Bool, code
            )
        }

        let wording: [String: Any] = try XCTUnwrap(rules["expectationWording"] as? [String: Any])
        for testCase in try XCTUnwrap(wording["cases"] as? [[String: Any]]) {
            let body: String = try XCTUnwrap(testCase["body"] as? String)
            let page: String = """
            ---
            title: B2.1
            ---

            \(body)
            """
            XCTAssertEqual(
                AssistCurriculumMentions.wording(in: page),
                try XCTUnwrap(testCase["expect"] as? String), body
            )
        }
    }

    // MARK: - Private

    /// The contract names refusals by CASE. The sentences are the product's
    /// wording and belong to the wording contract; WHICH refusal fired has to
    /// match on both platforms.
    private static func name(ofRefusal said: String) -> String {
        if said.contains("has already passed") {
            return "hasAlreadyPassed"
        }
        // The ADDITIONAL-destination phrasings are checked first in each
        // pair — "also deploys to a folder" contains "deploys to a
        // folder", so checking the general one first would misclassify
        // every additional-destination refusal as the primary's.
        if said.contains("also deploys to a folder") {
            return "additionalDeployFolderNeedsAttention"
        }
        if said.contains("deploys to a folder") {
            return "deployFolderNeedsAttention"
        }
        if said.contains("also deploys to Cloudflare Pages") {
            return "additionalCloudflareAccountMissing"
        }
        if said.contains("Account ID") {
            return "cloudflareAccountMissing"
        }
        if said.contains("never been deployed to") {
            return "additionalDestinationNeverDeployed"
        }
        if said.contains("never been deployed") {
            return "neverDeployed"
        }
        return "other"
    }

    private func makeCourse(
        in root: URL, target: String?, folderPath: String,
        hasDeployedBefore: Bool,
        additionalTarget: String? = nil,
        additionalFolderPath: String = "",
        additionalTargetHasDeployedBefore: Bool = true
    ) throws -> Course {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        var configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
        ]
        if let target {
            configuration["deploy_target"] = target
            configuration["deploy_folder_path"] = folderPath
        }
        if let additionalTarget {
            var entry: [String: Any] = ["type": additionalTarget]
            if additionalTarget == "local_folder" {
                entry["path"] = additionalFolderPath
            }
            configuration["additional_deploy_targets"] = [entry]
        }
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        // Markers are keyed purely by destination TYPE, never by whether
        // that type is this course's primary or an additional one — see
        // DeployCommand.firstDeployMarkerURL. The primary's own marker
        // has always assumed netlify here, which happens to be correct
        // for every existing case (none combines hasDeployedBefore with a
        // non-netlify primary target).
        if hasDeployedBefore {
            let marker: URL = courseURL.appendingPathComponent(".netlify_sites")
            try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
            try "{}".write(to: marker.appendingPathComponent("section1.json"),
                           atomically: true, encoding: .utf8)
        }
        if let additionalTarget, additionalTarget != "local_folder", additionalTargetHasDeployedBefore {
            let folderName: String = additionalTarget == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites"
            let marker: URL = courseURL.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
            try "{}".write(to: marker.appendingPathComponent("section1.json"),
                           atomically: true, encoding: .utf8)
        }
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    private func makeCourseFolder(code: String, name: String, in root: URL) throws {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent(code)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        let configuration: [String: Any] = [
            "course_code": code,
            "course_name": name,
            "section_numbers": [1],
            "num_sections": 1,
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
    }

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in shared-rules.json")
    }
}
