import SwiftUI

/// A detail view's tabs as one segmented control in a thin bar above its
/// content (#717): Website | Coverage | Problems on a section (Coverage
/// since #793), and Settings | Planning on a course (#708,
/// `CourseDetailView`, while Claude Code, Codex or GitHub Copilot is installed). Built once
/// so each later use added a tab rather than a second shell.
///
/// **Not a `TabView`**, which decides for itself what each tab keeps. The
/// page decides instead: since #708 (the course) and #793 (the section) only
/// the chosen tab's content is drawn (`CourseDetailContent`,
/// `SectionTabContent`), never one over another, so nothing hidden can take
/// a key; a section's live `WKWebView` keeps its page and scroll because its
/// controller owns it. This view is only the switch.
///
/// **Not in the toolbar either**, though the window's principal slot is
/// free: the section's toolbar keeps every item ALWAYS present, because
/// inserting one conditionally makes macOS rebuild the toolbar and briefly
/// mis-lay-out the title area — and the switch exists only while there are
/// problems. A bar that comes and goes inside the content moves nothing in
/// the toolbar.
struct DetailTabs<Tab: Hashable>: View {

    // MARK: - Stored properties

    /// Each tab and the word it shows, in order.
    let tabs: [(tab: Tab, title: String)]

    @Binding var selection: Tab

    /// For UI tests.
    let identifier: String

    // MARK: - Body

    var body: some View {
        HStack {
            Spacer()
            Picker("", selection: $selection) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Text(tabs[index].title).tag(tabs[index].tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier(identifier)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

/// The room under a detail view's tabs, given to whichever tab is chosen
/// (#831, #832): `SectionTabContent` and `CourseDetailContent` put every
/// tab's content in it.
///
/// **Its smallest height is nought, whatever the tab inside asks for.** A
/// split view sizes its column by asking the content how small it can be,
/// with almost no width offered, and a column cannot be shorter than the
/// answer. One wrapping sentence made rigid somewhere inside a tab (on the
/// Coverage tab, the line saying when the map was made; on the Planning
/// tab, the share bar's sentence for a teacher whose class sites go to
/// Netlify) answered about 2,200 and 2,600 points, the column grew past the
/// window, and the window centred it: the tabs, the header and the share
/// bar went out of view above and below, and the sidebar with them. With
/// the smallest height fixed at nought here, no tab can claim more than the
/// window gives, so the tab bar above stays where it is and a long page
/// scrolls inside its own web view. Measured in a window the size of
/// Plantoir's by `DetailTabsLayoutTests`; `documentation/09-mac-app.md` →
/// "A blank window: when a child claims a size the window cannot give".
///
/// Height only: the column's smallest WIDTH still comes from what the tab
/// needs, so a form never gets narrower than it can be drawn.
struct TabArea<Content: View>: View {

    // MARK: - Stored properties

    @ViewBuilder let content: () -> Content

    // MARK: - Body

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
