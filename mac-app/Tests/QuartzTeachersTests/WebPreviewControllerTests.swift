import WebKit
import XCTest
@testable import QuartzTeachers

final class WebPreviewControllerTests: XCTestCase {

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
    /// Judged by the loads the controller ASKS for, counted as each is
    /// asked (#1046). The test used to wait, on a fixed six seconds, for
    /// WebKit to begin each navigation; a load reaches WebKit only after the
    /// website data store has emptied its caches in WebKit's own process,
    /// and with another build running on the same Mac that round trip once
    /// took longer than the six seconds, so the test failed with nothing
    /// wrong in the preview. Whether to load is this controller's decision
    /// alone, and the count says it the moment it is made.
    @MainActor
    func testShowFreshBuildLoadsEvenWhenTheAddressWasAlreadyRequested() {
        let controller: WebPreviewController = WebPreviewController()
        let url: URL = URL(string: "http://127.0.0.1:8081/")!

        // The phantom load that re-arms the last-requested address.
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 1, "the first request for an address did not load it")
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 1, "a repeated request for the same address loaded it again")

        controller.showFreshBuild(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 2, "showFreshBuild did not load an address that was already requested")

        // And the mounting view's own loadIfNeeded is then the no-op, so
        // this stays a single load per rebuild.
        controller.loadIfNeeded(url)
        XCTAssertEqual(controller.appLoadsAskedFor, 2, "loadIfNeeded after showFreshBuild must not start another load")
    }
}
