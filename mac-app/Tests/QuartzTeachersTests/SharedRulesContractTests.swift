import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` — the rule sets both apps need and
/// neither platform owns.
///
/// Deliberately no count. This said "five" while the file held twenty, and the
/// file's own note said "eight"; a number in prose beside a list that grows is
/// a number that goes stale, and both of these proved it.
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
            let event: String = try XCTUnwrap(entry["event"] as? String)
            // An event nobody explained is an event nobody can implement.
            XCTAssertNotNil(entry["carries"] as? String, "\(entry) has no 'carries'")
            XCTAssertNotNil(entry["why"] as? String, "\(entry) has no 'why'")

            if SharedRulesContractTests.macMustRecord(entry) {
                wanted.append(event)
            }
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

    /// Whether a `mustRecord` entry is one the MAC has to record.
    ///
    /// `appliesOn` names the platforms an event belongs to; an entry without
    /// it belongs to both.
    ///
    /// **Honouring it is not a loosening**, and that is the part worth
    /// keeping. The assertion in the test above is still EQUALITY, so an event
    /// this app records and the contract does not still fails, and so does a
    /// both-platform event the app has forgotten. All this does is stop one
    /// platform's event reddening the other's suite forever.
    ///
    /// Windows added the same filter to its twin first, and its reason is the
    /// one that matters: the mac's own `built site moved out of the working
    /// folder` is `appliesOn: ["mac"]`, and until Windows filtered it, it held
    /// the WINDOWS suite red no matter what was implemented there — and a test
    /// that cannot go green stops being read. The mac met the mirror image on
    /// 2026-09-07, the day Windows proposed its first windows-only event.
    ///
    /// There is no windows-only entry in the contract as this is written —
    /// `section restored` dropped its `appliesOn` when the mac adopted it —
    /// so `SectionRestoredTrailTests` exercises this with entries of its own
    /// rather than leaving it to be discovered wrong by whoever adds the next
    /// one. (Windows' filter is still exercised by the data, because the
    /// mac-only `built site moved out of the working folder` remains.)
    ///
    /// **Anything it cannot READ as a platform list means "both".** Not just a
    /// value of the wrong type: an EMPTY list, or one naming no platform this
    /// knows — `["macos"]`, `["Mac"]`, a typo like `["windwos"]` — would
    /// otherwise excuse the event from both suites at once, silently, which is
    /// the exact failure the list exists to prevent. Erring towards "required"
    /// makes a typo show up as a red suite naming the event, which is a
    /// five-minute fix; erring the other way makes it disappear, which is
    /// nobody's five minutes because nobody finds out.
    static func macMustRecord(_ entry: [String: Any]) -> Bool {
        guard let platforms = entry["appliesOn"] as? [String] else {
            return true
        }
        var namesAPlatformThisKnows: Bool = false
        for platform in platforms {
            if platform == "mac" || platform == "windows" {
                namesAPlatformThisKnows = true
            }
        }
        if !namesAPlatformThisKnows {
            return true
        }
        return platforms.contains("mac")
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

    // MARK: - The New Course wizard's words

    /// The button a teacher presses to make a course says what the contract says.
    ///
    /// AUTHORED rather than generated, deliberately. Were this key written by
    /// `--write-contracts`, changing the button would rewrite the contract to
    /// match it and this test could never fail — which is the difference
    /// `AppRulesContract` draws between a readout and an expectation, and the
    /// reason this one is written by hand.
    func testTheWizardsCreateButtonIsTheOneInTheContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("wizard")

        XCTAssertEqual(
            WizardWording.createCourseButton,
            section["createCourseButton"] as? String,
            "The wizard's affirmative button and contracts/shared-rules.json → wizard "
            + "disagree. Both apps show this button and have said the same word since "
            + "the wizard existed; change it in the contract and in both apps, or not "
            + "at all."
        )
    }

    // MARK: - What a teacher reads on the Marks control

    /// The Marks tick list's title and its caption are the contract's, word
    /// for word. Pinned because they are sentences a teacher reads, and
    /// because the two apps worded them differently from the day the control
    /// was built with nothing to catch it — `gradedFolders.wording`, proposed
    /// from Windows 2026-09-08 and adopted here 2026-09-09 (issue #71).
    func testTheMarksWordingIsTheContractsOwn() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("gradedFolders")
        let wording: [String: Any] = try XCTUnwrap(section["wording"] as? [String: Any])

        XCTAssertEqual(
            GradedFolderWording.listTitle,
            wording["listTitle"] as? String,
            "The Marks list's title and contracts/shared-rules.json → gradedFolders.wording "
            + "disagree. Four surfaces show this title — Course Settings and the New Course "
            + "wizard, on both platforms — so change it in the contract and in both apps, or "
            + "not at all."
        )
        XCTAssertEqual(
            GradedFolderWording.caption,
            wording["caption"] as? String,
            "The Marks list's caption and contracts/shared-rules.json → gradedFolders.wording "
            + "disagree. Same four surfaces, same rule."
        )
    }

    /// The caption names only actions this control actually offers.
    ///
    /// It is a tick list: `MembershipToggleListView` draws check boxes and has
    /// no Add button, so a teacher told to "add Tests" is being pointed at a
    /// control that cannot do it — and "remove what you don't" invites the one
    /// action the product refuses outright, unticking the last graded folder
    /// while the coverage map is on (`SpecialNames.lastGradedFolderBlocked`).
    /// **Both verbs were the mac's own wording until this test existed**,
    /// which is why the correction is asserted rather than left to review.
    ///
    /// Whole words, and that matters twice over: a plain "does not contain
    /// add" lets through "adding" and a sentence-initial "Add", while the
    /// obvious tightening — anything starting "add" — matches "ADDRESSES it",
    /// which this caption legitimately contains. Windows' half of this
    /// (`TheMarksCaptionNamesOnlyActionsThisControlOffers`) records the same
    /// two failed alternatives.
    func testTheMarksCaptionNamesOnlyActionsThisControlOffers() {
        let caption: String = GradedFolderWording.caption

        XCTAssertTrue(
            SharedRulesContractTests.caption(caption, containsWord: "tick"),
            "The Marks caption stopped telling a teacher to tick anything."
        )

        var verbsFound: [String] = []
        // Eight forms where Windows' half of this test bans six: "anything
        // you added" is the same wrong promise in the past tense, and nothing
        // in this caption legitimately says either word. Windows could match
        // it and nothing breaks if it does not — this is code on each side
        // rather than contract data, so the two lists may differ.
        for verb in ["add", "adds", "adding", "added", "remove", "removes", "removing", "removed"] {
            if SharedRulesContractTests.caption(caption, containsWord: verb) {
                verbsFound.append(verb)
            }
        }
        XCTAssertEqual(
            verbsFound, [],
            "The Marks caption names an action this control does not offer: "
            + "\(verbsFound). It is a tick list with no Add button, and unticking the "
            + "last graded folder while the coverage map is on is refused outright."
        )
    }

    /// Both surfaces draw these sentences from the one constant, and no third
    /// copy exists.
    ///
    /// A contract test alone cannot see this: `GradedFolderWording` could
    /// match the contract perfectly while a view quietly went on rendering a
    /// literal of its own, which is the state this whole issue was fixing.
    /// The scan is the shape `ActivityTrailWiringTests` uses — and reuses its
    /// scanner rather than growing a second one.
    func testBothSurfacesDrawTheMarksWordingFromOneHome() throws {
        let productFolderURL: URL = ActivityTrailWiringTests.productSourceFolderURL()
        let viewFileNames: [String] = ["CourseSettingsView.swift", "NewCourseWizardView.swift"]

        for fileName in viewFileNames {
            let fileURL: URL = try XCTUnwrap(
                SharedRulesContractTests.fileNamed(fileName, under: productFolderURL),
                "\(fileName) was not found where this test expects it, so the checks below would pass vacuously."
            )
            let contents: String = try String(contentsOf: fileURL, encoding: .utf8)
            // Outside comments, so a doc note NAMING the constant cannot stand
            // in for a view that actually draws from it.
            XCTAssertTrue(
                SharedRulesContractTests.source(contents, uses: "GradedFolderWording.listTitle"),
                "\(fileName) no longer takes the Marks list's title from GradedFolderWording, so it can drift from the contract without a test noticing."
            )
            XCTAssertTrue(
                SharedRulesContractTests.source(contents, uses: "GradedFolderWording.caption"),
                "\(fileName) no longer takes the Marks caption from GradedFolderWording, so it can drift from the contract without a test noticing."
            )
        }

        // A fragment rather than the whole sentence: a second copy written as
        // concatenated pieces across lines — which is exactly how the near-twin
        // at SpecialFoldersHelpView is written — would slip past a
        // whole-sentence search. Taken from the constant, never retyped, so the
        // needle cannot drift from what the app shows.
        //
        // Honest about its reach: this is a PASTE-BACK guard, not an
        // adversarial one. The needle is the caption's first 24 characters, so
        // a copy split before that point, and any paraphrase, evades it — the
        // reference checks above are what catch a view that stops using the
        // constant at all.
        let captionOpening: String = String(GradedFolderWording.caption.prefix(24))
        var filesWithACopy: [String] = []
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: productFolderURL) {
            if fileURL.lastPathComponent == "GradedFolderWording.swift" {
                continue
            }
            let contents: String = try String(contentsOf: fileURL, encoding: .utf8)
            for line in contents.components(separatedBy: "\n") {
                let trimmedLine: String = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.hasPrefix("//") {
                    continue
                }
                if trimmedLine.contains(captionOpening) || trimmedLine.contains(GradedFolderWording.listTitle) {
                    filesWithACopy.append(fileURL.lastPathComponent)
                    break
                }
            }
        }
        XCTAssertEqual(
            filesWithACopy, [],
            "These files carry their own copy of a Marks sentence: \(filesWithACopy). "
            + "There is one home for both of them, GradedFolderWording, because four "
            + "literals on two surfaces is the state issue #71 fixed."
        )
    }

    /// The caption is drawn BELOW its list, which the contract requires by
    /// name (`gradedFolders.wording.rule`): it says "a page in one of these",
    /// and above the list "these" follows the section header "Marks" and
    /// refers to nothing. Windows drew it above until 2026-09-08 and moved.
    ///
    /// Source order IS stacking order inside the `Section` and `VStack` these
    /// two live in, so this reads it there. **A hosted-view geometry check was
    /// rejected**: `Form` and `Section` render lazily on macOS, so a walk of
    /// the view tree would have to fight the layout for an answer source order
    /// already gives — Windows asserts real UI-Automation tree order in
    /// `CourseSettingsCaptionUiTests.TheMarksCaptionIsOnScreenBelowItsList`,
    /// which it can because its list is built into a panel eagerly.
    ///
    /// **What this reaches**: the FIRST non-comment mention of each constant in
    /// the file, not the pair inside that one `Section`. Exact while each view
    /// references each constant once, which both do today — but a view that
    /// gained an earlier mention of `listTitle` that draws nothing (a stored
    /// property, a `.help(…)`) could pass this with the caption above its list.
    func testTheMarksCaptionIsDrawnBelowItsList() throws {
        let productFolderURL: URL = ActivityTrailWiringTests.productSourceFolderURL()

        for fileName in ["CourseSettingsView.swift", "NewCourseWizardView.swift"] {
            let fileURL: URL = try XCTUnwrap(
                SharedRulesContractTests.fileNamed(fileName, under: productFolderURL),
                "\(fileName) was not found where this test expects it."
            )
            let lines: [String] = try String(contentsOf: fileURL, encoding: .utf8)
                .components(separatedBy: "\n")

            var titleLine: Int = -1
            var captionLine: Int = -1
            var lineNumber: Int = 0
            for line in lines {
                // Comments skipped, as ActivityTrailWiringTests does: a note
                // ABOVE the list that happens to name the caption constant
                // would otherwise read as the caption itself being drawn there.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    lineNumber += 1
                    continue
                }
                if titleLine < 0 && line.contains("GradedFolderWording.listTitle") {
                    titleLine = lineNumber
                }
                if captionLine < 0 && line.contains("GradedFolderWording.caption") {
                    captionLine = lineNumber
                }
                lineNumber += 1
            }

            XCTAssertGreaterThan(titleLine, -1, "\(fileName) does not draw the Marks list.")
            // Answered here and not left to the comparison below: a missing
            // caption makes captionLine -1, which loses to any title line, so
            // the comparison would report a caption drawn ABOVE its list when
            // there is no caption at all. Measured — it said exactly that.
            if captionLine < 0 {
                XCTFail("\(fileName) does not draw the Marks caption at all.")
                continue
            }
            XCTAssertGreaterThan(
                captionLine, titleLine,
                "\(fileName) draws the Marks caption ABOVE its list. The caption says "
                + "\"a page in one of these\", which points at the list; above it, "
                + "\"these\" refers to the section header and to nothing else. "
                + "contracts/shared-rules.json → gradedFolders.wording.rule requires it below."
            )
        }
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

    /// The record of platform-worded sentences is COMPLETE, not a snapshot.
    ///
    /// `platformWording.keys` names every `specialNames` sentence containing the
    /// mac's platform word, so the other platform's suite can substitute its own
    /// word rather than assert the mac's.
    ///
    /// It pins the RECORD, not the behaviour, and the difference is worth
    /// stating: nothing on Windows reads `keys` today — its two tests name the
    /// sentences one at a time — so a fourth sentence fails HERE and still
    /// leaves a Windows test to be written by hand. What this buys is that the
    /// list cannot silently fall behind the contract it describes.
    ///
    /// The provenance, because two passes at the surrounding note got it wrong
    /// in opposite directions: issue #102 named two of the three, the mac's own
    /// log had all three from 2026-09-01 (GUI-IMPROVEMENTS.md rows 388-389),
    /// and Windows began substituting on the third on 2026-09-07. The list was
    /// never wrong; one issue body was.
    func testPlatformWordedKeysAreComplete() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")
        let platformWording: [String: Any] = try XCTUnwrap(section["platformWording"] as? [String: Any])
        let macWord: String = try XCTUnwrap(platformWording["mac"] as? String)

        var found: [String] = []
        collectKeyPaths(saying: macWord, in: section, prefix: "", into: &found)
        found.sort()

        var recorded: [String] = try XCTUnwrap(platformWording["keys"] as? [String])
        recorded.sort()

        // Both empty is the one way this passes having checked nothing: an
        // emptied `mac` matches nothing, and an emptied `keys` expects nothing.
        // MilestoneContractTests guards its mirror of this the same way.
        XCTAssertFalse(
            found.isEmpty,
            "No specialNames sentence contains the platform word \"\(macWord)\", so this "
            + "test would pass against an empty record. Either the word changed or "
            + "platformWording.mac is wrong."
        )

        XCTAssertEqual(
            found,
            recorded,
            "The specialNames sentences containing \"\(macWord)\" are not the ones "
            + "platformWording.keys names. Add the new sentence to that list — and note "
            + "that doing so does not give it a Windows test, which still has to be "
            + "written by hand, because nothing over there reads this list yet."
        )
    }

    /// Every dotted key path under `node` whose string value contains `phrase`.
    ///
    /// `platformWording` itself is skipped: it QUOTES the platform word as its
    /// own `mac` value and in its explanation, so walking it would make the
    /// list contain itself and the test would pass by accident.
    ///
    /// ARRAYS are walked too. No array under `specialNames` carries a
    /// platform-worded sentence today, but this contract's established shape
    /// puts teacher sentences inside arrays of cases — `renameFolder`
    /// .`linkRewriting`.`cases` and `curriculumFolderResolution`.`cases` are
    /// both here already — so a fourth sentence added as a case would otherwise
    /// be invisible to a test whose whole purpose is to notice a fourth
    /// sentence.
    private func collectKeyPaths(
        saying phrase: String,
        in node: [String: Any],
        prefix: String,
        into found: inout [String]
    ) {
        for (key, value) in node {
            if prefix.isEmpty && key == "platformWording" {
                continue
            }
            let path: String = prefix.isEmpty ? key : "\(prefix).\(key)"
            collectKeyPaths(saying: phrase, inValue: value, path: path, into: &found)
        }
    }

    /// One value of any shape, on the way to the strings inside it.
    private func collectKeyPaths(
        saying phrase: String,
        inValue value: Any,
        path: String,
        into found: inout [String]
    ) {
        if let text = value as? String {
            if text.contains(phrase) {
                found.append(path)
            }
        } else if let child = value as? [String: Any] {
            collectKeyPaths(saying: phrase, in: child, prefix: path, into: &found)
        } else if let items = value as? [Any] {
            var index: Int = 0
            for item in items {
                collectKeyPaths(saying: phrase, inValue: item, path: "\(path)[\(index)]", into: &found)
                index += 1
            }
        }
    }

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

        let tip: [String: Any] = try XCTUnwrap(section["contentStructureTip"] as? [String: Any])
        XCTAssertEqual(
            SpecialNames.contentStructureTip,
            tip["message"] as? String,
            "The Content Structure caption and contracts/shared-rules.json → "
            + "specialNames.contentStructureTip disagree. The two apps worded this same rule "
            + "differently for two weeks with nothing pinning either, which is the failure a "
            + "contract case exists to make impossible rather than to discover later."
        )
    }

    /// The tip promises its behaviour for BOTH kinds of thing the four lists
    /// above it hold. Both apps said "folders" alone until 2026-09-07, while
    /// the build discovers and excludes files identically — `discover_shared_items`
    /// and `discover_section_items` append top-level FILES, and `build_site.py`
    /// skips and drops excluded ones from `shared_files` and `per_section_files`
    /// exactly as it does folders. So a teacher who removed a file met a
    /// permanent, silent rule that no sentence anywhere warned them about.
    ///
    /// **Honest about its reach**: this guards the PROMISE clause only. An edit
    /// dropping "and files" from the first sentence fails here; one that
    /// narrowed the second sentence back to folders would not, and no test
    /// would catch it. Windows' half of this
    /// (`TheContentStructureTipCoversFilesAsWellAsFolders`) has the same limit
    /// and says so.
    func testTheContentStructureTipCoversFilesAsWellAsFolders() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")
        let tip: [String: Any] = try XCTUnwrap(section["contentStructureTip"] as? [String: Any])
        let message: String = try XCTUnwrap(tip["message"] as? String)

        XCTAssertTrue(
            message.contains("folders and files"),
            "The Content Structure caption promises its behaviour for folders alone. Two of "
            + "the four lists it sits under are FILE lists, and discovery and exclusion treat "
            + "files identically, so the narrower promise leaves a teacher who removed a file "
            + "with no warning anywhere about a permanent, silent rule."
        )
    }

    /// It is a caption, not a removal-blocked sentence, so it deliberately
    /// carries no `reason` key.
    ///
    /// Asserted HERE, on the side that can act on it, because the cost lands
    /// on the OTHER side: Windows'
    /// `NoBlockedSentenceInTheContractIsUnusedHere` sweeps every top-level
    /// entry's `reason` under `specialNames` and demands each be one of the seven sentences
    /// that app shows in a flyout. A `reason` added to this entry would fail
    /// the Windows suite for something that has nothing to do with what the
    /// sentence says — and `shared-rules.json` is an AUTHORED contract file
    /// that a mac session edits freely, so the mac is where that mistake gets
    /// made and where it should be caught.
    func testTheContentStructureTipIsNotABlockedSentence() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")
        let tip: [String: Any] = try XCTUnwrap(section["contentStructureTip"] as? [String: Any])

        XCTAssertNil(
            tip["reason"],
            "specialNames.contentStructureTip gained a `reason` key. It is a caption rather "
            + "than a removal-blocked sentence, and Windows sweeps every top-level `reason` here "
            + "expecting to find it in a flyout — so this breaks that suite for a reason "
            + "unrelated to the wording."
        )
    }

    /// Course Settings actually DRAWS the caption, from the one constant.
    ///
    /// The gap this closes is the one Windows named when it proposed the case:
    /// a contract test alone proves the constant matches the contract, and
    /// stays perfectly green if the line that renders it is deleted. Windows
    /// answered that with an opt-in UI-Automation test
    /// (`CourseSettingsCaptionUiTests`), MEASURED to fail with the caption
    /// commented out. The mac HAS an XCUITest target that could do the same,
    /// but it is outside the gate (`-only-testing:QuartzTeachersTests` runs
    /// this target only), and an attempt at it reached this caption — four
    /// list editors down the form — in one run out of four. So this is the
    /// gated guard: the source scan issue #71 established for the Marks
    /// wording (`testBothSurfacesDrawTheMarksWordingFromOneHome`), which
    /// reads the view rather than the screen. What went wrong with the UI
    /// attempt, and which part of it is worth fixing, is in
    /// `documentation/09-mac-app.md`.
    ///
    /// **What it reaches, plainly**: that the view references the constant on
    /// a non-comment line, and that no other product file carries a pasted
    /// copy of the sentence. It cannot see that the `Text` is inside the
    /// Content Structure section, that the section is reachable, or that
    /// anything is on screen. A paraphrase, or a copy split before the
    /// needle's 24th character, evades the paste-back half.
    func testCourseSettingsDrawsTheContentStructureTipFromOneHome() throws {
        let productFolderURL: URL = ActivityTrailWiringTests.productSourceFolderURL()
        let fileURL: URL = try XCTUnwrap(
            SharedRulesContractTests.fileNamed("CourseSettingsView.swift", under: productFolderURL),
            "CourseSettingsView.swift was not found where this test expects it, so the checks below would pass vacuously."
        )
        let contents: String = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            SharedRulesContractTests.source(contents, uses: "SpecialNames.contentStructureTip"),
            "CourseSettingsView.swift no longer draws the Content Structure caption from "
            + "SpecialNames.contentStructureTip. Either it was deleted — and the one rule a "
            + "teacher cannot infer went with it — or it went back to being a literal that "
            + "can drift from the contract without a test noticing."
        )

        // Taken from the constant, never retyped, so the needle cannot drift
        // from what the app shows.
        let tipOpening: String = String(SpecialNames.contentStructureTip.prefix(24))
        var filesWithACopy: [String] = []
        for candidateURL in ActivityTrailWiringTests.swiftFiles(under: productFolderURL) {
            if candidateURL.lastPathComponent == "SpecialNames.swift" {
                continue
            }
            let candidateContents: String = try String(contentsOf: candidateURL, encoding: .utf8)
            for line in candidateContents.components(separatedBy: "\n") {
                let trimmedLine: String = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.hasPrefix("//") {
                    continue
                }
                if trimmedLine.contains(tipOpening) {
                    filesWithACopy.append(candidateURL.lastPathComponent)
                    break
                }
            }
        }
        XCTAssertEqual(
            filesWithACopy, [],
            "These files carry their own copy of the Content Structure caption: "
            + "\(filesWithACopy). There is one home for it, SpecialNames.contentStructureTip, "
            + "because a second copy is how the two apps came to word this same rule "
            + "differently in the first place."
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

    /// Every sentence the unit-word rename sheet shows is the contract's.
    /// Named rather than quoted, so rewording is a one-place change.
    func testRenameUnitWordSentencesMatchContract() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("specialNames")
        let rename: [String: Any] = try XCTUnwrap(section["renameUnitWord"] as? [String: Any])
        XCTAssertEqual(UnitWordRenameWording.fieldLabel, rename["fieldLabel"] as? String)
        XCTAssertEqual(UnitWordRenameWording.renameButton, rename["renameButton"] as? String)
        XCTAssertEqual(UnitWordRenameWording.sheetTitle(for: "Unit"), "Rename “Unit”")
        XCTAssertEqual(
            UnitWordRenameWording.sheetTitle(for: "Unit"),
            (rename["sheetTitle"] as? String)?.replacingOccurrences(of: "{word}", with: "Unit")
        )
        XCTAssertEqual(
            UnitWordRenameWording.rowCaption(word: "Module"),
            (rename["rowCaption"] as? String)?.replacingOccurrences(of: "{word}", with: "Module")
        )
        XCTAssertEqual(UnitWordRenameWording.explanation, rename["explanation"] as? String)
        XCTAssertEqual(UnitWordRenameWording.proseIsLeftAlone, rename["proseIsLeftAlone"] as? String)

        let problems: [String: Any] = try XCTUnwrap(rename["problems"] as? [String: Any])
        XCTAssertEqual(UnitWordRenameWording.problemEmpty, problems["empty"] as? String)
        XCTAssertEqual(UnitWordRenameWording.problemUnchanged, problems["unchanged"] as? String)
        XCTAssertEqual(UnitWordRenameWording.lookingOver, rename["lookingOver"] as? String)
        XCTAssertEqual(
            UnitWordRenameWording.problemMustFinishFirst(target: "Module"),
            (problems["mustFinishFirst"] as? String)?.replacingOccurrences(of: "{target}", with: "Module")
        )
        XCTAssertEqual(UnitWordRenameWording.doneLinksNotWritten(pages: 1), rename["doneLinksNotWrittenOne"] as? String)
        XCTAssertEqual(
            UnitWordRenameWording.doneLinksNotWritten(pages: 3),
            (rename["doneLinksNotWrittenMany"] as? String)?.replacingOccurrences(of: "{pages}", with: "3")
        )
        XCTAssertEqual(
            UnitWordRenameWording.doneSentence(from: "Unit", to: "Module", pages: 86, links: 12, pagesNotWritten: 2),
            [
                UnitWordRenameWording.done(from: "Unit", to: "Module"),
                UnitWordRenameWording.donePages(count: 86),
                UnitWordRenameWording.doneLinks(count: 12),
                UnitWordRenameWording.doneLinksNotWritten(pages: 2),
                UnitWordRenameWording.donePublish,
                UnitWordRenameWording.doneBackup,
            ].joined(separator: " ")
        )
        XCTAssertEqual(
            UnitWordRenameWording.problemPageInTheWay(courseCode: "ICS3U", sectionNumber: 2, name: "Module 1, Day 2"),
            (problems["pageInTheWay"] as? String)?
                .replacingOccurrences(of: "{code}", with: "ICS3U")
                .replacingOccurrences(of: "{n}", with: "2")
                .replacingOccurrences(of: "{name}", with: "Module 1, Day 2")
        )
        XCTAssertEqual(
            UnitWordRenameWording.problemPageUnreadable(courseCode: "ICS3U", sectionNumber: 2, name: "Unit 1, Day 2"),
            (problems["pageUnreadable"] as? String)?
                .replacingOccurrences(of: "{code}", with: "ICS3U")
                .replacingOccurrences(of: "{n}", with: "2")
                .replacingOccurrences(of: "{name}", with: "Unit 1, Day 2")
        )
        XCTAssertEqual(
            UnitWordRenameWording.problemBusy(courseCode: "ICS3U"),
            (problems["busy"] as? String)?.replacingOccurrences(of: "{code}", with: "ICS3U")
        )

        let preview: [String: Any] = try XCTUnwrap(rename["preview"] as? [String: Any])
        XCTAssertEqual(
            UnitWordRenameWording.previewPages(courseCode: "ICS3U", pages: 0, sections: [], old: "Unit", new: "Module"),
            (preview["pagesNone"] as? String)?
                .replacingOccurrences(of: "{code}", with: "ICS3U")
                .replacingOccurrences(of: "{old}", with: "Unit")
                .replacingOccurrences(of: "{new}", with: "Module")
        )
        XCTAssertEqual(
            UnitWordRenameWording.previewPages(courseCode: "ICS3U", pages: 1, sections: [3], old: "Unit", new: "Module"),
            (preview["pagesOne"] as? String)?
                .replacingOccurrences(of: "{sections}", with: "Section 3")
                .replacingOccurrences(of: "{old}", with: "Unit")
                .replacingOccurrences(of: "{new}", with: "Module")
        )
        XCTAssertEqual(
            UnitWordRenameWording.previewPages(courseCode: "ICS3U", pages: 86, sections: [1, 2, 4], old: "Unit", new: "Module"),
            (preview["pagesMany"] as? String)?
                .replacingOccurrences(of: "{pages}", with: "86")
                .replacingOccurrences(of: "{sections}", with: "Sections 1, 2 and 4")
                .replacingOccurrences(of: "{old}", with: "Unit")
                .replacingOccurrences(of: "{new}", with: "Module")
        )
        XCTAssertEqual(UnitWordRenameWording.sectionsPhrase([1, 3]), "Sections 1 and 3")
        XCTAssertEqual(UnitWordRenameWording.previewLinks(count: 0), preview["linksNone"] as? String)
        XCTAssertEqual(UnitWordRenameWording.previewLinks(count: 1), preview["linksOne"] as? String)
        XCTAssertEqual(
            UnitWordRenameWording.previewLinks(count: 12),
            (preview["linksMany"] as? String)?.replacingOccurrences(of: "{count}", with: "12")
        )

        XCTAssertEqual(
            UnitWordRenameWording.done(from: "Unit", to: "Module"),
            (rename["done"] as? String)?
                .replacingOccurrences(of: "{old}", with: "Unit")
                .replacingOccurrences(of: "{new}", with: "Module")
        )
        XCTAssertEqual(UnitWordRenameWording.donePages(count: 0), rename["donePagesNone"] as? String)
        XCTAssertEqual(UnitWordRenameWording.donePages(count: 1), rename["donePagesOne"] as? String)
        XCTAssertEqual(
            UnitWordRenameWording.donePages(count: 86),
            (rename["donePagesMany"] as? String)?.replacingOccurrences(of: "{pages}", with: "86")
        )
        XCTAssertEqual(UnitWordRenameWording.doneLinks(count: 0), rename["doneLinksNone"] as? String)
        XCTAssertEqual(UnitWordRenameWording.doneLinks(count: 1), rename["doneLinksOne"] as? String)
        XCTAssertEqual(
            UnitWordRenameWording.doneLinks(count: 12),
            (rename["doneLinksMany"] as? String)?.replacingOccurrences(of: "{links}", with: "12")
        )
        XCTAssertEqual(UnitWordRenameWording.donePublish, rename["donePublish"] as? String)
        XCTAssertEqual(UnitWordRenameWording.doneBackup, rename["doneBackup"] as? String)
        // The order of the whole sentence, as `doneOrder` describes it.
        XCTAssertEqual(
            UnitWordRenameWording.doneSentence(from: "Unit", to: "Module", pages: 86, links: 12),
            [
                UnitWordRenameWording.done(from: "Unit", to: "Module"),
                UnitWordRenameWording.donePages(count: 86),
                UnitWordRenameWording.doneLinks(count: 12),
                UnitWordRenameWording.donePublish,
                UnitWordRenameWording.doneBackup,
            ].joined(separator: " ")
        )

        let interrupted: [String: Any] = try XCTUnwrap(rename["interruptedRename"] as? [String: Any])
        XCTAssertEqual(
            UnitWordRenameWording.interruptedRename(from: "Unit", to: "Module"),
            (interrupted["message"] as? String)?
                .replacingOccurrences(of: "{old}", with: "Unit")
                .replacingOccurrences(of: "{new}", with: "Module")
        )
        XCTAssertEqual(
            UnitWordRenameWording.halfDone(renamed: 40, of: 86, stoppedAt: "Unit 3, Day 2", reason: "disk full"),
            (rename["halfDone"] as? String)?
                .replacingOccurrences(of: "{renamed}", with: "40")
                .replacingOccurrences(of: "{total}", with: "86")
                .replacingOccurrences(of: "{name}", with: "Unit 3, Day 2")
                .replacingOccurrences(of: "{reason}", with: "disk full")
        )
        XCTAssertEqual(
            UnitWordRenameWording.settingsNotWritten(new: "Module", reason: "disk full"),
            (rename["settingsNotWritten"] as? String)?
                .replacingOccurrences(of: "{new}", with: "Module")
                .replacingOccurrences(of: "{reason}", with: "disk full")
        )
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

    /// Whether a caption uses a word AS a word — so "addresses" is not a use
    /// of "add", and a sentence-initial "Add" is. Letters only: the caption's
    /// curly quotes and semicolon are separators like any other.
    private static func caption(_ caption: String, containsWord word: String) -> Bool {
        let wordsInCaption: [String] = caption.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
        for wordInCaption in wordsInCaption {
            if wordInCaption == word.lowercased() {
                return true
            }
        }
        return false
    }

    /// Whether source code USES a token — on a line that is not a comment, so
    /// a doc comment mentioning it does not count as a use.
    ///
    /// `//` only: a use inside a `/* … */` block would still count, and a
    /// reference split across two lines would not be found. Both are shapes
    /// this repository's Swift does not use, and the cost of being wrong is a
    /// test that has to be read rather than a bug that ships.
    private static func source(_ contents: String, uses token: String) -> Bool {
        for line in contents.components(separatedBy: "\n") {
            let trimmedLine: String = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("//") {
                continue
            }
            if trimmedLine.contains(token) {
                return true
            }
        }
        return false
    }

    /// The one product source file with this name, or nil.
    private static func fileNamed(_ fileName: String, under folderURL: URL) -> URL? {
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: folderURL) {
            if fileURL.lastPathComponent == fileName {
                return fileURL
            }
        }
        return nil
    }

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

    // MARK: - A scheduled publish that stopped

    /// The sentences a teacher reads are the contract's, filled in.
    ///
    /// Both apps show these to a teacher, so both retype them and both pin
    /// them here. `neededAnAnswer` and `buildNeededAnAnswer` are Windows'
    /// wording, adopted verbatim; `didNotFinish` and `succeeded` were written
    /// on this side. Which platform a sentence came from stops mattering the
    /// moment it is in the contract, which is the point of the contract.
    func testTheStoppedPublishSentencesAreTheContractsOwn() throws {
        let section: [String: Any] = try SharedRulesContractTests
            .section("scheduledPublishStopped")
        let sentences: [String: Any] = try XCTUnwrap(section["sentences"] as? [String: Any])

        let cases: [(ScheduledPublishOutcome.Kind, String)] = [
            (.neededAnAnswer, "neededAnAnswer"),
            (.buildNeededAnAnswer, "buildNeededAnAnswer"),
            (.didNotFinish, "didNotFinish"),
            (.succeeded, "succeeded"),
        ]
        for (kind, key) in cases {
            let template: String = try XCTUnwrap(sentences[key] as? String)
            let expected: String = template
                .replacingOccurrences(of: "{course}", with: "ICS3U")
                .replacingOccurrences(of: "{section}", with: "2")
                .replacingOccurrences(of: "{destination}", with: "Netlify")
            let actual: String = ScheduledPublishOutcome.sentence(
                for: ScheduledPublishOutcome.Stopped(
                    kind: kind, destination: "Netlify", when: Date()
                ),
                course: "ICS3U",
                section: 2
            )
            XCTAssertEqual(
                actual, expected,
                "The \(key) sentence and contracts/shared-rules.json → "
                + "scheduledPublishStopped.sentences disagree. Both apps show this to a "
                + "teacher; change it in the contract and in both apps, or not at all."
            )
        }
    }

    /// Every kind the contract names is a kind the app has, and the other way
    /// round — so a kind added on one platform cannot be missed on the other.
    func testTheStoppedPublishKindsAreTheOnesTheContractNames() throws {
        let section: [String: Any] = try SharedRulesContractTests
            .section("scheduledPublishStopped")
        let kinds: [String: Any] = try XCTUnwrap(section["kinds"] as? [String: Any])

        var named: [String] = []
        for key in kinds.keys {
            named.append(key)
        }
        named.sort()

        var built: [String] = []
        for kind in ScheduledPublishOutcome.Kind.allCases {
            switch kind {
            case .neededAnAnswer: built.append("neededAnAnswer")
            case .buildNeededAnAnswer: built.append("buildNeededAnAnswer")
            case .didNotFinish: built.append("didNotFinish")
            case .succeeded: built.append("succeeded")
            }
        }
        built.sort()

        XCTAssertEqual(built, named)
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
