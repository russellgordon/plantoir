import AppKit
import Observation
import SwiftUI
import WebKit

/// Owns the Planning tab's web view (#708) and tells SwiftUI whether Back
/// and Forward can go anywhere.
///
/// **A plan is content Plantoir did not write**: an outside assistant wrote
/// it, so the view is set up to show local pages and nothing else. Three
/// guards, each doing one job (documentation/09-mac-app.md, "What stops a
/// plan page reading other files"):
///
/// 1. `loadFileURL(_:allowingReadAccessTo:)` names the PLANNING folder, never
///    the course: WebKit's page process is given read access to that folder
///    alone, so a picture or a frame pointing at `../../course_config.json`
///    loads nothing.
/// 2. `PlanNavigation.decide` on every navigation, in every frame: a page
///    may open another file in the folder; a CLICK on a web or email link
///    goes to the teacher's own browser or mail app; anything else is
///    refused.
/// 3. No JavaScript (the template has none), no stored website data, and a
///    content rule list that blocks every load that is not a `file:` one,
///    so a page cannot reach the network for a font, a picture or anything
///    else.
///
/// Guard 2's "only on a click" rests on guard 3: measured (708
/// implementation review L1), a script's `click()` on a link reaches the
/// delegate as a link click. Turning page scripts on would reopen that.
///
/// Each guard is proved with no window by `PlanWebViewGuardTests`.
@MainActor
@Observable
final class PlanWebController {

    // MARK: - Stored properties

    /// The web view, made once and kept while the course's page is open.
    @ObservationIgnored let webView: WKWebView

    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// The rule list is compiled before the first page loads; until then a
    /// page asked for waits here. Nil once nothing waits.
    @ObservationIgnored private var waitingPage: URL?

    @ObservationIgnored private(set) var rulesAreInstalled: Bool = false

    /// True when the rule list could not be made, so no page will ever be
    /// shown: the tab says so instead of staying blank.
    var couldNotShow: Bool = false

    /// The page the web view is on, as it last changed: what the unit popup
    /// follows when a link inside the plan leads to another unit (708
    /// implementation review L4).
    var currentPage: URL?

    /// Told once when the rule list could not be made, for the trail.
    @ObservationIgnored var whenItCannotShow: (() -> Void)?

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// Every navigation's decision, and links asking for a new window.
    @ObservationIgnored let navigationGuard: PlanNavigationGuard

    /// `WKContentRuleList` source: block everything, then let `file:` loads
    /// through.
    static let localOnlyRules: String = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},\
        {"trigger":{"url-filter":"^file:"},"action":{"type":"ignore-previous-rules"}}]
        """

    static let rulesIdentifier: String = "PlantoirPlanningTabLocalFilesOnly"

    /// The rule list this controller compiles: `localOnlyRules` in the app;
    /// a test may hand it another to prove what a broken one does.
    @ObservationIgnored private let rules: String

    // MARK: - Initializer

    init(rules: String = PlanWebController.localOnlyRules) {
        self.rules = rules
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        // Off: the template needs none, and guard 2's "a click only" holds
        // only while a page cannot click a link itself (review L1).
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView: WKWebView = WKWebView(frame: .zero, configuration: configuration)
        let navigationGuard: PlanNavigationGuard = PlanNavigationGuard()
        webView.navigationDelegate = navigationGuard
        webView.uiDelegate = navigationGuard
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityIdentifier("planningWebViewNative")
        self.webView = webView
        self.navigationGuard = navigationGuard

        let backObservation: NSKeyValueObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.canGoBack = self.webView.canGoBack
            }
        }
        let forwardObservation: NSKeyValueObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.canGoForward = self.webView.canGoForward
            }
        }
        let pageObservation: NSKeyValueObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if self.currentPage != self.webView.url {
                    self.currentPage = self.webView.url
                }
            }
        }
        observations.append(backObservation)
        observations.append(forwardObservation)
        observations.append(pageObservation)

        Task { @MainActor [weak self] in
            await self?.installTheRules()
        }
    }

    // MARK: - Functions

    /// Shows `page`, reading only inside `planningFolder`.
    func show(page: URL, planningFolder: URL) {
        navigationGuard.planningFolder = planningFolder
        if !rulesAreInstalled {
            waitingPage = page
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: planningFolder)
    }

    /// Loads the page on screen again, as it is on disk now.
    func reload() {
        if !rulesAreInstalled {
            return
        }
        if webView.url == nil {
            return
        }
        webView.reloadFromOrigin()
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    /// No page will be shown: say so on screen and on the trail.
    private func giveUp() {
        waitingPage = nil
        couldNotShow = true
        whenItCannotShow?()
    }

    /// Compiles the local-only rule list, adds it, and loads any page that
    /// was waiting. If it cannot be compiled no page is ever loaded: a plan
    /// shown without the rule could reach the network, so the tab stays
    /// blank rather than open (the rule is a fixed string, so this is not
    /// expected to happen).
    private func installTheRules() async {
        let store: WKContentRuleListStore? = WKContentRuleListStore.default()
        do {
            guard let store,
                  let list = try await store.compileContentRuleList(
                      forIdentifier: PlanWebController.rulesIdentifier,
                      encodedContentRuleList: rules
                  ) else {
                AppLog.interface.error("the Planning tab's local-only rule list could not be made")
                giveUp()
                return
            }
            webView.configuration.userContentController.add(list)
        } catch {
            AppLog.interface.error("the Planning tab's local-only rule list could not be made: \(error.localizedDescription, privacy: .public)")
            giveUp()
            return
        }
        rulesAreInstalled = true
        if let page = waitingPage, let folder = navigationGuard.planningFolder {
            waitingPage = nil
            webView.loadFileURL(page, allowingReadAccessTo: folder)
        }
    }
}

/// The web view's navigation and window delegate, applying
/// `PlanNavigation.decide`. An NSObject of its own because WebKit's
/// protocols need one, and so the web view's weak reference is to something
/// the controller owns.
@MainActor
final class PlanNavigationGuard: NSObject, WKNavigationDelegate, WKUIDelegate {

    // MARK: - Stored properties

    /// The folder the plan's pages may read; nil refuses everything.
    var planningFolder: URL?

    /// Opens a link outside Plantoir; replaceable so a test can watch.
    var openOutside: (URL) -> Void = { (url: URL) in
        NSWorkspace.shared.open(url)
    }

    // MARK: - Functions

    /// Acts on one decision. Answers whether the navigation may go ahead
    /// where it was going.
    func act(on decision: PlanNavigation.Decision, url: URL, in webView: WKWebView) -> Bool {
        switch decision {
        case .load:
            return true
        case .loadHere:
            if let planningFolder {
                webView.loadFileURL(url, allowingReadAccessTo: planningFolder)
            }
            return false
        case .openOutside:
            openOutside(url)
            return false
        case .refuse:
            return false
        }
    }

    func decision(for navigationAction: WKNavigationAction) -> PlanNavigation.Decision {
        guard let url = navigationAction.request.url, let planningFolder else {
            return .refuse
        }
        return PlanNavigation.decide(
            url: url,
            isNewWindow: navigationAction.targetFrame == nil,
            byALinkClick: navigationAction.navigationType == .linkActivated,
            planningFolder: planningFolder
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let decision: PlanNavigation.Decision = decision(for: navigationAction)
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if act(on: decision, url: url, in: webView) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    /// A link that asks for a new window (`target="_blank"`, a plan's PDFs
    /// among them), when WebKit asks for the window rather than first for a
    /// decision: the same rule, and never a second window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            _ = act(on: decision(for: navigationAction), url: url, in: webView)
        }
        return nil
    }
}

/// The Planning tab's web view, taking exactly the room it is offered.
struct PlanWebView: NSViewRepresentable {

    // MARK: - Stored properties

    let controller: PlanWebController

    // MARK: - Functions

    func makeNSView(context: Context) -> WKWebView {
        return controller.webView
    }

    /// Never the document's height (see `WebPreviewView`).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        return CGSize(width: proposal.width ?? 600, height: proposal.height ?? 400)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
    }
}
