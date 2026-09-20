import XCTest
@testable import QuartzTeachers

/// The cross-window record of which courses are previewing or publishing,
/// used to decline actions (like Add Section…) that would rewrite a
/// course's files mid-task.
final class CourseActivityTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAnIdleCourseIsNotBusy() {
        CourseActivity.reset()
        PreviewLeases.reset()
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
    }

    @MainActor
    func testAPreviewMakesItsCourseBusyUntilTheLeaseIsReleased() throws {
        CourseActivity.reset()
        PreviewLeases.reset()
        let lease: PreviewLeases.Lease = try PreviewLeases.lease(
            folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
        XCTAssertEqual(CourseActivity.busyDescription(folderPath: "/folder", courseCode: "ICS3U"),
                       "Available once preview completed")
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "MPM2D"),
                       "Only the previewing course is busy, not its neighbours")
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/other-folder", courseCode: "ICS3U"),
                       "The same code in a different working folder is a different course")

        PreviewLeases.release(lease)
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
    }

    @MainActor
    func testAPublishMakesItsCourseBusyUntilItEnds() {
        CourseActivity.reset()
        PreviewLeases.reset()
        CourseActivity.beginPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
        XCTAssertEqual(CourseActivity.busyDescription(folderPath: "/folder", courseCode: "ICS3U"),
                       "Available once deploy completed")

        CourseActivity.endPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
    }

    @MainActor
    func testTwoPublishesOfOneCourseEndIndependently() {
        CourseActivity.reset()
        PreviewLeases.reset()
        // Two windows publishing two sections of the same course: the
        // course stays busy until BOTH finish.
        CourseActivity.beginPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 1)
        CourseActivity.beginPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 3)

        CourseActivity.endPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"),
                      "The other section is still publishing")

        CourseActivity.endPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 3)
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
    }

    @MainActor
    func testEndingAPublishThatNeverBeganChangesNothing() {
        CourseActivity.reset()
        PreviewLeases.reset()
        CourseActivity.beginPublish(folderPath: "/folder", courseCode: "ICS3U", sectionNumber: 1)
        CourseActivity.endPublish(folderPath: "/folder", courseCode: "MPM2D", sectionNumber: 1)
        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "ICS3U"))
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: "/folder", courseCode: "MPM2D"))
    }
}

/// Which question the repair dialog asks before starting a preview.
///
/// It must ask whether somebody is PUBLISHING. `courseIsBusy` answers
/// "previewing or publishing", and asking that one refused the preview whenever
/// a preview was already running — which is every time the button is offered,
/// since the findings come from a build. Found by pressing the button.
@MainActor
final class CourseActivityPublishOnlyTests: XCTestCase {

    // MARK: - Functions

    override func setUp() {
        super.setUp()
        CourseActivity.reset()
        PreviewLeases.reset()
    }

    override func tearDown() {
        CourseActivity.reset()
        PreviewLeases.reset()
        super.tearDown()
    }

    func testAPreviewDoesNotCountAsAPublish() throws {
        let folder: String = "/tmp/some-folder"
        let lease: PreviewLeases.Lease = try PreviewLeases.lease(
            folderPath: folder, courseCode: "ICS3U", sectionNumber: 1
        )
        defer { PreviewLeases.release(lease) }

        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: folder, courseCode: "ICS3U"),
                      "a preview does make the course busy")
        XCTAssertFalse(
            CourseActivity.coursePublishIsRunning(folderPath: folder, courseCode: "ICS3U"),
            "but it is not a publish, and the repair dialog must not treat it as one"
        )
    }

    func testAPublishDoesCountAsAPublish() {
        let folder: String = "/tmp/some-folder"
        CourseActivity.beginPublish(folderPath: folder, courseCode: "ICS3U", sectionNumber: 1)
        defer { CourseActivity.endPublish(folderPath: folder, courseCode: "ICS3U", sectionNumber: 1) }

        XCTAssertTrue(
            CourseActivity.coursePublishIsRunning(folderPath: folder, courseCode: "ICS3U")
        )
    }

    func testAnotherCoursesPublishIsNotThisCoursesProblem() {
        CourseActivity.beginPublish(folderPath: "/tmp/f", courseCode: "OTHER", sectionNumber: 1)
        defer { CourseActivity.endPublish(folderPath: "/tmp/f", courseCode: "OTHER", sectionNumber: 1) }

        XCTAssertFalse(
            CourseActivity.coursePublishIsRunning(folderPath: "/tmp/f", courseCode: "ICS3U")
        )
    }
}
