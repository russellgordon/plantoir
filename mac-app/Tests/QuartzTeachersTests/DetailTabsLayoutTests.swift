import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import QuartzTeachers

/// The Coverage and Planning tabs keep their place in the window (#831,
/// #832), measured on LAID-OUT FRAMES: the real tab views, with a page
/// taller than the window loaded in their web views, in a
/// `NavigationSplitView` window the size Plantoir opens at (1100 × 720)
/// and a larger one (1440 × 860), the window's content sized exactly as
/// the app's scene sizes it.
///
/// The fault both issues reported: the split view's column was laid out
/// about 2,200 points tall (Coverage) and 2,600 (Planning, Netlify) inside
/// a 700-point content area, and the window centred it, so the tab bar,
/// the header and the share bar were off the window above and below. The
/// column takes its smallest height from what its content claims when
/// squeezed (no height, almost no width), and one rigid wrapping sentence
/// in each tab claimed it: `CoverageTabView`'s header lines and
/// `PlanShareBar`'s Netlify sentence, each `.fixedSize(horizontal: false,
/// vertical: true)`. The structure tests these tabs already had
/// (`SectionDetailStructureTests`, `CourseDetailStructureTests`) look at
/// what is in the tree, and none laid a frame out, which is why none of
/// them saw it.
///
/// The layout tests fail on the code before #831 (measured by putting the
/// old files back). Either fix alone passes them: `TabArea`'s
/// `minHeight: 0`, or the `.fixedSize` taken off; both are kept (see
/// `TabArea`).
@MainActor
final class DetailTabsLayoutTests: XCTestCase {

    // MARK: - Types

    /// The window as the app draws it: a sidebar, the detail column with
    /// the working-folder bar under the page, and the scene's own frame.
    struct Shell<Detail: View>: View {

        // MARK: - Stored properties

        let workspace: WorkspaceModel
        @ViewBuilder let detail: () -> Detail

        // MARK: - Body

        var body: some View {
            NavigationSplitView {
                List {
                    Text("EXC2O")
                }
            } detail: {
                VStack(spacing: 0) {
                    detail()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    Text("Working folder:")
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                }
            }
            .environment(workspace)
            // `QuartzTeachersApp`'s window frame.
            .frame(
                minWidth: WindowChrome.minimumWindowWidth,
                idealWidth: 1100,
                maxWidth: .infinity,
                minHeight: WindowChrome.minimumWindowHeight,
                idealHeight: 720,
                maxHeight: .infinity
            )
        }
    }

    /// What a laid-out window is measured for.
    struct Measured {

        // MARK: - Stored properties

        /// The window's content area, in window coordinates.
        let content: NSRect
        let tabBar: NSRect
        let webView: NSRect
        /// The tallest view outside any scroll view's content.
        let tallest: NSRect
        /// The buttons AppKit draws for the page: the Unit popup and the
        /// share bar's checkboxes on Planning.
        let controls: [NSRect]
    }

    // MARK: - Stored properties

    nonisolated(unsafe) private var rootURLs: [URL] = []
    nonisolated(unsafe) private var previousStore: ProblemReportStore?

    static let sizes: [NSSize] = [NSSize(width: 1100, height: 720), NSSize(width: 1440, height: 860)]

    // MARK: - Functions

    override func setUp() async throws {
        previousStore = ActivityTrail.store
        let trail: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tabs-layout-trail-\(UUID().uuidString)", isDirectory: true)
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
        for url in rootURLs {
            try? FileManager.default.removeItem(at: url)
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

    /// Every view under `view`, leaving out what is inside a scroll view's
    /// clip view (a list's rows may be as tall as they like).
    func viewsOutsideScrolling(in view: NSView) -> [NSView] {
        var found: [NSView] = [view]
        if view is NSClipView {
            return found
        }
        for child in view.subviews {
            found.append(contentsOf: viewsOutsideScrolling(in: child))
        }
        return found
    }

    func allViews(in view: NSView) -> [NSView] {
        var found: [NSView] = [view]
        for child in view.subviews {
            found.append(contentsOf: allViews(in: child))
        }
        return found
    }

    /// A page of `rows` rows, 44 points each: far taller than any window.
    static func tallPage(rows: Int) -> String {
        var page: String = "<html><body>"
        for row in 0..<rows {
            page += "<div style=\"height:44px\">Expectation \(row + 1)</div>"
        }
        page += "</body></html>"
        return page
    }

    /// Lays `view` out in a window of `size`, runs `before`, waits for the
    /// tab's web view to finish loading a page, and measures.
    func measure(
        _ view: some View, size: NSSize,
        before: (NSHostingView<AnyView>) -> Void = { (_: NSHostingView<AnyView>) in }
    ) throws -> Measured {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: size.width, height: size.height),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host: NSHostingView<AnyView> = NSHostingView(rootView: AnyView(view))
        window.contentView = host
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }
        before(host)
        var webView: WKWebView?
        XCTAssertTrue(runUntil(timeout: 15) {
            host.layoutSubtreeIfNeeded()
            for candidate in allViews(in: host) {
                if let found = candidate as? WKWebView {
                    webView = found
                }
            }
            return webView?.url != nil && webView?.isLoading == false
        }, "the tab's web view loaded its page")
        // A beat for the page's own layout to reach the window's.
        _ = runUntil(timeout: 0.5) { false }
        host.layoutSubtreeIfNeeded()

        var tabBar: NSRect = .zero
        var tallest: NSRect = .zero
        var controls: [NSRect] = []
        for candidate in viewsOutsideScrolling(in: host) {
            let frame: NSRect = candidate.convert(candidate.bounds, to: nil)
            if candidate is NSSegmentedControl {
                tabBar = frame
            }
            if candidate is NSButton {
                controls.append(frame)
            }
            if candidate !== host && frame.height > tallest.height {
                tallest = frame
            }
        }
        let shownWebView: WKWebView = try XCTUnwrap(webView)
        return Measured(
            content: host.convert(host.bounds, to: nil),
            tabBar: tabBar,
            webView: shownWebView.convert(shownWebView.bounds, to: nil),
            tallest: tallest,
            controls: controls
        )
    }

    /// The three things the issues asked for, at one size: the tab bar and
    /// the web view inside the window, the page below the bar, and nothing
    /// taller than the window.
    func checkTheLayout(_ measured: Measured, what: String) {
        let content: NSRect = measured.content.insetBy(dx: -0.5, dy: -0.5)
        XCTAssertNotEqual(measured.tabBar, .zero, "\(what): the tab bar was not found")
        XCTAssertTrue(content.contains(measured.tabBar), "\(what): the tab bar \(measured.tabBar) is outside the window \(measured.content)")
        XCTAssertTrue(content.contains(measured.webView), "\(what): the web view \(measured.webView) is outside the window \(measured.content)")
        // Window coordinates rise upwards: the page sits under the bar.
        XCTAssertLessThanOrEqual(
            measured.webView.maxY, measured.tabBar.minY,
            "\(what): the page \(measured.webView) is not below the tab bar \(measured.tabBar)"
        )
        XCTAssertLessThanOrEqual(
            measured.tallest.height, measured.content.height + 0.5,
            "\(what): something is laid out \(measured.tallest.height) points tall in a \(measured.content.height)-point window"
        )
        for control in measured.controls {
            XCTAssertTrue(content.contains(control), "\(what): a control \(control) is outside the window \(measured.content)")
        }
    }

    // MARK: - Tests

    /// #831: a section whose last build made a map of 60 expectations.
    func testTheCoverageTabKeepsItsTabsAndHeaderInTheWindow() throws {
        for size in DetailTabsLayoutTests.sizes {
            SectionCoverage.shared.reset()
            SectionProblems.shared.reset()
            let root: URL = try FixtureWorkspace.materialize()
            rootURLs.append(root)
            let courses: [Course] = try WorkspaceModel.discoverCourses(in: root.appendingPathComponent("courses"))
            let course: Course = try XCTUnwrap(courses.first)
            let output: URL = CoverageTab.sectionOutput(courseFolder: course.directoryURL, sectionNumber: 1)
            try? FileManager.default.removeItem(at: course.directoryURL.appendingPathComponent(BuildOutputLocation.linkName))
            let coverageFolder: URL = output.appendingPathComponent(CoverageTab.folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: coverageFolder, withIntermediateDirectories: true)
            try Data("build-1\n".utf8).write(to: output.appendingPathComponent(CoverageTab.buildIdName))
            try Data(DetailTabsLayoutTests.tallPage(rows: 60).utf8)
                .write(to: coverageFolder.appendingPathComponent("map-build-1.html"))
            try Data("""
                {"version": 1, "buildId": "build-1", "page": "map-build-1.html", "startedNs": null,
                 "maps": [{"title": "Curriculum Coverage", "folder": "Curriculum", "expectations": 60, "notYetAddressed": 20, "pages": {}}]}
                """.utf8).write(to: coverageFolder.appendingPathComponent(CoverageTab.recordName))
            let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
            workspace.workspaceURL = root
            let key: String = SectionCoverage.shared.key(folder: root, course: course, sectionNumber: 1)

            let measured: Measured = try measure(Shell(workspace: workspace) {
                SectionDetailView(course: course, sectionNumber: 1)
            }, size: size) { (host: NSHostingView<AnyView>) in
                SectionProblems.shared.show(.coverage, folder: root, courseCode: course.code, sectionNumber: 1)
                XCTAssertTrue(runUntil(timeout: 10) {
                    host.layoutSubtreeIfNeeded()
                    return SectionCoverage.shared.entry(key).reading?.kind == .thisBuild
                }, "the Coverage tab read its map")
            }
            let what: String = "Coverage at \(Int(size.width)) × \(Int(size.height))"
            checkTheLayout(measured, what: what)
            // The header (the made-when line and Make the Map Again) sits
            // between the tab bar and the page, with room of its own.
            XCTAssertGreaterThanOrEqual(
                measured.tabBar.minY - measured.webView.maxY, 30,
                "\(what): no room left for the header between the tabs and the map"
            )
        }
    }

    /// #832: the Planning tab, on a course whose class sites go to Netlify
    /// (no destination saved, which reads as Netlify, and `netlify` itself),
    /// so the share bar shows its sentence about Netlify; and on
    /// Cloudflare, which was always laid out right, as the control.
    func testThePlanningTabKeepsItsTabsPopupAndShareBarInTheWindow() throws {
        for target in ["", "netlify", "cloudflare_pages"] {
            for size in DetailTabsLayoutTests.sizes {
                let root: URL = try FixtureWorkspace.materialize()
                rootURLs.append(root)
                let courses: [Course] = try WorkspaceModel.discoverCourses(in: root.appendingPathComponent("courses"))
                let course: Course = try XCTUnwrap(courses.first)
                course.configuration.deployTarget = target
                let planning: URL = course.directoryURL.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
                try FileManager.default.createDirectory(at: planning, withIntermediateDirectories: true)
                try DetailTabsLayoutTests.tallPage(rows: 80).write(
                    to: PlanningTab.page(for: .allPlans, planningFolder: planning), atomically: true, encoding: .utf8
                )
                let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
                workspace.workspaceURL = root
                let model: PlanningTabModel = PlanningTabModel()

                // `CourseDetailView`'s body with Planning chosen: the tab
                // bar, then the page under it in `CourseDetailContent`.
                let measured: Measured = try measure(Shell(workspace: workspace) {
                    VStack(spacing: 0) {
                        DetailTabs(
                            tabs: [
                                (tab: CourseDetailTab.settings, title: PlanningWording.tabSettings),
                                (tab: CourseDetailTab.planning, title: PlanningWording.tabPlanning),
                            ],
                            selection: .constant(CourseDetailTab.planning),
                            identifier: "courseTabs"
                        )
                        CourseDetailContent(course: course, session: CourseSettingsSession(), showsPlanning: true) {
                            PlanningTabView(course: course, folder: root, model: model)
                        }
                    }
                }, size: size)
                let what: String = "Planning ('\(target)') at \(Int(size.width)) × \(Int(size.height))"
                checkTheLayout(measured, what: what)
                // The Unit popup above the plan and the share bar's two
                // checkboxes below it are all found, and all in the window.
                XCTAssertGreaterThanOrEqual(
                    measured.controls.count, 3,
                    "\(what): the popup and the share bar's checkboxes were not found (\(measured.controls))"
                )
            }
        }
    }

    /// Without the `.fixedSize`, the share bar still shows its sentence in
    /// full at a real width: taller narrow than wide, which is what
    /// wrapping looks like, and taller for a Netlify teacher than for a
    /// Cloudflare one.
    func testTheShareBarStillShowsTheNetlifySentenceInFull() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURLs.append(root)
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: root.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        course.configuration.deployTarget = ""
        let narrow: CGFloat = NSHostingController(rootView: PlanShareBar(course: course, folder: root))
            .sizeThatFits(in: NSSize(width: 420, height: 900)).height
        let wide: CGFloat = NSHostingController(rootView: PlanShareBar(course: course, folder: root))
            .sizeThatFits(in: NSSize(width: 1200, height: 900)).height
        course.configuration.deployTarget = "cloudflare_pages"
        let cloudflare: CGFloat = NSHostingController(rootView: PlanShareBar(course: course, folder: root))
            .sizeThatFits(in: NSSize(width: 1200, height: 900)).height
        XCTAssertGreaterThan(narrow, wide, "the Netlify sentence is not wrapping at 420 points, so it is being cut short")
        XCTAssertGreaterThan(wide, cloudflare, "the Netlify sentence takes no room of its own")
    }

    /// The tab area claims no height when squeezed, whatever a tab inside
    /// it claims: a rigid sentence a thousand points tall stays inside.
    func testTheTabAreaClaimsNoHeightWhenSqueezed() {
        let sentence: String = String(repeating: "A sentence that wraps. ", count: 40)
        let alone: CGFloat = NSHostingController(rootView: Text(sentence).fixedSize(horizontal: false, vertical: true))
            .sizeThatFits(in: NSSize(width: 1, height: 0)).height
        let inTheArea: CGFloat = NSHostingController(rootView: TabArea {
            Text(sentence).fixedSize(horizontal: false, vertical: true)
        }).sizeThatFits(in: NSSize(width: 1, height: 0)).height
        XCTAssertGreaterThan(alone, 1000, "the control: a rigid sentence squeezed claims a great height (\(alone))")
        XCTAssertLessThanOrEqual(inTheArea, ProgressViewSizeTests.squeezedHeightBound, "the tab area passed on \(inTheArea) points")
    }

    /// Nothing drawn in either tab makes a sentence rigid: the rule of
    /// `documentation/09-mac-app.md` → "A blank window", for the files the
    /// two tabs are made of. The sheets they open are hosted at a width of
    /// their own and may.
    func testNothingInEitherTabMakesASentenceRigid() throws {
        let views: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views")
        let files: [String] = [
            "Section/CoverageTabView.swift", "Section/SectionDetailCoverage.swift", "Section/DetailTabs.swift",
            "Planning/PlanningTabView.swift", "Planning/PlanShareBar.swift", "Planning/PlanWebView.swift",
        ]
        for file in files {
            let text: String = try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
            XCTAssertNil(
                text.range(of: ".fixedSize(horizontal: false, vertical: true)"),
                "\(file) makes a sentence rigid in a tab (#831, #832)"
            )
        }
    }
}
