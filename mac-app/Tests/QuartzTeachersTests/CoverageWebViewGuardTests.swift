import AppKit
import WebKit
import XCTest
@testable import QuartzTeachers

/// The Coverage tab's web view keeps the map's page to its folder (#793,
/// `shared-rules.json` → `coverageTab.tab.whatAPageMayRead`), proved by
/// RUNNING the real controller (`PlanWebController.forCoverage`) with no
/// window, as `PlanWebViewGuardTests` proves the Planning tab's.
///
/// To see each fail:
/// - network: in `PlanWebController.localOnlyRules` change the first rule's
///   `"block"` to `"ignore-previous-rules"`, and
///   `testTheMapReachesNothingOnTheNetwork` sees connections;
/// - scripts: delete `allowsContentJavaScript = false`, and
///   `testTheMapRunsNoScript` sees the title change;
/// - read access: pass the section's output folder (the `.coverage-tab`
///   folder's parent) to `show(page:readingOnlyInside:)` here, and
///   `testTheMapCannotShowAFileOutsideItsFolder` sees the picture;
/// - clicks: make `CoverageNavigation.decide` hand a link over without
///   `byALinkClick`, and `testAClickOnACodeIsHandedToTheAppAndARefreshIsNot`
///   sees the refresh handed over.
///
/// The fixtures live under `/Users/Shared`, for the reason
/// `PlanWebViewGuardTests.fixturesFolder` gives.
@MainActor
final class CoverageWebViewGuardTests: XCTestCase {

    // MARK: - Stored properties

    nonisolated(unsafe) private var root: URL!

    static let fixturesFolder: URL = URL(fileURLWithPath: "/Users/Shared/plantoir-coverage-guard-tests", isDirectory: true)

    // MARK: - Functions

    override func setUpWithError() throws {
        root = CoverageWebViewGuardTests.fixturesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        let shared: URL = root.deletingLastPathComponent()
        let left: [String] = (try? FileManager.default.contentsOfDirectory(atPath: shared.path)) ?? []
        if left.isEmpty {
            try? FileManager.default.removeItem(at: shared)
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

    /// The `.coverage-tab` folder of a section's built output.
    private var coverageFolder: URL {
        return root.appendingPathComponent("builds/ICS3U/section1/.coverage-tab", isDirectory: true)
    }

    private func writePage(_ html: String) throws -> URL {
        let page: URL = coverageFolder.appendingPathComponent("map-20261112T190405Z-ab12cd34.html")
        try FileManager.default.createDirectory(at: coverageFolder, withIntermediateDirectories: true)
        try html.write(to: page, atomically: true, encoding: .utf8)
        return page
    }

    private func writePicture(at url: URL, side: Int) throws {
        let image: NSBitmapImageRep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data: Data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func readyController(handed: @escaping (URL) -> Void = { (_: URL) in }) -> PlanWebController {
        let controller: PlanWebController = PlanWebController.forCoverage(handToTheApp: handed)
        let ready: Bool = runUntil(timeout: 10) {
            return controller.rulesAreInstalled || controller.couldNotShow
        }
        XCTAssertTrue(ready, "the rule list was neither installed nor refused")
        return controller
    }

    private func evaluate(_ script: String, in webView: WKWebView) -> String? {
        var answer: String? = nil
        var finished: Bool = false
        webView.evaluateJavaScript(script) { (result: Any?, _: Error?) in
            if let result {
                answer = "\(result)"
            }
            finished = true
        }
        _ = runUntil(timeout: 5) {
            return finished
        }
        return answer
    }

    private func waitForTheLoad(_ webView: WKWebView) -> Bool {
        return runUntil(timeout: 10) {
            return !webView.isLoading && evaluate("document.readyState", in: webView) == "complete"
        }
    }

    // MARK: - Tests

    func testTheRulesCompileUnderTheCoverageTabsOwnName() {
        let controller: PlanWebController = readyController()
        XCTAssertTrue(controller.rulesAreInstalled)
        XCTAssertFalse(controller.couldNotShow)
        XCTAssertNotEqual(PlanWebController.coverageRulesIdentifier, PlanWebController.rulesIdentifier,
                          "neither tab compiles over the other's list")
    }

    func testTheMapReachesNothingOnTheNetwork() throws {
        let listener: ConnectionCounter = try ConnectionCounter()
        defer {
            listener.close()
        }
        let base: String = "http://127.0.0.1:\(listener.port)"
        let page: URL = try writePage("""
            <!doctype html><html><head><title>map</title>
            <link rel="stylesheet" href="\(base)/sheet.css">
            <style>@import url("\(base)/import.css"); body { background: url("\(base)/background.png"); }</style>
            </head><body><p>map</p><img src="\(base)/picture.png"><iframe src="\(base)/frame.html"></iframe>
            </body></html>
            """)
        let controller: PlanWebController = readyController()
        controller.show(page: page, readingOnlyInside: coverageFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView), "the map loaded")
        listener.acceptWaiting()
        XCTAssertEqual(listener.connections, 0, "the map reached the network")
    }

    func testTheMapRunsNoScript() throws {
        let page: URL = try writePage("""
            <!doctype html><html><head><title>map</title>
            <script>document.title = "a script ran";</script></head>
            <body onload="document.title = 'an onload ran'"><p>map</p></body></html>
            """)
        let controller: PlanWebController = readyController()
        controller.show(page: page, readingOnlyInside: coverageFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView))
        XCTAssertEqual(controller.webView.title, "map", "a page script ran")
    }

    func testTheMapCannotShowAFileOutsideItsFolder() throws {
        let outside: URL = root.appendingPathComponent("builds/ICS3U/section1/public/outside.png")
        let inside: URL = coverageFolder.appendingPathComponent("inside.png")
        try writePicture(at: outside, side: 9)
        try writePicture(at: inside, side: 7)
        let page: URL = try writePage("""
            <!doctype html><html><head><title>map</title></head><body>
            <img id="inside" src="inside.png"><img id="outside" src="../public/outside.png">
            </body></html>
            """)
        let controller: PlanWebController = readyController()
        controller.show(page: page, readingOnlyInside: coverageFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView))
        XCTAssertEqual(evaluate("String(document.getElementById('inside').naturalWidth)", in: controller.webView), "7",
                       "a picture inside the map's folder shows")
        XCTAssertEqual(evaluate("String(document.getElementById('outside').naturalWidth)", in: controller.webView), "0",
                       "the built site's picture beside the folder showed")
    }

    /// A click on a code reaches the app with the link; the same link as a
    /// page's own refresh does not, and neither does a web link.
    func testAClickOnACodeIsHandedToTheAppAndARefreshIsNot() throws {
        let link: String = "plantoir-coverage:open/20261112T190405Z-ab12cd34/0/A1.1"
        let page: URL = try writePage("""
            <!doctype html><html><head><title>map</title></head><body>
            <a id="code" href="\(link)">A1.1</a>
            <a id="web" href="https://example.com/">web</a>
            </body></html>
            """)
        var handed: [String] = []
        let controller: PlanWebController = readyController { (url: URL) in
            handed.append(url.absoluteString)
        }
        var openedOutside: [String] = []
        controller.navigationGuard.openOutside = { (url: URL) in
            openedOutside.append(url.absoluteString)
        }
        controller.show(page: page, readingOnlyInside: coverageFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView))

        // The app's own script clicks, as a teacher's click arrives
        // (708 implementation review L1: it reaches the delegate as a link
        // click). Page scripts are off; this is the app's.
        _ = evaluate("document.getElementById('code').click(); 'clicked'", in: controller.webView)
        XCTAssertTrue(runUntil(timeout: 5) { handed == [link] }, "the click on a code was not handed over: \(handed)")
        _ = evaluate("document.getElementById('web').click(); 'clicked'", in: controller.webView)
        // Proving that nothing happened needs a window to watch it in: a
        // second of the run loop, bounded, is that window.
        _ = runUntil(timeout: 1) { !openedOutside.isEmpty || handed.count > 1 }
        XCTAssertEqual(openedOutside, [], "a web link from the map opened outside")
        XCTAssertEqual(handed, [link], "a web link was handed to the app")
        XCTAssertEqual(controller.webView.url?.lastPathComponent, page.lastPathComponent, "the map stayed where it was")

        // A page sending itself to a code without a click.
        let refreshing: URL = try writePage("""
            <!doctype html><html><head><title>map</title>
            <meta http-equiv="refresh" content="0; url=\(link)"></head><body><p>map</p></body></html>
            """)
        controller.show(page: refreshing, readingOnlyInside: coverageFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView))
        _ = runUntil(timeout: 2) { handed.count > 1 }
        XCTAssertEqual(handed, [link], "a page's own refresh was handed to the app")
    }
}
