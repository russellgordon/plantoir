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
}
