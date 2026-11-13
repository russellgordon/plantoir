import SwiftUI

/// A section's Coverage tab (#793): the curriculum coverage map as it would
/// be if every page were published, which every build of the section writes
/// beside its built site, shown with no browser.
///
/// What it shows is decided by `CoverageTabDisplay.display`, from the record
/// `SectionCoverage` last read and the facts the section's page passes in
/// about the builds under way; every sentence is `CoverageTabWording`'s. The
/// map's page is shown by the Planning tab's web view, set up for the map's
/// folder alone (`PlanWebController.forCoverage`): local files only, no
/// script, no network. The click hint is said HERE, above the page, and only
/// when it is true (the plan review's L1).
///
/// Drawn only while the Coverage tab is chosen (`SectionTabContent`), so the
/// section's preview is not in the window while it shows.
struct CoverageTabView: View {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int

    /// The working folder the section is open in.
    let folder: URL

    /// The facts about builds under way that only the section's page knows.
    let ownBuildBeforeItsMap: Bool
    let ownBuildRunning: Bool
    let deploying: Bool
    let otherWindow: Bool
    let previewIsShowing: Bool
    let browserHasThePreview: Bool

    /// Whether the folder lets a build start at all (being copied, or its
    /// tools still being made ready), and why not.
    let folderIsReady: Bool
    let folderNotReadyReason: String?

    /// Make the Map (Again): the section page's own refresh, which never
    /// takes the teacher off this tab.
    let makeAgain: () -> Void

    /// A click on a code, as the page sent it.
    let openCode: (URL) -> Void

    var coverage: SectionCoverage = SectionCoverage.shared

    // MARK: - Computed properties

    var key: String {
        return coverage.key(folder: folder, course: course, sectionNumber: sectionNumber)
    }

    var entry: SectionCoverage.Entry {
        return coverage.entry(key)
    }

    var facts: CoverageTabDisplay.Facts {
        return CoverageTabView.facts(
            entry: entry, rulesFailed: coverage.rulesFailed,
            ownBuildBeforeItsMap: ownBuildBeforeItsMap, ownBuildRunning: ownBuildRunning,
            deploying: deploying, otherWindow: otherWindow,
            previewIsShowing: previewIsShowing, browserHasThePreview: browserHasThePreview,
            obsidianInstalled: FolderActions.obsidianIsInstalled
        )
    }

    var display: CoverageTabDisplay.Display {
        return CoverageTabDisplay.display(facts)
    }

    var when: String {
        return CoverageTabWording.when(entry.reading?.record?.startedAt)
    }

    var refusalReason: String {
        if case .refused(let reason) = entry.refresh {
            return reason
        }
        return ""
    }

    /// The page to show, with every link on the way followed, and the
    /// folder it may read, the same way: the built output is reached
    /// through the course's `.merged_output` link.
    var pageToShow: (page: URL, folder: URL)? {
        guard let reading = entry.reading, let page = reading.page else {
            return nil
        }
        let resolvedFolder: URL = URL(fileURLWithPath: PlanNavigation.resolvedPath(reading.folder.path), isDirectory: true)
        let resolvedPage: URL = resolvedFolder.appendingPathComponent(page.lastPathComponent, isDirectory: false)
        return (page: resolvedPage, folder: resolvedFolder)
    }

    // MARK: - Functions

    /// The facts the tab is drawn from, from what the store holds and what
    /// the section's page knows: one place, which a test of the real page
    /// asks too.
    static func facts(
        entry: SectionCoverage.Entry, rulesFailed: Bool,
        ownBuildBeforeItsMap: Bool, ownBuildRunning: Bool,
        deploying: Bool, otherWindow: Bool,
        previewIsShowing: Bool, browserHasThePreview: Bool,
        obsidianInstalled: Bool
    ) -> CoverageTabDisplay.Facts {
        var facts: CoverageTabDisplay.Facts = CoverageTabDisplay.Facts()
        facts.record = entry.reading?.kind ?? .noRecord
        facts.refresh = entry.refresh
        facts.ownBuildBeforeItsMap = ownBuildBeforeItsMap
        facts.ownBuildRunning = ownBuildRunning
        facts.deploying = deploying
        facts.elsewhere = entry.elsewhere
        facts.otherWindow = otherWindow
        facts.changed = entry.changed
        facts.startKnown = entry.reading?.record?.startedAt != nil
        facts.previewIsShowing = previewIsShowing
        facts.restartingThePreview = entry.restartsThePreview
            && (entry.refresh == .starting || entry.refresh == .pending)
        facts.browserHasThePreview = browserHasThePreview
        facts.rulesCompiled = !rulesFailed
        facts.obsidianInstalled = obsidianInstalled
        return facts
    }

    // MARK: - Body

    var body: some View {
        let shown: CoverageTabDisplay.Display = display
        let controller: PlanWebController = coverage.controller(key, open: openCode, cannotShow: noteCannotShow)
        VStack(spacing: 0) {
            switch shown.kind {
            case .cannotShow:
                ContentUnavailableView(
                    CoverageTabWording.cannotShowTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(CoverageTabWording.sentence("cannotShowDescription"))
                )
            case .empty:
                ContentUnavailableView {
                    Label(CoverageTabWording.emptyTitle, systemImage: "map")
                } description: {
                    VStack(spacing: 8) {
                        Text(CoverageTabWording.sentence(shown.description ?? "emptyDescription"))
                        ForEach(shown.lines, id: \.self) { line in
                            Text(CoverageTabWording.sentence(line, when: when, reason: refusalReason))
                                .foregroundStyle(.secondary)
                        }
                    }
                } actions: {
                    makeButton(shown)
                }
                // A container with its own identifier, keeping its controls' (#832).
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("coverageEmpty")
            case .map:
                header(shown)
                Divider()
                PlanWebView(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("coverageWebView")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            coverage.reload(folder: folder, course: course, sectionNumber: sectionNumber)
            noteTheLook()
        }
        .onChange(of: pageToShow?.page, initial: true) { _, _ in
            showThePageIfItIsNew(in: controller)
        }
    }

    /// Loads the record's page, unless the web view already shows it: a
    /// switch back to the tab finds the map where the teacher left it, and
    /// a new build's map (a new file name) loads in place.
    func showThePageIfItIsNew(in controller: PlanWebController) {
        guard let shownPage = pageToShow else {
            return
        }
        if let onScreen = controller.webView.url, onScreen.isFileURL,
           onScreen.standardizedFileURL.path == shownPage.page.standardizedFileURL.path {
            return
        }
        controller.show(page: shownPage.page, readingOnlyInside: shownPage.folder)
    }

    /// The lines above the map, and its one button.
    func header(_ shown: CoverageTabDisplay.Display) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(shown.lines, id: \.self) { line in
                    headerLine(line)
                }
                if let clickLine = entry.clickLine {
                    Text(clickLine)
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            makeButton(shown)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // A container with its own identifier, keeping its controls' (#832).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coverageHeader")
    }

    /// One line above the map. A line saying the map may be out of date
    /// is a caution (`CoverageTabWording.cautionLines`, #831): the caution
    /// symbol before it, with its own accessibility label, and the words
    /// saying it too, so the symbol is never the only signal.
    @ViewBuilder
    func headerLine(_ line: String) -> some View {
        let words: Text = Text(CoverageTabWording.sentence(line, when: when, reason: refusalReason))
        if CoverageTabWording.cautionLines.contains(line) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(CoverageTabWording.cautionLabel)
                words
                    .font(.callout)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coverageCaution")
        } else {
            words
                .font(.callout)
                .foregroundStyle(line == "asOf" || line == "clickHint" ? .secondary : .primary)
        }
    }

    func makeButton(_ shown: CoverageTabDisplay.Display) -> some View {
        Button(CoverageTabWording.sentence(shown.button ?? "makeTheMap")) {
            makeAgain()
        }
        .disabled(!shown.buttonEnabled || !folderIsReady)
        .help(folderNotReadyReason ?? CoverageTabWording.makeHelp)
        .accessibilityIdentifier("coverageMakeAgainButton")
    }

    /// One trail line per appearance (`activityTrail.mustRecord` → "looked
    /// at a section's curriculum coverage").
    func noteTheLook() {
        guard let reading = coverage.entry(key).reading else {
            return
        }
        ActivityTrail.note(
            .lookedAtSectionCoverage,
            CoverageTabTrail.lookedText(reading: reading, changed: coverage.entry(key).changed, rulesCompiled: !coverage.rulesFailed),
            course: course.code,
            section: sectionNumber
        )
    }

    /// The map could not be shown at all: a line of its own, once.
    func noteCannotShow() {
        ActivityTrail.note(.lookedAtSectionCoverage, CoverageTabTrail.filled(CoverageTabTrail.couldNotShow), course: course.code, section: sectionNumber)
    }
}

/// What a section's page draws below its tabs: only the chosen tab's
/// content, never one over another (#793, the plan review's H1, the shape
/// the course page ended with in #708). While Coverage or Problems shows,
/// the section's preview is not in the window at all, so no key, no Space
/// and no paste can reach it. The preview's web view is OWNED by its
/// controller, so leaving the window costs it neither its page nor its
/// scroll (measured by the plan review; `SectionDetailStructureTests`).
struct SectionTabContent<Website: View, Coverage: View, Problems: View>: View {

    // MARK: - Stored properties

    let showing: SectionTab
    @ViewBuilder let website: () -> Website
    @ViewBuilder let coverage: () -> Coverage
    @ViewBuilder let problems: () -> Problems

    // MARK: - Body

    var body: some View {
        // In the tab area, so no tab can make the page taller than the
        // window (#831).
        TabArea {
            if showing == .coverage {
                coverage()
            } else if showing == .problems {
                problems()
            } else {
                website()
            }
        }
    }
}
