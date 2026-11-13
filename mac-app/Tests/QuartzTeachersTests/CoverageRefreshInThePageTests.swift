import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Make the Map Again driven through the REAL section page (#793, the 793b
/// fix review's H1): the real `SectionDetailView` in an `NSWindow` that is
/// never put on screen, with a stand-in `preview.sh` in the working folder.
/// The page starts a preview that "serves" (sleeps); the teacher's press on
/// the Coverage tab stops it, and the stand-in's stop takes a second, so
/// the old run's end, and the page's own readings of the record that it
/// brings, land DURING the stop, as they do on a teacher's Mac. The second
/// run writes `.build-id`, the map and its record, then the problems line.
///
/// To see it fail: delete the `starting` guard at the top of
/// `SectionCoverage.settle` (the code ccd76e83d shipped), and the press
/// starts no second run and the map is never made again.
@MainActor
final class CoverageRefreshInThePageTests: XCTestCase {

    // MARK: - Types

    /// The page, with its working folder, as the window gives it.
    struct Page: View {

        // MARK: - Stored properties

        let course: Course
        let workspace: WorkspaceModel

        // MARK: - Body

        var body: some View {
            SectionDetailView(course: course, sectionNumber: 1)
                .environment(workspace)
        }
    }

    // MARK: - Stored properties

    nonisolated(unsafe) private var rootURL: URL?
    nonisolated(unsafe) private var previousStore: ProblemReportStore?

    // MARK: - Functions

    override func setUp() async throws {
        previousStore = ActivityTrail.store
        let trail: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-refresh-trail-\(UUID().uuidString)", isDirectory: true)
        ActivityTrail.store = ProblemReportStore(folderURL: trail)
        SectionCoverage.shared.reset()
        SectionProblems.shared.reset()
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        SectionCoverage.shared.reset()
        SectionProblems.shared.reset()
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func runUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end: Date = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }

    /// The stand-in launcher. `--stop` takes a second, as the real stop
    /// mode takes seconds. The first run serves the map that is already
    /// there; every later run is a build that writes its own.
    static let standIn: String = """
        #!/bin/bash
        here="$(cd "$(dirname "$0")" && pwd)"
        log="$here/.stand-in-log"
        for word in "$@"; do
          if [ "$word" = "--stop" ]; then
            echo stop >> "$log"
            sleep 1
            exit 0
          fi
        done
        echo run >> "$log"
        runs=$(grep -c '^run$' "$log")
        out="$here/courses/$1/.merged_output/section$2"
        if [ "$runs" -ge 2 ]; then
          id="build-$runs"
          printf '%s\\n' "$id" > "$out/.build-id"
          printf '<p>map</p>' > "$out/.coverage-tab/map-$id.html"
          printf '{"version": 1, "buildId": "%s", "page": "map-%s.html", "startedNs": null, "maps": [{"title": "Curriculum Coverage", "folder": "Curriculum", "expectations": 2, "notYetAddressed": 1, "pages": {}}]}' "$id" "$id" > "$out/.coverage-tab/about.json"
          echo "PLANTOIR_PROBLEMS: {\\"course\\": \\"$1\\", \\"section\\": $2, \\"buildId\\": \\"$id\\", \\"rows\\": 0}"
        fi
        exec sleep 600
        """

    private func runs(in folder: URL) -> (runs: Int, stops: Int) {
        let text: String = (try? String(contentsOf: folder.appendingPathComponent(".stand-in-log"), encoding: .utf8)) ?? ""
        var runs: Int = 0
        var stops: Int = 0
        for line in text.components(separatedBy: "\n") {
            if line == "run" {
                runs += 1
            } else if line == "stop" {
                stops += 1
            }
        }
        return (runs: runs, stops: stops)
    }

    // MARK: - Tests

    func testAPressWithAPreviewServingStopsItAndMakesTheMapAgain() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURL = root
        try CoverageRefreshInThePageTests.standIn.write(to: root.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("preview.sh").path)
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: root.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        // The map an earlier build made, beside a real (not linked) output.
        let output: URL = CoverageTab.sectionOutput(courseFolder: course.directoryURL, sectionNumber: 1)
        try? FileManager.default.removeItem(at: course.directoryURL.appendingPathComponent(BuildOutputLocation.linkName))
        let coverageFolder: URL = output.appendingPathComponent(CoverageTab.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: coverageFolder, withIntermediateDirectories: true)
        try Data("build-1\n".utf8).write(to: output.appendingPathComponent(CoverageTab.buildIdName))
        try Data("<p>map</p>".utf8).write(to: coverageFolder.appendingPathComponent("map-build-1.html"))
        try Data("""
            {"version": 1, "buildId": "build-1", "page": "map-build-1.html", "startedNs": null,
             "maps": [{"title": "Curriculum Coverage", "folder": "Curriculum", "expectations": 2, "notYetAddressed": 2, "pages": {}}]}
            """.utf8).write(to: coverageFolder.appendingPathComponent(CoverageTab.recordName))

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.workspaceURL = root
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 900, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host: NSHostingView<Page> = NSHostingView(rootView: Page(course: course, workspace: workspace))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }

        let registry: SectionWindowControllers = SectionWindowControllers.shared
        XCTAssertTrue(runUntil(timeout: 10) {
            registry.controller(folderPath: root.path, courseCode: course.code, sectionNumber: 1) != nil
        }, "the page registered itself")
        let controller: SectionWindowControllers.Controller = try XCTUnwrap(
            registry.controller(folderPath: root.path, courseCode: course.code, sectionNumber: 1)
        )
        // The teacher previewed first: a preview is serving.
        controller.startPreview()
        XCTAssertTrue(runUntil(timeout: 10) { runs(in: root).runs == 1 && controller.previewState() != .notRunning },
                      "the first preview is running")

        let coverage: SectionCoverage = SectionCoverage.shared
        let key: String = coverage.key(folder: root, course: course, sectionNumber: 1)
        SectionProblems.shared.show(.coverage, folder: root, courseCode: course.code, sectionNumber: 1)
        XCTAssertTrue(runUntil(timeout: 10) {
            host.layoutSubtreeIfNeeded()
            return coverage.entry(key).reading?.kind == .thisBuild
        }, "the Coverage tab reads its map")
        // The button's own action, through the page's registration: SwiftUI
        // offers no control to click in a window that is never on screen
        // (measured: no NSButton and no accessibility element in the tree).
        controller.makeTheCoverageMapAgain()
        XCTAssertTrue(runUntil(timeout: 2) { coverage.entry(key).refresh == .starting }, "recorded at the press")
        // The stop runs for a second; the old run ends inside it, and the
        // page reads the record as that happens.
        XCTAssertTrue(runUntil(timeout: 20) { runs(in: root).runs == 2 },
                      "the press started its build after the stop (runs \(runs(in: root)), refresh \(coverage.entry(key).refresh))")
        XCTAssertTrue(runUntil(timeout: 20) {
            return coverage.entry(key).reading?.record?.buildId == "build-2" && coverage.entry(key).refresh == .none
        }, "the map was made again, in place (refresh \(coverage.entry(key).refresh))")
        XCTAssertGreaterThanOrEqual(runs(in: root).stops, 1, "the old preview was stopped")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        XCTAssertTrue(trail.contains(CoverageTabTrail.madeAgain), trail)

        // Leave nothing running.
        var stopped: Bool = false
        Task { @MainActor in
            await controller.stopPreview()
            stopped = true
        }
        XCTAssertTrue(runUntil(timeout: 20) { stopped })
    }
}
