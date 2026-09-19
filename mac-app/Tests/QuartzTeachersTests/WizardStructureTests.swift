import XCTest
@testable import QuartzTeachers

/// The New Course wizard's structure editor shows what will actually be
/// created, in BOTH directions: the skeleton toggle adopts a subject's
/// folders and gives them up again.
///
/// The rule itself, and every case a teacher can reach, is
/// `contracts/shared-rules.json` → `wizard.skeletonToggle`, run by
/// `SharedRulesContractTests`. What is here is what the contract cannot
/// carry: the pieces the rule is assembled from, and — because a control
/// with no handler is invisible to a test that calls the handler itself —
/// a scan proving the view is WIRED to it.
@MainActor
final class WizardStructureTests: XCTestCase {

    // MARK: - The pieces the rule is assembled from

    /// Adopting a family takes its four lists and the marks pool it
    /// declares.
    func testAdoptingAFamilyTakesItsOwnFiveLists() throws {
        let science: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(forCode: "SNC4M"))
        let adopted: WizardStructure.Lists = WizardStructure.adopting(science)

        XCTAssertEqual(adopted.sharedFolders, science.sharedFolders)
        XCTAssertEqual(adopted.sharedFiles, science.sharedFiles)
        XCTAssertEqual(adopted.perSectionFolders, science.perSectionFolders)
        XCTAssertEqual(adopted.perSectionFiles, science.perSectionFiles)
        XCTAssertEqual(adopted.gradedFolders, science.gradedFolders,
                       "A family that declares its own graded folders keeps them")
    }

    /// A family that declares no marks pool of its own falls back to the
    /// rule the build applied before the key existed — and the fallback is
    /// the same function every other part of the app now asks.
    func testAFamilyWithNoDeclaredPoolFallsBackToTheHistoricalRule() throws {
        var familiesWithADeclaredPool: Int = 0
        for name in SkeletonCatalog.everyFamilyName() {
            let family: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(named: name))
            let pool: [String] = SkeletonCatalog.adoptedGradedFolders(for: family)
            if family.gradedFolders.isEmpty {
                XCTAssertEqual(
                    pool,
                    GradedFolderRule.inferredPool(
                        from: family.sharedFolders + family.perSectionFolders
                    ),
                    "\(name) declares no graded folders, so the historical rule decides its pool"
                )
            } else {
                familiesWithADeclaredPool += 1
                XCTAssertEqual(pool, family.gradedFolders, "\(name) declares its own pool")
            }
        }
        XCTAssertGreaterThan(familiesWithADeclaredPool, 0,
                             "No family declared a pool at all — the manifests were not found")
    }

    /// The one rule the three surfaces that ask "what is this course
    /// counting?" now share, including the de-duplication Windows' own
    /// `InferredPool` does.
    func testTheHistoricalRuleCountsTaskFoldersOnceEach() {
        XCTAssertEqual(
            GradedFolderRule.inferredPool(from: ["Concepts", "Tasks", "Thinking Tasks", "Setup"]),
            ["Tasks", "Thinking Tasks"],
            "Any folder whose name mentions tasks, case ignored"
        )
        XCTAssertEqual(
            GradedFolderRule.inferredPool(from: ["Tasks", "All Classes", "Tasks"]),
            ["Tasks"],
            "A folder reaching the rule from two lists at once is still one folder"
        )
        XCTAssertEqual(
            GradedFolderRule.inferredPool(from: ["tasks", "TASKS"]),
            ["tasks", "TASKS"],
            "Different spellings are different folders — the course's own capitalisation is kept"
        )
        XCTAssertEqual(GradedFolderRule.inferredPool(from: []), [])
    }

    // MARK: - Restoring, beyond what the contract's cases reach

    /// Nothing adopted, nothing restored. Pinned here as well as in the
    /// contract because it is the branch a caller is most likely to drop:
    /// the view passes an optional straight through, so a restore with no
    /// snapshot has to be safe rather than merely unreachable.
    func testARestoreWithNoSnapshotChangesNothing() {
        let editorsLists: WizardStructure.Lists = WizardStructure.Lists(
            sharedFolders: ["Only", "Mine"],
            sharedFiles: ["Notes.md"],
            perSectionFolders: ["All Classes"],
            perSectionFiles: ["Key Links.md"],
            gradedFolders: []
        )

        XCTAssertEqual(
            WizardStructure.restoringDefaults(
                in: editorsLists, adopted: nil, usesLCSTerminology: false
            ),
            editorsLists
        )
        XCTAssertEqual(
            WizardStructure.restoringDefaults(
                in: editorsLists, adopted: nil, usesLCSTerminology: true
            ),
            editorsLists
        )
    }

    /// The marks pool the teacher has ticked themselves is theirs, exactly
    /// like a folder list they have edited.
    func testAMarksPoolTheTeacherChangedIsLeftAlone() throws {
        let science: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(forCode: "SNC4M"))
        let adopted: WizardStructure.Lists = WizardStructure.adopting(science)
        let withTheirOwnPool: WizardStructure.Lists = WizardStructure.Lists(
            sharedFolders: adopted.sharedFolders,
            sharedFiles: adopted.sharedFiles,
            perSectionFolders: adopted.perSectionFolders,
            perSectionFiles: adopted.perSectionFiles,
            gradedFolders: ["Investigations"]
        )

        let restored: WizardStructure.Lists = WizardStructure.restoringDefaults(
            in: withTheirOwnPool, adopted: adopted, usesLCSTerminology: false
        )

        XCTAssertEqual(restored.sharedFolders, WizardDefaults.sharedFolders,
                       "The untouched folder lists still go back")
        XCTAssertEqual(restored.gradedFolders, ["Investigations"],
                       "A pool the teacher ticked is not re-inferred over folders they never chose")
    }

    // MARK: - The wizard's own two call sites

    /// Adopting does nothing while the toggle is off.
    ///
    /// This runs on every change to the course code, so without the guard a
    /// teacher who declined the skeleton and then corrected a typo in the
    /// code would silently be given the skeleton's folders back — which is
    /// the same bug as the one this work fixes, reached from the other end.
    func testAdoptingIsGuardedByTheToggle() throws {
        let source: String = try WizardStructureTests.wizardSource()
        let adoptBody: String = try XCTUnwrap(
            WizardStructureTests.body(ofFunction: "func adoptSkeletonStructure()", in: source),
            "adoptSkeletonStructure() was not found in the wizard — this test cannot see what it guards"
        )

        XCTAssertTrue(
            adoptBody.contains("guard startsFromSkeleton"),
            "adoptSkeletonStructure() no longer checks the toggle before it adopts, so editing "
            + "the course code with the skeleton declined puts the skeleton's folders back."
        )
    }

    /// The toggle is WIRED to both directions.
    ///
    /// A control with no handler is exactly the bug this work fixes, and no
    /// test that calls the handler itself can see it — so this reads the
    /// view. The handler sits on the whole sheet rather than on the Toggle,
    /// because the Toggle lives inside a branch SwiftUI rebuilds on every
    /// keystroke in the course-code field.
    func testTheToggleIsWiredToAdoptAndToRestore() throws {
        let source: String = try WizardStructureTests.wizardSource()

        XCTAssertTrue(
            source.contains(".onChange(of: startsFromSkeleton)"),
            "Nothing in the wizard watches the skeleton toggle, so turning it off leaves the "
            + "skeleton's folders in the structure editor for a course that will not have them "
            + "(contracts/shared-rules.json → wizard.skeletonToggle)."
        )
        XCTAssertTrue(
            source.contains("restoreGenericStructure()"),
            "The wizard never restores the generic structure — see wizard.skeletonToggle."
        )

        // The snapshot is what tells an untouched list from an edited one, so
        // an adoption that fails to record one, or a restore that fails to
        // forget one, breaks the rule without breaking either function.
        let adoptBody: String = try XCTUnwrap(
            WizardStructureTests.body(ofFunction: "func adoptSkeletonStructure()", in: source)
        )
        XCTAssertTrue(
            adoptBody.contains("adoptedStructure = adopted"),
            "Adopting no longer records what it put in the editor, so a later restore has "
            + "nothing to compare against and puts nothing back."
        )
        let restoreBody: String = try XCTUnwrap(
            WizardStructureTests.body(ofFunction: "func restoreGenericStructure()", in: source)
        )
        XCTAssertTrue(
            restoreBody.contains("adoptedStructure = nil"),
            "Restoring no longer forgets the snapshot, so turning the toggle off twice would "
            + "restore against an adoption that is no longer on screen."
        )
    }

    /// The sentence a teacher reads while the toggle is off is drawn, not
    /// merely declared. Windows shows it in the same situation.
    func testTheOffCaptionIsDrawnWhileTheToggleIsOff() throws {
        let source: String = try WizardStructureTests.wizardSource()

        let branch: String = try XCTUnwrap(
            WizardStructureTests.text(following: "if !startsFromSkeleton {", in: source),
            "The wizard no longer says anything while the skeleton is declined. A teacher who "
            + "turns the toggle off is in exactly the situation "
            + "WizardWording.noExampleContentNote describes, and both apps say so "
            + "(contracts/shared-rules.json → wizard.whenTheNoteIsShown)."
        )
        XCTAssertTrue(
            branch.contains("noExampleContentNote"),
            "The branch that runs while the skeleton is declined shows something other than the "
            + "note both apps show there."
        )
    }

    /// What the wizard WRITES and what its editor SHOWS have to be the same
    /// answer: a course created with the skeleton declined gets the factory
    /// folders in `course_config.json` beside `use_skeleton: false`.
    ///
    /// Not a proof of the restore — the lists here were never adopted — but
    /// the pin that stops the file and the editor being fixed apart.
    func testDecliningTheSkeletonWritesTheFactoryStructure() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "SNC4M", startsFromSkeleton: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "SNC4M", name: "Science"
        )

        XCTAssertEqual(configuration["use_skeleton"] as? Bool, false)
        XCTAssertEqual(configuration["shared_folders"] as? [String], WizardDefaults.sharedFolders)
        XCTAssertEqual(configuration["per_section_files"] as? [String], WizardDefaults.perSectionFiles)
    }

    /// The same course code with the toggle left on still adopts, so the
    /// guard has not cost the feature its point.
    func testKeepingTheSkeletonStillWritesTheSubjectsStructure() throws {
        let science: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(forCode: "SNC4M"))
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "SNC4M", startsFromSkeleton: true
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "SNC4M", name: "Science"
        )

        XCTAssertEqual(configuration["use_skeleton"] as? Bool, true)
        XCTAssertEqual(configuration["shared_folders"] as? [String], science.sharedFolders)
    }

    /// A code with ready-made pages is offered no skeleton, so neither
    /// direction may touch its lists.
    func testACodeWithExampleContentIsNeverAdoptedOrRestored() throws {
        let payloadCode: String = "ADA1O"
        XCTAssertTrue(ExampleContentCatalog.hasContent(forCode: payloadCode))
        XCTAssertFalse(SkeletonCatalog.hasSkeleton(forCode: payloadCode))

        XCTAssertNil(
            SkeletonCatalog.structureToAdopt(
                forCode: payloadCode, currentSharedFolders: WizardDefaults.sharedFolders
            ),
            "The example content chooses the folders for a code that has it"
        )

        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: payloadCode, startsFromSkeleton: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: payloadCode, name: "Drama"
        )
        XCTAssertEqual(configuration["use_skeleton"] as? Bool, false)
        XCTAssertEqual(configuration["shared_folders"] as? [String], WizardDefaults.sharedFolders)
    }

    // MARK: - Functions

    /// The wizard's own source, read from the checkout so the scan works
    /// wherever the repository lives.
    static func wizardSource() throws -> String {
        let viewURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers/Views/Wizard/NewCourseWizardView.swift")
        let source: String = try String(contentsOf: viewURL, encoding: .utf8)
        XCTAssertGreaterThan(source.count, 1000,
                             "The wizard's source was not found where this test expects it — the scans below would pass vacuously.")
        return source
    }

    /// Everything between a function's opening line and the first line that
    /// closes it at the function's own indentation, or nil when the
    /// function is not there.
    static func body(ofFunction declaration: String, in source: String) -> String? {
        let lines: [String] = source.components(separatedBy: "\n")
        var collected: [String] = []
        var isInside: Bool = false
        for line in lines {
            if isInside {
                if line == "    }" {
                    return collected.joined(separator: "\n")
                }
                collected.append(line)
            } else if line.contains(declaration) {
                isInside = true
            }
        }
        return nil
    }

    /// The few lines that follow a marker in a file, or nil when the marker
    /// is not there — enough to see what a short branch does.
    static func text(following marker: String, in source: String) -> String? {
        guard let found = source.range(of: marker) else {
            return nil
        }
        let remainder: Substring = source[found.upperBound...]
        return String(remainder.prefix(200))
    }
}
