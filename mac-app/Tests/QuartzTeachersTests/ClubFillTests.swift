import XCTest
@testable import QuartzTeachers

/// "This is a club" in the New Course wizard (#267): the contract's
/// `wizard.clubToggle` block, and the wizard's own use of it.
@MainActor
final class ClubFillTests: XCTestCase {

    // MARK: - Functions

    private func clubToggle() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let wizard: [String: Any] = try XCTUnwrap(all["wizard"] as? [String: Any])
        return try XCTUnwrap(wizard["clubToggle"] as? [String: Any])
    }

    private func fields(from raw: [String: Any]) throws -> ClubFillFields {
        return ClubFillFields(
            sharedFolders: try XCTUnwrap(raw["sharedFolders"] as? [String]),
            perSectionFolders: try XCTUnwrap(raw["perSectionFolders"] as? [String]),
            classFolder: try XCTUnwrap(raw["classFolder"] as? String),
            unitWord: try XCTUnwrap(raw["unitWord"] as? String),
            frontPageHeading: try XCTUnwrap(raw["frontPageHeading"] as? String),
            noun: ClassNoun.reading(raw["noun"] as? String)
        )
    }

    func testTheFillMatchesTheContract() throws {
        for testCase in try XCTUnwrap(clubToggle()["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: ClubFillFields = try fields(from: try XCTUnwrap(testCase["given"] as? [String: Any]))
            let expected: ClubFillFields = try fields(from: try XCTUnwrap(testCase["expect"] as? [String: Any]))
            let filled: ClubFillFields = ClubFill.applying(
                isClub: try XCTUnwrap(testCase["isClub"] as? Bool),
                to: given,
                usesLCSTerminology: testCase["usesLCSTerminology"] as? Bool ?? false
            )
            XCTAssertEqual(filled, expected, name)
        }
    }

    func testTheWordsAreTheContracts() throws {
        let block: [String: Any] = try clubToggle()
        XCTAssertEqual(WizardWording.clubToggleLabel, block["label"] as? String)
        XCTAssertEqual(WizardWording.clubToggleCaption, block["caption"] as? String)
        XCTAssertEqual(WizardWording.clubStartingContentNote, block["startingContentNote"] as? String)
        let rows: [String: Any] = try XCTUnwrap(block["rows"] as? [String: Any])
        XCTAssertEqual(WizardWording.clubClassFolderLabel, rows["classFolder"] as? String)
        XCTAssertEqual(WizardWording.clubFrontPageHeadingLabel, rows["frontPageHeading"] as? String)
        XCTAssertEqual(WizardWording.clubPageWordLabel, rows["pageWord"] as? String)
        XCTAssertEqual(WizardWording.clubNounLabel, rows["noun"] as? String)
        XCTAssertEqual(
            WizardWording.clubPageWordCaption(word: "Week"),
            (rows["pageWordCaption"] as? String)?.replacingOccurrences(of: "{word}", with: "Week")
        )
        let settings: [String: Any] = try XCTUnwrap(block["settingsRows"] as? [String: Any])
        XCTAssertEqual(WizardWording.settingsPageNamingLabel, settings["pageNaming"] as? String)
        XCTAssertEqual(WizardWording.settingsFrontPageHeadingLabel, settings["frontPageHeading"] as? String)
        XCTAssertEqual(WizardWording.settingsNounLabel, settings["noun"] as? String)
        XCTAssertEqual(WizardWording.settingsLockedCaption, settings["lockedCaption"] as? String)
        XCTAssertEqual(WizardWording.settingsFrontPageHeadingNotSet, settings["frontPageHeadingNotSet"] as? String)

        let club: [String: Any] = try XCTUnwrap(block["club"] as? [String: Any])
        XCTAssertEqual(ClubVocabulary.club.classFolder, club["classFolder"] as? String)
        XCTAssertEqual(ClubVocabulary.club.unitWord, club["unitWord"] as? String)
        XCTAssertEqual(ClubVocabulary.club.frontPageHeading, club["frontPageHeading"] as? String)
        XCTAssertEqual(ClubVocabulary.club.noun.rawValue, club["noun"] as? String)
        XCTAssertEqual(ClubFill.curriculumFolders, block["curriculumFolders"] as? [String])
    }

    /// The locked heading row says what the course RECORDED, and never a
    /// default: CODING has no `front_page_heading` and its front page reads
    /// "Most Recent Meeting", so "Most Recent Class" there would be false.
    func testTheHeadingRowShowsOnlyWhatWasRecorded() {
        let coding: CourseConfiguration = CourseConfiguration(
            values: ["code": "CODING", "unit_word": "Unit"], lastSavedData: Data()
        )
        XCTAssertNil(coding.recordedFrontPageHeading)
        XCTAssertEqual(
            WizardWording.settingsFrontPageHeadingValue(coding.recordedFrontPageHeading),
            WizardWording.settingsFrontPageHeadingNotSet
        )
        let blank: CourseConfiguration = CourseConfiguration(
            values: ["front_page_heading": "   "], lastSavedData: Data()
        )
        XCTAssertNil(blank.recordedFrontPageHeading)
        let club: CourseConfiguration = CourseConfiguration(
            values: ["front_page_heading": "Most Recent Meeting"], lastSavedData: Data()
        )
        XCTAssertEqual(
            WizardWording.settingsFrontPageHeadingValue(club.recordedFrontPageHeading),
            "Most Recent Meeting"
        )
    }

    /// The club's class-pages folder gets the checks every other folder
    /// name gets, in the same sentences (#267 review): it is typed into a
    /// field of its own, so the list's checks never saw it.
    func testTheClubsClassFolderNameIsChecked() {
        XCTAssertNil(NewCourseWizardView.clubClassFolderProblem(
            "All Meetings", perSectionFolders: ["All Meetings", "Private Notes"]
        ))
        XCTAssertEqual(
            NewCourseWizardView.clubClassFolderProblem("  ", perSectionFolders: ["  ", "Private Notes"]),
            SpecialNames.renameFolderProblemEmpty
        )
        XCTAssertEqual(
            NewCourseWizardView.clubClassFolderProblem("Weeks/All", perSectionFolders: ["Weeks/All"]),
            SpecialNames.renameFolderProblemHasSeparator
        )
        XCTAssertEqual(
            NewCourseWizardView.clubClassFolderProblem(
                "Private Notes", perSectionFolders: ["Private Notes", "Private Notes"]
            ),
            SpecialNames.renameFolderProblemAlreadyUsed(name: "Private Notes")
        )
        XCTAssertEqual(
            NewCourseWizardView.clubClassFolderProblem(
                "private notes", perSectionFolders: ["private notes", "Private Notes"]
            ),
            SpecialNames.renameFolderProblemAlreadyUsed(name: "private notes")
        )
    }

    /// What the wizard WRITES for a club: the numbered scheme and the four
    /// words, the recorded class folder, no skeleton, no ready-made pages,
    /// no curriculum — for CODING, whose code offers the general skeleton.
    func testAClubsConfigurationIsAClubs() throws {
        let fill: ClubFillFields = ClubFill.applying(
            isClub: true,
            to: ClubFillFields(
                sharedFolders: WizardDefaults.sharedFolders,
                perSectionFolders: ["Resources", "All Classes"],
                classFolder: "All Classes", unitWord: "Unit",
                frontPageHeading: "Most Recent Class", noun: .class
            ),
            usesLCSTerminology: false
        )
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "CODING",
            sharedFolders: fill.sharedFolders,
            perSectionFolders: fill.perSectionFolders,
            isClubCourse: true,
            classFolderName: fill.classFolder,
            unitWord: fill.unitWord,
            frontPageHeading: fill.frontPageHeading,
            classNoun: fill.noun
        )
        let config: [String: Any] = wizard.buildConfigurationDictionary(code: "CODING", name: "Coding Club")

        XCTAssertEqual(config["class_page_scheme"] as? String, "numbered")
        XCTAssertEqual(config["unit_word"] as? String, "Week")
        XCTAssertEqual(config["class_folder"] as? String, "All Meetings", "recorded, not guessed")
        XCTAssertEqual(config["front_page_heading"] as? String, "Most Recent Meeting")
        XCTAssertEqual(config["class_noun"] as? String, "meeting")
        XCTAssertEqual(config["use_skeleton"] as? Bool, false)
        XCTAssertEqual(config["prepopulate_example_content"] as? Bool, false)
        XCTAssertEqual(config["include_curriculum_pages"] as? Bool, false)
        XCTAssertEqual(config["include_curriculum_coverage"] as? Bool, false)
        XCTAssertEqual(config["include_coverage_notes"] as? Bool, false)
        let shared: [String] = try XCTUnwrap(config["shared_folders"] as? [String])
        for folder in ClubFill.curriculumFolders {
            XCTAssertFalse(shared.contains(folder), "a club has no \(folder) folder")
        }
        XCTAssertEqual(config["per_section_folders"] as? [String], ["Resources", "All Meetings"])

        // The protection follows the chosen folder: "All Meetings" is the
        // class folder and cannot be removed.
        if case .blocked = wizard.wizardPerSectionFolderProtection(for: "All Meetings") {
        } else {
            XCTFail("a club's class folder must not be removable")
        }
    }

    /// The same wizard, NOT a club, writes none of the three keys — and takes
    /// the general skeleton CODING is offered today.
    func testAnOrdinaryCourseWritesTheOrdinaryWords() throws {
        let wizard: NewCourseWizardView = NewCourseWizardView(courseCode: "ICS3U", prepopulatesExampleContent: false)
        let config: [String: Any] = wizard.buildConfigurationDictionary(code: "ICS3U", name: "Computer Science")
        XCTAssertNil(config["class_page_scheme"], "absent means Unit/Day; the file is unchanged")
        XCTAssertNil(config["front_page_heading"])
        XCTAssertNil(config["class_noun"])
        XCTAssertEqual(config["use_skeleton"] as? Bool, true)
    }
}
