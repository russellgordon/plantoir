import AppKit
import Foundation

/// Where a teacher's press of Preview opens the site (#504): the front page,
/// as it always did, or the page they were last looking at in the preview.
///
/// **An app-wide default, and Option gives the other one** (Russell's comment
/// on #504, 2026-10-11). The default is chosen in Plantoir ▸ Settings ▸
/// Preview; holding Option while pressing Preview — or choosing the Option
/// alternate in Section ▸ — does the opposite, and the button and the menu
/// item are TITLED by what will happen, so a teacher reads the outcome
/// before pressing (decision 504-2: "Preview" opens the front page, "Preview
/// at Last Viewed" opens the page left off).
///
/// The rule, the cases and the words are in `contracts/shared-rules.json` →
/// `previewStartPage`; `documentation/09-mac-app.md` → "Opening the preview
/// at the page last viewed (#504)" says what was measured and rejected.
///
/// Persisted raw values are the contract's `setting.values`: never rename a
/// case, or a teacher's saved choice reads as the default.
nonisolated enum PreviewOpensAt: String, CaseIterable, Sendable {

    /// The site's front page — the default, and what Preview always did.
    case frontPage

    /// The page this section's preview last showed, chosen by the teacher.
    case lastViewed

    // MARK: - Computed properties

    /// The other choice: what Option gives.
    var opposite: PreviewOpensAt {
        if self == .frontPage {
            return .lastViewed
        }
        return .frontPage
    }
}

/// The words of #504, in one place. Pinned against
/// `previewStartPage.wording` in the contract (PreviewStartPageTests), so a
/// change here is a change the Windows side is told about.
nonisolated enum PreviewStartPageWording {

    // MARK: - Stored properties

    /// The button and menu item when the preview opens at the front page.
    static let preview: String = "Preview"

    /// The button and menu item when it opens at the page last viewed.
    static let previewAtLastViewed: String = "Preview at Last Viewed"

    /// The button and menu item while a preview is running. Option changes
    /// nothing then.
    static let stopPreview: String = "Stop Preview"

    /// The Settings pane's tab.
    static let paneTitle: String = "Preview"

    /// The question the pane asks.
    static let settingLabel: String = "When you press Preview, open"

    /// The two answers, in the order shown.
    static let frontPageChoice: String = "The site's front page"
    static let lastViewedChoice: String = "The page you last viewed"

    /// Under the choices: how to get the other one once.
    static let optionNote: String = "Hold Option to do the other one. The Preview button and Section ▸ Preview change their names while Option is held, so they always say what will happen."
}

/// The rules of #504 as pure functions, so the contract's cases run against
/// them without a window.
nonisolated enum PreviewStartPage {

    // MARK: - Types

    /// What a press asked for, carried from the press to the moment the
    /// server answers — through the question about today's class (#397) when
    /// that is asked first.
    struct Request: Equatable, Sendable {

        // MARK: - Stored properties

        var opensAt: PreviewOpensAt

        /// The teacher answered Show on Front Page a moment ago and the page
        /// was written (#397's `.shown`): they have just asked to change the
        /// FRONT page, so that is what they are shown, whatever the setting
        /// says (504 plan review, finding 6).
        var frontPageWasJustChanged: Bool = false

        /// Every way in that is not the teacher's press — the assistant,
        /// Rebuild Preview, Course Settings, Start of the Year, a repair.
        static let frontPage: Request = Request(opensAt: .frontPage)
    }

    /// What asking the remembered page's address found out.
    enum PageAnswer: String, Equatable, Sendable {
        /// It answered 200: open it.
        case answered
        /// It answered 404 or 410 — renamed, deleted or unpublished (an
        /// unpublished page is never built, so it is a 404 too).
        case gone
        /// No answer that says either, after every attempt: a timeout, an
        /// error, or any other status. A request made during a rebuild WAITS
        /// on the server's build lock (measured, 504 plan review M-c), so
        /// silence is not evidence that the page has gone.
        case didNotAnswer
    }

    /// Where the preview opens, and the trail's words for it.
    struct Decision: Equatable, Sendable {

        // MARK: - Stored properties

        /// True when the remembered page is opened rather than the front page.
        var opensRememberedPage: Bool

        /// The trail's words (`activityTrail` → "preview started at the page
        /// last viewed"), or nil when nothing about the start page is worth a
        /// line — a plain press that opened the front page.
        var trailWords: String?
    }

    // MARK: - Stored properties

    /// The statuses that mean the page is not on the site any more.
    static let goneStatuses: [Int] = [404, 410]

    /// How many times the remembered page is asked before giving up, and how
    /// long each try may take. Three tries of five seconds: long enough for a
    /// rebuild started by a save in Obsidian to finish (the request waits for
    /// it), short enough that a teacher is not left watching a spinner for a
    /// page that will not come.
    static let attempts: Int = 3
    static let secondsPerAttempt: Double = 5

    // MARK: - Functions

    /// The XOR at the heart of it: the setting, or its opposite while Option
    /// is held.
    static func opensAt(setting: PreviewOpensAt, optionHeld: Bool) -> PreviewOpensAt {
        if optionHeld {
            return setting.opposite
        }
        return setting
    }

    /// The title that says what a press will do.
    static func title(for opensAt: PreviewOpensAt) -> String {
        if opensAt == .lastViewed {
            return PreviewStartPageWording.previewAtLastViewed
        }
        return PreviewStartPageWording.preview
    }

    /// The ONE function behind the Preview button's title and Section ▸
    /// Preview's (contract: `previewStartPage.titles`). While a preview runs
    /// the item stops it, and Option changes nothing.
    static func buttonTitle(setting: PreviewOpensAt, optionHeld: Bool, previewIsRunning: Bool) -> String {
        if previewIsRunning {
            return PreviewStartPageWording.stopPreview
        }
        return title(for: opensAt(setting: setting, optionHeld: optionHeld))
    }

    /// The setting read back from the preferences: anything unreadable — no
    /// value, a retired name — is the front page, which is what Preview did
    /// before the setting existed.
    static func setting(fromStored stored: String?) -> PreviewOpensAt {
        guard let stored, let choice = PreviewOpensAt(rawValue: stored) else {
            return .frontPage
        }
        return choice
    }

    /// Whether Option is in a set of modifier flags.
    static func optionIsHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        return flags.contains(.option)
    }

    /// What to remember of an address the TEACHER navigated to in the pane:
    /// its path below the preview's root, percent-encoded as it arrived, with
    /// no query and no fragment — so `#plantoir-print=` is never replayed —
    /// or "" for the front page. Nil means ignore it and keep what was
    /// remembered: nothing (`nil`, `about:blank`), another site, another port
    /// (a dead server's provisional address, measured: `http://localhost:1/…`).
    ///
    /// `percentEncodedPath`, not `URL.path`, which DECODES.
    static func rememberedPath(page: URL?, previewRoot: URL) -> String? {
        guard let page,
              let pageParts = URLComponents(url: page, resolvingAgainstBaseURL: false),
              let rootParts = URLComponents(url: previewRoot, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let pageScheme = pageParts.scheme?.lowercased(),
              pageScheme == "http" || pageScheme == "https",
              pageScheme == rootParts.scheme?.lowercased() else {
            return nil
        }
        guard let pageHost = pageParts.host?.lowercased(),
              let rootHost = rootParts.host?.lowercased(),
              sameMachine(pageHost, rootHost) else {
            return nil
        }
        if pageParts.port != rootParts.port {
            return nil
        }
        var path: String = pageParts.percentEncodedPath
        while path.hasPrefix("/") {
            path.removeFirst()
        }
        return path
    }

    /// `localhost` and `127.0.0.1` are the same Mac: the launcher announces
    /// one and the web view may show either.
    static func sameMachine(_ first: String, _ second: String) -> Bool {
        if first == second {
            return true
        }
        let names: [String] = ["localhost", "127.0.0.1"]
        return names.contains(first) && names.contains(second)
    }

    /// The remembered page's address on THIS run's server — a path is kept,
    /// never a whole address, because the port can change between runs.
    static func pageAddress(root: URL, path: String) -> URL? {
        guard var parts = URLComponents(url: root, resolvingAgainstBaseURL: false) else {
            return nil
        }
        parts.percentEncodedPath = "/" + path
        parts.percentEncodedQuery = nil
        parts.fragment = nil
        return parts.url
    }

    /// What one status means, or nil for "ask again".
    static func answer(forStatus status: Int?) -> PageAnswer? {
        guard let status else {
            return nil
        }
        if status == 200 {
            return .answered
        }
        if goneStatuses.contains(status) {
            return .gone
        }
        return nil
    }

    /// Asks the page's address up to `attempts` times. `fetch` answers a
    /// status, or nil for a timeout or an error; `pause` waits between tries.
    /// Both are injected, so the rule is tested without a server.
    static func askWhetherThePageIsThere(
        _ page: URL,
        attempts: Int,
        fetch: (URL) async -> Int?,
        pause: () async -> Void
    ) async -> PageAnswer {
        var attempt: Int = 0
        while attempt < attempts {
            let status: Int? = await fetch(page)
            if let answer = answer(forStatus: status) {
                return answer
            }
            attempt += 1
            if attempt < attempts {
                await pause()
            }
        }
        return .didNotAnswer
    }

    /// Whether the remembered page has to be asked about at all.
    static func needsAsking(_ request: Request, remembered: String?) -> Bool {
        if request.opensAt != .lastViewed || request.frontPageWasJustChanged {
            return false
        }
        guard let remembered else {
            return false
        }
        return !remembered.isEmpty
    }

    /// Where the preview opens and what the trail says, from what was asked,
    /// what was remembered and what the server answered (nil when it was not
    /// asked). Contract: `previewStartPage.cases`.
    static func decide(_ request: Request, remembered: String?, answer: PageAnswer?) -> Decision {
        if request.opensAt == .frontPage {
            return Decision(opensRememberedPage: false, trailWords: nil)
        }
        if request.frontPageWasJustChanged {
            return Decision(
                opensRememberedPage: false,
                trailWords: "started preview at the front page because today's class was just put on it"
            )
        }
        guard let remembered else {
            return Decision(
                opensRememberedPage: false,
                trailWords: "started preview at the front page because no page had been viewed yet"
            )
        }
        if remembered.isEmpty {
            return Decision(
                opensRememberedPage: false,
                trailWords: "started preview at the front page, the page last viewed"
            )
        }
        let place: String = slug(remembered)
        if answer == .answered {
            return Decision(opensRememberedPage: true, trailWords: "started preview at " + place)
        }
        if answer == .gone {
            return Decision(
                opensRememberedPage: false,
                trailWords: "started preview at the front page because the page was gone (" + place + ")"
            )
        }
        return Decision(
            opensRememberedPage: false,
            trailWords: "started preview at the front page because the page did not answer (" + place + ")"
        )
    }

    /// A remembered path as the trail writes it: decoded, so a teacher reads
    /// "Unit 1/Lesson 3" rather than "Unit%201/Lesson%203". The page's PLACE,
    /// never its words.
    static func slug(_ path: String) -> String {
        return path.removingPercentEncoding ?? path
    }

    /// The trail's words for a change of the setting
    /// (`activityTrail` → "preview start page chosen in Settings").
    static func settingChangedWords(_ choice: PreviewOpensAt) -> String {
        if choice == .lastViewed {
            return "Settings ▸ Preview — Preview now opens at the page last viewed"
        }
        return "Settings ▸ Preview — Preview now opens at the front page"
    }
}

/// Tells the teacher's navigations in the preview pane from the app's own
/// loads, so only the first are remembered (504 plan review, the BLOCKER).
///
/// Every load the APP makes — the first page of a fresh build, Rebuild
/// Preview, the assistant's restart, Preview Again, Reload — lands on a page
/// the teacher did not choose, usually the front page. Remembering those
/// would erase the page they were reading the moment anything rebuilt, and
/// "Preview at Last Viewed" would open the front page the next morning. So an
/// app load is marked as begun when it is requested and as ended when WebKit
/// says that navigation finished or failed, and an address change in between
/// is not the teacher's.
///
/// A FLAG, not "the address equals the one the app asked for": that
/// comparison would also ignore a teacher's own click on the site's Home
/// link, and a redirect (`/Concepts` → `/Concepts/`, measured) would leave it
/// waiting for an address that never comes.
nonisolated struct PreviewNavigationLedger: Equatable, Sendable {

    // MARK: - Stored properties

    /// True from an app load's request until WebKit ends that navigation.
    private(set) var appLoadIsUnderWay: Bool = false

    // MARK: - Functions

    mutating func appLoadBegan() {
        appLoadIsUnderWay = true
    }

    mutating func appLoadEnded() {
        appLoadIsUnderWay = false
    }

    /// Whether an address change happening now was the teacher's.
    func changeIsTheTeachers() -> Bool {
        return !appLoadIsUnderWay
    }
}

/// The page each section's preview last showed, kept across quits (504-1:
/// per section — the section's own window is the thing a teacher comes back
/// to). A PATH below the site's root, never an address: the port can change.
///
/// Keyed by the working folder's canonical path (`FolderIdentity`), the
/// course code and the section, so a folder moved or a course renamed starts
/// with nothing remembered — and "Preview at Last Viewed" then opens the
/// front page and says so on the trail.
///
/// The store is injectable so tests never write into the teacher's real
/// preferences, the way `AppSettings` is.
final class LastViewedPages {

    // MARK: - Stored properties

    /// The app's own store, used by every window.
    static let shared: LastViewedPages = LastViewedPages()

    /// The preference holding every section's page, as one dictionary.
    static let storageKey: String = "previewLastViewedPages"

    private let defaults: UserDefaults

    // MARK: - Computed properties

    /// False while the hosted tests drive the real app, so a test run cannot
    /// leave a page behind in the teacher's preferences.
    private var canRemember: Bool {
        if WorkspaceModel.isRunningTests && defaults === PlantoirDefaults.shared {
            return false
        }
        return true
    }

    // MARK: - Initializer

    init(defaults: UserDefaults = PlantoirDefaults.shared) {
        self.defaults = defaults
    }

    // MARK: - Functions

    /// The key for one section. `folderPath` is already canonical.
    static func key(folderPath: String, courseCode: String, sectionNumber: Int) -> String {
        return folderPath + "|" + courseCode + "|" + String(sectionNumber)
    }

    /// The remembered path ("" for the front page), or nil when this section
    /// has never been navigated in.
    func page(forKey key: String) -> String? {
        let all: [String: Any] = defaults.dictionary(forKey: LastViewedPages.storageKey) ?? [:]
        return all[key] as? String
    }

    /// Remembers a path for a section, replacing what was there.
    func remember(_ path: String, forKey key: String) {
        if !canRemember {
            return
        }
        var all: [String: Any] = defaults.dictionary(forKey: LastViewedPages.storageKey) ?? [:]
        if (all[key] as? String) == path {
            return
        }
        all[key] = path
        defaults.set(all, forKey: LastViewedPages.storageKey)
    }
}
