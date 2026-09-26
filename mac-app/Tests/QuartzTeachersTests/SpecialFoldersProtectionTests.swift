import XCTest
@testable import QuartzTeachers

@MainActor
final class SpecialFoldersProtectionTests: XCTestCase {

    // MARK: - Stored properties

    /// Where this test's trail lines go, and the store that was there before.
    /// A removal through the list editor runs `folderWasRemoved`, which writes
    /// an `.itemExcluded` line — without the redirect it would land in the
    /// real `~/Library/Logs/Plantoir`.
    var trailFolderURL: URL?
    var previousTrailStore: ProblemReportStore?

    // MARK: - Functions

    override func setUp() async throws {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("special-folders-trail-\(UUID().uuidString)", isDirectory: true)
        trailFolderURL = folderURL
        previousTrailStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: folderURL)
    }

    override func tearDown() async throws {
        if let previousTrailStore {
            ActivityTrail.store = previousTrailStore
        }
        if let trailFolderURL {
            try? FileManager.default.removeItem(at: trailFolderURL)
        }
    }

    /// Removes a shared folder the way the teacher does, through the list
    /// editor Course Settings builds: `removeItem(named:)` takes the name out
    /// of the list, then `onRemove` runs `folderWasRemoved` — the exclusion,
    /// then the pool. Issue #183: a hand replay of those steps stays green
    /// when the shipped order changes, so these tests call its owner.
    private func removeSharedFolderThroughTheListEditor(_ name: String, in view: CourseSettingsView) {
        let editor: StringListEditorView = CourseSettingsGestureScript.editor(for: .sharedFolders, of: view)
        editor.removeItem(named: name)
    }

    private func makeCourse(
        in root: URL,
        sharedFolders: [String] = ["Concepts", "Curriculum", "Tasks"],
        perSectionFolders: [String] = ["All Classes"],
        perSectionFiles: [String] = ["index.md"],
        gradedFolders: [String]? = nil,
        includesCoverage: Bool = true,
        curriculumFolder: String? = nil
    ) throws -> Course {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        var configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "shared_folders": sharedFolders,
            "per_section_folders": perSectionFolders,
            "per_section_files": perSectionFiles,
            "include_curriculum_coverage": includesCoverage,
        ]
        if let gradedFolders {
            configuration["graded_folders"] = gradedFolders
        }
        if let curriculumFolder {
            configuration["curriculum_folder"] = curriculumFolder
        }
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    // MARK: - Course Settings protection tests

    func testCourseSettingsCurriculumFolderBlockedWhenCoverageOn() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(in: root, includesCoverage: true)
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.sharedFolderProtection(for: "Curriculum")
        XCTAssertEqual(protection, .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageSetting))
    }

    func testCourseSettingsCurriculumFolderConsequentialWhenCoverageOff() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(in: root, includesCoverage: false)
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.sharedFolderProtection(for: "Curriculum")
        XCTAssertEqual(
            protection,
            .consequential(
                title: SpecialNames.removeCurriculumFolderTitle(for: "Curriculum"),
                message: SpecialNames.removeCurriculumFolderMessage
            )
        )
    }

    func testCourseSettingsLastGradedFolderBlockedWhenCoverageOn() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            sharedFolders: ["Concepts", "Tasks"],
            gradedFolders: ["Tasks"],
            includesCoverage: true
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.sharedFolderProtection(for: "Tasks")
        XCTAssertEqual(protection, .blocked(reason: SpecialNames.lastGradedFolderBlocked))

        let marksProtection: ItemProtection = view.gradedFolderProtection(for: "Tasks")
        XCTAssertEqual(marksProtection, .blocked(reason: SpecialNames.lastGradedFolderBlocked))
    }

    func testCourseSettingsGradedFolderConsequentialWhenMultipleGradedFoldersExist() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            sharedFolders: ["Concepts", "Tasks", "Tests"],
            gradedFolders: ["Tasks", "Tests"],
            includesCoverage: true
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.sharedFolderProtection(for: "Tasks")
        XCTAssertEqual(
            protection,
            .consequential(
                title: SpecialNames.removeGradedFolderTitle(for: "Tasks"),
                message: SpecialNames.removeGradedFolderMessage
            )
        )

        let marksProtection: ItemProtection = view.gradedFolderProtection(for: "Tasks")
        XCTAssertEqual(marksProtection, .ordinary)
    }

    func testCourseSettingsLastPerSectionFolderBlocked() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            perSectionFolders: ["All Classes"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.perSectionFolderProtection(for: "All Classes")
        XCTAssertEqual(protection, .blocked(reason: SpecialNames.lastPerSectionFolderBlocked))
    }

    func testCourseSettingsAllClassesIsBlockedEvenWhenOtherPerSectionFoldersExist() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            perSectionFolders: ["All Classes", "Labs"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let classProtection: ItemProtection = view.perSectionFolderProtection(for: "All Classes")
        // Russell's decision, 2026-08-24: "All Classes" is never removable,
        // however many other per-section folders there are.
        XCTAssertEqual(classProtection, .blocked(reason: SpecialNames.classFolderBlocked))

        let labProtection: ItemProtection = view.perSectionFolderProtection(for: "Labs")
        XCTAssertEqual(labProtection, .ordinary)
    }

    func testOnlyAllClassesIsBlockedNotEveryClassFolder() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        // "Class Resources" counts as a class folder for the coverage map,
        // but it is not "All Classes", so it stays removable.
        let course: Course = try makeCourse(
            in: root,
            perSectionFolders: ["All Classes", "Class Resources", "Labs"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)
        XCTAssertEqual(view.perSectionFolderProtection(for: "Class Resources"), .ordinary)
        XCTAssertEqual(view.perSectionFolderProtection(for: "all classes"), .blocked(reason: SpecialNames.classFolderBlocked))
    }

    func testCourseSettingsIndexFileBlocked() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(in: root)
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.perSectionFileProtection(for: "index.md")
        XCTAssertEqual(protection, .blocked(reason: SpecialNames.sectionIndexFileBlocked))

        let protectionUpper: ItemProtection = view.perSectionFileProtection(for: "INDEX.MD")
        XCTAssertEqual(protectionUpper, .blocked(reason: SpecialNames.sectionIndexFileBlocked))

        let otherProtection: ItemProtection = view.perSectionFileProtection(for: "Key Links.md")
        XCTAssertEqual(otherProtection, .ordinary)
    }

    // MARK: - Wizard protection and marks tests

    /// ICS3U declines its ready-made pages and keeps the computer studies
    /// skeleton — which, since GitHub issue #251, still gets the Ontario
    /// expectations written for ICS3U and a coverage map built over them.
    ///
    /// This asserted the OPPOSITE until that landed: the Curriculum folder
    /// was merely `.consequential` ("you can take it out, here is what you
    /// lose") because a skeleton course's curriculum folder held two
    /// placeholder pages worth nothing. The same sentences that protect it
    /// for a teacher taking the payload now protect it here, because the
    /// same pages are in it. The marks pool moves with it for the same
    /// reason: a coverage map with an empty pool counts nothing.
    ///
    /// The case where nothing is offered is
    /// `testWizardStructureProtectionForACodeWithNoReadyMadePages` below.
    func testWizardStructureProtectionWithExampleContentDeclined() {
        let skeleton: SkeletonCatalog.Family = try! XCTUnwrap(SkeletonCatalog.family(forCode: "ICS3U"))
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ICS3U",
            prepopulatesExampleContent: false,
            sharedFolders: skeleton.sharedFolders,
            sharedFiles: skeleton.sharedFiles,
            perSectionFolders: skeleton.perSectionFolders,
            perSectionFiles: skeleton.perSectionFiles,
            gradedFolders: skeleton.gradedFolders
        )

        let curriculumProt: ItemProtection = wizard.wizardSharedFolderProtection(for: "Curriculum")
        XCTAssertEqual(
            curriculumProt,
            .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageMap)
        )

        let tasksProt: ItemProtection = wizard.wizardSharedFolderProtection(for: "Tasks")
        XCTAssertEqual(
            tasksProt,
            .blocked(reason: SpecialNames.lastGradedFolderBlockedWizard),
            "Tasks is this skeleton's whole marks pool, and the coverage map counts the "
            + "pages in it."
        )

        let classesProt: ItemProtection = wizard.wizardPerSectionFolderProtection(for: "All Classes")
        XCTAssertEqual(classesProt, .blocked(reason: SpecialNames.lastPerSectionFolderBlocked))

        let indexProt: ItemProtection = wizard.wizardPerSectionFileProtection(for: "index.md")
        XCTAssertEqual(indexProt, .blocked(reason: SpecialNames.sectionIndexFileBlocked))
    }

    /// The ~1,900 codes with no ready-made pages keep exactly the old
    /// answers: their skeleton's Curriculum folder is empty and there is
    /// nothing anywhere to fill it with, so taking it out costs a teacher
    /// nothing they have not yet done.
    func testWizardStructureProtectionForACodeWithNoReadyMadePages() {
        XCTAssertFalse(ExampleContentCatalog.hasContent(forCode: "ICS2O"))
        let skeleton: SkeletonCatalog.Family = try! XCTUnwrap(SkeletonCatalog.family(forCode: "ICS2O"))
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ICS2O",
            prepopulatesExampleContent: false,
            sharedFolders: skeleton.sharedFolders,
            sharedFiles: skeleton.sharedFiles,
            perSectionFolders: skeleton.perSectionFolders,
            perSectionFiles: skeleton.perSectionFiles,
            gradedFolders: skeleton.gradedFolders
        )

        XCTAssertEqual(
            wizard.wizardSharedFolderProtection(for: "Curriculum"),
            .consequential(
                title: SpecialNames.removeCurriculumFolderTitle(for: "Curriculum"),
                message: SpecialNames.removeCurriculumFolderMessage
            )
        )
        XCTAssertEqual(
            wizard.wizardSharedFolderProtection(for: "Tasks"),
            .consequential(
                title: SpecialNames.removeGradedFolderTitle(for: "Tasks"),
                message: SpecialNames.removeGradedFolderMessage
            )
        )
    }

    func testWizardGradedFoldersIncludedInConfigWhenNotUsingExampleContent() {
        // The folder lists carry both names, because what is written is now
        // narrowed to the folders the course will actually have — a pool
        // naming a folder nobody is creating is not a choice, it is a name
        // that matches nothing (see GradedFolderRule.reconciled).
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ICS3U",
            prepopulatesExampleContent: false,
            sharedFolders: ["Concepts", "Tasks", "Projects"],
            gradedFolders: ["Tasks", "Projects"]
        )

        let dict: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ICS3U", name: "Introduction to Computer Science"
        )
        let graded: [String]? = dict["graded_folders"] as? [String]
        XCTAssertEqual(graded, ["Tasks", "Projects"])
    }

    func testWizardStructureProtectionWithCurriculumCoverageEnabled() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ADA1O",
            prepopulatesExampleContent: true,
            includesCurriculumPages: true,
            includesCurriculumCoverage: true,
            sharedFolders: ["Concepts", "Ontario Curriculum", "Tasks"],
            gradedFolders: ["Tasks"]
        )

        let curriculumProt: ItemProtection = wizard.wizardSharedFolderProtection(for: "Ontario Curriculum")
        XCTAssertEqual(curriculumProt, .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageMap))

        let tasksProt: ItemProtection = wizard.wizardSharedFolderProtection(for: "Tasks")
        XCTAssertEqual(tasksProt, .blocked(reason: SpecialNames.lastGradedFolderBlockedWizard))

        let marksProt: ItemProtection = wizard.wizardGradedFolderProtection(for: "Tasks")
        XCTAssertEqual(marksProt, .blocked(reason: SpecialNames.lastGradedFolderBlockedWizard))
    }

    func testLegacyNilGradedFoldersMaterialisationOnEdit() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            sharedFolders: ["Concepts", "Tasks", "Other"],
            gradedFolders: nil,
            includesCoverage: true
        )
        XCTAssertNil(course.configuration.gradedFolders)

        let view: CourseSettingsView = CourseSettingsView(course: course)
        let initialValues: [String] = view.gradedFoldersBinding.wrappedValue
        XCTAssertEqual(initialValues, ["Tasks"])

        view.gradedFoldersBinding.wrappedValue = ["Tasks", "Other"]
        XCTAssertEqual(course.configuration.gradedFolders, ["Tasks", "Other"])
    }

    func testCourseSettingsClassFolderBlockedWhenAlsoSoleGradedFolderWithCoverageOn() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            sharedFolders: ["Concepts"],
            perSectionFolders: ["All Classes", "Labs"],
            gradedFolders: ["All Classes"],
            includesCoverage: true
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let protection: ItemProtection = view.perSectionFolderProtection(for: "All Classes")
        XCTAssertEqual(protection, .blocked(reason: SpecialNames.lastGradedFolderBlocked))
    }

    func testWizardReconcileGradedFoldersRemovesOrphanedEntries() {
        let validChoices: [String] = ["Concepts", "Tasks", "All Classes"]
        let currentGraded: [String] = ["Tasks", "DeletedFolder"]
        let reconciled: [String] = NewCourseWizardView.reconciledGradedFolders(
            from: currentGraded, validChoices: validChoices
        )
        XCTAssertEqual(reconciled, ["Tasks"])
    }
    func testRemovingAGradedFolderInSettingsDropsItFromTheMarksPool() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            sharedFolders: ["Concepts", "Tasks", "Tests"],
            gradedFolders: ["Tasks", "Tests"],
            includesCoverage: true
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        // The confirmation promises the folder leaves the marks pool, and
        // the build must never be handed a pool naming an excluded folder.
        // Run through the list editor, so it happens in the order Course
        // Settings does it — the editor drops the name, then `onRemove`
        // excludes it — because since 2026-09-09 the drop asks what the
        // checklist offers, and it offers what the lists and the disk still
        // hold.
        removeSharedFolderThroughTheListEditor("Tasks", in: view)
        XCTAssertEqual(course.configuration.sharedFolders, ["Concepts", "Tests"])
        XCTAssertEqual(course.configuration.gradedFolders, ["Tests"])

        // A name that was never in the pool changes nothing.
        removeSharedFolderThroughTheListEditor("Concepts", in: view)
        XCTAssertEqual(course.configuration.sharedFolders, ["Tests"])
        XCTAssertEqual(course.configuration.gradedFolders, ["Tests"])
    }

    /// Removing a folder from a course that has NEVER been asked leaves the
    /// pool unasked — it does not freeze it.
    ///
    /// This test asserted the opposite until 2026-09-09, and passed only
    /// because it left out the `exclude` that Course Settings does first. Once
    /// the Marks checklist stopped offering a removed folder (issue #79), the
    /// name is gone from the choices by the time the pool is touched, so
    /// `dropFromMarksPool` finds nothing to drop and `graded_folders` stays
    /// absent.
    ///
    /// **That is the better answer, not a side effect to be repaired.**
    /// Freezing here wrote the historical rule's answer MINUS the removed
    /// folder — and on the ordinary course whose only marked folder is
    /// `Tasks`, that is an empty pool: nothing counts for marks, permanently,
    /// from one removal the teacher was told only would "take it out of your
    /// course's marks pool". Leaving the key absent keeps the historical rule
    /// running, so a `Thinking Tasks` still counts and putting the folder back
    /// restores it.
    ///
    /// **Windows does this too, since 2026-09-18** — and an earlier draft of
    /// this comment said it did not, which was true when it was written and
    /// then was not. `DropFromMarksPool` there used to materialise over a walk
    /// cached by the previous `BuildForm` pass, taken before the exclusion was
    /// written, so the removed folder was still among the choices and the pool
    /// was written anyway. Issue #142 settled that Windows adopts this rule,
    /// and the whole gesture is now one Core method,
    /// `FolderRemoval.RemoveFolderFromCourse`. Pinned on both platforms by
    /// `gradedFolders.removingAFolder`.
    func testRemovingAGradedFolderLeavesANeverAskedCourseUnasked() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            sharedFolders: ["Concepts", "Tasks", "Homework Tasks"],
            gradedFolders: nil,
            includesCoverage: false
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        // Through the list editor, so in the order Course Settings really
        // does it: the editor drops the name, `onRemove` excludes it, and only
        // then is the pool touched.
        removeSharedFolderThroughTheListEditor("Tasks", in: view)
        XCTAssertEqual(course.configuration.sharedFolders, ["Concepts", "Homework Tasks"])

        XCTAssertNil(course.configuration.gradedFolders)
    }
}
