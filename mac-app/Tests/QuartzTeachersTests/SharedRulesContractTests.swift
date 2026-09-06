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

    // MARK: - Special names and folder protections

    func testSpecialNamesSentencesMatchContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")

        let excludedNote: [String: Any] = try XCTUnwrap(section["excludedFolderIndexNote"] as? [String: Any])
        XCTAssertEqual(SpecialNames.excludedFolderIndexNoteBody, excludedNote["noteBody"] as? String)
        XCTAssertEqual(SpecialNames.excludedFolderSentinelStart, excludedNote["sentinelStart"] as? String)
        XCTAssertEqual(SpecialNames.excludedFolderSentinelEnd, excludedNote["sentinelEnd"] as? String)

        let covSetting: [String: Any] = try XCTUnwrap(section["curriculumFolderBlockedByCoverageSetting"] as? [String: Any])
        XCTAssertEqual(SpecialNames.curriculumFolderBlockedByCoverageSetting, covSetting["reason"] as? String)

        let covMap: [String: Any] = try XCTUnwrap(section["curriculumFolderBlockedByCoverageMap"] as? [String: Any])
        XCTAssertEqual(SpecialNames.curriculumFolderBlockedByCoverageMap, covMap["reason"] as? String)

        let curPages: [String: Any] = try XCTUnwrap(section["curriculumFolderBlockedByCurriculumPages"] as? [String: Any])
        let expectedCurPagesTemplate: String = try XCTUnwrap(curPages["reason"] as? String)
        let actualCurPages: String = SpecialNames.curriculumFolderBlockedByCurriculumPages(jurisdiction: "Ontario")
        XCTAssertEqual(actualCurPages, expectedCurPagesTemplate.replacingOccurrences(of: "{jurisdiction}", with: "Ontario"))

        let lastGraded: [String: Any] = try XCTUnwrap(section["lastGradedFolderBlocked"] as? [String: Any])
        XCTAssertEqual(SpecialNames.lastGradedFolderBlocked, lastGraded["reason"] as? String)

        let lastGradedWiz: [String: Any] = try XCTUnwrap(section["lastGradedFolderBlockedWizard"] as? [String: Any])
        XCTAssertEqual(SpecialNames.lastGradedFolderBlockedWizard, lastGradedWiz["reason"] as? String)

        let classBlocked: [String: Any] = try XCTUnwrap(section["classFolderBlocked"] as? [String: Any])
        XCTAssertEqual(SpecialNames.classFolderBlocked, classBlocked["reason"] as? String)

        let lastPerSec: [String: Any] = try XCTUnwrap(section["lastPerSectionFolderBlocked"] as? [String: Any])
        XCTAssertEqual(SpecialNames.lastPerSectionFolderBlocked, lastPerSec["reason"] as? String)

        let secIndex: [String: Any] = try XCTUnwrap(section["sectionIndexFileBlocked"] as? [String: Any])
        XCTAssertEqual(SpecialNames.sectionIndexFileBlocked, secIndex["reason"] as? String)

        let remGraded: [String: Any] = try XCTUnwrap(section["removeGradedFolderConfirmation"] as? [String: Any])
        XCTAssertEqual(SpecialNames.removeGradedFolderMessage, remGraded["message"] as? String)
        XCTAssertEqual(SpecialNames.removeGradedFolderTitle(for: "Tasks"), (remGraded["title"] as? String)?.replacingOccurrences(of: "{name}", with: "Tasks"))

        let remCurriculum: [String: Any] = try XCTUnwrap(section["removeCurriculumFolderConfirmation"] as? [String: Any])
        XCTAssertEqual(SpecialNames.removeCurriculumFolderMessage, remCurriculum["message"] as? String)
        XCTAssertEqual(SpecialNames.removeCurriculumFolderTitle(for: "Curriculum"), (remCurriculum["title"] as? String)?.replacingOccurrences(of: "{name}", with: "Curriculum"))

        let rename: [String: Any] = try XCTUnwrap(section["renameFolder"] as? [String: Any])
        XCTAssertEqual(SpecialNames.renameFolderExplanation, rename["explanation"] as? String)
        XCTAssertEqual(
            SpecialNames.renameFolderTitle(for: "Tasks"),
            (rename["sheetTitle"] as? String)?.replacingOccurrences(of: "{name}", with: "Tasks")
        )
        XCTAssertEqual(
            SpecialNames.renameFolderDone(from: "Tasks", to: "Assessments"),
            (rename["done"] as? String)?
                .replacingOccurrences(of: "{old}", with: "Tasks")
                .replacingOccurrences(of: "{new}", with: "Assessments")
        )
        XCTAssertEqual(SpecialNames.renameFolderRelinked(pages: 0), rename["doneRelinkedNone"] as? String)
        XCTAssertEqual(SpecialNames.renameFolderNothingWasThere, rename["doneNothingWasThere"] as? String)
        XCTAssertEqual(SpecialNames.renameFolderRelinked(pages: 1), rename["doneRelinkedOne"] as? String)
        XCTAssertEqual(
            SpecialNames.renameFolderRelinked(pages: 4),
            (rename["doneRelinkedMany"] as? String)?.replacingOccurrences(of: "{count}", with: "4")
        )

        let renameProblems: [String: Any] = try XCTUnwrap(rename["problems"] as? [String: Any])
        XCTAssertEqual(SpecialNames.renameFolderProblemEmpty, renameProblems["empty"] as? String)
        XCTAssertEqual(SpecialNames.renameFolderProblemUnchanged, renameProblems["unchanged"] as? String)
        XCTAssertEqual(SpecialNames.renameFolderProblemHasSeparator, renameProblems["hasSeparator"] as? String)
        XCTAssertEqual(SpecialNames.renameFolderProblemIsHidden, renameProblems["isHidden"] as? String)
        XCTAssertEqual(SpecialNames.renameFolderProblemIsMedia, renameProblems["isMedia"] as? String)
        XCTAssertEqual(
            SpecialNames.renameFolderProblemAlreadyUsed(name: "Tasks"),
            (renameProblems["alreadyUsed"] as? String)?.replacingOccurrences(of: "{name}", with: "Tasks")
        )
        XCTAssertEqual(
            SpecialNames.renameFolderProblemLooksLikeASection(name: "section3"),
            (renameProblems["looksLikeASection"] as? String)?.replacingOccurrences(of: "{name}", with: "section3")
        )
        XCTAssertEqual(
            SpecialNames.renameFolderProblemDestinationExists(name: "Tasks"),
            (renameProblems["destinationExists"] as? String)?.replacingOccurrences(of: "{name}", with: "Tasks")
        )

        let added: [String: Any] = try XCTUnwrap(section["addCreatesTheFolder"] as? [String: Any])
        XCTAssertEqual(
            SpecialNames.addCreatesTheFolderMessage(name: "Tests"),
            (added["message"] as? String)?.replacingOccurrences(of: "{name}", with: "Tests")
        )

        let removed: [String: Any] = try XCTUnwrap(section["removeLeavesTheFolderOnDisk"] as? [String: Any])
        XCTAssertEqual(
            SpecialNames.removeLeavesTheFolderOnDiskMessage(name: "Tests"),
            (removed["message"] as? String)?.replacingOccurrences(of: "{name}", with: "Tests")
        )
    }

    /// Every key the contract says a rename carries across is one the renamer
    /// actually rewrites. A key added to the list and not to the code is the
    /// failure this catches — the config would then name a folder that is not
    /// there, which is the state the whole feature exists to make impossible.
    func testEveryKeyARenameCarriesAcrossIsActuallyRewritten() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")
        let rename: [String: Any] = try XCTUnwrap(section["renameFolder"] as? [String: Any])
        let keys: [String] = try XCTUnwrap(rename["carriesAcross"] as? [String])

        let before: [String: Any] = [
            "shared_folders": ["Tasks"],
            "per_section_folders": ["Tasks"],
            "graded_folders": ["Tasks"],
            "curriculum_folder": "Tasks",
            "class_folder": "Tasks",
            "hidden": ["Tasks", "Private Notes.md"],
            "expandable": ["Tasks", "Concepts"],
            "excluded_items": ["shared": ["Tasks"], "per_section": ["Tasks"]],
        ]
        let afterShared: [String: Any] = SpecialFolderRenamer.renaming(
            "Tasks", to: "Assessments", scope: .shared, in: before
        )
        let afterPerSection: [String: Any] = SpecialFolderRenamer.renaming(
            "Tasks", to: "Assessments", scope: .perSection, in: before
        )

        for key in keys {
            switch key {
            case "shared_folders":
                XCTAssertEqual(afterShared[key] as? [String], ["Assessments"])
            case "per_section_folders":
                XCTAssertEqual(afterPerSection[key] as? [String], ["Assessments"])
            case "graded_folders":
                XCTAssertEqual(afterShared[key] as? [String], ["Assessments"])
            case "hidden":
                // The dangerous one: left naming the old folder, a rename
                // un-hides it and the next publish shows students pages the
                // teacher hid.
                XCTAssertEqual(afterShared[key] as? [String], ["Assessments", "Private Notes.md"])
                XCTAssertEqual(afterPerSection[key] as? [String], ["Assessments", "Private Notes.md"])
            case "expandable":
                XCTAssertEqual(afterShared[key] as? [String], ["Assessments", "Concepts"])
            case "curriculum_folder":
                XCTAssertEqual(afterShared[key] as? String, "Assessments")
                XCTAssertEqual(
                    afterPerSection[key] as? String, "Tasks",
                    "The curriculum folder is SHARED; a per-section rename must not touch it"
                )
            case "class_folder":
                // Carried by the per-section rename: a class folder is a
                // per-section folder, and a SHARED rename of a name that
                // happens to match must not touch it.
                XCTAssertEqual(afterPerSection[key] as? String, "Assessments")
                XCTAssertEqual(
                    afterShared[key] as? String, "Tasks",
                    "The class folder is PER-SECTION; a shared rename must not touch it"
                )
            case "excluded_items":
                // Each scope's list is rewritten by a rename in THAT scope and
                // left alone by the other — the whole reason the key is keyed
                // by scope is that the same bare name can exist in both.
                let shared: [String: Any] = try XCTUnwrap(afterShared[key] as? [String: Any])
                XCTAssertEqual(shared["shared"] as? [String], ["Assessments"])
                XCTAssertEqual(shared["per_section"] as? [String], ["Tasks"])
                let perSection: [String: Any] = try XCTUnwrap(afterPerSection[key] as? [String: Any])
                XCTAssertEqual(perSection["per_section"] as? [String], ["Assessments"])
                XCTAssertEqual(perSection["shared"] as? [String], ["Tasks"])
            default:
                XCTFail("The contract says a rename carries \(key) across, and nothing here checks it.")
            }
        }
    }

    func testCurriculumFolderResolutionCases() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")
        let resolutionSection: [String: Any] = try XCTUnwrap(section["curriculumFolderResolution"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(resolutionSection["cases"] as? [[String: Any]])

        for testCase in cases {
            let configured: String? = testCase["configured"] as? String
            let folders: [String] = try XCTUnwrap(testCase["folders"] as? [String])
            let expected: String? = testCase["resolved"] as? String
            let why: String = testCase["why"] as? String ?? ""

            let actual: String? = CurriculumFolderRule.resolvedCurriculumFolder(configured: configured, in: folders)
            XCTAssertEqual(actual, expected, "Failed case: \(why)")
        }
    }

    // MARK: - Functions

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

    // MARK: - Where built websites are kept

    /// The contract states the two paths a built website is found at, with
    /// `{home}` and `{folder id}` standing in — and the app computes exactly
    /// those. Written out rather than left implicit because the launchers are
    /// a second implementation of this rule and the contract is what they are
    /// both written against: if the app's answer drifts, the app and the
    /// command line build into different places and every build reads as
    /// stale, which is precisely the failure this section exists to stop.
    func testTheBuiltWebsiteIsWhereTheContractSaysItIs() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("buildOutputLocation")
        let macLocation: [String: Any] = try XCTUnwrap(section["macLocation"] as? [String: Any])

        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        let folder: URL = URL(fileURLWithPath: "/tmp/some working folder")
        let identifier: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: folder.path)

        func filledIn(_ key: String) throws -> String {
            return try XCTUnwrap(macLocation[key] as? String)
                .replacingOccurrences(of: "{home}", with: home.path)
                .replacingOccurrences(of: "{folder id}", with: identifier)
                .replacingOccurrences(of: "{COURSE}", with: "ICS3U")
        }

        // The REAL rule, as a pure function of the home folder: the live
        // buildsRoot answers a temporary folder while the suite runs so that
        // no test can write into the teacher's own Application Support.
        let real: URL = BuildOutputLocation.buildsRoot(inHomeFolder: home)
            .appendingPathComponent(identifier)
        XCTAssertEqual(real.path, try filledIn("buildsRoot"))
        XCTAssertEqual(real.appendingPathComponent("ICS3U").path, try filledIn("perCourse"))
        XCTAssertEqual(
            BuildOutputLocation.workingFolderMarkerName,
            "working-folder.txt",
            "the contract's macLocation.workingFolderMarker names this file"
        )
        XCTAssertTrue(
            try XCTUnwrap(macLocation["workingFolderMarker"] as? String)
                .contains(BuildOutputLocation.workingFolderMarkerName)
        )
    }

    /// Every launcher carries the same rule, because a teacher at the command
    /// line and a publish scheduled with launchd have no app to do it for
    /// them. Checked against the shell itself: all three must define the
    /// builds root, create it before the container, mount it at its own
    /// absolute path, and recreate a container that was made without it.
    func testEveryLauncherCarriesTheSameRule() throws {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for launcher in ["setup.sh", "preview.sh", "deploy.sh"] {
            let text: String = try String(
                contentsOf: repository.appendingPathComponent(launcher), encoding: .utf8
            )
            XCTAssertTrue(
                text.contains("Library/Application Support/Plantoir/builds/${WORKDIR_ID}"),
                "\(launcher) does not know where built websites go"
            )
            XCTAssertTrue(
                text.contains("-v \"$BUILD_ROOT\":\"$BUILD_ROOT\""),
                "\(launcher) does not mount the builds folder at its own absolute path, so the link would dangle inside the container"
            )
            // The DEFINITION is not the behaviour. An earlier version of this
            // test matched only the function names and the mount flag, and
            // passed with `setup.sh` never calling the function at all — so
            // each of these asks for the CALL, on its own line.
            XCTAssertTrue(
                text.contains("\n  elif ! container_has_builds_mount; then"),
                "\(launcher) defines the check but never branches on it, so a container made before this change keeps running without the mount — and a mount cannot be added to a container that exists"
            )
            XCTAssertTrue(
                text.contains("\n  ensure_build_root\n  docker run -dit"),
                "\(launcher) creates the container without making the builds folder first — a bind mount whose source is missing gives the container an empty folder of its own, and the built website goes nowhere"
            )
            XCTAssertTrue(
                text.contains("\nlink_course_build_output \"$")
                    || text.contains("\n  link_course_build_output \"$"),
                "\(launcher) never calls link_course_build_output, so it does nothing about where the built website goes"
            )
        }
    }

    // MARK: - Stopping a section's preview

    /// The mac app does not implement this rule — it shells out to
    /// `preview.sh --stop`, and the rule itself lives in
    /// `scripts/stop_preview.py`, run against these cases by
    /// `scripts/test_stop_preview.py`. What the mac suite is for here is the
    /// SHAPE: that the cases exist, that they are well formed, and that the
    /// launcher on this side still delegates rather than growing a fourth
    /// copy of the question. The same precedent as `gradedFolders`.
    func testStopPreviewCasesAreWellFormed() throws {
        let rule: [String: Any] = try Self.section("stopPreview")
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(
            cases.count, 23,
            "the stopPreview case list has lost cases; it is the only gate on a rule that "
                + "used to be written out three times"
        )
        var modesSeen: Set<String> = []
        for oneCase in cases {
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            let mode: String = try XCTUnwrap(oneCase["mode"] as? String, "\(name) has no mode")
            modesSeen.insert(mode)
            XCTAssertNotNil(oneCase["why"] as? String, "\(name) does not say why it exists")
            let section: [String: Any] = try XCTUnwrap(
                oneCase["section"] as? [String: Any], "\(name) names no section"
            )
            let directories: [String] = try XCTUnwrap(section["directories"] as? [String])
            XCTAssertFalse(directories.isEmpty, "\(name) gives no build directory")
            // A blank directory is a prefix of every path, so a case carrying
            // one would sweep an entire container — that was a real hole in
            // the rule, found by review. One case tests it ON PURPOSE and
            // says so in its name; anything else with a blank is a mistake.
            if !name.contains("blank build directory") {
                for directory in directories {
                    XCTAssertFalse(
                        directory.isEmpty,
                        "\(name) carries a blank build directory, which matches everything"
                    )
                }
            }
            // A case that only some platforms can answer must SAY so, and
            // may name only evidence a platform can genuinely lack.
            if let needs = oneCase["needsEvidence"] as? [String] {
                XCTAssertFalse(needs.isEmpty, "\(name) has an empty needsEvidence")
                for evidence in needs {
                    XCTAssertEqual(
                        evidence, "workingDirectory",
                        "\(name) excuses a runner from '\(evidence)', which every platform "
                            + "can see; the only evidence a platform genuinely lacks is a "
                            + "working directory, and Windows is the platform"
                    )
                }
            }
            let snapshot: [[String: Any]] = try XCTUnwrap(
                oneCase["snapshot"] as? [[String: Any]], "\(name) has no process snapshot"
            )
            XCTAssertFalse(snapshot.isEmpty, "\(name) has an empty snapshot")
            let pids: Set<Int> = Set(snapshot.compactMap { process in process["pid"] as? Int })
            XCTAssertEqual(pids.count, snapshot.count, "\(name) reuses a process id")
            let stops: [Int] = try XCTUnwrap(oneCase["stops"] as? [Int], "\(name) has no verdict")
            for stopped in stops {
                XCTAssertTrue(
                    pids.contains(stopped),
                    "\(name) expects pid \(stopped) to be stopped and its snapshot has no such process"
                )
            }
        }
        XCTAssertEqual(
            modesSeen, ["everything", "servingOnly"],
            "both questions must be covered: what `--stop` reclaims, and what a build for "
                + "publishing removes from its own way"
        )
    }

    // The launcher's own half of this — that `preview.sh` delegates to the
    // shared rule, keeps no sweep of its own, and pipes the code in rather
    // than naming a path baked into the image — is asserted ONCE, in
    // `scripts/test_stop_preview.py` (`ThereIsOnlyOneCopyOfTheRule`), which
    // runs in `verify.sh` beside the rule it protects. It was asserted here
    // too for a while; two gates checking the same three substrings of the
    // same file is the shape that drifts, and the toolchain's gate is the
    // right home for a claim about a toolchain file.

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
