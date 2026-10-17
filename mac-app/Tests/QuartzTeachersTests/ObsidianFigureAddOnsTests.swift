import XCTest
@testable import QuartzTeachers

/// Obsidian's add-ons for diagrams and graphs (#495): the pins, the scan, the
/// install table, the list, the asking, the words and the trail — each run
/// against `contracts/shared-rules.json` → `obsidianAddOnsForFigures`, so the
/// Windows side runs the identical cases.
///
/// No test here reaches the teacher's Obsidian: the route is driven through
/// `WorkspaceModel.obsidianOpening`, whose every door to Obsidian, its
/// registry and the disk outside a temporary folder is replaced.
@MainActor
final class ObsidianFigureAddOnsTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    override func setUp() async throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("obsidian-figure-add-ons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        ObsidianFigureAddOnsThisRun.forget()
    }

    override func tearDown() async throws {
        ObsidianFigureAddOnsThisRun.forget()
        try? FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - The pins and the carried copy

    func testThePinsAreTheContracts() throws {
        let addOns: [[String: Any]] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["addOns"] as? [[String: Any]])
        XCTAssertEqual(addOns.count, ObsidianFigureAddOns.pinned.count)
        for (index, contractAddOn) in addOns.enumerated() {
            let pinned: ObsidianFigureAddOn = ObsidianFigureAddOns.pinned[index]
            XCTAssertEqual(contractAddOn["kind"] as? String, pinned.kind)
            XCTAssertEqual(contractAddOn["id"] as? String, pinned.id)
            XCTAssertEqual(contractAddOn["name"] as? String, pinned.name)
            XCTAssertEqual(contractAddOn["version"] as? String, pinned.version)
            let files: [[String: Any]] = try XCTUnwrap(contractAddOn["files"] as? [[String: Any]])
            XCTAssertEqual(files.count, pinned.files.count, pinned.id)
            for (fileIndex, file) in files.enumerated() {
                let pinnedFile: ObsidianFigureAddOn.CarriedFile = pinned.files[fileIndex]
                XCTAssertEqual(file["name"] as? String, pinnedFile.name, pinned.id)
                XCTAssertEqual(file["bytes"] as? Int, pinnedFile.bytes, "\(pinned.id)/\(pinnedFile.name)")
                XCTAssertEqual(file["sha256"] as? String, pinnedFile.sha256, "\(pinned.id)/\(pinnedFile.name)")
            }
        }
    }

    /// The bundle carries every pinned file, exactly — and a copy with one
    /// byte changed is refused before anything is written.
    func testTheCarriedFilesMatchThePins() throws {
        let carriedURL: URL = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent(ObsidianFigureAddOns.carriedFolderName)
        XCTAssertTrue(
            ObsidianFigureAddOns.carriedCopyMatches(ObsidianFigureAddOns.pinned, in: carriedURL),
            "Contents/Resources/obsidian-addons does not match the pins — run mac-app/Vendor/fetch-obsidian-addons.sh, then xcodegen generate"
        )
        var expected: Set<String> = []
        for addOn in ObsidianFigureAddOns.pinned {
            for file in addOn.files {
                expected.insert(addOn.id + "/" + file.name)
            }
        }
        var carried: Set<String> = []
        let walker: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(at: carriedURL, includingPropertiesForKeys: [.isRegularFileKey])
        while let fileURL = walker?.nextObject() as? URL {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                carried.insert(fileURL.deletingLastPathComponent().lastPathComponent + "/" + fileURL.lastPathComponent)
            }
        }
        XCTAssertEqual(carried, expected, "the bundle carries exactly the pinned files")

        let flippedURL: URL = rootURL.appendingPathComponent("flipped")
        try FileManager.default.copyItem(at: carriedURL, to: flippedURL)
        let licenceURL: URL = flippedURL.appendingPathComponent("obsidian-functionplot/LICENSE")
        var bytes: Data = try Data(contentsOf: licenceURL)
        bytes[0] = bytes[0] ^ 0x01
        try bytes.write(to: licenceURL)
        XCTAssertFalse(ObsidianFigureAddOns.carriedCopyMatches(ObsidianFigureAddOns.pinned, in: flippedURL))
        let courseURL: URL = try makeCourse(named: "MPM2D")
        let results: [ObsidianFigureAddOns.Result] = ObsidianFigureAddOns.install(
            ObsidianFigureAddOns.pinned, inCourseAt: courseURL, carriedFrom: flippedURL, defaultsFrom: defaultsURL()
        )
        for result in results {
            XCTAssertEqual(result.outcome, .refusedCarriedCopy)
        }
        XCTAssertNil(try? FileManager.default.contentsOfDirectory(atPath: courseURL.appendingPathComponent(".obsidian/plugins").path))
    }

    func testTheFetchScriptCarriesNoPinOfItsOwn() throws {
        let script: String = try String(
            contentsOf: UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("Vendor/fetch-obsidian-addons.sh"), encoding: .utf8
        )
        let hexRun: NSRegularExpression = try NSRegularExpression(pattern: "[0-9a-fA-F]{64}")
        XCTAssertEqual(hexRun.numberOfMatches(in: script, range: NSRange(script.startIndex..., in: script)), 0,
                       "the pins are the contract's; the script reads them")
        XCTAssertTrue(script.contains("obsidianAddOnsForFigures.addOns"))
        XCTAssertFalse(script.contains("0.5.2") || script.contains("1.2.1"), "no version of its own either")
    }

    func testPublishAndTheProjectRunTheFetch() throws {
        let root: URL = UserFacingLabelWordsTests.macAppRoot()
        let publish: String = try String(contentsOf: root.appendingPathComponent("publish.sh"), encoding: .utf8)
        XCTAssertTrue(publish.contains("./Vendor/fetch-obsidian-addons.sh"))
        let project: String = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("- path: Vendor/obsidian-addons"))
    }

    // MARK: - Which add-ons a course needs

    /// The Swift walker finds exactly the figures the build finds, on every
    /// `figureFences.fences` case — the three readers agree on one set of data
    /// (plan review S1).
    func testFenceKindsFollowEveryFigureFencesCase() throws {
        let figureFences: [String: Any] = try SharedRulesContractTests.section("figureFences")
        let fences: [String: Any] = try XCTUnwrap(figureFences["fences"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(fences["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 13)
        let kinds: Set<String> = ["tikz", "functionplot"]
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let page: String = try XCTUnwrap(testCase["page"] as? String)
            var expected: [String] = []
            var expectedKinds: Set<String> = []
            for found in try XCTUnwrap(testCase["found"] as? [[String: Any]]) {
                let engine: String = try XCTUnwrap(found["engine"] as? String)
                expected.append(engine + "@" + String(try XCTUnwrap(found["line"] as? Int)))
                expectedKinds.insert(engine)
            }
            var got: [String] = []
            for block in FigureFenceScan.blocks(in: page) where !block.nested && kinds.contains(block.lang) {
                got.append(block.lang + "@" + String(block.line))
            }
            XCTAssertEqual(got, expected, name)
            XCTAssertEqual(FigureFenceScan.kinds(in: page, among: kinds), expectedKinds, name)
        }
    }

    func testWhichPagesCases() throws {
        let whichPages: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["whichPages"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(whichPages["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)
        for (index, testCase) in cases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let courseURL: URL = rootURL.appendingPathComponent("pages-\(index)/MPM2D")
            try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
            for (path, text) in try XCTUnwrap(testCase["files"] as? [String: String]) {
                let fileURL: URL = courseURL.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: fileURL)
            }
            XCTAssertEqual(neededIDs(inCourseAt: courseURL), try XCTUnwrap(testCase["needs"] as? [String]), name)
        }
    }

    /// A page the cloud has not downloaded is never read — the predicate is
    /// injected, because the dataless flag cannot be set by a test (it is the
    /// file provider's; `chflags` refuses it). The real predicate reads
    /// `SF_DATALESS` from `lstat`, unmeasured on an evicted file here.
    func testAnEvictedPageIsNotRead() throws {
        let courseURL: URL = try makeCourse(named: "MPM2D")
        try Data("```tikz\n\\begin{document}\n\\end{document}\n```\n".utf8).write(to: courseURL.appendingPathComponent("Figures.md"))
        let kinds: Set<String> = ["tikz", "functionplot"]
        XCTAssertEqual(ObsidianFigureAddOns.kindsUsed(inCourseAt: courseURL, among: kinds), ["tikz"])
        XCTAssertEqual(ObsidianFigureAddOns.kindsUsed(inCourseAt: courseURL, among: kinds, isEvicted: { _ in true }), [])
        XCTAssertFalse(ObsidianFigureAddOns.pageIsEvicted(courseURL.appendingPathComponent("Figures.md")))
    }

    /// Measured, not asserted: a cold scan of 2,000 pages (doc 09 records
    /// the number). Generous bound, so a slow machine does not fail it.
    func testTheScanOfTwoThousandPagesIsQuick() throws {
        let courseURL: URL = try makeCourse(named: "BIG")
        let page: String = String(repeating: "A line of a lesson with `code` and [[a link]].\n", count: 60)
        for index in 0..<2000 {
            let folder: URL = courseURL.appendingPathComponent("Unit \(index % 20)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data((page + (index == 1999 ? "\n```functionplot\ny = x\n```\n" : "")).utf8)
                .write(to: folder.appendingPathComponent("Page \(index).md"))
        }
        let started: Date = Date()
        let kinds: Set<String> = ObsidianFigureAddOns.kindsUsed(inCourseAt: courseURL, among: ["tikz", "functionplot"])
        let seconds: Double = Date().timeIntervalSince(started)
        XCTAssertEqual(kinds, ["functionplot"])
        print("obsidian add-ons scan: 2000 pages in \(String(format: "%.0f", seconds * 1000)) ms")
        XCTAssertLessThan(seconds, 5)
    }

    // MARK: - What a pass writes

    func testEveryVaultCase() throws {
        let vaultCases: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["vaultCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(vaultCases["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 22)
        for (index, testCase) in cases.enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("vault-\(index)")
            let courseURL: URL = caseURL.appendingPathComponent("MPM2D")
            try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
            let made: (addOns: [ObsidianFigureAddOn], carried: URL) = try fakeAddOns(
                in: caseURL, mismatched: (testCase["carried"] as? String) == "mismatch"
            )
            try build(before: try XCTUnwrap(testCase["before"] as? [String: Any]), course: courseURL, caseURL: caseURL)

            var needed: [ObsidianFigureAddOn] = []
            for id in try XCTUnwrap(testCase["needs"] as? [String]) {
                for addOn in made.addOns where addOn.id == id {
                    needed.append(addOn)
                }
            }
            let defaults: URL = (testCase["defaults"] as? String) == "missing"
                ? caseURL.appendingPathComponent("no-defaults-here")
                : try fakeDefaults(in: caseURL)
            let results: [ObsidianFigureAddOns.Result] = ObsidianFigureAddOns.install(
                needed, inCourseAt: courseURL, carriedFrom: made.carried, defaultsFrom: defaults
            )

            var outcomes: [String: String] = [:]
            for result in results {
                outcomes[result.addOn.id] = ObsidianFigureAddOnsTests.contractWords(for: result.outcome)
            }
            XCTAssertEqual(outcomes, try XCTUnwrap(testCase["outcomes"] as? [String: String]), name)

            let listURL: URL = courseURL.appendingPathComponent(".obsidian/community-plugins.json")
            let listAfter: String? = try? String(contentsOf: listURL, encoding: .utf8)
            XCTAssertEqual(listAfter, testCase["listAfter"] as? String, "\(name): the list")

            if let written = testCase["written"] as? [String] {
                for addOn in made.addOns {
                    let folderURL: URL = courseURL.appendingPathComponent(".obsidian/plugins/\(addOn.id)")
                    let main: Data? = try? Data(contentsOf: folderURL.appendingPathComponent("main.js"))
                    let carriedMain: Data = try Data(contentsOf: made.carried.appendingPathComponent("\(addOn.id)/main.js"))
                    if written.contains(addOn.id) {
                        for file in addOn.files {
                            XCTAssertEqual(
                                try? Data(contentsOf: folderURL.appendingPathComponent(file.name)),
                                try Data(contentsOf: made.carried.appendingPathComponent("\(addOn.id)/\(file.name)")),
                                "\(name): \(addOn.id)/\(file.name)"
                            )
                        }
                        XCTAssertEqual(
                            try? String(contentsOf: folderURL.appendingPathComponent(ObsidianFigureAddOns.markerName), encoding: .utf8),
                            ObsidianFigureAddOns.markerText(version: addOn.version), "\(name): the marker"
                        )
                    } else {
                        XCTAssertNotEqual(main, carriedMain, "\(name): \(addOn.id) was written")
                    }
                }
            }
            if testCase["seeded"] as? Bool == true {
                XCTAssertTrue(FileManager.default.fileExists(atPath: courseURL.appendingPathComponent(".obsidian/appearance.json").path),
                              "\(name): the course defaults came first (plan finding P7)")
            }
            if let partialAfter = testCase["partialAfter"] as? [String] {
                var partials: [String] = []
                for entry in (try? FileManager.default.contentsOfDirectory(atPath: courseURL.appendingPathComponent(".obsidian/plugins").path)) ?? [] {
                    if entry.hasSuffix(ObsidianFigureAddOns.partialSuffix) {
                        partials.append(entry)
                    }
                }
                XCTAssertEqual(partials, partialAfter, "\(name): leftover partial folders")
            }
        }
    }

    func testEveryListCase() throws {
        let listCases: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["listCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(listCases["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 11)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var listData: Data?
            if let text = testCase["list"] as? String {
                listData = Data(text.utf8)
            }
            let after: ObsidianFigureAddOns.ListAfter = ObsidianFigureAddOns.listAfterAdding(
                try XCTUnwrap(testCase["adding"] as? [String]), to: listData
            )
            let expected: String = try XCTUnwrap(testCase["after"] as? String)
            switch after {
            case .write(let text):
                XCTAssertEqual(text, expected, name)
            case .unchanged:
                XCTAssertEqual("unchanged", expected, name)
            case .refused:
                XCTAssertEqual("refused", expected, name)
            }
        }
    }

    /// The real carried add-ons, written twice: the second pass changes no
    /// byte and no modification date, and says so with no trail line.
    func testASecondPassChangesNoByte() throws {
        let courseURL: URL = try makeCourse(named: "MPM2D")
        let carriedURL: URL = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent(ObsidianFigureAddOns.carriedFolderName)
        let first: [ObsidianFigureAddOns.Result] = ObsidianFigureAddOns.install(
            ObsidianFigureAddOns.pinned, inCourseAt: courseURL, carriedFrom: carriedURL, defaultsFrom: defaultsURL()
        )
        for result in first {
            XCTAssertEqual(result.outcome, .added, result.addOn.id)
        }
        let before: [String: String] = ObsidianFigureAddOnsTests.snapshot(of: courseURL.appendingPathComponent(".obsidian"))
        let second: [ObsidianFigureAddOns.Result] = ObsidianFigureAddOns.install(
            ObsidianFigureAddOns.pinned, inCourseAt: courseURL, carriedFrom: carriedURL, defaultsFrom: defaultsURL()
        )
        for result in second {
            XCTAssertEqual(result.outcome, .alreadyThere, result.addOn.id)
        }
        XCTAssertEqual(ObsidianFigureAddOnsTests.snapshot(of: courseURL.appendingPathComponent(".obsidian")), before)
        XCTAssertNil(ObsidianFigureAddOnsTrail.pass(course: "MPM2D", trigger: .afterAPreview, results: second))
        XCTAssertEqual(
            try String(contentsOf: courseURL.appendingPathComponent(".obsidian/community-plugins.json"), encoding: .utf8),
            "[\n  \"obsidian-tikzjax\",\n  \"obsidian-functionplot\"\n]"
        )
    }

    /// Passes over the same course, asked for at once, never overlap (plan
    /// review S2): the queue runs one at a time, and every pass sees a whole
    /// course.
    func testPassesNeverOverlap() async throws {
        let courseURL: URL = try makeCourse(named: "MPM2D")
        let made: (addOns: [ObsidianFigureAddOn], carried: URL) = try fakeAddOns(in: rootURL, mismatched: false)
        let defaults: URL = try fakeDefaults(in: rootURL)
        ObsidianFigureAddOns.forgetMostPassesAtOnce()
        let coursePath: String = courseURL.path
        let addOns: [ObsidianFigureAddOn] = made.addOns
        let carried: URL = made.carried
        var addedCount: Int = 0
        await withTaskGroup(of: [ObsidianFigureAddOns.Result].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    return await ObsidianFigureAddOnsQueue.shared.install(addOns, inCourseAt: coursePath, carriedFrom: carried, defaultsFrom: defaults)
                }
            }
            for await results in group {
                for result in results where result.outcome == .added {
                    addedCount += 1
                }
            }
        }
        XCTAssertEqual(ObsidianFigureAddOns.mostPassesAtOnce, 1, "two passes ran at once")
        XCTAssertEqual(addedCount, addOns.count, "each add-on is added once, by the first pass")
    }

    // MARK: - Asking

    func testTheAnswerCases() throws {
        let answer: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["answer"] as? [String: Any])
        var values: [String] = []
        for value in ObsidianFigureAddOnsAnswer.allCases {
            values.append(value.rawValue)
        }
        XCTAssertEqual(answer["values"] as? [String], values)
        XCTAssertEqual(answer["default"] as? String, ObsidianFigureAddOnsAnswer.reading(stored: nil).rawValue)
        for testCase in try XCTUnwrap(answer["cases"] as? [[String: Any]]) {
            let stored: String? = testCase["stored"] as? String
            XCTAssertEqual(ObsidianFigureAddOnsAnswer.reading(stored: stored).rawValue, testCase["reads"] as? String, stored ?? "nil")
        }
        for testCase in try XCTUnwrap(answer["toggle"] as? [[String: Any]]) {
            let on: Bool = try XCTUnwrap(testCase["on"] as? Bool)
            XCTAssertEqual(ObsidianSettingsView.answer(turnedOn: on).rawValue, testCase["stores"] as? String)
        }
        // Kept in the preferences it was given.
        let defaults: UserDefaults = TestDefaults.make()
        let settings: AppSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.obsidianFigureAddOns, .notAsked)
        settings.obsidianFigureAddOns = .yes
        XCTAssertEqual(AppSettings(defaults: defaults).obsidianFigureAddOns, .yes)
    }

    func testEveryOfferCase() throws {
        let offerCases: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["offerCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(offerCases["cases"] as? [[String: Any]])
        var decisionsSeen: Set<String> = []
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let situation: ObsidianFigureAddOnsOffer.Situation = ObsidianFigureAddOnsOffer.Situation(
                reference: try XCTUnwrap(testCase["reference"] as? Bool),
                obsidianInstalled: try XCTUnwrap(testCase["obsidianInstalled"] as? Bool),
                answer: try XCTUnwrap(ObsidianFigureAddOnsAnswer(rawValue: try XCTUnwrap(testCase["answer"] as? String))),
                suppressedThisRun: try XCTUnwrap(testCase["suppressedThisRun"] as? Bool),
                wouldAdd: try XCTUnwrap(testCase["wouldAdd"] as? Bool),
                vaultIsTheCourse: try XCTUnwrap(testCase["vaultIsTheCourse"] as? Bool),
                courseOpenInObsidian: try XCTUnwrap(testCase["courseOpenInObsidian"] as? Bool),
                reopenDeclinedThisRun: try XCTUnwrap(testCase["reopenDeclinedThisRun"] as? Bool)
            )
            XCTAssertEqual(ObsidianFigureAddOnsOffer.decision(situation).rawValue, testCase["decision"] as? String, name)
            XCTAssertEqual(
                ObsidianFigureAddOnsOffer.scans(
                    reference: situation.reference, obsidianInstalled: situation.obsidianInstalled,
                    answer: situation.answer, suppressedThisRun: situation.suppressedThisRun
                ),
                testCase["scans"] as? Bool, "\(name): scans"
            )
            decisionsSeen.insert(try XCTUnwrap(testCase["decision"] as? String))
        }
        var everyDecision: Set<String> = []
        for decision in ObsidianFigureAddOnsOffer.Decision.allCases {
            everyDecision.insert(decision.rawValue)
        }
        XCTAssertEqual(decisionsSeen, everyDecision, "every decision has a case")
    }

    func testEveryPreviewCase() throws {
        let previewCases: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["previewCases"] as? [String: Any])
        for testCase in try XCTUnwrap(previewCases["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let decision: ObsidianFigureAddOnsOffer.PreviewDecision = ObsidianFigureAddOnsOffer.afterAPreview(
                reference: try XCTUnwrap(testCase["reference"] as? Bool),
                obsidianInstalled: try XCTUnwrap(testCase["obsidianInstalled"] as? Bool),
                answer: try XCTUnwrap(ObsidianFigureAddOnsAnswer(rawValue: try XCTUnwrap(testCase["answer"] as? String))),
                wouldAdd: try XCTUnwrap(testCase["wouldAdd"] as? Bool),
                vaultIsTheCourse: try XCTUnwrap(testCase["vaultIsTheCourse"] as? Bool),
                courseOpenInObsidian: try XCTUnwrap(testCase["courseOpenInObsidian"] as? Bool)
            )
            XCTAssertEqual(decision.rawValue, testCase["decision"] as? String, name)
        }
    }

    func testWhichVaultOpensCases() throws {
        let rules: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["whichVaultOpens"] as? [String: Any])
        for testCase in try XCTUnwrap(rules["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let registry: Data = try ObsidianFigureAddOnsTests.registry(vaults: try XCTUnwrap(testCase["vaults"] as? [String]))
            let target: String = try XCTUnwrap(testCase["target"] as? String)
            let course: String = try XCTUnwrap(testCase["course"] as? String)
            XCTAssertEqual(ObsidianFigureAddOnsOffer.vaultThatOpens(targetPath: target, registryData: registry), testCase["opens"] as? String, name)
            XCTAssertEqual(
                ObsidianFigureAddOnsOffer.vaultIsTheCourse(targetPath: target, coursePath: course, registryData: registry),
                testCase["isTheCourse"] as? Bool, name
            )
        }
    }

    /// The contract's sequence is eight steps, and the route follows them —
    /// the route tests below walk steps 1, 2, 5, 6, 7 and 8 through the real
    /// function.
    func testTheSequenceIsTheContracts() throws {
        let sequence: [[String: Any]] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["sequence"] as? [[String: Any]])
        var steps: [Int] = []
        for step in sequence {
            steps.append(try XCTUnwrap(step["step"] as? Int))
            XCTAssertNotNil(step["then"] as? String)
        }
        XCTAssertEqual(steps, [1, 2, 3, 4, 5, 6, 7, 8])
    }

    // MARK: - The route, driven without Obsidian

    /// Step 6: a course with a figure, never asked — the offer is set and
    /// Obsidian is NOT opened; Add Them writes the add-ons, THEN opens.
    func testOpenInObsidianAsksBeforeOpening() async throws {
        let made: Driven = try drive(answer: .notAsked)
        let opened: Bool = made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        XCTAssertFalse(opened)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertEqual(made.log.opened, [], "Obsidian opened before the teacher answered")
        let request: ObsidianAddOnsRequest = try XCTUnwrap(made.workspace.obsidianAddOnsOfferRequest, "the offer is waiting")
        XCTAssertFalse(request.courseIsOpen)
        var ids: [String] = []
        for addOn in request.needed {
            ids.append(addOn.id)
        }
        XCTAssertEqual(ids, ["obsidian-tikzjax"], "only what the course uses")

        await made.workspace.answerObsidianAddOnsOffer(request, .addThem)
        XCTAssertNil(made.workspace.obsidianAddOnsOfferRequest)
        XCTAssertEqual(made.settings.obsidianFigureAddOns, .yes)
        XCTAssertEqual(made.log.opened, [made.course.directoryURL.path])
        XCTAssertEqual(made.log.pluginsAtOpen, [["obsidian-tikzjax"]], "the add-on was written before Obsidian opened")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        XCTAssertTrue(trail.contains(ObsidianFigureAddOnsTrail.offered(course: made.course.code, answered: .addThem)))
        XCTAssertTrue(trail.contains("TikZJax 0.5.2 added"), trail)
    }

    /// Not Now asks no more this run; Not Now with "Don't ask again" stores
    /// no. Obsidian opens after either.
    func testNotNowAndDontAskAgain() async throws {
        let made: Driven = try drive(answer: .notAsked)
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        await made.workspace.answerObsidianAddOnsOffer(try XCTUnwrap(made.workspace.obsidianAddOnsOfferRequest), .notNow)
        XCTAssertEqual(made.log.opened.count, 1)
        XCTAssertEqual(made.settings.obsidianFigureAddOns, .notAsked)
        XCTAssertTrue(made.workspace.openInObsidian(course: made.course, sectionNumber: nil), "Not Now: opened at once, no scan")
        XCTAssertEqual(made.log.scans, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path))

        ObsidianFigureAddOnsThisRun.forget()
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        await made.workspace.answerObsidianAddOnsOffer(try XCTUnwrap(made.workspace.obsidianAddOnsOfferRequest), .notNowDontAskAgain)
        XCTAssertEqual(made.settings.obsidianFigureAddOns, .no)
        XCTAssertTrue(made.workspace.openInObsidian(course: made.course, sectionNumber: nil), "the answer no: opened at once")
        XCTAssertEqual(made.log.scans, 2)
    }

    /// Step 7: the answer yes — the add-ons are written, then Obsidian opens,
    /// with no question.
    func testWithYesItInstallsThenOpens() async throws {
        let made: Driven = try drive(answer: .yes)
        XCTAssertFalse(made.workspace.openInObsidian(course: made.course, sectionNumber: 1))
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertNil(made.workspace.obsidianAddOnsOfferRequest)
        XCTAssertEqual(made.log.opened, [made.course.sectionDirectoryURL(forSection: 1).path], "the section's own folder, as before")
        XCTAssertEqual(made.log.pluginsAtOpen, [["obsidian-tikzjax"]])
    }

    /// Step 1: a reference course is never scanned and never offered.
    func testAReferenceCourseIsNeverScanned() async throws {
        LockedPagesNote.defaults = TestDefaults.make()
        defer { LockedPagesNote.defaults = PlantoirDefaults.shared }
        let made: Driven = try drive(answer: .yes)
        made.course.configuration.keptForReference = true
        LockedPagesNote.remember(courseCode: made.course.code)
        let opened: Bool = made.workspace.openInObsidian(course: made.course, sectionNumber: nil) { _ in }
        XCTAssertTrue(opened)
        XCTAssertEqual(made.log.scans, 0)
        XCTAssertEqual(made.log.opened.count, 1)
        made.workspace.addObsidianAddOnsAfterAPreview(course: made.course)
        XCTAssertNil(made.workspace.obsidianAddOnsWork)
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path))
    }

    /// Step 8: open in Obsidian — nothing is written under it; Reopen quits
    /// first, writes, then reopens every vault that was open.
    func testWithTheCourseOpenItAsksToReopenAndNeverWritesUnderIt() async throws {
        let made: Driven = try drive(answer: .yes)
        made.log.running = true
        made.log.openVaults = [made.course.directoryURL.path, "/elsewhere/Other"]
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        let request: ObsidianAddOnsRequest = try XCTUnwrap(made.workspace.obsidianReopenRequest)
        XCTAssertEqual(made.log.opened, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path),
                       "written into a course open in Obsidian")
        await made.workspace.answerObsidianReopen(request, reopen: true)
        XCTAssertEqual(made.log.quits, 1)
        // Every vault the registry marked open, sorted, so the hidden ones come back too.
        XCTAssertEqual(made.log.reopened, [["/elsewhere/Other", made.course.directoryURL.path].sorted()])
        XCTAssertEqual(made.log.pluginsAtOpen, [["obsidian-tikzjax"]])
        XCTAssertTrue(ActivityTrail.store.activityText(includingPrompts: false).contains(ObsidianFigureAddOnsTrail.reopened(course: made.course.code)))
    }

    /// Implementation review B1, the measured shape: Obsidian running and
    /// HIDDEN (no window on screen at all), the registry marking the course
    /// open. It counts as open — the reopen question, never a write — and the
    /// preview pass waits.
    func testAHiddenObsidianStillCountsAsOpen() async throws {
        XCTAssertEqual(
            ObsidianFigureAddOnsOffer.vaultsOpen(obsidianRunning: true, registryData: try ObsidianFigureAddOnsTests.registry(vaults: ["/w/MPM2D"], open: true)),
            ["/w/MPM2D"], "no window is counted"
        )
        XCTAssertEqual(ObsidianFigureAddOnsOffer.vaultsOpen(obsidianRunning: false, registryData: try ObsidianFigureAddOnsTests.registry(vaults: ["/w/MPM2D"], open: true)), [])
        let made: Driven = try drive(answer: .yes)
        made.log.running = true
        made.log.registry = try ObsidianFigureAddOnsTests.registry(vaults: [made.course.directoryURL.path], open: true)
        made.workspace.addObsidianAddOnsAfterAPreview(course: made.course)
        await made.workspace.obsidianAddOnsWork?.value
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertNotNil(made.workspace.obsidianReopenRequest, "the reopen question, not a write")
        XCTAssertEqual(made.log.opened, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path),
                       "written under a hidden Obsidian")
    }

    /// Fixes review N1: while Obsidian runs, a registry that cannot be read
    /// (caught mid-write) counts as open — no write.
    func testAnUnreadableRegistryWhileRunningCountsAsOpen() async throws {
        XCTAssertTrue(ObsidianFigureAddOnsOffer.courseIsOpen(coursePath: "/w/MPM2D", obsidianRunning: true, registryData: Data("{\"vaults\": {\"a".utf8)))
        XCTAssertTrue(ObsidianFigureAddOnsOffer.courseIsOpen(coursePath: "/w/MPM2D", obsidianRunning: true, registryData: nil))
        XCTAssertFalse(ObsidianFigureAddOnsOffer.courseIsOpen(coursePath: "/w/MPM2D", obsidianRunning: false, registryData: nil))
        XCTAssertFalse(ObsidianFigureAddOnsOffer.courseIsOpen(coursePath: "/w/MPM2D", obsidianRunning: true, registryData: try ObsidianFigureAddOnsTests.registry(vaults: ["/w/ICS3U"], open: true)))
        let made: Driven = try drive(answer: .yes)
        made.log.running = true
        made.log.registry = Data("{\"vaults\": {\"a".utf8)
        made.workspace.addObsidianAddOnsAfterAPreview(course: made.course)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path),
                       "written while the registry could not be read")
    }

    /// Fixes review N2: the course opened in Obsidian WHILE the offer was up —
    /// Add Them asks again and goes the reopen way, never writing under it.
    func testAddThemChecksAgainWhenAnswered() async throws {
        let made: Driven = try drive(answer: .notAsked)
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        let request: ObsidianAddOnsRequest = try XCTUnwrap(made.workspace.obsidianAddOnsOfferRequest)
        XCTAssertFalse(request.courseIsOpen)
        made.log.running = true
        made.log.openVaults = [made.course.directoryURL.path]
        made.log.quitCloses = false
        await made.workspace.answerObsidianAddOnsOffer(request, .addThem)
        XCTAssertEqual(made.log.quits, 1, "the reopen way")
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path),
                       "written under an Obsidian opened while the offer was up")
    }

    /// Later: opened as it is, nothing written, not asked again this run.
    func testLaterWritesNothingAndIsNotAskedAgain() async throws {
        let made: Driven = try drive(answer: .yes)
        made.log.running = true
        made.log.openVaults = [made.course.directoryURL.path]
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        await made.workspace.answerObsidianReopen(try XCTUnwrap(made.workspace.obsidianReopenRequest), reopen: false)
        XCTAssertEqual(made.log.opened.count, 1)
        XCTAssertEqual(made.log.quits, 0)
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertNil(made.workspace.obsidianReopenRequest)
        XCTAssertEqual(made.log.opened.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path))
    }

    /// If Obsidian does not close, nothing is written.
    func testObsidianThatDoesNotCloseIsNeverWrittenUnder() async throws {
        let made: Driven = try drive(answer: .yes)
        made.log.running = true
        made.log.openVaults = [made.course.directoryURL.path]
        made.log.quitCloses = false
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        await made.workspace.answerObsidianReopen(try XCTUnwrap(made.workspace.obsidianReopenRequest), reopen: true)
        XCTAssertEqual(made.log.quits, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path))
        XCTAssertEqual(made.log.opened.count, 1)
    }

    /// Step 5: a larger vault holds the course — nothing offered, one line.
    func testALargerVaultIsNeverOfferedAndSaysWhyOnce() async throws {
        let made: Driven = try drive(answer: .notAsked)
        made.log.registry = try ObsidianFigureAddOnsTests.registry(vaults: [made.course.directoryURL.deletingLastPathComponent().path])
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertNil(made.workspace.obsidianAddOnsOfferRequest)
        XCTAssertEqual(made.log.opened.count, 2)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        XCTAssertEqual(trail.components(separatedBy: ObsidianFigureAddOnsTrail.notTheVault(course: made.course.code)).count - 1, 1)
    }

    /// The second trigger: after the yes, a finished preview adds them —
    /// but never into a course open in Obsidian (plan review S3).
    func testAPreviewAddsThemOnlyWhileTheCourseIsClosed() async throws {
        let made: Driven = try drive(answer: .yes)
        made.log.running = true
        made.log.openVaults = [made.course.directoryURL.path]
        made.workspace.addObsidianAddOnsAfterAPreview(course: made.course)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins").path))
        made.log.running = false
        made.workspace.addObsidianAddOnsAfterAPreview(course: made.course)
        await made.workspace.obsidianAddOnsWork?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: made.course.directoryURL.appendingPathComponent(".obsidian/plugins/obsidian-tikzjax/manifest.json").path))
        XCTAssertEqual(made.log.opened, [], "a preview never opens Obsidian")
        XCTAssertTrue(ActivityTrail.store.activityText(includingPrompts: false).contains("(after a preview): TikZJax 0.5.2 added"))
    }

    func testEveryRouteIsStillTheOneFunction() throws {
        let route: String = try String(
            contentsOf: UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers/Models/OpenInObsidianRoute.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(route.contains("obsidianOpening.open(folder, course.directoryURL)"))
        let detail: String = try String(
            contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent("Section/SectionDetailView.swift"), encoding: .utf8
        )
        XCTAssertTrue(detail.contains("workspace.addObsidianAddOnsAfterAPreview(course: course)"), "the preview trigger is wired")
    }

    // MARK: - Words and trail

    func testTheWordsAreTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["wording"] as? [String: Any])
        let ours: [String: String] = ObsidianFigureAddOnsTests.ourWords()
        var contractKeys: Set<String> = Set(wording.keys)
        contractKeys.remove("note")
        XCTAssertEqual(contractKeys, Set(ours.keys), "the contract and the app name the same words")
        for (key, words) in ours {
            XCTAssertEqual(wording[key] as? String, words, key)
        }
        let windowsWording: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["windowsWording"] as? [String: Any])
        for key in windowsWording.keys where key != "note" {
            XCTAssertNotNil(ours[key], "windowsWording.\(key) names a sentence the app does not have")
        }
        XCTAssertEqual(
            ObsidianFigureAddOnsWording.offerText(course: "MPM2D", courseIsOpen: true),
            ObsidianFigureAddOnsWording.filling(ObsidianFigureAddOnsWording.offerMessage, course: "MPM2D") + "\n\n"
                + ObsidianFigureAddOnsWording.filling(ObsidianFigureAddOnsWording.offerWhileOpen, course: "MPM2D")
        )
    }

    /// Rule 1, with Obsidian's own quoted labels taken out first: those are
    /// Obsidian's words, which the teacher must recognise on its screen.
    func testTheWordsNeverNameTheMachinery() throws {
        let banned: [String] = ["plugin", "vault", "json", "folder", "script", "toolchain", "cannot", "docker", "container",
                                "pyodide", "webassembly", "worker", "sidecar", "marker"]
        let quoted: NSRegularExpression = try NSRegularExpression(pattern: "“[^”]*”")
        for (key, words) in ObsidianFigureAddOnsTests.ourWords() {
            let unquoted: String = quoted.stringByReplacingMatches(
                in: words, range: NSRange(words.startIndex..., in: words), withTemplate: ""
            ).lowercased()
            for word in banned {
                XCTAssertFalse(unquoted.contains(word), "\(key) says “\(word)”")
            }
        }
    }

    func testTheTrailLinesAreTheContracts() throws {
        let trail: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["trail"] as? [String: Any])
        let offered: [String: String] = try XCTUnwrap(trail["offered"] as? [String: String])
        for answered in ObsidianFigureAddOnsTrail.Answered.allCases {
            XCTAssertEqual(
                ObsidianFigureAddOnsTrail.offered(course: "MPM2D", answered: answered),
                try XCTUnwrap(offered[answered.rawValue]).replacingOccurrences(of: "{course}", with: "MPM2D")
            )
        }
        XCTAssertEqual(ObsidianFigureAddOnsTrail.notTheVault(course: "MPM2D"),
                       try XCTUnwrap(trail["notTheVault"] as? String).replacingOccurrences(of: "{course}", with: "MPM2D"))
        let reopened: [String: String] = try XCTUnwrap(trail["reopened"] as? [String: String])
        XCTAssertEqual(ObsidianFigureAddOnsTrail.reopened(course: "C"), reopened["reopened"]?.replacingOccurrences(of: "{course}", with: "C"))
        XCTAssertEqual(ObsidianFigureAddOnsTrail.reopenDeclined(course: "C"), reopened["later"]?.replacingOccurrences(of: "{course}", with: "C"))
        XCTAssertEqual(ObsidianFigureAddOnsTrail.didNotClose(course: "C"), reopened["didNotClose"]?.replacingOccurrences(of: "{course}", with: "C"))
        let setting: [String: String] = try XCTUnwrap(trail["settingChanged"] as? [String: String])
        XCTAssertEqual(ObsidianFigureAddOnsTrail.settingChanged(on: true), setting["on"])
        XCTAssertEqual(ObsidianFigureAddOnsTrail.settingChanged(on: false), setting["off"])

        let pass: [String: Any] = try XCTUnwrap(trail["pass"] as? [String: Any])
        let triggers: [String: String] = try XCTUnwrap(pass["triggers"] as? [String: String])
        for trigger in ObsidianFigureAddOnsTrail.Trigger.allCases {
            XCTAssertEqual(ObsidianFigureAddOnsTrail.triggerWords(trigger), triggers[trigger.rawValue])
        }
        let parts: [String: String] = try XCTUnwrap(pass["parts"] as? [String: String])
        let tikz: ObsidianFigureAddOn = ObsidianFigureAddOns.pinned[0]
        let samples: [ObsidianFigureAddOns.Outcome] = [
            .added, .alreadyThere, .alreadyThereSwitchedOff, .leftAloneTheirs(version: "0.6.0"),
            .leftAloneOtherVersion(version: "0.6.0"), .leftAloneUnreadable, .couldNotWrite(reason: "The disk is full."),
        ]
        for outcome in samples {
            let template: String = try XCTUnwrap(parts[outcome.contractName], outcome.contractName)
            let expected: String = template
                .replacingOccurrences(of: "{name}", with: tikz.name)
                .replacingOccurrences(of: "{pinned}", with: tikz.version)
                .replacingOccurrences(of: "{version}", with: "0.6.0")
                .replacingOccurrences(of: "{reason}", with: "The disk is full.")
            XCTAssertEqual(ObsidianFigureAddOnsTrail.words(for: ObsidianFigureAddOns.Result(addOn: tikz, outcome: outcome)), expected)
        }
        let refusals: [String: String] = try XCTUnwrap(pass["refusals"] as? [String: String])
        let refused: [ObsidianFigureAddOns.Outcome] = [.refusedListUnreadable, .refusedLink, .refusedCarriedCopy, .refusedSettingsNotSeeded]
        for outcome in refused {
            XCTAssertEqual(ObsidianFigureAddOnsTrail.refusalWords(outcome), refusals[outcome.contractName], outcome.contractName)
        }
        let example: String = try XCTUnwrap(pass["example"] as? String)
        XCTAssertEqual(
            ObsidianFigureAddOnsTrail.pass(course: "MPM2D", trigger: .openInObsidian, results: [
                ObsidianFigureAddOns.Result(addOn: tikz, outcome: .added),
                ObsidianFigureAddOns.Result(addOn: ObsidianFigureAddOns.pinned[1], outcome: .alreadyThere),
            ]),
            example
        )
    }

    /// A refusal is said once per course per run, not at every preview
    /// (plan review N4); an addition is always said.
    func testARefusalIsSaidOncePerRun() throws {
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))
        defer { ActivityTrail.store = previous }
        let refused: [ObsidianFigureAddOns.Result] = [ObsidianFigureAddOns.Result(addOn: ObsidianFigureAddOns.pinned[0], outcome: .refusedListUnreadable)]
        ObsidianFigureAddOnsThisRun.notePass(course: "MPM2D", trigger: .afterAPreview, results: refused)
        ObsidianFigureAddOnsThisRun.notePass(course: "MPM2D", trigger: .afterAPreview, results: refused)
        ObsidianFigureAddOnsThisRun.notePass(course: "MPM2D", trigger: .openInObsidian, results: refused)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        XCTAssertEqual(trail.components(separatedBy: "could not be read").count - 1, 1, trail)
    }

    // MARK: - Backups

    /// A REAL zip of a course, read back: Plantoir's add-on is left out, the
    /// teacher's own is kept, and so is the list.
    func testBackupsLeavePlantoirsAddOnsOut() async throws {
        let rules: [String: Any] = try XCTUnwrap(try ObsidianFigureAddOnsTests.rules()["backups"] as? [String: Any])
        // A folder name zip would read as wildcards (implementation review N1).
        for folderName in ["MPM2D", "MPM2D [old]"] {
        for (index, testCase) in try XCTUnwrap(rules["cases"] as? [[String: Any]]).enumerated() {
            let name: String = try XCTUnwrap(testCase["name"] as? String) + " (" + folderName + ")"
            let coursesURL: URL = rootURL.appendingPathComponent("backups-\(index)-\(folderName.count)/courses")
            let courseURL: URL = coursesURL.appendingPathComponent(folderName)
            let pluginsURL: URL = courseURL.appendingPathComponent(".obsidian/plugins")
            try FileManager.default.createDirectory(at: pluginsURL, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: courseURL.appendingPathComponent(".obsidian/app.json"))
            try Data("[]".utf8).write(to: courseURL.appendingPathComponent(".obsidian/community-plugins.json"))
            try Data("# Hi\n".utf8).write(to: courseURL.appendingPathComponent("index.md"))
            for (folder, value) in try XCTUnwrap(testCase["plugins"] as? [String: [String: Bool]]) {
                let folderURL: URL = pluginsURL.appendingPathComponent(folder)
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: folderURL.appendingPathComponent("main.js"))
                if value["marker"] == true {
                    try Data(ObsidianFigureAddOns.markerText(version: "0.5.2").utf8).write(to: folderURL.appendingPathComponent(ObsidianFigureAddOns.markerName))
                }
            }
            let zipURL: URL = try await CourseArchiver.backingUp(
                courseDirectoryPath: courseURL.path, code: "MPM2D", coursesDirectoryPath: coursesURL.path
            )
            let listing: Set<String> = try ObsidianFigureAddOnsTests.zipListing(zipURL)
            for path in try XCTUnwrap(testCase["inZip"] as? [String]) {
                XCTAssertTrue(listing.contains(folderName + "/" + path), "\(name): \(path) is missing from the zip")
            }
            for path in try XCTUnwrap(testCase["notInZip"] as? [String]) {
                XCTAssertFalse(listing.contains(folderName + "/" + path), "\(name): \(path) is in the zip")
            }
        }
        }
    }

    // MARK: - Helpers

    /// What a driven route did, and what the fake world says.
    @MainActor
    final class Log {
        var opened: [String] = []
        var pluginsAtOpen: [[String]] = []
        var scans: Int = 0
        var quits: Int = 0
        var quitCloses: Bool = true
        /// Obsidian is running (hidden or not: no window is ever counted).
        var running: Bool = false
        var reopened: [[String]] = []
        var openVaults: [String] = []
        var registry: Data?
    }

    struct Driven {
        let workspace: WorkspaceModel
        let course: Course
        let settings: AppSettings
        let log: Log
    }

    /// A course with a tikz fence on a section page, and a workspace whose
    /// every door to Obsidian is a fake that writes in `log`. The trail goes
    /// to a throwaway folder.
    func drive(answer: ObsidianFigureAddOnsAnswer) throws -> Driven {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixtureURL)
        }
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: fixtureURL.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        try Data("```tikz\n\\begin{document}\n\\end{document}\n```\n".utf8)
            .write(to: course.sectionDirectoryURL(forSection: 1).appendingPathComponent("Figures.md"))
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail-\(UUID().uuidString)"))
        addTeardownBlock {
            ActivityTrail.store = previous
        }

        let settings: AppSettings = AppSettings(defaults: TestDefaults.make())
        settings.obsidianFigureAddOns = answer
        let log: Log = Log()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        var opening: ObsidianOpening = ObsidianOpening()
        opening.settings = settings
        opening.isInstalled = { return true }
        opening.isRunning = { return log.running }
        opening.registryData = {
            if let registry = log.registry {
                return registry
            }
            return try? ObsidianFigureAddOnsTests.registry(vaults: log.openVaults, open: true)
        }
        opening.open = { folder, vault in
            log.opened.append(folder.path)
            let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent(".obsidian/plugins").path)) ?? []
            log.pluginsAtOpen.append(entries.sorted())
        }
        opening.quitAndWait = {
            log.quits += 1
            if log.quitCloses {
                log.running = false
            }
        }
        opening.reopen = { paths in
            log.reopened.append(paths)
        }
        opening.scan = { coursePath in
            await MainActor.run {
                log.scans += 1
            }
            return await ObsidianFigureAddOns.scan(courseAt: coursePath)
        }
        opening.carriedFolder = Bundle.main.resourceURL?.appendingPathComponent(ObsidianFigureAddOns.carriedFolderName)
        opening.defaultsFolder = defaultsURL()
        workspace.obsidianOpening = opening
        return Driven(workspace: workspace, course: course, settings: settings, log: log)
    }

    func makeCourse(named code: String) throws -> URL {
        let courseURL: URL = rootURL.appendingPathComponent(UUID().uuidString).appendingPathComponent(code)
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        return courseURL
    }

    func defaultsURL() -> URL? {
        return Bundle.main.resourceURL?.appendingPathComponent("support/obsidian_defaults/.obsidian")
    }

    func neededIDs(inCourseAt courseURL: URL) -> [String] {
        var kinds: Set<String> = []
        for addOn in ObsidianFigureAddOns.pinned {
            kinds.insert(addOn.kind)
        }
        var ids: [String] = []
        for addOn in ObsidianFigureAddOns.addOns(forKinds: ObsidianFigureAddOns.kindsUsed(inCourseAt: courseURL, among: kinds)) {
            ids.append(addOn.id)
        }
        return ids
    }

    /// Small stand-ins for the pinned add-ons — the same ids and versions,
    /// a few bytes each, pinned to their own hashes — so 22 cases do not
    /// copy 13 MB each. `mismatched` changes a file after it is pinned.
    func fakeAddOns(in folderURL: URL, mismatched: Bool) throws -> (addOns: [ObsidianFigureAddOn], carried: URL) {
        let carriedURL: URL = folderURL.appendingPathComponent("carried")
        var addOns: [ObsidianFigureAddOn] = []
        for pinned in ObsidianFigureAddOns.pinned {
            let addOnURL: URL = carriedURL.appendingPathComponent(pinned.id)
            try FileManager.default.createDirectory(at: addOnURL, withIntermediateDirectories: true)
            var files: [ObsidianFigureAddOn.CarriedFile] = []
            for file in pinned.files {
                let text: String
                if file.name == "manifest.json" {
                    text = "{\"id\":\"\(pinned.id)\",\"version\":\"\(pinned.version)\"}"
                } else {
                    text = "Plantoir's copy of \(pinned.id)/\(file.name)"
                }
                let data: Data = Data(text.utf8)
                try data.write(to: addOnURL.appendingPathComponent(file.name))
                files.append(ObsidianFigureAddOn.CarriedFile(name: file.name, bytes: data.count, sha256: ObsidianFigureAddOns.sha256(of: data)))
            }
            addOns.append(ObsidianFigureAddOn(kind: pinned.kind, id: pinned.id, name: pinned.name, version: pinned.version, files: files))
        }
        if mismatched {
            try Data("Plantoir's copy of obsidian-tikzjax/main.jz".utf8).write(to: carriedURL.appendingPathComponent("obsidian-tikzjax/main.js"))
        }
        return (addOns: addOns, carried: carriedURL)
    }

    func fakeDefaults(in folderURL: URL) throws -> URL {
        let defaultsURL: URL = folderURL.appendingPathComponent("defaults/.obsidian")
        try FileManager.default.createDirectory(at: defaultsURL, withIntermediateDirectories: true)
        try Data("{\"attachmentFolderPath\":\"Media\"}".utf8).write(to: defaultsURL.appendingPathComponent("app.json"))
        try Data("{}".utf8).write(to: defaultsURL.appendingPathComponent("appearance.json"))
        return defaultsURL
    }

    /// Builds a vault case's `before`.
    func build(before: [String: Any], course courseURL: URL, caseURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        let settingsURL: URL = courseURL.appendingPathComponent(".obsidian")
        let settings: String = (before["settings"] as? String) ?? "present"
        switch settings {
        case "absent":
            break
        case "link":
            let elsewhere: URL = caseURL.appendingPathComponent("elsewhere-settings")
            try fileManager.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: elsewhere.appendingPathComponent("app.json"))
            try fileManager.createSymbolicLink(at: settingsURL, withDestinationURL: elsewhere)
        case "presentWithoutAppJson":
            try fileManager.createDirectory(at: settingsURL, withIntermediateDirectories: true)
        default:
            try fileManager.createDirectory(at: settingsURL, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: settingsURL.appendingPathComponent("app.json"))
        }
        let pluginsURL: URL = settingsURL.appendingPathComponent("plugins")
        if before["plugins"] as? String == "readOnly" {
            try fileManager.createDirectory(at: pluginsURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: pluginsURL.path)
            addTeardownBlock {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pluginsURL.path)
            }
        }
        if before["plugins"] as? String == "link" {
            let elsewhere: URL = caseURL.appendingPathComponent("elsewhere-plugins")
            try fileManager.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: pluginsURL, withDestinationURL: elsewhere)
        }
        if let list = before["list"] as? String {
            try Data(list.utf8).write(to: settingsURL.appendingPathComponent("community-plugins.json"))
        }
        if let addOns = before["addOns"] as? [String: Any] {
            for (id, state) in addOns {
                let folderURL: URL = pluginsURL.appendingPathComponent(id)
                if state as? String == "file" {
                    try fileManager.createDirectory(at: pluginsURL, withIntermediateDirectories: true)
                    try Data("not a folder".utf8).write(to: folderURL)
                    continue
                }
                let described: [String: Any] = try XCTUnwrap(state as? [String: Any])
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try Data("the copy that was there".utf8).write(to: folderURL.appendingPathComponent("main.js"))
                if let version = described["version"] as? String {
                    try Data("{\"id\":\"\(id)\",\"version\":\"\(version)\"}".utf8).write(to: folderURL.appendingPathComponent("manifest.json"))
                } else {
                    try Data("{ not json".utf8).write(to: folderURL.appendingPathComponent("manifest.json"))
                }
                if described["marker"] as? Bool == true {
                    try Data(ObsidianFigureAddOns.markerText(version: (described["version"] as? String) ?? "0.5.2").utf8)
                        .write(to: folderURL.appendingPathComponent(ObsidianFigureAddOns.markerName))
                }
            }
        }
        for id in (before["partial"] as? [String]) ?? [] {
            let partialURL: URL = pluginsURL.appendingPathComponent(id + ObsidianFigureAddOns.partialSuffix)
            try fileManager.createDirectory(at: partialURL, withIntermediateDirectories: true)
            try Data("half".utf8).write(to: partialURL.appendingPathComponent("main.js"))
        }
    }

    /// An outcome as the contract writes it: the name, and `:<version>` for
    /// the left-alone ones.
    static func contractWords(for outcome: ObsidianFigureAddOns.Outcome) -> String {
        switch outcome {
        case .leftAloneTheirs(let version), .leftAloneOtherVersion(let version):
            return outcome.contractName + ":" + version
        default:
            return outcome.contractName
        }
    }

    /// Every file under a folder: its hash and modification date.
    static func snapshot(of folderURL: URL) -> [String: String] {
        var result: [String: String] = [:]
        let walker: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )
        while let fileURL = walker?.nextObject() as? URL {
            let values: URLResourceValues? = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile != true {
                continue
            }
            let data: Data = (try? Data(contentsOf: fileURL)) ?? Data()
            let date: String = String(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            result[fileURL.path] = ObsidianFigureAddOns.sha256(of: data) + " " + date
        }
        return result
    }

    static func registry(vaults: [String], open: Bool = false) throws -> Data {
        var entries: [String: Any] = [:]
        for (index, path) in vaults.enumerated() {
            if open {
                entries[String(format: "%016x", index + 1)] = ["path": path, "ts": 1, "open": true]
            } else {
                entries[String(format: "%016x", index + 1)] = ["path": path, "ts": 1]
            }
        }
        return try JSONSerialization.data(withJSONObject: ["vaults": entries])
    }

    static func zipListing(_ zipURL: URL) throws -> Set<String> {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zipURL.path]
        let output: Pipe = Pipe()
        process.standardOutput = output
        try process.run()
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var listing: Set<String> = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            listing.insert(String(line))
        }
        return listing
    }

    static func ourWords() -> [String: String] {
        return [
            "offerTitle": ObsidianFigureAddOnsWording.offerTitle,
            "offerMessage": ObsidianFigureAddOnsWording.offerMessage,
            "offerWhileOpen": ObsidianFigureAddOnsWording.offerWhileOpen,
            "offerAdd": ObsidianFigureAddOnsWording.offerAdd,
            "offerNotNow": ObsidianFigureAddOnsWording.offerNotNow,
            "dontAskAgain": ObsidianFigureAddOnsWording.dontAskAgain,
            "reopenTitle": ObsidianFigureAddOnsWording.reopenTitle,
            "reopenMessage": ObsidianFigureAddOnsWording.reopenMessage,
            "reopen": ObsidianFigureAddOnsWording.reopen,
            "later": ObsidianFigureAddOnsWording.later,
            "paneTitle": ObsidianFigureAddOnsWording.paneTitle,
            "settingLabel": ObsidianFigureAddOnsWording.settingLabel,
            "settingFooter": ObsidianFigureAddOnsWording.settingFooter,
        ]
    }

    static func rules() throws -> [String: Any] {
        return try SharedRulesContractTests.section("obsidianAddOnsForFigures")
    }
}
