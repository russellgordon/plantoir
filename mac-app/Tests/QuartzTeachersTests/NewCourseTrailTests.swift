import XCTest
@testable import QuartzTeachers

/// What a new course leaves on the breadcrumb trail.
///
/// Until 2026-09-21 the answer was "started setup.sh" and nothing else —
/// the arguments are empty for a course creation, so the line did not even
/// carry the course code, let alone what the course was meant to start
/// from. Adding one folder to a list recorded more. That is how GitHub
/// issue #248 stayed invisible for five weeks: a teacher declined the
/// ready-made pages for a code that had some, got empty folders instead of
/// the subject's skeleton, and nothing written down said which of those two
/// things had happened.
///
/// The rule is `contracts/shared-rules.json` → `activityTrail.mustRecord`,
/// "course created". Windows creates courses too and owes the same line.
final class NewCourseTrailTests: XCTestCase {

    // MARK: - Functions

    /// Each of the three starting points says which one it was, in words a
    /// teacher would recognise rather than the config keys behind them.
    @MainActor
    func testTheLineSaysWhichStartingContentTheCourseBeganFrom() {
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: true,
                usesSkeleton: false, skeletonSubject: "Computer Studies"
            ),
            "created ICS4U from the ready-made pages written for it"
        )
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: false,
                usesSkeleton: true, skeletonSubject: "Computer Studies"
            ),
            "created ICS4U from the computer studies skeleton"
        )
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: false,
                usesSkeleton: false, skeletonSubject: "Computer Studies"
            ),
            "created ICS4U with empty folders"
        )
    }

    /// A club (#267) says so, in its own words — and every other course's
    /// line is exactly what it was, because the words are read from a
    /// configuration whose pages are numbered and from nothing else.
    @MainActor
    func testAClubSaysItIsAClubInItsOwnWords() {
        let clubConfiguration: [String: Any] = [
            "class_page_scheme": "numbered", "unit_word": "Week", "class_folder": "All Meetings",
            "prepopulate_example_content": false, "use_skeleton": false,
        ]
        let club: (pageWord: String, classFolder: String)? = NewCourseCreator.clubWords(in: clubConfiguration)
        XCTAssertEqual(club?.pageWord, "Week")
        XCTAssertEqual(club?.classFolder, "All Meetings")
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "CODING", takesExampleContent: false,
                usesSkeleton: false, skeletonSubject: nil, asAClub: club
            ),
            "created CODING as a club, with pages named “Week 1” in “All Meetings”"
        )

        let ordinary: [String: Any] = ["class_page_scheme": "unit_day", "unit_word": "Unit"]
        XCTAssertNil(NewCourseCreator.clubWords(in: ordinary))
        XCTAssertNil(NewCourseCreator.clubWords(in: [:]), "an absent scheme is not a club")
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: false,
                usesSkeleton: false, skeletonSubject: nil,
                asAClub: NewCourseCreator.clubWords(in: ordinary)
            ),
            "created ICS4U with empty folders"
        )
    }

    /// A skeleton course now comes out two ways, and they differ by
    /// fifty-nine pages and by whether the curriculum coverage map works
    /// at all (GitHub issue #251) — so the line says which of the two
    /// happened. The report it exists to answer is "my new course came out
    /// wrong"; a line that could not tell them apart could not answer it.
    @MainActor
    func testASkeletonCourseSaysWhetherItGotItsCurriculumPages() {
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: false,
                usesSkeleton: true, skeletonSubject: "Computer Studies",
                withCurriculumPages: true
            ),
            "created ICS4U from the computer studies skeleton with the ICS4U curriculum pages"
        )
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "MCMPR11", takesExampleContent: false,
                usesSkeleton: true, skeletonSubject: nil,
                withCurriculumPages: true
            ),
            "created MCMPR11 from the general course skeleton with the MCMPR11 curriculum pages"
        )

        // The other two starting points are untouched. The ready-made
        // pages have always carried their own curriculum, and an empty
        // course has nothing to say about one.
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: true,
                usesSkeleton: false, skeletonSubject: "Computer Studies",
                withCurriculumPages: true
            ),
            "created ICS4U from the ready-made pages written for it"
        )
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "ICS4U", takesExampleContent: false,
                usesSkeleton: false, skeletonSubject: "Computer Studies",
                withCurriculumPages: true
            ),
            "created ICS4U with empty folders"
        )
    }

    /// The clause is read from the configuration the wizard just wrote —
    /// `include_curriculum_pages`, the same key the launcher answers its
    /// question with — rather than guessed from the code or the catalog.
    @MainActor
    func testTheClauseIsReadFromTheFileTheWizardWrote() throws {
        let source: String = try NewCourseTrailTests.creatorSource()
        let body: String = try XCTUnwrap(
            NewCourseTrailTests.body(ofFunction: "func createCourse(", in: source),
            "createCourse() was not found — this scan cannot see what it records."
        )
        XCTAssertTrue(
            body.contains("withCurriculumPages: configuration[\"include_curriculum_pages\"]"),
            "The line no longer reads the key the launcher itself answers with, so the trail "
            + "can claim curriculum pages a course did not get, or miss ones it did."
        )
    }

    /// A code whose skeleton has no subject of its own still reads as
    /// English — the general family's label is "This Course", written for
    /// the skeleton's pages rather than for a sentence.
    @MainActor
    func testACodeWithNoSubjectOfItsOwnStillReadsAsEnglish() {
        XCTAssertNil(NewCourseCreator.skeletonSubject(forCode: "MCMPR11"),
                     "MCMPR11's prefix is in no map entry, so it falls to the general family")
        XCTAssertEqual(NewCourseCreator.skeletonSubject(forCode: "ICS4U"), "Computer Studies")

        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "CODING", takesExampleContent: false,
                usesSkeleton: true, skeletonSubject: nil
            ),
            "created CODING from the general course skeleton"
        )
    }

    /// The line carries the code and nothing else a teacher wrote. The
    /// course NAME is theirs — it can hold a student's name, a room, a
    /// nickname — and the trail is a file they hand over.
    @MainActor
    func testTheLineCarriesTheCodeAndNothingElseTheTeacherTyped() {
        let line: String = NewCourseCreator.startingContentLine(
            courseCode: "ICS4U", takesExampleContent: false,
            usesSkeleton: true, skeletonSubject: "Computer Studies"
        )
        XCTAssertTrue(line.contains("ICS4U"))
        XCTAssertFalse(line.contains("/"), "No paths on this line")
    }

    /// The event is declared and the contract knows it. The list pin lives
    /// in `SharedRulesContractTests`; this is the half that says the case
    /// exists at all, so a merge that dropped it fails here too.
    @MainActor
    func testTheEventExists() {
        XCTAssertEqual(ActivityTrail.Event.courseCreated.rawValue, "course created")
    }

    // MARK: - Every button that makes a course leaves the line

    /// "Add Example Course" makes a course too, and must leave the same
    /// line — it was the one creator that left none.
    ///
    /// A source scan, for two reasons a test that calls the function cannot
    /// meet: `installExampleCourse` runs the real `setup.sh`, and the thing
    /// most easily got wrong here is not the sentence but WHERE it is
    /// written. The code is not known before the run — the example installs
    /// as EXC2O unless that code is taken — so a line written up front would
    /// name the wrong course, and a line written outside the `if let` would
    /// claim a course that a failed run never made.
    @MainActor
    func testAddingTheExampleCourseLeavesTheLineToo() throws {
        let source: String = try NewCourseTrailTests.creatorSource()
        let body: String = try XCTUnwrap(
            NewCourseTrailTests.body(ofFunction: "func installExampleCourse(", in: source),
            "installExampleCourse() was not found — this scan cannot see what it records."
        )

        XCTAssertTrue(
            body.contains(".courseCreated"),
            "Adding the example course records nothing, so a teacher who pressed that button "
            + "and asked about the course a week later leaves no trace of having made it "
            + "(contracts/shared-rules.json → activityTrail.mustRecord, \"course created\")."
        )
        XCTAssertTrue(
            body.contains("if let installedCode = installedExampleCode"),
            "The line no longer waits for the code the run actually installed. The example "
            + "takes another code when EXC2O is taken, so a line written before the run names "
            + "a course that may not exist — and a run that installed nothing must say nothing."
        )
        // The sentence itself comes from the same function the wizard uses,
        // so a reword reaches both creators at once.
        XCTAssertTrue(
            body.contains("startingContentLine("),
            "The example course's line is no longer built by startingContentLine(), so the two "
            + "creators can drift into saying different things about the same act."
        )
    }

    /// The sentence that button leaves, spelled out once.
    @MainActor
    func testTheExampleCourseSaysWhereItsPagesCameFrom() {
        XCTAssertEqual(
            NewCourseCreator.startingContentLine(
                courseCode: "EXC2O", takesExampleContent: true,
                usesSkeleton: false, skeletonSubject: nil
            ),
            "created EXC2O from the ready-made pages written for it"
        )
    }

    // MARK: - Functions

    /// `NewCourseCreator`'s own source, read from the checkout.
    static func creatorSource() throws -> String {
        let fileURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers/Scripting/NewCourseCreator.swift")
        let source: String = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertGreaterThan(
            source.count, 1000,
            "NewCourseCreator.swift was not found where this test expects it — the scan would "
            + "pass vacuously."
        )
        return source
    }

    /// Everything between a function's opening line and the first line that
    /// closes it at the function's own indentation.
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
}
