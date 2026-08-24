import XCTest
@testable import QuartzTeachers

@MainActor
final class SpecialFoldersProtectionTests: XCTestCase {

    // MARK: - Helper methods

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

    func testCourseSettingsClassFolderConsequentialWhenOtherPerSectionFoldersExist() throws {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-prot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let course: Course = try makeCourse(
            in: root,
            perSectionFolders: ["All Classes", "Labs"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let classProtection: ItemProtection = view.perSectionFolderProtection(for: "All Classes")
        XCTAssertEqual(
            classProtection,
            .consequential(
                title: SpecialNames.removeClassFolderTitle(for: "All Classes"),
                message: SpecialNames.removeClassFolderMessage
            )
        )

        let labProtection: ItemProtection = view.perSectionFolderProtection(for: "Labs")
        XCTAssertEqual(labProtection, .ordinary)
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
            .consequential(
                title: SpecialNames.removeCurriculumFolderTitle(for: "Curriculum"),
                message: SpecialNames.removeCurriculumFolderMessage
            )
        )

        let tasksProt: ItemProtection = wizard.wizardSharedFolderProtection(for: "Tasks")
        XCTAssertEqual(
            tasksProt,
            .consequential(
                title: SpecialNames.removeGradedFolderTitle(for: "Tasks"),
                message: SpecialNames.removeGradedFolderMessage
            )
        )

        let classesProt: ItemProtection = wizard.wizardPerSectionFolderProtection(for: "All Classes")
        XCTAssertEqual(classesProt, .blocked(reason: SpecialNames.lastPerSectionFolderBlocked))

        let indexProt: ItemProtection = wizard.wizardPerSectionFileProtection(for: "index.md")
        XCTAssertEqual(indexProt, .blocked(reason: SpecialNames.sectionIndexFileBlocked))
    }

    func testWizardGradedFoldersIncludedInConfigWhenNotUsingExampleContent() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ICS3U",
            prepopulatesExampleContent: false,
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
}
