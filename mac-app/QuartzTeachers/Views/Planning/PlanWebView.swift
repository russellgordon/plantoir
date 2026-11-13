import AppKit
import Observation
import SwiftUI
import WebKit

/// Owns the Planning tab's web view (#708), and since #793 the Coverage
/// tab's too, and tells SwiftUI whether Back and Forward can go anywhere.
///
/// One class for both, parameterised rather than copied (793b's brief): the
/// rule list, its compile, the configuration and the delegate are shared, so
/// a fix to the network block reaches both tabs. Each tab names its own rule
/// list identifier, its own navigation rule (`PlanNavigation.decide` for a
/// plan, `CoverageNavigation.decide` for the map) and the folder its page
/// may read. `PlanWebController()` is the Planning tab's, as it always was;
/// `PlanWebController.forCoverage` is the Coverage tab's.
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

    /// The Coverage tab's own identifier for the same list, so neither tab
    /// compiles over the other's (#793).
    static let coverageRulesIdentifier: String = "PlantoirCoverageTabLocalFilesOnly"

    /// The rule list this controller compiles: `localOnlyRules` in the app;
    /// a test may hand it another to prove what a broken one does.
    @ObservationIgnored private let rules: String

    /// The name the list is kept under.
    @ObservationIgnored private let identifier: String

    // MARK: - Initializer

    /// The Planning tab's web view.
    convenience init(rules: String = PlanWebController.localOnlyRules) {
        self.init(
            rules: rules,
            rulesIdentifier: PlanWebController.rulesIdentifier,
            accessibilityIdentifier: "planningWebViewNative",
            decide: PlanNavigation.decide
        )
    }

    /// A web view that shows local pages from one folder and nothing else,
    /// deciding each navigation with `decide` (url, a new window, a click,
    /// the folder).
    init(
        rules: String,
        rulesIdentifier: String,
        accessibilityIdentifier: String,
        decide: @escaping (URL, Bool, Bool, URL) -> PlanNavigation.Decision
    ) {
        self.rules = rules
        self.identifier = rulesIdentifier
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        // Off: the template needs none, and guard 2's "a click only" holds
        // only while a page cannot click a link itself (review L1).
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView: WKWebView = WKWebView(frame: .zero, configuration: configuration)
        let navigationGuard: PlanNavigationGuard = PlanNavigationGuard()
        navigationGuard.decide = decide
        webView.navigationDelegate = navigationGuard
        webView.uiDelegate = navigationGuard
        webView.allowsBackForwardNavigationGestures = true
        webView.setAccessibilityIdentifier(accessibilityIdentifier)
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

    /// The Coverage tab's web view (#793): the same guards, the map's own
    /// rule list identifier and navigation rule, and `handToTheApp` told of
    /// every click on a code.
    static func forCoverage(
        rules: String = PlanWebController.localOnlyRules,
        handToTheApp: @escaping (URL) -> Void
    ) -> PlanWebController {
        let controller: PlanWebController = PlanWebController(
            rules: rules,
            rulesIdentifier: PlanWebController.coverageRulesIdentifier,
            accessibilityIdentifier: "coverageWebViewNative",
            decide: { (url: URL, isNewWindow: Bool, byALinkClick: Bool, folder: URL) -> PlanNavigation.Decision in
                return CoverageNavigation.decide(
                    url: url, isNewWindow: isNewWindow, byALinkClick: byALinkClick, coverageFolder: folder
                )
            }
        )
        controller.navigationGuard.handToTheApp = handToTheApp
        return controller
    }

    /// Shows `page`, reading only inside `planningFolder`.
    func show(page: URL, planningFolder: URL) {
        show(page: page, readingOnlyInside: planningFolder)
    }

    /// Shows `page`, reading only inside `folder`.
    func show(page: URL, readingOnlyInside folder: URL) {
        navigationGuard.planningFolder = folder
        if !rulesAreInstalled {
            waitingPage = page
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: folder)
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
                      forIdentifier: identifier,
                      encodedContentRuleList: rules
                  ) else {
                AppLog.interface.error("the local-only rule list \(self.identifier, privacy: .public) could not be made")
                giveUp()
                return
            }
            webView.configuration.userContentController.add(list)
        } catch {
            AppLog.interface.error("the local-only rule list \(self.identifier, privacy: .public) could not be made: \(error.localizedDescription, privacy: .public)")
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

    /// The folder the plan's pages may read; nil refuses everything. The
    /// map's folder on the Coverage tab (#793).
    var planningFolder: URL?

    /// The navigation rule: a plan's, or the map's.
    var decide: (URL, Bool, Bool, URL) -> PlanNavigation.Decision = PlanNavigation.decide

    /// Opens a link outside Plantoir; replaceable so a test can watch.
    var openOutside: (URL) -> Void = { (url: URL) in
        NSWorkspace.shared.open(url)
    }

    /// Told of a navigation `decide` hands to the app (a click on a code in
    /// the Coverage tab's map); a plan never reaches it.
    var handToTheApp: (URL) -> Void = { (_: URL) in
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
        case .handToTheApp:
            handToTheApp(url)
            return false
        }
    }

    func decision(for navigationAction: WKNavigationAction) -> PlanNavigation.Decision {
        guard let url = navigationAction.request.url, let planningFolder else {
            return .refuse
        }
        return decide(
            url,
            navigationAction.targetFrame == nil,
            navigationAction.navigationType == .linkActivated,
            planningFolder
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

/// Hands a page of a plan to the Mac's default web browser (#803, Open in
/// Browser), as a `file:` address. The DEFAULT BROWSER is asked by name,
/// the app that opens `https:` links, rather than whatever app opens the
/// file's type: an `.html` file can belong to a text editor on a teacher's
/// Mac, and a PDF to Preview, and the button says "Browser". With no browser
/// set, the file is opened as the Mac opens it.
///
/// `PlanInTheBrowser.pageToOpen` has already refused anything outside the
/// course's planning folder; this only opens.
enum PlanBrowserOpener {

    // MARK: - Stored properties

    /// Any web address: only the app that would open it is asked for.
    static let browserProbe: URL? = URL(string: "https://example.com/")

    // MARK: - Functions

    static func openInTheDefaultBrowser(_ page: URL, done: @escaping @MainActor (Bool) -> Void) {
        guard let probe = browserProbe,
              let browser = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
            done(NSWorkspace.shared.open(page))
            return
        }
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([page], withApplicationAt: browser, configuration: configuration) {
            (_: NSRunningApplication?, error: Error?) in
            let opened: Bool = error == nil
            let reason: String = error?.localizedDescription ?? ""
            Task { @MainActor in
                if !opened {
                    AppLog.interface.error("the Planning tab could not open a page in the browser: \(reason, privacy: .public)")
                }
                done(opened)
            }
        }
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
