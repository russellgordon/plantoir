import SwiftUI
import XCTest
@testable import QuartzTeachers

/// "Copy a Page from This Course…" — the rule set, run from
/// `contracts/shared-rules.json` → `copyingAPageBetweenCourses`.
///
/// The cases are AUTHORED data, deserialised rather than retyped, so the
/// Windows app runs the identical list. Two families:
///
/// * `frontmatterCases` — a source page's text and a destination's sections in,
///   the composed text out. Pure, and the family that pins the one failure
///   this feature must never have.
/// * `cases` — a small synthetic source course and destination on disk, and
///   the plan that must come out.
///
/// The must-fail tests are at the bottom, each named for the fault it proves
/// is closed.
final class CoursePageCopyTests: XCTestCase {

    // MARK: - Stored properties

    var rules: [String: Any] = [:]
    var scratch: URL = URL(fileURLWithPath: "/tmp")

    // MARK: - Functions

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        rules = try XCTUnwrap(
            all["copyingAPageBetweenCourses"] as? [String: Any],
            "No copyingAPageBetweenCourses in shared-rules.json"
        )
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("copy-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        ReferenceLock.unlock(courseDirectory: scratch)
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - The frontmatter, from the contract

    /// Every authored frontmatter case: the composed text carries what it must,
    /// carries nothing it must not, and READS hidden in every section named —
    /// including ones the destination does not have.
    func testEveryFrontmatterCaseComposesAHiddenPage() throws {
        let cases: [[String: Any]] = try XCTUnwrap(rules["frontmatterCases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 5, "The contract's frontmatter cases did not load.")

        for oneCase in cases {
            let name: String = (oneCase["name"] as? String) ?? "?"
            let source: String = try XCTUnwrap(oneCase["source"] as? String, name)
            let sections: [Int] = try XCTUnwrap(oneCase["sections"] as? [Int], name)
            let written: String = CopiedPageText.hidden(from: source, forSections: sections)

            for fragment in (oneCase["mustContain"] as? [String]) ?? [] {
                XCTAssertTrue(
                    written.contains(fragment),
                    "\(name): the copy does not carry “\(fragment)”:\n\(written)"
                )
            }
            for fragment in (oneCase["mustNotContain"] as? [String]) ?? [] {
                XCTAssertFalse(
                    written.contains(fragment),
                    "\(name): the copy still carries “\(fragment)”:\n\(written)"
                )
            }
            for sectionNumber in (oneCase["hiddenInSections"] as? [Int]) ?? [] {
                XCTAssertEqual(
                    AssistPageVisibility.answer(in: written, forSection: sectionNumber), .hidden,
                    "\(name): section \(sectionNumber) does not read hidden:\n\(written)"
                )
            }
        }
    }

    /// The per-section keys read 1, 2, 3 in the file rather than backwards.
    /// Cosmetic, and it is the one thing the writer's insert-at-the-top
    /// behaviour makes easy to get wrong and never notice.
    func testThePerSectionKeysAreInReadingOrder() {
        let written: String = CopiedPageText.hidden(
            from: "---\ntitle: X\n---\nBody\n", forSections: [1, 2, 3]
        )
        let one: Range<String.Index>? = written.range(of: "publishForSection1")
        let two: Range<String.Index>? = written.range(of: "publishForSection2")
        let three: Range<String.Index>? = written.range(of: "publishForSection3")
        XCTAssertNotNil(one)
        XCTAssertNotNil(two)
        XCTAssertNotNil(three)
        if let one, let two, let three {
            XCTAssertTrue(one.lowerBound < two.lowerBound)
            XCTAssertTrue(two.lowerBound < three.lowerBound)
        }
    }

    // MARK: - The planner, from the contract

    func testEveryPlannerCaseGivesThePlanTheContractNames() throws {
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 10, "The contract's planner cases did not load.")

        for oneCase in cases {
            let name: String = (oneCase["name"] as? String) ?? "?"
            let built: Built = try build(oneCase, named: name)

            if let offers = oneCase["offers"] as? [String] {
                var listed: [String] = []
                for page in CoursePageCopyPlanner.copyablePages(in: built.source) {
                    listed.append(page.relativePath)
                }
                XCTAssertEqual(listed, offers, "\(name): the wrong pages are offered")
                continue
            }

            let plan: CoursePageCopyPlan = CoursePageCopyPlanner.plan(try XCTUnwrap(built.request))
            let expected: [String: Any] = try XCTUnwrap(oneCase["expect"] as? [String: Any], name)

            var landed: [String] = []
            for placement in plan.pages {
                landed.append(placement.destinationFolderName + "/" + placement.fileName.text)
            }
            XCTAssertEqual(
                landed.sorted(), ((expected["pages"] as? [String]) ?? []).sorted(),
                "\(name): pages"
            )

            var required: [String] = []
            for placement in plan.pages where placement.isRequired {
                required.append(placement.pageName)
            }
            XCTAssertEqual(
                required.sorted(), ((expected["required"] as? [String]) ?? []).sorted(),
                "\(name): pages that cannot be unticked"
            )

            var created: [String] = []
            for item in plan.mediaToCreate {
                created.append(item.destinationName.text)
            }
            XCTAssertEqual(
                created.sorted(), ((expected["mediaCreated"] as? [String]) ?? []).sorted(),
                "\(name): pictures and files created"
            )

            var reused: [String] = []
            for item in plan.mediaAlreadyThere {
                reused.append(item.destinationName.text)
            }
            XCTAssertEqual(
                reused.sorted(), ((expected["mediaReused"] as? [String]) ?? []).sorted(),
                "\(name): pictures reused"
            )

            var renamed: [String: String] = [:]
            for item in plan.mediaUnderANewName {
                renamed[item.sourceName.text] = item.destinationName.text
            }
            XCTAssertEqual(
                renamed, (expected["mediaRenamed"] as? [String: String]) ?? [:],
                "\(name): pictures under a new name"
            )

            var skipped: [String] = []
            for skip in plan.skipped {
                skipped.append(skip.name + "|" + skip.reason.rawValue)
            }
            var expectedSkips: [String] = []
            for entry in (expected["skipped"] as? [[String: String]]) ?? [] {
                expectedSkips.append((entry["name"] ?? "") + "|" + (entry["reason"] ?? ""))
            }
            XCTAssertEqual(skipped.sorted(), expectedSkips.sorted(), "\(name): skips")

            XCTAssertEqual(
                plan.linksLeadingNowhere.sorted(),
                ((expected["linksLeadingNowhere"] as? [String]) ?? []).sorted(),
                "\(name): links leading nowhere"
            )
        }
    }

    // MARK: - The planner writes nothing

    /// A plan is a SURVEY. Nothing on either disk moves, and asking twice
    /// gives the same answer — which is what lets the sheet show a teacher
    /// what will happen before they agree to it.
    func testPlanningWritesNothingAndIsTheSameTwice() throws {
        let built: Built = try buildOrdinaryPair()
        let before: [String: String] = manifest(of: built.source.directoryURL)
            .merging(manifest(of: built.destination.directoryURL)) { first, _ in first }

        let first: CoursePageCopyPlan = CoursePageCopyPlanner.plan(try XCTUnwrap(built.request))
        let second: CoursePageCopyPlan = CoursePageCopyPlanner.plan(try XCTUnwrap(built.request))

        let after: [String: String] = manifest(of: built.source.directoryURL)
            .merging(manifest(of: built.destination.directoryURL)) { first, _ in first }
        XCTAssertEqual(before, after, "Planning changed something on disk.")
        XCTAssertEqual(first.pages.count, second.pages.count)
        XCTAssertEqual(first.media.count, second.media.count)
        XCTAssertEqual(first.totalBytes, second.totalBytes)
    }

    // MARK: - The copy, end to end

    func testACopyArrivesHiddenUnlockedAndChangesNothingElse() async throws {
        let built: Built = try buildOrdinaryPair()
        let before: [String: String] = manifest(of: built.destination.directoryURL)
        let sourceBefore: [String: String] = manifest(of: built.source.directoryURL)

        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertEqual(outcome.pagesCreated, ["Recursion"])
        XCTAssertEqual(outcome.mediaCreated, 1)
        XCTAssertEqual(outcome.skipped.count, 0)

        let landed: URL = built.destination.directoryURL
            .appendingPathComponent("Concepts/Recursion.md")
        let text: String = try String(contentsOf: landed, encoding: .utf8)
        for sectionNumber in [1, 2, 9] {
            XCTAssertEqual(
                AssistPageVisibility.answer(in: text, forSection: sectionNumber), .hidden,
                "The copy is not hidden in section \(sectionNumber):\n\(text)"
            )
        }
        XCTAssertFalse(ReferenceLock.isLocked(landed))

        XCTAssertEqual(
            sourceBefore, manifest(of: built.source.directoryURL),
            "The SOURCE course changed. It is only ever read."
        )
        let after: [String: String] = manifest(of: built.destination.directoryURL)
        for (path, contents) in before {
            XCTAssertEqual(after[path], contents, "“\(path)” changed in the destination.")
        }
    }

    /// A copy taken out of a course whose pages are all LOCKED arrives
    /// unlocked — the page and the picture alike.
    ///
    /// MUST-FAIL. Without `ReferenceLock.clearLock` on the copied picture,
    /// `copyfile` carries the user-immutable flag across and the teacher meets
    /// a file they cannot replace, with no explanation.
    func testACopyTakenFromALockedCourseIsNotItselfLocked() async throws {
        let built: Built = try buildOrdinaryPair()
        ReferenceLock.lock(courseDirectory: built.source.directoryURL)
        XCTAssertTrue(
            ReferenceLock.isLocked(
                built.source.directoryURL.appendingPathComponent("Media/one.png")
            ),
            "The test's own source course is not locked, so this would pass vacuously."
        )

        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertEqual(outcome.pagesCreated, ["Recursion"])

        let page: URL = built.destination.directoryURL
            .appendingPathComponent("Concepts/Recursion.md")
        let picture: URL = built.destination.directoryURL
            .appendingPathComponent("Media/one.png")
        XCTAssertFalse(ReferenceLock.isLocked(page), "The copied page arrived locked.")
        XCTAssertFalse(ReferenceLock.isLocked(picture), "The copied picture arrived locked.")
        // Proved by USE rather than by the flag alone: the teacher's test is
        // whether they can save over it.
        XCTAssertNoThrow(try Data("edited".utf8).write(to: picture))
    }

    /// A page of that name already in the destination is left exactly as it
    /// is.
    ///
    /// MUST-FAIL. Without the create-exclusive write the teacher's own page is
    /// replaced by last year's.
    func testAPageOfThatNameIsNeverOverwritten() async throws {
        let built: Built = try buildPair(
            destinationPages: [("Concepts/Recursion.md", "THE TEACHER’S OWN PAGE\n")]
        )
        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertTrue(outcome.createdNothing)
        XCTAssertEqual(outcome.skipped.first?.reason, .aPageOfThatNameIsAlreadyHere)
        let theirs: String = try String(
            contentsOf: built.destination.directoryURL
                .appendingPathComponent("Concepts/Recursion.md"),
            encoding: .utf8
        )
        XCTAssertEqual(theirs, "THE TEACHER’S OWN PAGE\n")
    }

    /// A picture of the same name and different bytes is never written over —
    /// the incoming one arrives beside it and only the COPIED page is pointed
    /// at it.
    ///
    /// MUST-FAIL. Without the rename the teacher's picture is replaced.
    func testAPictureOfTheSameNameAndDifferentBytesIsNeverOverwritten() async throws {
        let built: Built = try buildPair(destinationMedia: [("one.png", "THEIRS")])
        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertEqual(outcome.pagesCreated, ["Recursion"])
        XCTAssertEqual(outcome.renamed.count, 1)

        let theirs: String = try String(
            contentsOf: built.destination.directoryURL.appendingPathComponent("Media/one.png"),
            encoding: .utf8
        )
        XCTAssertEqual(theirs, "THEIRS", "The teacher's own picture was replaced.")

        let newName: String = try XCTUnwrap(outcome.renamed.first?.to)
        XCTAssertEqual(newName, "one (from ICS4U-2025).png")
        let copied: String = try String(
            contentsOf: built.destination.directoryURL
                .appendingPathComponent("Media").appendingPathComponent(newName),
            encoding: .utf8
        )
        XCTAssertEqual(copied, "PICTURE")

        let page: String = try String(
            contentsOf: built.destination.directoryURL
                .appendingPathComponent("Concepts/Recursion.md"),
            encoding: .utf8
        )
        XCTAssertTrue(
            page.contains("![[one (from ICS4U-2025).png]]"),
            "The copied page was not pointed at the renamed picture:\n\(page)"
        )
        XCTAssertFalse(
            page.contains("![[one.png]]"),
            "The copied page still names the teacher's own different picture."
        )
    }

    /// A copy that cannot be shown to be hidden is DELETED and reported as not
    /// copied.
    ///
    /// MUST-FAIL for the read-back guard: with the guard removed, a page whose
    /// composed text this app cannot read would be left on disk, and the build
    /// publishes anything that does not certainly say false.
    func testAPageThatCannotBeProvedHiddenIsTakenAwayAgain() throws {
        let hidden: String = CopiedPageText.hidden(
            from: "---\ntitle: X\n---\nBody\n", forSections: [1]
        )
        let good: URL = scratch.appendingPathComponent("good.md")
        try Data(hidden.utf8).write(to: good)
        XCTAssertTrue(CoursePageCopier.isCertainlyHidden(at: good, forSections: [1]))

        // A value this app will not read. The build resolves the per-section
        // key onto the plain one, so a page it cannot read is one that may
        // well be published — and "cannot tell" has to count as failure.
        let odd: URL = scratch.appendingPathComponent("odd.md")
        try Data("---\npublishForSection1: &anchor false\npublish: &b false\n---\nBody\n".utf8)
            .write(to: odd)
        XCTAssertFalse(
            CoursePageCopier.isCertainlyHidden(at: odd, forSections: [1]),
            "A page whose flag this app cannot read was accepted as hidden."
        )

        // A page hidden in the sections it was told about and silent about a
        // section the course could gain.
        let future: URL = scratch.appendingPathComponent("future.md")
        try Data("---\npublishForSection1: false\n---\nBody\n".utf8).write(to: future)
        XCTAssertFalse(
            CoursePageCopier.isCertainlyHidden(at: future, forSections: [1]),
            "A page that says nothing about a section the course could gain was accepted as hidden."
        )
    }

    /// Names are BYTES. A picture whose name is composed stays composed, and
    /// one whose name is decomposed stays decomposed.
    ///
    /// MUST-FAIL. Rebuilding the destination from a `URL` decomposes a
    /// composed name — measured — the page's embed then stops resolving, and
    /// the picture vanishes from the built site with no error anywhere.
    func testAPicturesNameIsCarriedAsBytes() async throws {
        // Run once per spelling, in a course of its own: this volume looks a
        // name up without regard to normalisation, so the two cannot sit in
        // one folder — the second create is refused as already existing.
        for name in ["Bone App\u{00e9}tit.jpg", "Bone Appe\u{0301}tit.jpg"] {
            let built: Built = try buildPair(
                in: "bytes-\(Array(name.utf8).count)",
                pageText: "![[\(name)]]\n",
                sourceMedia: [(name, "ONE")]
            )
            let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
                try XCTUnwrap(built.request)
            )
            XCTAssertEqual(outcome.pagesCreated, ["Recursion"])

            var landed: [[UInt8]] = []
            for nameBytes in ReferenceTreeCopier.names(
                inFolderAt: built.destination.directoryURL.appendingPathComponent("Media")
            ) {
                landed.append(nameBytes)
            }
            XCTAssertEqual(
                landed, [Array(name.utf8)],
                "The name was re-spelled on the way in. In: \(Array(name.utf8)); out: \(landed)"
            )
        }
    }


    // MARK: - Would the website builder read it the same way?

    /// Every authored case in the contract's `builderAgreement` family.
    ///
    /// The app's reader is not the one that decides what students see, and
    /// the two shapes this closes were reproduced end to end with the copy
    /// certified hidden here and PUBLISHED there.
    func testTheBuilderAgreementCasesAnswerAsTheContractSays() throws {
        let family: [String: Any] = try XCTUnwrap(rules["builderAgreement"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(family["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 5, "The builder-agreement cases did not load.")
        for oneCase in cases {
            let name: String = (oneCase["name"] as? String) ?? "?"
            let text: String = try XCTUnwrap(oneCase["text"] as? String, name)
            let expected: Bool = try XCTUnwrap(oneCase["builderAgrees"] as? Bool, name)
            XCTAssertEqual(
                CopiedPageText.theBuilderWouldReadItTheSameWay(text), expected,
                "\(name): the builder-agreement answer is wrong for:\n\(text)"
            )
        }
    }

    /// A source page whose settings block is closed by an INDENTED fence is
    /// not copied, and nothing is left behind.
    ///
    /// MUST-FAIL. Without the second question the app's own reader certifies
    /// the copy hidden, the build reads no settings at all, and Quartz
    /// publishes the page to students.
    func testAPageTheBuilderWouldReadDifferentlyIsNotCopied() async throws {
        let built: Built = try buildPair(
            in: "indented-fence",
            pageText: "---\ntitle: X\npublish: true\n  ---\nbody\n",
            sourceMedia: []
        )
        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertTrue(outcome.createdNothing, "The page was copied.")
        XCTAssertEqual(
            outcome.skipped.first?.reason, .thePageIsWrittenInAWayPlantoirCannotBeSureOf
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: built.destination.directoryURL
                .appendingPathComponent("Concepts/Recursion.md").path),
            "The page that could not be certified was left on disk."
        )
        XCTAssertEqual(outcome.couldNotBeRemoved, [])
    }

    /// The read-back's DELETE branch, run through the real copy rather than
    /// asked of `isCertainlyHidden` alone.
    ///
    /// A tab-indented settings line reads `cannotTell` in this app, which is
    /// the branch that writes the file and then takes it away again — the
    /// four most safety-critical lines in the feature, and nothing ran them
    /// until this test.
    func testThePageIsWrittenAndThenDeletedWhenItCannotBeProvedHidden() async throws {
        let built: Built = try buildPair(
            in: "tab-frontmatter",
            pageText: "---\n\ttitle: X\npublish:\ttrue\n---\nbody\n",
            sourceMedia: []
        )
        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertTrue(outcome.createdNothing)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: built.destination.directoryURL
                .appendingPathComponent("Concepts/Recursion.md").path),
            "The page was left on disk after the guard refused it."
        )
        XCTAssertEqual(outcome.couldNotBeRemoved, [])
    }

    /// When an incoming picture that needs a new name cannot get one, the
    /// PAGE is not copied.
    ///
    /// MUST-FAIL. With the page written anyway, its embed names a file the
    /// destination already has with DIFFERENT bytes — so the copy shows the
    /// teacher their own, wrong picture, and the summary says the link "will
    /// not lead anywhere".
    func testAPictureThatCannotBeGivenAFreeNameStopsThePage() async throws {
        var destinationMedia: [(String, String)] = [("one.png", "THEIRS")]
        destinationMedia.append(("one (from ICS4U-2025).png", "taken"))
        for attempt in 2...50 {
            destinationMedia.append(("one (from ICS4U-2025) \(attempt).png", "taken"))
        }
        let built: Built = try buildPair(
            in: "rename-exhausted", destinationMedia: destinationMedia
        )
        let outcome: CoursePageCopyOutcome = await CoursePageCopier.copying(
            try XCTUnwrap(built.request)
        )
        XCTAssertTrue(outcome.createdNothing, "The page was copied with an embed pointing at the teacher's own different picture.")
        XCTAssertEqual(
            outcome.skipped.first?.reason, .thePicturesCouldNotBePointedAtTheirNewNames
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: built.destination.directoryURL
                .appendingPathComponent("Concepts/Recursion.md").path)
        )
        let theirs: String = try String(
            contentsOf: built.destination.directoryURL.appendingPathComponent("Media/one.png"),
            encoding: .utf8
        )
        XCTAssertEqual(theirs, "THEIRS")
    }

    // MARK: - Off the main actor

    /// The backup and the copy do not run on the main thread.
    ///
    /// Asserted rather than trusted to the `@concurrent` annotation, because a
    /// plain `nonisolated async` function runs on its CALLER's actor in this
    /// target — `SWIFT_APPROACHABLE_CONCURRENCY` is on — so losing the
    /// attribute in an edit would put a ten-second zip back on the main actor
    /// while the code still read as though it did not.
    @MainActor
    func testTheCopyDoesNotRunOnTheMainThread() async throws {
        let built: Built = try buildOrdinaryPair()
        CoursePageCopier.lastPassRanOnTheMainThread = nil
        _ = await CoursePageCopier.copying(try XCTUnwrap(built.request))
        XCTAssertEqual(
            CoursePageCopier.lastPassRanOnTheMainThread, false,
            "The copy ran on the main thread."
        )
    }

    @MainActor
    func testTheBackupDoesNotRunOnTheMainThread() async throws {
        let built: Built = try buildOrdinaryPair()
        let coursesURL: URL = built.destination.directoryURL.deletingLastPathComponent()
        CoursePageCopier.lastPassRanOnTheMainThread = nil
        let backupURL: URL = try await CoursePageCopier.backingUp(
            courseDirectoryPath: built.destination.directoryPath,
            code: "ICS4U",
            coursesDirectoryPath: coursesURL.path
        )
        XCTAssertEqual(
            CoursePageCopier.lastPassRanOnTheMainThread, false,
            "The backup ran on the main thread."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(backupURL.lastPathComponent.hasPrefix("ICS4U_backup_"))
    }

    // MARK: - The sentences

    func testTheWordingIsTheContractsWording() throws {
        let wording: [String: Any] = try XCTUnwrap(rules["wording"] as? [String: Any])
        XCTAssertEqual(CopyPageWording.menuItem, wording["menuItem"] as? String)
        XCTAssertEqual(
            CopyPageWording.sheetTitle(course: "{course}"), wording["sheetTitle"] as? String
        )
        XCTAssertEqual(CopyPageWording.whichPage, wording["whichPage"] as? String)
        XCTAssertEqual(CopyPageWording.whichCourse, wording["whichCourse"] as? String)
        XCTAssertEqual(CopyPageWording.whichFolder, wording["whichFolder"] as? String)
        XCTAssertEqual(
            CopyPageWording.pagePickerPrompt, wording["pagePickerPrompt"] as? String
        )
        XCTAssertEqual(CopyPageWording.noPagesMatch, wording["noPagesMatch"] as? String)
        XCTAssertEqual(
            CopyPageWording.copiesStartHidden, wording["copiesStartHidden"] as? String
        )
        XCTAssertEqual(CopyPageWording.datesAreKept, wording["datesAreKept"] as? String)
        XCTAssertEqual(
            CopyPageWording.nothingIsWrittenOver, wording["nothingIsWrittenOver"] as? String
        )
        XCTAssertEqual(CopyPageWording.nothingWasCopied, wording["nothingWasCopied"] as? String)
        XCTAssertEqual(CopyPageWording.copyAnother, wording["copyAnother"] as? String)
        XCTAssertEqual(
            CopyPageWording.thereIsNoCourseToCopyInto,
            wording["thereIsNoCourseToCopyInto"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.savingACopyFirst(course: "{course}"),
            wording["savingACopyFirst"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.theBackupTaken(course: "{course}", named: "{named}"),
            wording["theBackupTaken"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.copiedInto(pages: 3, course: "{course}", folder: "{folder}")
                .replacingOccurrences(of: "3", with: "{pages}"),
            wording["copiedInto"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.willBringPicturesAndFiles(count: 4, size: "{size}")
                .replacingOccurrences(of: "4", with: "{count}"),
            wording["willBringPicturesAndFiles"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.picturesAlreadyThere(count: 4)
                .replacingOccurrences(of: "4", with: "{count}"),
            wording["picturesAlreadyThere"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.picturesBroughtInUnderANewName(count: 4)
                .replacingOccurrences(of: "4", with: "{count}"),
            wording["picturesBroughtInUnderANewName"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.aPageOfThatNameIsAlreadyHere(page: "{page}"),
            wording["aPageOfThatNameIsAlreadyHere"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.theseLinksWillNotLeadAnywhereYet(names: ["{name}", "{name}"]),
            wording["theseLinksWillNotLeadAnywhereYet"] as? String
        )
        // The reason the list is quoted at all: a real page is called
        // "Operators, Selection, Iteration", and a comma-joined list of names
        // read as three pages rather than one.
        XCTAssertEqual(
            CopyPageWording.theseLinksWillNotLeadAnywhereYet(
                names: ["Operators, Selection, Iteration", "Command-Line Projects"]
            ),
            "These links will not lead anywhere yet: “Operators, Selection, Iteration”, “Command-Line Projects”."
        )
        XCTAssertEqual(
            CopyPageWording.thatCourseIsDeployingRightNow(course: "{course}"),
            wording["thatCourseIsDeployingRightNow"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.thisCourseHasNoPagesToCopy(course: "{course}"),
            wording["thisCourseHasNoPagesToCopy"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.theCopyCouldNotBeMadeHidden(page: "{page}"),
            wording["theCopyCouldNotBeMadeHidden"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.thePicturesCouldNotBePointedAtTheirNewNames(page: "{page}"),
            wording["thePicturesCouldNotBePointedAtTheirNewNames"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.thePageCouldNotBeWritten(page: "{page}"),
            wording["thePageCouldNotBeWritten"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.aPictureCouldNotBeCopied(name: "{name}"),
            wording["aPictureCouldNotBeCopied"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.alsoCopyLinkedPages, wording["alsoCopyLinkedPages"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.embeddedPagesAlwaysComeAlong,
            wording["embeddedPagesAlwaysComeAlong"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.aClassPageWasLeftAlone(page: "{page}"),
            wording["aClassPageWasLeftAlone"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.anIndexPageIsNotCopied(page: "{page}"),
            wording["anIndexPageIsNotCopied"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.aPageAtTheCourseRootIsNotCopied(page: "{page}"),
            wording["aPageAtTheCourseRootIsNotCopied"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.aPageInsideOneSectionsFolderIsNotCopied(page: "{page}"),
            wording["aPageInsideOneSectionsFolderIsNotCopied"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.thatCourseHasNowhereToPutIt(course: "{course}"),
            wording["thatCourseHasNowhereToPutIt"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.theCopyOfTheCourseCouldNotBeSaved(course: "{course}"),
            wording["theCopyOfTheCourseCouldNotBeSaved"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.thePageIsWrittenInAWayPlantoirCannotBeSureOf(page: "{page}"),
            wording["thePageIsWrittenInAWayPlantoirCannotBeSureOf"] as? String
        )
        XCTAssertEqual(
            CopyPageWording.theCopyIsStillThereAndMustBeRemoved(page: "{page}", at: "{path}"),
            wording["theCopyIsStillThereAndMustBeRemoved"] as? String
        )
    }

    /// Rule 1: the interface never mentions the machinery.
    func testNoSentenceMentionsTheMachinery() throws {
        let wording: [String: Any] = try XCTUnwrap(rules["wording"] as? [String: Any])
        let forbidden: [String] = [
            "frontmatter", "wikilink", "embed", "media folder", "walk", "graph",
            "script", "container", "toolchain", "docker", "yaml", "symlink",
            "actor", "thread",
        ]
        for (key, value) in wording {
            if key == "rule" || key == "machineryCheck" {
                continue
            }
            guard let sentence = value as? String else {
                continue
            }
            for word in forbidden {
                XCTAssertFalse(
                    sentence.lowercased().contains(word),
                    "copyingAPageBetweenCourses.wording.\(key) says “\(word)”: \(sentence)"
                )
            }
        }
    }

    // MARK: - The trail

    /// The line names the courses and the counts, and never a page.
    @MainActor
    func testTheTrailLineCarriesWhatTheContractSaysAndNothingElse() {
        let outcome: CoursePageCopyOutcome = CoursePageCopyOutcome(
            pagesCreated: ["Recursion", "Stack Frames"],
            mediaCreated: 12,
            mediaReused: 2,
            renamed: [CoursePageCopyOutcome.Renamed(from: "one.png", to: "one (from X).png")],
            skipped: [CopySkip(name: "Arrays", reason: .aPageOfThatNameIsAlreadyHere)],
            linksLeadingNowhere: [],
            bytesCopied: 1_000,
            couldNotBeRemoved: []
        )
        let line: String = CopyPageSheet.trailLine(
            for: outcome,
            fromCourseFolder: "ICS4U-2025",
            intoCourse: "ICS4U",
            folder: "Concepts",
            backupNamed: "ICS4U_backup_2026-09-21_070000.zip"
        )
        XCTAssertTrue(line.contains("ICS4U-2025"))
        XCTAssertTrue(line.contains("ICS4U"))
        XCTAssertTrue(line.contains("Concepts"))
        XCTAssertTrue(line.contains("2 pages"))
        XCTAssertTrue(line.contains("12 pictures"))
        XCTAssertTrue(line.contains("ICS4U_backup_2026-09-21_070000.zip"))
        for pageTitle in ["Recursion", "Stack Frames", "Arrays", "one.png"] {
            XCTAssertFalse(
                line.contains(pageTitle),
                "The trail line names “\(pageTitle)”, which is the teacher's own content."
            )
        }
        XCTAssertFalse(line.contains("could not be removed"))

        // The one thing the line asks the teacher to DO.
        let stuck: CoursePageCopyOutcome = CoursePageCopyOutcome(
            pagesCreated: [], mediaCreated: 0, mediaReused: 0, renamed: [],
            skipped: [CopySkip(name: "Recursion", reason: .theCopyIsStillThereAndMustBeRemoved)],
            linksLeadingNowhere: [], bytesCopied: 0,
            couldNotBeRemoved: ["/x/ICS4U/Concepts/Recursion.md"]
        )
        let stuckLine: String = CopyPageSheet.trailLine(
            for: stuck, fromCourseFolder: "ICS4U-2025", intoCourse: "ICS4U",
            folder: "Concepts", backupNamed: nil
        )
        XCTAssertTrue(stuckLine.contains("could not be removed and must not be deployed"))
        XCTAssertFalse(
            stuckLine.contains("Recursion"),
            "The trail line names a page, which is the teacher's own content."
        )
    }

    /// The event is declared in both places, which is what makes a missing one
    /// fail on both platforms rather than being noticed months later.
    func testTheTrailEventIsInTheContract() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let mustRecord: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        var events: [String] = []
        for entry in mustRecord {
            if let event = entry["event"] as? String {
                events.append(event)
            }
        }
        XCTAssertTrue(
            events.contains(ActivityTrail.Event.pagesCopiedFromAnotherCourse.rawValue),
            "The trail event is not in contracts/shared-rules.json → activityTrail.mustRecord."
        )
        let declared: [String: Any] = try XCTUnwrap(rules["theTrail"] as? [String: Any])
        XCTAssertEqual(
            declared["event"] as? String,
            ActivityTrail.Event.pagesCopiedFromAnotherCourse.rawValue
        )
    }

    // MARK: - The picker's card

    /// The card is sized by the rows a teacher can SEE.
    ///
    /// Measured on a real course: ICS4U offers 156 pages across 11 folders, so
    /// counting every heading regardless of the row cap opened a 494pt card
    /// for one meant to show 252pt of rows — nearly half a screen, mostly
    /// headings.
    @MainActor
    func testTheCardIsNotTallerThanTheRowsItShows() {
        var sections: [PickerSection<CopyablePage>] = []
        for index in 1...11 {
            var rows: [CopyablePage] = []
            for page in 1...14 {
                rows.append(CopyablePage(
                    folderName: "Folder \(index)", fileName: ExactName("Page \(page).md")
                ))
            }
            sections.append(PickerSection(title: "Folder \(index)", rows: rows))
        }
        let overlay: SearchablePickerOverlay<CopyablePage, EmptyView> = SearchablePickerOverlay(
            fieldFrame: CGRect(x: 0, y: 0, width: 300, height: 24),
            sections: sections,
            highlightedRowId: nil,
            emptyMessage: "",
            onSelect: { _ in },
            rowIdentifier: { page in return page.id },
            row: { _, _ in EmptyView() }
        )
        let cap: CGFloat = CGFloat(SearchablePickerOverlay<CopyablePage, EmptyView>.maxVisibleRows)
            * SearchablePickerOverlay<CopyablePage, EmptyView>.rowHeight
            + 2 * SearchablePickerOverlay<CopyablePage, EmptyView>.headingHeight
        XCTAssertLessThanOrEqual(
            overlay.cardHeightForTests, cap,
            "The card opens taller than the rows it can show."
        )
    }

    // MARK: - Building a pair of courses

    struct Built {
        let source: CopyCourseFacts
        let destination: CopyCourseFacts
        let request: CoursePageCopyRequest?
    }

    func buildOrdinaryPair() throws -> Built {
        return try buildPair()
    }

    /// One source page in `Concepts` that embeds one picture, and an empty
    /// two-section destination — the shape most of the tests above vary.
    func buildPair(
        in folderName: String = "courses",
        pageText: String = "![[one.png]]\n",
        sourceMedia: [(String, String)] = [("one.png", "PICTURE")],
        destinationPages: [(String, String)] = [],
        destinationMedia: [(String, String)] = []
    ) throws -> Built {
        let coursesURL: URL = scratch.appendingPathComponent(folderName)
        let sourcePages: [(String, String)] = [("Concepts/Recursion.md", pageText)]
        let source: CopyCourseFacts = try makeCourse(
            at: coursesURL.appendingPathComponent("ICS4U-2025"),
            code: "ICS4U-2025",
            sections: [1],
            sharedFolders: ["Concepts"],
            pages: sourcePages,
            media: sourceMedia
        )
        let destination: CopyCourseFacts = try makeCourse(
            at: coursesURL.appendingPathComponent("ICS4U"),
            code: "ICS4U",
            sections: [1, 2],
            sharedFolders: ["Concepts"],
            pages: destinationPages,
            media: destinationMedia
        )
        let page: CopyablePage = CopyablePage(
            folderName: "Concepts", fileName: ExactName("Recursion.md")
        )
        return Built(
            source: source,
            destination: destination,
            request: CoursePageCopyRequest(
                source: source,
                page: page,
                destination: destination,
                destinationFolderName: "Concepts"
            )
        )
    }

    /// A course from one contract case.
    func build(_ oneCase: [String: Any], named name: String) throws -> Built {
        let coursesURL: URL = scratch.appendingPathComponent("case-\(UUID().uuidString)")
        let sourceSpec: [String: Any] = try XCTUnwrap(oneCase["source"] as? [String: Any], name)
        let source: CopyCourseFacts = try makeCourse(
            at: coursesURL.appendingPathComponent(
                try XCTUnwrap(sourceSpec["folder"] as? String, name)
            ),
            code: try XCTUnwrap(sourceSpec["folder"] as? String, name),
            sections: (sourceSpec["sections"] as? [Int]) ?? [1],
            sharedFolders: (sourceSpec["sharedFolders"] as? [String]) ?? [],
            pages: CoursePageCopyTests.pages(from: sourceSpec["pages"]),
            media: CoursePageCopyTests.media(from: sourceSpec["media"])
        )
        guard let destinationSpec = oneCase["destination"] as? [String: Any] else {
            return Built(source: source, destination: source, request: nil)
        }
        let destination: CopyCourseFacts = try makeCourse(
            at: coursesURL.appendingPathComponent(
                try XCTUnwrap(destinationSpec["folder"] as? String, name)
            ),
            code: try XCTUnwrap(destinationSpec["folder"] as? String, name),
            sections: (destinationSpec["sections"] as? [Int]) ?? [1],
            sharedFolders: (destinationSpec["sharedFolders"] as? [String]) ?? [],
            pages: CoursePageCopyTests.pages(from: destinationSpec["pages"]),
            media: CoursePageCopyTests.fillingInNumberedNames(
                destinationSpec, onto: CoursePageCopyTests.media(from: destinationSpec["media"])
            )
        )
        guard let copy = oneCase["copy"] as? [String: String] else {
            return Built(source: source, destination: destination, request: nil)
        }
        let path: String = try XCTUnwrap(copy["page"], name)
        guard let slash = path.firstIndex(of: "/") else {
            throw XCTSkip("\(name): the page to copy has no folder")
        }
        let page: CopyablePage = CopyablePage(
            folderName: String(path[path.startIndex..<slash]),
            fileName: ExactName(String(path[path.index(after: slash)...]))
        )
        // A case that follows links says so. `keepNone` asks for an EMPTY
        // tick list, which is how the required-embed rule is pinned: a page
        // shown inside another comes along even when nothing is ticked.
        let follows: Bool = copy["alsoCopiesLinkedPages"] != nil
        let keptNone: Bool = copy["keepNone"] != nil
        return Built(
            source: source,
            destination: destination,
            request: CoursePageCopyRequest(
                source: source,
                page: page,
                destination: destination,
                destinationFolderName: try XCTUnwrap(copy["intoFolder"], name),
                alsoCopiesLinkedPages: follows,
                keptLinkedPages: keptNone ? [] : nil
            )
        )
    }

    /// Pages as `{path: text}`, from either a list of paths or a list of
    /// `{path, text}` objects.
    static func pages(from raw: Any?) -> [(String, String)] {
        var result: [(String, String)] = []
        if let paths = raw as? [String] {
            for path in paths {
                result.append((path, "Body\n"))
            }
            return result
        }
        for entry in (raw as? [[String: String]]) ?? [] {
            if let path = entry["path"] {
                result.append((path, entry["text"] ?? "Body\n"))
            }
        }
        return result
    }

    static func media(from raw: Any?) -> [(String, String)] {
        var result: [(String, String)] = []
        for entry in (raw as? [[String: String]]) ?? [] {
            if let name = entry["name"] {
                result.append((name, entry["bytes"] ?? "x"))
            }
        }
        return result
    }

    /// A case that asks for every numbered rename to be taken already —
    /// the 51-same-stem precondition, spelled once rather than fifty times.
    static func fillingInNumberedNames(_ spec: [String: Any], onto media: [(String, String)])
        -> [(String, String)] {
        guard let upTo = (spec["andEveryNumberedNameUpTo"] as? NSNumber)?.intValue else {
            return media
        }
        var result: [(String, String)] = media
        for attempt in 2...upTo {
            result.append(("one (from ICS4U-2025) \(attempt).png", "taken"))
        }
        return result
    }

    /// Builds a course on disk.
    ///
    /// Every file is created through `ReferenceTreeCopier.create`, which takes
    /// the name as BYTES — a test that wrote its own fixtures through a `URL`
    /// would decompose the very names the byte rule exists to protect, and
    /// would then pass while the product was broken.
    func makeCourse(
        at directoryURL: URL,
        code: String,
        sections: [Int],
        sharedFolders: [String],
        pages: [(String, String)],
        media: [(String, String)]
    ) throws -> CopyCourseFacts {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for folderName in sharedFolders {
            try fileManager.createDirectory(
                at: directoryURL.appendingPathComponent(folderName), withIntermediateDirectories: true
            )
        }
        try fileManager.createDirectory(
            at: directoryURL.appendingPathComponent("Media"), withIntermediateDirectories: true
        )

        for (path, text) in pages {
            // The folder part goes through `URL`, which is harmless; the NAME
            // is handed over as bytes, because a fixture written through a
            // `URL` would decompose the very names the byte rule protects and
            // would then pass while the product was broken.
            var folderPath: String = ""
            var fileName: String = path
            if let lastSlash = path.lastIndex(of: "/") {
                folderPath = String(path[path.startIndex..<lastSlash])
                fileName = String(path[path.index(after: lastSlash)...])
            }
            let folderURL: URL = folderPath.isEmpty
                ? directoryURL
                : directoryURL.appendingPathComponent(folderPath)
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try ReferenceTreeCopier.create(
                Data(text.utf8), named: Array(fileName.utf8), inFolderAt: folderURL
            )
        }
        for (name, contents) in media {
            try ReferenceTreeCopier.create(
                Data(contents.utf8),
                named: Array(name.utf8),
                inFolderAt: directoryURL.appendingPathComponent("Media")
            )
        }

        let config: [String: Any] = [
            "course_code": code,
            "section_numbers": sections,
            "shared_folders": sharedFolders,
        ]
        try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
            .write(to: directoryURL.appendingPathComponent("course_config.json"))

        return CopyCourseFacts(
            code: code,
            displayCode: code,
            directoryPath: directoryURL.path,
            sectionNumbers: sections,
            sharedFolderNames: sharedFolders,
            isKeptForReference: false,
            classFolderNames: ["All Classes"]
        )
    }

    /// Every file in a tree, by relative path, with its contents — so a test
    /// can say that nothing else changed.
    func manifest(of directoryURL: URL) -> [String: String] {
        var found: [String: String] = [:]
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
            courseAt: directoryURL, leavingBehind: []
        )
        for item in survey.items where !item.isDirectory {
            let fileURL: URL = URL(fileURLWithPath: directoryURL.path + "/" + item.text)
            let data: Data = (try? Data(contentsOf: fileURL)) ?? Data()
            found[directoryURL.lastPathComponent + "/" + item.text] =
                data.base64EncodedString()
        }
        return found
    }
}
