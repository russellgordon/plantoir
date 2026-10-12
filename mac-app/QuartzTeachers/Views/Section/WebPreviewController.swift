import Foundation
import Observation
import WebKit

/// Owns the preview's web view and exposes its navigation state to
/// SwiftUI, so toolbar Back/Forward/Reload buttons can drive it and
/// enable/disable themselves correctly.
@Observable
class WebPreviewController {

    // MARK: - Stored properties

    /// The web view itself (created once and reused across page loads).
    let webView: WKWebView

    /// Mirrors the web view's navigation state for SwiftUI.
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// The URL most recently asked for, so SwiftUI updates never reload
    /// a page the user has navigated away from.
    private var lastRequestedURL: URL?

    /// KVO subscriptions watching the web view's navigation state.
    private var observations: [NSKeyValueObservation] = []

    /// Print and new-window links, handed to the web browser (#454).
    let browserHandoff: PreviewBrowserHandoff

    /// The last address the TEACHER navigated to in the pane (#504) — a
    /// click, Back, Forward, a swipe — and how many such navigations there
    /// have been, so a view can act on each one even when two land on the
    /// same address. The app's own loads never move either
    /// (`PreviewNavigationLedger`).
    var teacherPage: URL?
    var teacherNavigations: Int = 0

    /// Whether an app load is under way, and which navigation it is.
    @ObservationIgnored private var ledger: PreviewNavigationLedger = PreviewNavigationLedger()
    @ObservationIgnored private var appNavigation: WKNavigation?

    /// Tells this controller when a navigation ends (#504).
    let navigationWatcher: PreviewNavigationWatcher

    // MARK: - Initializer

    init() {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        let handoff: PreviewBrowserHandoff = PreviewBrowserHandoff()
        configuration.userContentController.add(handoff, name: PreviewBrowserHandoff.messageName)
        let webView: WKWebView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = handoff
        let watcher: PreviewNavigationWatcher = PreviewNavigationWatcher()
        webView.navigationDelegate = watcher
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityIdentifier("previewWebViewNative")
        self.webView = webView
        self.browserHandoff = handoff
        self.navigationWatcher = watcher

        let backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.canGoBack = self.webView.canGoBack
            }
        }
        let forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.canGoForward = self.webView.canGoForward
            }
        }
        // The address, for the page last viewed (#504). Measured (504 plan
        // review M-a, an offscreen WKWebView on a built Quartz site): this
        // fires for Quartz's own in-page navigation — a link click is a
        // pushState with no `didFinish` — and for Back and Forward. Handled
        // at once when it arrives on the main thread, as WebKit delivers it,
        // so it is judged against the ledger as it stands at that moment
        // rather than after an app load's end has already been noted.
        let addressObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    self.addressChanged(to: self.webView.url)
                }
            } else {
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.addressChanged(to: self.webView.url)
                }
            }
        }
        observations.append(backObservation)
        observations.append(forwardObservation)
        observations.append(addressObservation)
        watcher.whenEnded = { [weak self] navigation in
            self?.navigationEnded(navigation)
        }
    }

    // MARK: - Functions

    /// Loads the URL if it is a new request (SwiftUI may call repeatedly).
    ///
    /// **The "if needed" is about SwiftUI, not about the site.** This is
    /// called from `updateNSView`, which SwiftUI may run at any moment for
    /// reasons of its own; without the check, a teacher who had clicked
    /// through to a lesson would be thrown back to the front page on the next
    /// redraw.
    ///
    /// What it must NOT mean is "this address has been seen before, so there
    /// is nothing new there". A preview keeps its port across a stop and a
    /// start, so a rebuilt site has exactly the same address as the old one —
    /// and comparing addresses meant the web view kept showing the pages it
    /// had, silently, no matter how many times the site was rebuilt. Whoever
    /// stops a preview now calls `forgetLoadedPage()`, which is the honest
    /// way to say "whatever is on screen is no longer the truth".
    ///
    /// The request also ignores WebKit's own cache. Everything here is served
    /// from localhost and rebuilt constantly, so a cached copy is never the
    /// one wanted — and a cache hit looks exactly like the bug above.
    func loadIfNeeded(_ url: URL) {
        if url == lastRequestedURL {
            return
        }
        lastRequestedURL = url
        loadIgnoringEverythingCached(url)
    }

    /// Empty WebKit's caches, then load.
    ///
    /// `cachePolicy` on the request is not enough, and this is why: a Quartz
    /// site is a single-page app. The policy governs the MAIN request — the
    /// HTML — while the scripts, the styles and the content the page fetches
    /// for itself all come from whatever WebKit already has. So a preview
    /// could be handed a freshly built index.html and still assemble last
    /// week's page out of its own cache, which is precisely what "only a
    /// manual refresh shows the new content" means.
    ///
    /// Emptying the caches costs nothing worth keeping. Everything here is
    /// served from localhost, by a server that rebuilds the whole site every
    /// time it starts; there is no slow network to spare and no version of
    /// these files worth holding on to.
    ///
    /// Only the CACHES are cleared — not local storage or cookies — so the
    /// preview keeps the things a teacher would notice losing, such as the
    /// site's own light or dark setting.
    private func loadIgnoringEverythingCached(_ url: URL) {
        // An app load: nothing it lands on is the teacher's choice (#504).
        // The previous app navigation is forgotten HERE, not when this one
        // is handed to WebKit after the caches are emptied: an earlier load
        // ending in between must not end this one.
        ledger.appLoadBegan()
        appNavigation = nil
        let caches: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
        ]
        URLCache.shared.removeAllCachedResponses()
        webView.configuration.websiteDataStore.removeData(
            ofTypes: caches,
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { [weak self] in
            guard let self else {
                return
            }
            self.appNavigation = self.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    /// Says that what the web view is showing is no longer current, so the
    /// next request for the same address loads it again.
    func forgetLoadedPage() {
        lastRequestedURL = nil
    }

    /// A build has just finished, so whatever the web view is showing —
    /// whatever it is — predates that build. Always loads.
    ///
    /// This exists because `forgetLoadedPage()` alone was not enough, and the
    /// gap was watched happening: between a stop forgetting the page and the
    /// restarted preview coming up, SwiftUI ran one more update on the
    /// outgoing web view, which re-loaded the OLD server's site and quietly
    /// re-armed `lastRequestedURL`. When the fresh build was ready — at the
    /// same address, because a section keeps its port — `loadIfNeeded`
    /// compared the URLs, found them equal, and skipped. The teacher was left
    /// looking at the page from before their change, with no reload coming.
    ///
    /// Encoding "must reload" as cleared state can be undone by any stray
    /// load in that window. Saying it as a call cannot. Setting
    /// `lastRequestedURL` here also makes the view's own `loadIfNeeded` a
    /// no-op when it mounts a moment later, so this stays a single load —
    /// the unconditional-reload flicker is not reintroduced.
    func showFreshBuild(_ url: URL) {
        lastRequestedURL = url
        loadIgnoringEverythingCached(url)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    /// Reload, going past the cache. The Reload button exists precisely
    /// because a teacher thinks the page is out of date, so serving them the
    /// copy they are already unhappy with is the one useless answer.
    func reload() {
        // Same treatment as a first load: a teacher pressing Reload has
        // already decided that what they are looking at is wrong, and
        // `reloadFromOrigin` alone leaves the page's own fetches free to come
        // back out of the cache.
        if let url = lastRequestedURL {
            loadIgnoringEverythingCached(url)
            return
        }
        ledger.appLoadBegan()
        appNavigation = webView.reloadFromOrigin()
    }

    /// The web view's address changed. Counted as the teacher's only when no
    /// app load is under way (#504).
    func addressChanged(to address: URL?) {
        if !ledger.changeIsTheTeachers() {
            return
        }
        teacherPage = address
        teacherNavigations += 1
    }

    /// A navigation committed, finished or failed. When it is the app's own
    /// load, the address changes after it are the teacher's again. A
    /// teacher's click that interrupts an app load ends that load as failed,
    /// so the ledger is never left waiting.
    func navigationEnded(_ navigation: WKNavigation?) {
        guard let navigation, let appNavigation, navigation === appNavigation else {
            return
        }
        appLoadEnded()
    }

    /// Marks the app's load as over. Called by `navigationEnded`, and by a
    /// test standing in for WebKit.
    func appLoadEnded() {
        ledger.appLoadEnded()
        appNavigation = nil
    }

    /// Whether an app load is under way — for tests.
    var appLoadIsUnderWay: Bool {
        return ledger.appLoadIsUnderWay
    }
}

/// Tells the preview's controller when WebKit ends a navigation — COMMITTED,
/// finished, failed, or failed before it began (#504). Implements nothing
/// else, so
/// every other navigation decision stays WebKit's default, as it was before
/// this delegate existed (no policy method is implemented: everything is
/// allowed, exactly as with no delegate at all).
///
/// **Commit ends an app load, not only the load event** (implementation
/// review, 1, measured). didFinish waits for the window's `load` event, and
/// every built page pulls KaTeX and fonts from CDNs in its head: with one
/// resource answering after 8 s, a teacher's click at 2 s was not
/// remembered. Server redirects happen BEFORE commit, so a redirected page
/// still ends correctly, and no app load's address was ever seen to change
/// after its commit.
///
/// An NSObject of its own because WebKit's delegate protocol needs one, and
/// so the web view's (weak) reference to its delegate is to something the
/// controller owns.
final class PreviewNavigationWatcher: NSObject, WKNavigationDelegate {

    // MARK: - Stored properties

    /// Told which navigation ended.
    var whenEnded: ((WKNavigation?) -> Void)?

    // MARK: - Functions

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        whenEnded?(navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        whenEnded?(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        whenEnded?(navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        whenEnded?(navigation)
    }
}
