import SwiftUI

/// A detail view's tabs as one segmented control in a thin bar above its
/// content (#717): Website | Coverage | Problems on a section (Coverage
/// since #793), and Settings | Planning on a course (#708,
/// `CourseDetailView`, while Claude Code or Codex is installed). Built once
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
