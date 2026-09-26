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

    /// Every bundled family declares its own marks pool, and the adoption
    /// takes it as declared.
    ///
    /// Written as its own check rather than as the `else` of the one below,
    /// because that is what it really is: the generator writes
    /// `graded_folders` for all fifty, so nothing in the bundle can exercise
    /// the fallback and a test that walked them believing it did would be
    /// reporting on a branch it never ran.
    func testEveryBundledFamilyDeclaresItsOwnPoolAndKeepsIt() throws {
        var familiesSeen: Int = 0
        for name in SkeletonCatalog.everyFamilyName() {
            let family: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(named: name))
            familiesSeen += 1
            XCTAssertFalse(
                family.gradedFolders.isEmpty,
                "\(name) declares no graded_folders. The fallback below would decide its marks "
                + "pool instead — check that it says what the subject means."
            )
            XCTAssertEqual(SkeletonCatalog.adoptedGradedFolders(for: family), family.gradedFolders,
                           "\(name)'s declared pool is what an adoption takes")
        }
        XCTAssertGreaterThan(familiesSeen, 40, "The bundled manifests were not found")
    }

    /// A family that declares no pool falls back to the rule the build
    /// applied before the key existed.
    ///
    /// Run against a family built here, because no bundled one can reach it —
    /// and the branch is still worth holding: a hand-written manifest, or a
    /// generator change, brings it back, and the fallback is what stops such
    /// a course opening with no marks at all.
    func testAFamilyWithNoDeclaredPoolFallsBackToTheHistoricalRule() {
        let family: SkeletonCatalog.Family = SkeletonCatalog.Family(
            name: "improvised",
            label: "Improvised",
            sharedFolders: ["Concepts", "Thinking Tasks", "Curriculum"],
            sharedFiles: ["Learning Goals.md"],
            perSectionFolders: ["All Classes", "Group Tasks"],
            perSectionFiles: ["Key Links.md"],
            hidden: ["Curriculum"],
            expandable: ["Concepts"],
            curriculumFolder: "Curriculum",
            gradedFolders: []
        )

        XCTAssertEqual(
            SkeletonCatalog.adoptedGradedFolders(for: family),
            ["Thinking Tasks", "Group Tasks"],
            "Every folder whose name mentions tasks, shared and per-section alike"
        )
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

    /// The marks pool the teacher ticked themselves is theirs — but only as
    /// far as the folders the course will actually have.
    ///
    /// Both halves matter, and the second was missed on the first attempt:
    /// keeping `Investigations` here would write a `graded_folders` naming a
    /// folder that has just left the editor, which the build counts and
    /// never finds. `Tasks` survives because the factory list has one.
    func testAMarksPoolTheTeacherChangedIsKeptButNarrowed() throws {
        let science: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(forCode: "SNC4M"))
        let adopted: WizardStructure.Lists = WizardStructure.adopting(science)
        let withTheirOwnPool: WizardStructure.Lists = WizardStructure.Lists(
            sharedFolders: adopted.sharedFolders,
            sharedFiles: adopted.sharedFiles,
            perSectionFolders: adopted.perSectionFolders,
            perSectionFiles: adopted.perSectionFiles,
            gradedFolders: ["Tasks", "Investigations"]
        )

        let restored: WizardStructure.Lists = WizardStructure.restoringDefaults(
            in: withTheirOwnPool, adopted: adopted, usesLCSTerminology: false
        )

        XCTAssertEqual(restored.sharedFolders, WizardDefaults.sharedFolders,
                       "The untouched folder lists still go back")
        XCTAssertEqual(restored.gradedFolders, ["Tasks"],
                       "Their own choice is kept where the folder survives the restore, and "
                       + "dropped where it does not")
    }

    /// A pool narrowed to nothing is written as nothing — "asked, and nothing
    /// counts" — rather than quietly naming folders that are gone.
    func testAMarksPoolCanNarrowToNothing() throws {
        let mathematics: SkeletonCatalog.Family = try XCTUnwrap(
            SkeletonCatalog.family(forCode: "MPM1D")
        )
        let adopted: WizardStructure.Lists = WizardStructure.adopting(mathematics)
        XCTAssertEqual(adopted.gradedFolders, ["Thinking Tasks", "Tasks"],
                       "The one family that declares a pool other than [\"Tasks\"]")

        let afterUntickingTasks: WizardStructure.Lists = WizardStructure.Lists(
            sharedFolders: adopted.sharedFolders,
            sharedFiles: adopted.sharedFiles,
            perSectionFolders: adopted.perSectionFolders,
            perSectionFiles: adopted.perSectionFiles,
            gradedFolders: ["Thinking Tasks"]
        )

        let restored: WizardStructure.Lists = WizardStructure.restoringDefaults(
            in: afterUntickingTasks, adopted: adopted, usesLCSTerminology: false
        )
        XCTAssertEqual(restored.gradedFolders, [],
                       "Thinking Tasks left the editor with the rest of the skeleton")
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

        // The handler's own body, not merely the handler: a test that asks
        // whether the file mentions `restoreGenericStructure()` passes on the
        // function's own declaration, with nothing calling it.
        let handler: String = try XCTUnwrap(
            WizardStructureTests.text(following: ".onChange(of: startsFromSkeleton)", in: source),
            "Nothing in the wizard watches the skeleton toggle, so turning it off leaves the "
            + "skeleton's folders in the structure editor for a course that will not have them "
            + "(contracts/shared-rules.json → wizard.skeletonToggle)."
        )
        XCTAssertTrue(
            handler.contains("adoptSkeletonStructure()"),
            "The skeleton toggle no longer adopts when it goes on."
        )
        XCTAssertTrue(
            handler.contains("restoreGenericStructure()"),
            "The skeleton toggle no longer restores the generic structure when it goes off — "
            + "see wizard.skeletonToggle."
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
    ///
    /// It asserted one thing until 2026-09-21 — that the branch shows
    /// `noExampleContentNote` — and now asserts two, because there are two
    /// sentences: that the branch draws the thing that CHOOSES between
    /// them, and that the chooser has both limbs and the test that tells
    /// them apart. The window over the branch is the same 120 characters as
    /// before, for the same reason (the section's own `else if` shows the
    /// note too, a little further down, and a window that reached it would
    /// pass while this branch showed anything at all).
    func testTheOffCaptionIsDrawnWhileTheToggleIsOff() throws {
        let source: String = try WizardStructureTests.wizardSource()

        let branch: String = try XCTUnwrap(
            WizardStructureTests.text(
                following: "if !startsFromSkeleton {", in: source, charactersToRead: 120
            ),
            "The wizard no longer says anything while the skeleton is declined. A teacher who "
            + "turns the toggle off is in exactly the situation "
            + "WizardWording.noExampleContentNote describes, and both apps say so "
            + "(contracts/shared-rules.json → wizard.whenTheNoteIsShown)."
        )
        XCTAssertTrue(
            branch.contains("noteForACourseStartingEmpty"),
            "The branch that runs while the skeleton is declined shows something other than the "
            + "note both apps show there."
        )

        let chooser: String = try XCTUnwrap(
            WizardStructureTests.body(
                ofFunction: "var noteForACourseStartingEmpty: some View {", in: source
            ),
            "Nothing chooses which of the two sentences a teacher reads."
        )
        XCTAssertTrue(
            chooser.contains("noStartingContentNote"),
            "A teacher who declined ready-made pages and then declined the skeleton is told "
            + "\"example content isn't available for this course code yet\" — about the code "
            + "they were offered example content for one question ago "
            + "(contracts/shared-rules.json → wizard.whenTheNoteIsShown, situation 3)."
        )
        XCTAssertTrue(
            chooser.contains("noExampleContentNote"),
            "The ~1,900 codes with no ready-made pages must keep reading the sentence they "
            + "have always read."
        )
        XCTAssertTrue(
            chooser.contains("ExampleContentCatalog.hasContent"),
            "The two sentences are told apart by whether ready-made pages exist for the code, "
            + "not by which toggle the teacher used to get here."
        )
    }

    /// The EXAMPLE-content toggle is wired to move the structure editor
    /// too, in both directions.
    ///
    /// Its own test rather than a clause of the one above, because it is
    /// its own handler and the failure is its own: without it the skeleton
    /// toggle appears switched ON while the lists stay factory and the file
    /// says `use_skeleton: true` — the skeleton's pages then arrive in
    /// folders the course does not have. A source scan for the same reason
    /// the other one is: a handler that is not there cannot fire, and no
    /// test that calls the handler itself can see that.
    func testDecliningTheExampleIsWiredToAdoptAndRestore() throws {
        let source: String = try WizardStructureTests.wizardSource()

        let handler: String = try XCTUnwrap(
            WizardStructureTests.text(
                following: ".onChange(of: prepopulatesExampleContent)", in: source
            ),
            "Nothing in the wizard watches the example-content toggle, so turning it off "
            + "offers a skeleton the structure editor knows nothing about "
            + "(contracts/shared-rules.json → wizard.skeletonToggle, the declineExampleContent "
            + "and takeExampleContent steps)."
        )
        XCTAssertTrue(
            handler.contains("adoptSkeletonStructure()"),
            "Turning the example content off no longer adopts the subject's folders, so the "
            + "editor shows one course and the file describes another."
        )
        XCTAssertTrue(
            handler.contains("restoreGenericStructure()"),
            "Turning the example content back on no longer restores, so a teacher who changed "
            + "their mind gets a different file from the one they would have got without "
            + "changing it."
        )
    }

    // MARK: - A declined payload starts from its subject's skeleton

    /// Issue #248, as the file the wizard writes: a teacher who turns down
    /// ADA1O's ready-made pages gets the drama SHAPE, not empty folders.
    ///
    /// MEASURED before the fix, by driving the real `setup_course.py`
    /// through a pty: this config with `use_skeleton: false` produces 18
    /// `.md` files; with it true, 47 — identical to what ICS2O, same
    /// family and no payload, has always produced.
    func testAPayloadCodeAdoptsItsSkeletonWhenTheExampleIsDeclined() throws {
        let drama: SkeletonCatalog.Family = try XCTUnwrap(SkeletonCatalog.family(forCode: "ADA1O"))
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ADA1O", prepopulatesExampleContent: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ADA1O", name: "Drama"
        )

        XCTAssertEqual(configuration["use_skeleton"] as? Bool, true)
        XCTAssertEqual(configuration["prepopulate_example_content"] as? Bool, false)
        XCTAssertEqual(configuration["shared_folders"] as? [String], drama.sharedFolders)
        XCTAssertEqual(configuration["per_section_files"] as? [String], drama.perSectionFiles)
        // The sidebar comes from the skeleton, not from the app's generic
        // list — which knows nothing about Conventions or Warm-Ups.
        let plan = SkeletonCatalog.sidebar(
            for: drama,
            sharedFolders: drama.sharedFolders,
            sharedFiles: drama.sharedFiles,
            perSectionFolders: drama.perSectionFolders,
            perSectionFiles: drama.perSectionFiles
        )
        XCTAssertEqual(configuration["hidden"] as? [String], plan.hidden)
        XCTAssertEqual(configuration["expandable"] as? [String], plan.expandable)
    }

    /// The marks pool comes with them, for the one family whose pool is not
    /// `["Tasks"]` — the silent loss this rule exists to stop, reached by
    /// the new road.
    func testADeclinedPayloadCarriesTheSubjectsMarksPoolToo() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "MCV4U", prepopulatesExampleContent: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "MCV4U", name: "Calculus and Vectors"
        )

        XCTAssertEqual(configuration["use_skeleton"] as? Bool, true)
        XCTAssertEqual(configuration["graded_folders"] as? [String], ["Thinking Tasks", "Tasks"])
    }

    /// Declining the ready-made pages AND the skeleton is still a choice a
    /// teacher can make, and it writes the factory structure.
    func testDecliningBothLeavesTheFactoryStructure() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ADA1O", prepopulatesExampleContent: false, startsFromSkeleton: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ADA1O", name: "Drama"
        )

        XCTAssertEqual(configuration["use_skeleton"] as? Bool, false)
        XCTAssertEqual(configuration["shared_folders"] as? [String], WizardDefaults.sharedFolders)
        XCTAssertEqual(configuration["graded_folders"] as? [String], ["Tasks"])
    }

    /// The round trip, as the pure rule rather than as a driven wizard:
    /// what a teacher sees after declining the ready-made pages and then
    /// taking them again is what they saw before touching anything.
    ///
    /// `@State` never takes on a view that is not on screen
    /// (`WizardStructure.swift`), so there is no way to drive the real
    /// toggles in a unit test. What CAN be proved is the rule the handler
    /// calls, and — in the test below — the file built from the lists that
    /// rule leaves behind.
    func testDecliningAndThenTakingTheExampleLeavesTheFactoryListsExactlyAsTheyWere() throws {
        let mathematics: SkeletonCatalog.Family = try XCTUnwrap(
            SkeletonCatalog.family(forCode: "MCV4U")
        )
        let factory: WizardStructure.Lists = WizardStructure.Lists(
            sharedFolders: WizardDefaults.sharedFolders,
            sharedFiles: WizardDefaults.sharedFiles,
            perSectionFolders: WizardDefaults.perSectionFolders,
            perSectionFiles: WizardDefaults.perSectionFiles,
            gradedFolders: ["Tasks"]
        )

        let adopted: WizardStructure.Lists = WizardStructure.adopting(mathematics)
        XCTAssertNotEqual(adopted, factory, "The decline must actually change something")

        let restored: WizardStructure.Lists = WizardStructure.restoringDefaults(
            in: adopted, adopted: adopted, usesLCSTerminology: false
        )
        XCTAssertEqual(restored, factory,
                       "A teacher who changed their mind must end where they started")
    }

    // MARK: - A new course's marks pool (#292)

    /// Every case in `contracts/shared-rules.json` → `gradedFolders.newCourse`
    /// that applies to the mac, played through the wizard the way the Create
    /// button plays it: a wizard in that state, then
    /// `buildConfigurationDictionary`, which is the file setup reads.
    ///
    /// Setup keeps a saved pool and reads a saved file WITHOUT one as a
    /// course that was never asked, so what this writes is what the course
    /// gets. The expectation "manifest" is read from the payload's own
    /// manifest in the checkout, never from the bundle, so a stale bundle
    /// fails here rather than agreeing with itself.
    func testANewCourseIsWrittenTheContractsMarksPool() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["gradedFolders", "newCourse"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "the contract lost new-course cases")

        var casesPlayed: Int = 0
        for testCase in cases {
            let caseName: String = testCase["name"] as? String ?? "unnamed"
            if let platforms = testCase["appliesOn"] as? [String], !platforms.contains("mac") {
                continue
            }
            var courseCodes: [String] = []
            if testCase["everyPayload"] as? Bool == true {
                courseCodes = try WizardStructureTests.payloadCodesInTheCheckout()
                XCTAssertGreaterThanOrEqual(courseCodes.count, 39, "the sweep found too few payloads")
            } else {
                courseCodes.append(try XCTUnwrap(testCase["courseCode"] as? String, caseName))
            }

            for code in courseCodes {
                let takesTheExample: Bool = (testCase["exampleContent"] as? String) == "taken"
                let wizard: NewCourseWizardView = NewCourseWizardView(
                    courseCode: code,
                    prepopulatesExampleContent: takesTheExample,
                    startsFromSkeleton: testCase["startsFromSkeleton"] as? Bool ?? true,
                    gradedFolders: testCase["wizardGradedFolders"] as? [String] ?? ["Tasks"],
                    isClubCourse: testCase["club"] as? Bool ?? false
                )
                let configuration: [String: Any] = wizard.buildConfigurationDictionary(
                    code: code, name: "Marks Pool Course"
                )

                var expected: [String] = []
                if let symbol = testCase["expect"] as? String {
                    XCTAssertEqual(symbol, "manifest", "\(caseName): an unknown symbol")
                    expected = try WizardStructureTests.declaredMarksPoolInTheCheckout(forCode: code)
                } else {
                    expected = try XCTUnwrap(testCase["expect"] as? [String], caseName)
                }
                XCTAssertEqual(
                    configuration["graded_folders"] as? [String], expected,
                    "\(caseName) (\(code)): a new course's file must carry the marks pool the "
                    + "command line would write — an absent key is a course that was never asked "
                    + "(contracts/shared-rules.json → gradedFolders.newCourse)."
                )
                casesPlayed += 1
            }
        }
        XCTAssertGreaterThanOrEqual(casesPlayed, 44, "every case, and one per payload for the sweep")
    }

    /// `contracts/shared-rules.json` → `gradedFolders.reconcilingAChosenPool`
    /// through `GradedFolderRule.reconciled`, the one copy of the rule the
    /// wizard and the manifest reader share (#152, from #85's second item).
    /// The command line runs the same cases through `graded_folders_for`.
    func testAChosenPoolIsReconciledAsTheContractSays() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["gradedFolders", "reconcilingAChosenPool"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "the contract lost reconciling cases")
        for testCase in cases {
            let caseName: String = testCase["name"] as? String ?? "unnamed"
            let declared: [String] = try XCTUnwrap(testCase["declared"] as? [String], caseName)
            let folders: [String] = try XCTUnwrap(testCase["folders"] as? [String], caseName)
            let expected: [String] = try XCTUnwrap(testCase["expect"] as? [String], caseName)
            XCTAssertEqual(GradedFolderRule.reconciled(declared, toFolders: folders), expected, caseName)
        }
    }

    /// The same rule reaches the file Create writes: a course made from
    /// scratch with a shared folder spelled `tasks` and the wizard's default
    /// pool `["Tasks"]` is written `["tasks"]`, as the command line writes it
    /// — not the empty pool an exact match gave, which read as "asked, and
    /// nothing counts".
    func testCreateWritesAChosenPoolInTheFoldersOwnSpelling() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            startedForTesting: true, courseCode: "ZZZ9Z", prepopulatesExampleContent: false,
            startsFromSkeleton: false, sharedFolders: ["Concepts", "tasks"], gradedFolders: ["Tasks"]
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(code: "ZZZ9Z", name: "Respelled")
        XCTAssertEqual(configuration["graded_folders"] as? [String], ["tasks"])
    }

    // MARK: - What must not move

    /// A teacher who TAKES the example content gets byte for byte the
    /// `course_config.json` this app wrote before issue #248 was fixed.
    ///
    /// The goldens in `Tests/Goldens/` were captured from `origin/dev` at
    /// 5d941927, by a throwaway test deleted in the same commit, BEFORE any
    /// of this piece was written — so they are what the app did, not what
    /// it was changed to do. Four payload codes and both paths of a code
    /// with no payload: ADA1O plain, MCV4U for the only family whose marks
    /// pool is not `["Tasks"]`, MCMPR11 for the DEFAULT family and the one
    /// British Columbia code with ready-made pages, ICS4U for the course
    /// this was reported against, and AMU3M twice for the ~1,900 codes the
    /// change was not for.
    ///
    /// The four payload goldens moved ONCE, on purpose, for GitHub issue
    /// #292: each gained exactly one key, `"graded_folders" : ["Tasks"]` —
    /// its manifest's own marks pool, which the command line always wrote
    /// and the app had left out since 2026-08-24, so every such course read
    /// as never asked (`gradedFolders.newCourse`). Nothing else in them
    /// moved, and the AMU3M goldens did not move at all.
    func testTheFileForEveryPathThatExistedBeforeIsUnchanged() throws {
        let takenFromTheExample: [String] = ["ADA1O", "MCV4U", "MCMPR11", "ICS4U"]
        for code in takenFromTheExample {
            let wizard: NewCourseWizardView = NewCourseWizardView(
                courseCode: code, prepopulatesExampleContent: true
            )
            try assertConfigurationMatchesGolden(
                wizard.buildConfigurationDictionary(code: code, name: "Golden Course"),
                named: code,
                because: "\(code) takes the ready-made pages written for it, and nothing about "
                + "that path changed — a teacher who says yes must get the file they have "
                + "always got."
            )
        }

        let noPayload: [(String, Bool)] = [("AMU3M-skeleton-on", true), ("AMU3M-skeleton-off", false)]
        for (goldenName, startsFromSkeleton) in noPayload {
            let wizard: NewCourseWizardView = NewCourseWizardView(
                courseCode: "AMU3M",
                prepopulatesExampleContent: true,
                startsFromSkeleton: startsFromSkeleton
            )
            try assertConfigurationMatchesGolden(
                wizard.buildConfigurationDictionary(code: "AMU3M", name: "Golden Course"),
                named: goldenName,
                because: "AMU3M has no ready-made pages, so the example-content toggle cannot "
                + "mean anything for it and neither of its two paths may move."
            )
        }
    }

    /// A teacher who declines the ready-made pages and keeps the subject's
    /// skeleton is written the same three curriculum keys as one who takes
    /// the pages — because the expectations written for their code exist
    /// either way, and `setup_course.py` reads these three as its answers
    /// (GitHub issue #251).
    ///
    /// Before this, all three were `false` by construction for this path,
    /// so the launcher never ran its new branch however the interface
    /// looked, and the course got the skeleton's placeholder Curriculum
    /// folder: a generic index and one fake expectation for the coverage
    /// map to colour.
    func testDecliningTheReadyMadePagesStillWritesTheCurriculumKeys() {
        // ICS4U is the course this was reported against; MCMPR11 is the
        // British Columbia payload, whose standards are not Ontario's.
        for code in ["ICS4U", "MCMPR11"] {
            let wizard: NewCourseWizardView = NewCourseWizardView(
                courseCode: code,
                prepopulatesExampleContent: false,
                startsFromSkeleton: true
            )
            let configuration: [String: Any] = wizard.buildConfigurationDictionary(
                code: code, name: "Golden Course"
            )

            XCTAssertEqual(configuration["prepopulate_example_content"] as? Bool, false, code)
            XCTAssertEqual(configuration["use_skeleton"] as? Bool, true, code)
            XCTAssertEqual(configuration["include_curriculum_pages"] as? Bool, true, code)
            XCTAssertEqual(configuration["include_curriculum_coverage"] as? Bool, true, code)
            XCTAssertEqual(configuration["include_coverage_notes"] as? Bool, true, code)
        }
    }

    /// Declining the pages AND the skeleton is an empty course, and an
    /// empty course has no expectations to map.
    func testDecliningTheSkeletonTooWritesNoCurriculumKeys() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "ICS4U",
            prepopulatesExampleContent: false,
            startsFromSkeleton: false
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "ICS4U", name: "Golden Course"
        )

        XCTAssertEqual(configuration["use_skeleton"] as? Bool, false)
        XCTAssertEqual(configuration["include_curriculum_pages"] as? Bool, false)
        XCTAssertEqual(configuration["include_curriculum_coverage"] as? Bool, false)
        XCTAssertEqual(configuration["include_coverage_notes"] as? Bool, false)
    }

    /// The ~1,900 codes with no ready-made pages are untouched: their
    /// skeleton ships an empty Curriculum folder and there is nothing
    /// anywhere to fill it with, so the keys stay false on both paths.
    ///
    /// The goldens above pin the whole file for AMU3M; this says out loud
    /// which three keys are the reason, so that a future change to them
    /// fails with an explanation rather than as a diff of a large file.
    func testACodeWithNoReadyMadePagesIsOfferedNoCurriculum() {
        XCTAssertFalse(ExampleContentCatalog.hasContent(forCode: "AMU3M"))
        for startsFromSkeleton in [true, false] {
            let wizard: NewCourseWizardView = NewCourseWizardView(
                courseCode: "AMU3M",
                prepopulatesExampleContent: false,
                startsFromSkeleton: startsFromSkeleton
            )
            let configuration: [String: Any] = wizard.buildConfigurationDictionary(
                code: "AMU3M", name: "Golden Course"
            )
            XCTAssertEqual(configuration["include_curriculum_pages"] as? Bool, false)
            XCTAssertEqual(configuration["include_curriculum_coverage"] as? Bool, false)
            XCTAssertEqual(configuration["include_coverage_notes"] as? Bool, false)
        }
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

    /// The configuration adopts once more as it is built, whether or not the
    /// code field's handler ever ran — and the marks pool goes with the four
    /// lists. Windows sets all five in the same place.
    ///
    /// The pool is the half that was missed: the wizard's default is
    /// `["Tasks"]`, and a mathematics course keeping it would count nothing
    /// in `Thinking Tasks`, which is where its assessed work goes.
    func testTheLateAdoptionCarriesTheSubjectsMarksPoolToo() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "MPM1D", startsFromSkeleton: true
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "MPM1D", name: "Mathematics"
        )

        XCTAssertEqual(configuration["graded_folders"] as? [String], ["Thinking Tasks", "Tasks"])
        XCTAssertEqual(
            (configuration["shared_folders"] as? [String])?.contains("Thinking Tasks"), true
        )
    }

    /// What the wizard WRITES never names a folder the course will not have,
    /// whatever route the pool took to get there.
    ///
    /// The route this closes is the terminology switch: turning LCS on,
    /// ticking `College Board Curriculum` for marks and turning LCS off again
    /// takes the folder out of the course and leaves the pool naming it —
    /// that handler is the one place the editor changes a folder list without
    /// narrowing the pool. Windows narrows as it writes
    /// (`NewCourseDialog.BuildConfiguration`) and now so does this.
    func testTheFileNeverNamesAFolderTheCourseWillNotHave() {
        let wizard: NewCourseWizardView = NewCourseWizardView(
            courseCode: "SNC4M",
            startsFromSkeleton: false,
            gradedFolders: ["Tasks", "College Board Curriculum"]
        )
        let configuration: [String: Any] = wizard.buildConfigurationDictionary(
            code: "SNC4M", name: "Science"
        )

        XCTAssertEqual(
            configuration["graded_folders"] as? [String], ["Tasks"],
            "The LCS folder is not in this course's folder lists, so writing it into the "
            + "marks pool would be a name that matches nothing on disk — and a different "
            + "file from the one Windows writes for the same clicks."
        )
    }

    /// A code whose ready-made pages the teacher is TAKING is offered no
    /// skeleton, so neither direction may touch its lists.
    func testACodeWhoseExampleContentIsBeingTakenIsNeverAdoptedOrRestored() throws {
        let payloadCode: String = "ADA1O"
        XCTAssertTrue(ExampleContentCatalog.hasContent(forCode: payloadCode))
        XCTAssertFalse(SkeletonCatalog.hasSkeleton(forCode: payloadCode, takingExampleContent: true, numbered: false))

        XCTAssertNil(
            SkeletonCatalog.structureToAdopt(
                forCode: payloadCode, takingExampleContent: true, numbered: false,
                currentSharedFolders: WizardDefaults.sharedFolders
            ),
            "The example content chooses the folders for a teacher who is taking it"
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

    /// The configuration, serialized the way the goldens were, against the
    /// golden of that name.
    ///
    /// Serialized rather than compared key by key on purpose: a key that
    /// APPEARED would pass a key-by-key comparison of the keys somebody
    /// thought to list, and `graded_folders` is written for one of these
    /// paths and deliberately omitted for the other.
    func assertConfigurationMatchesGolden(_ configuration: [String: Any],
                                          named goldenName: String,
                                          because reason: String,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) throws {
        let goldenURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Goldens")
            .appendingPathComponent("\(goldenName).json")
        let golden: String = try String(contentsOf: goldenURL, encoding: .utf8)
        let built: Data = try JSONSerialization.data(
            withJSONObject: configuration, options: [.sortedKeys, .prettyPrinted]
        )
        XCTAssertEqual(
            String(data: built, encoding: .utf8), golden, reason, file: file, line: line
        )
    }

    /// Every course code with ready-made pages, read from the checkout's
    /// `support/example_content/` rather than from the bundle.
    static func payloadCodesInTheCheckout() throws -> [String] {
        let folder: URL = WizardStructureTests.exampleContentInTheCheckout()
        let entries: [String] = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var codes: [String] = []
        for entry in entries.sorted() {
            let manifest: URL = folder.appendingPathComponent(entry).appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                codes.append(entry)
            }
        }
        return codes
    }

    /// The `graded_folders` a payload's manifest declares, as written in the
    /// checkout — the contract's "manifest" symbol. Every payload declares
    /// one, and a runner fails if it does not.
    static func declaredMarksPoolInTheCheckout(forCode code: String) throws -> [String] {
        let manifestURL: URL = WizardStructureTests.exampleContentInTheCheckout()
            .appendingPathComponent(code)
            .appendingPathComponent("manifest.json")
        let manifest: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: manifestURL)) as? [String: Any]
        )
        return try XCTUnwrap(manifest["graded_folders"] as? [String],
                             "\(code)'s manifest declares no marks pool")
    }

    static func exampleContentInTheCheckout() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .deletingLastPathComponent()   // the repository
            .appendingPathComponent("support/example_content")
    }

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
    /// is not there — enough to see what a short branch or handler does.
    ///
    /// The window is generous on purpose: a scan that reaches exactly as far
    /// as today's code starts failing on a renamed variable rather than on a
    /// lost behaviour, which is the kind of test that gets deleted.
    static func text(following marker: String, in source: String,
                     charactersToRead: Int = 600) -> String? {
        guard let found = source.range(of: marker) else {
            return nil
        }
        let remainder: Substring = source[found.upperBound...]
        return String(remainder.prefix(charactersToRead))
    }
}
