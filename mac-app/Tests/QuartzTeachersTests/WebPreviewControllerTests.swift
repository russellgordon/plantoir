import WebKit
import XCTest
@testable import QuartzTeachers

final class WebPreviewControllerTests: XCTestCase {

    // MARK: - Stored properties

    /// How long a load may take to reach WebKit before the test says it
    /// never did: a hang guard, never a settling time (#1046).
    static let longestWaitForAHandOff: TimeInterval = 60

    // MARK: - Functions

    @MainActor
    func testFreshControllerHasNoHistoryAndGesturesEnabled() {
        let controller: WebPreviewController = WebPreviewController()
        XCTAssertFalse(controller.canGoBack)
        XCTAssertFalse(controller.canGoForward)
        XCTAssertTrue(controller.webView.allowsBackForwardNavigationGestures, "Trackpad swipe navigation should be enabled")
    }

    @MainActor
    func testLoadIfNeededIgnoresRepeatedRequestsForTheSameURL() {
        let controller: WebPreviewController = WebPreviewController()
        let url: URL = URL(string: "http://localhost:8081/")!
        controller.loadIfNeeded(url)
        let firstNavigationURL: URL? = controller.webView.url
        // A second identical request must not restart the load (which
        // would interrupt a teacher's navigation on SwiftUI updates).
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.webView.url, firstNavigationURL)
    }

    /// The trap this guards was watched happening: between a stop and a
    /// restart, a stray SwiftUI update re-requested the OLD site — and the
    /// fresh build, arriving at the SAME address because a section keeps its
    /// port, then looked "already loaded" to `loadIfNeeded`, which skipped.
    /// The teacher kept the page from before their change with no reload
    /// coming. `showFreshBuild` must start a load anyway.
    ///
    /// Judged twice (#1046): by the loads the controller DECIDES on,
    /// counted the moment each is decided, and by the loads it HANDS to
    /// WebKit, which happens only after the website data store has emptied
    /// its caches in WebKit's own process. The test awaits each hand-off
    /// itself: the controller calls `whenALoadIsHandedToWebKit` where
    /// `webView.load` returns, and that call fulfils the expectation. The
    /// test used to wait, on a fixed six seconds, for WebKit to begin each
    /// navigation, and with another build running on the same Mac the
    /// round trip once took longer. The bound below is not a settling
    /// time: it only ends a test whose hand-off never comes.
    @MainActor
    func testShowFreshBuildLoadsEvenWhenTheAddressWasAlreadyRequested() {
        let controller: WebPreviewController = WebPreviewController()
        let url: URL = URL(string: "http://127.0.0.1:8081/")!

        // The phantom load that re-arms the last-requested address.
        let firstHandOff: XCTestExpectation = expectation(description: "the first load is handed to WebKit")
        controller.whenALoadIsHandedToWebKit = {
            firstHandOff.fulfill()
        }
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 1, "the first request for an address did not load it")
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 1, "a repeated request for the same address loaded it again")
        // WebKit empties its caches and calls back on a later turn, so no
        // load may have reached WebKit yet: one that has went ahead of the
        // emptying (#1046).
        XCTAssertEqual(controller.appLoadsHandedToWebKit, 0, "the first load reached WebKit before the caches were emptied")
        wait(for: [firstHandOff], timeout: WebPreviewControllerTests.longestWaitForAHandOff)
        XCTAssertEqual(controller.appLoadsHandedToWebKit, 1, "the first load was not handed to WebKit once")

        let freshHandOff: XCTestExpectation = expectation(description: "showFreshBuild's load is handed to WebKit")
        controller.whenALoadIsHandedToWebKit = {
            freshHandOff.fulfill()
        }
        controller.showFreshBuild(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 2, "showFreshBuild did not load an address that was already requested")
        XCTAssertEqual(controller.appLoadsHandedToWebKit, 1, "showFreshBuild's load reached WebKit before the caches were emptied")
        wait(for: [freshHandOff], timeout: WebPreviewControllerTests.longestWaitForAHandOff)
        XCTAssertEqual(controller.appLoadsHandedToWebKit, 2, "showFreshBuild's load was not handed to WebKit once")

        // And the mounting view's own loadIfNeeded is then the no-op, so
        // this stays a single load per rebuild.
        controller.whenALoadIsHandedToWebKit = {
            XCTFail("loadIfNeeded after showFreshBuild handed WebKit another load")
        }
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 2, "loadIfNeeded after showFreshBuild must not start another load")
    }
}
