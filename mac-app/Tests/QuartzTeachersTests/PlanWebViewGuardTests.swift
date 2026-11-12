import AppKit
import Darwin
import WebKit
import XCTest
@testable import QuartzTeachers

/// The Planning tab's web view keeps a plan's pages to the planning folder
/// (#708, `shared-rules.json` → `unitPlanning.tab.whatAPageMayRead`), proved
/// by RUNNING the real `PlanWebController` with no window, as the 708
/// implementation review did (M3), rather than by reading its source.
///
/// To see each fail on the old or a broken guard:
/// - network: make `PlanWebController.localOnlyRules` let everything through
///   (change its first rule's `"block"` to `"ignore-previous-rules"`), and
///   `testAPlanPageReachesNothingOnTheNetwork` sees connections;
/// - scripts: delete `allowsContentJavaScript = false` in its initializer,
///   and `testAPlanPageRunsNoScript` sees the title change;
/// - read access: pass `planningFolder.deletingLastPathComponent()
///   .deletingLastPathComponent()` (the course) to `loadFileURL` in `show`,
///   and `testAPlanPageCannotShowAFileOutsideThePlanningFolder` sees the
///   picture;
/// - the rule list: `testABrokenRuleListShowsNothingAndSaysSo` hands the
///   controller a list that cannot compile, which is what a bad edit of
///   `localOnlyRules` would be.
///
/// The fixtures live under `/Users/Shared` (`fixturesFolder` says why),
/// and each run removes its own folder.
@MainActor
final class PlanWebViewGuardTests: XCTestCase {

    // MARK: - Stored properties

    nonisolated(unsafe) private var root: URL!

    /// Where the fixtures live: a folder WebKit's page process does not open
    /// by itself, or a picture "outside the planning folder" would load and
    /// prove nothing. MEASURED (macOS 26.6): the process reads
    /// `/private/tmp` and this user's temporary folder (`/var/folders/…/T`,
    /// where `RealHome.forFiles` points under the suite) whatever folder it
    /// was given, so a fixture there loaded the outside picture with the
    /// guard in place; under `/Users/Shared` it did not, and it did once the
    /// guard was widened to the course. Not the teacher's home: the
    /// tripwire (`RealHomeTripwireTests`) keeps the suite out of it.
    static let fixturesFolder: URL = URL(fileURLWithPath: "/Users/Shared/plantoir-plan-guard-tests", isDirectory: true)

    // MARK: - Functions

    override func setUpWithError() throws {
        root = PlanWebViewGuardTests.fixturesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        // The folder the runs share, once no run is left in it.
        let shared: URL = root.deletingLastPathComponent()
        let left: [String] = (try? FileManager.default.contentsOfDirectory(atPath: shared.path)) ?? []
        if left.isEmpty {
            try? FileManager.default.removeItem(at: shared)
        }
    }

    /// Runs the main run loop until `condition` holds or `timeout` passes.
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

    private var planningFolder: URL {
        return root.appendingPathComponent("course/.internal/planning", isDirectory: true)
    }

    private func writePage(_ html: String, at relative: String) throws -> URL {
        let page: URL = planningFolder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try html.write(to: page, atomically: true, encoding: .utf8)
        return page
    }

    /// A small PNG, `side` pixels square.
    private func writePicture(at url: URL, side: Int) throws {
        let image: NSBitmapImageRep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data: Data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A controller with its rule list in, or a skip if WebKit would not
    /// make one here.
    private func readyController(rules: String = PlanWebController.localOnlyRules) throws -> PlanWebController {
        let controller: PlanWebController = PlanWebController(rules: rules)
        let ready: Bool = runUntil(timeout: 10) {
            return controller.rulesAreInstalled || controller.couldNotShow
        }
        XCTAssertTrue(ready, "the rule list was neither installed nor refused")
        return controller
    }

    /// The text a script returns, run by the APP (page scripts are off;
    /// the app's own still run).
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

    func testTheLocalOnlyRulesCompile() throws {
        let controller: PlanWebController = try readyController()
        XCTAssertTrue(controller.rulesAreInstalled, "localOnlyRules did not compile")
        XCTAssertFalse(controller.couldNotShow)
    }

    func testABrokenRuleListShowsNothingAndSaysSo() throws {
        let page: URL = try writePage("<!doctype html><title>plan</title><p>plan</p>", at: "index.html")
        var told: Int = 0
        let controller: PlanWebController = PlanWebController(rules: "[{\"trigger\":")
        controller.whenItCannotShow = {
            told += 1
        }
        controller.show(page: page, planningFolder: planningFolder)
        XCTAssertTrue(runUntil(timeout: 10) { controller.couldNotShow }, "a list that cannot compile is said")
        XCTAssertEqual(told, 1, "and written on the trail once")
        XCTAssertNil(controller.webView.url, "and no page was ever loaded without the block")
    }

    func testAPlanPageReachesNothingOnTheNetwork() throws {
        let listener: ConnectionCounter = try ConnectionCounter()
        defer {
            listener.close()
        }
        let base: String = "http://127.0.0.1:\(listener.port)"
        let html: String = """
            <!doctype html><html><head><title>plan</title>
            <link rel="stylesheet" href="\(base)/sheet.css">
            <link rel="prefetch" href="\(base)/prefetch">
            <link rel="preconnect" href="\(base)">
            <link rel="icon" href="\(base)/icon.png">
            <style>@import url("\(base)/import.css"); @font-face { font-family: F; src: url("\(base)/font.woff2"); }
            body { font-family: F; background: url("\(base)/background.png"); }</style>
            <script src="\(base)/script.js"></script>
            </head><body><p>plan</p>
            <img src="\(base)/picture.png"><img srcset="\(base)/picture-2x.png 2x">
            <iframe src="\(base)/frame.html"></iframe>
            <object data="\(base)/object.pdf"></object>
            <video poster="\(base)/poster.png"></video>
            <a ping="\(base)/ping" href="#here">here</a>
            </body></html>
            """
        let page: URL = try writePage(html, at: "unit/index.html")

        let controller: PlanWebController = try readyController()
        controller.show(page: page, planningFolder: planningFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView), "the plan page loaded")
        listener.acceptWaiting()
        XCTAssertEqual(listener.connections, 0, "a plan page reached the network")

        // Then the probe can see a load when nothing blocks it, so the zero
        // above is a measurement and not a deaf listener.
        let plainConfiguration: WKWebViewConfiguration = WKWebViewConfiguration()
        plainConfiguration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let plain: WKWebView = WKWebView(frame: .zero, configuration: plainConfiguration)
        plain.loadFileURL(page, allowingReadAccessTo: planningFolder)
        XCTAssertTrue(runUntil(timeout: 10) {
            listener.acceptWaiting()
            return listener.connections > 0
        }, "a plain web view reached the listener, so the probe works")
        plain.stopLoading()
    }

    func testAPlanPageRunsNoScript() throws {
        let html: String = """
            <!doctype html><html><head><title>plan</title>
            <script>document.title = "a script ran";</script></head>
            <body onload="document.title = 'an onload ran'"><p>plan</p></body></html>
            """
        let page: URL = try writePage(html, at: "unit/index.html")
        let controller: PlanWebController = try readyController()
        controller.show(page: page, planningFolder: planningFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView))
        XCTAssertEqual(controller.webView.title, "plan", "a page script ran")
    }

    func testAPlanPageCannotShowAFileOutsideThePlanningFolder() throws {
        let outside: URL = root.appendingPathComponent("course/outside.png")
        let inside: URL = planningFolder.appendingPathComponent("unit/inside.png")
        try writePicture(at: outside, side: 9)
        try writePicture(at: inside, side: 7)
        let html: String = """
            <!doctype html><html><head><title>plan</title></head><body>
            <img id="inside" src="inside.png"><img id="outside" src="../../../outside.png">
            </body></html>
            """
        let page: URL = try writePage(html, at: "unit/index.html")
        let controller: PlanWebController = try readyController()
        controller.show(page: page, planningFolder: planningFolder)
        XCTAssertTrue(waitForTheLoad(controller.webView))
        XCTAssertEqual(
            evaluate("String(document.getElementById('inside').naturalWidth)", in: controller.webView), "7",
            "a picture inside the planning folder shows"
        )
        XCTAssertEqual(
            evaluate("String(document.getElementById('outside').naturalWidth)", in: controller.webView), "0",
            "a picture outside the planning folder showed"
        )
    }
}

/// A listener on 127.0.0.1 that counts the connections made to it, polled
/// from the test's own run loop (no queue): enough to say whether a page
/// tried to reach the network.
@MainActor
final class ConnectionCounter {

    // MARK: - Stored properties

    let port: UInt16
    private(set) var connections: Int = 0
    private var socketDescriptor: Int32

    // MARK: - Initializer

    init() throws {
        let descriptor: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        if descriptor < 0 {
            throw XCTSkip("no socket for the listener")
        }
        var address: sockaddr_in = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound: Int32 = withUnsafePointer(to: &address) { (pointer: UnsafePointer<sockaddr_in>) -> Int32 in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { (raw: UnsafePointer<sockaddr>) -> Int32 in
                return bind(descriptor, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 || listen(descriptor, 64) != 0 {
            Darwin.close(descriptor)
            throw XCTSkip("the listener could not bind")
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var chosen: sockaddr_in = sockaddr_in()
        var length: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &chosen) { (pointer: UnsafeMutablePointer<sockaddr_in>) -> Int32 in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { (raw: UnsafeMutablePointer<sockaddr>) -> Int32 in
                return getsockname(descriptor, raw, &length)
            }
        }
        socketDescriptor = descriptor
        port = UInt16(bigEndian: chosen.sin_port)
    }

    // MARK: - Functions

    /// Accepts every connection waiting, counting each, and closes it.
    func acceptWaiting() {
        while true {
            let accepted: Int32 = accept(socketDescriptor, nil, nil)
            if accepted < 0 {
                return
            }
            connections += 1
            Darwin.close(accepted)
        }
    }

    func reset() {
        acceptWaiting()
        connections = 0
    }

    func close() {
        if socketDescriptor >= 0 {
            Darwin.close(socketDescriptor)
            socketDescriptor = -1
        }
    }
}
