import SwiftUI

/// The line above a section's preview that says Course Settings has changes
/// nobody saved, so the preview uses the settings as they were last saved
/// (`SpecialNames.previewUsesSavedSettings`, issue #265).
///
/// Its own view, with nothing read from the environment, so a test can put it
/// in a hosting view of a known width and MEASURE it — the arrangement
/// `ScheduledPublishNoticeView` and `CloudSyncNoticeContentView` already use,
/// for the same reason.
///
/// **No `fixedSize` on the sentence.** It arrived with one, inline in
/// `SectionDetailView`, in the detail column above the stack the site lives
/// in — the exact shape `documentation/09-mac-app.md` → "A blank window: when
/// a child claims a size the window cannot give" records as blanking the
/// whole window. A text told to keep its vertical size answers with the lines
/// it needs at the width it is PROPOSED, and a split view measures a column
/// by proposing next to no width. Measured on 2026-09-26: squeezed, it
/// claimed 1,337 points with the modifier (the suite's measurement); and in a
/// real `NavigationSplitView` window at Plantoir's 900 × 600 minimum (a
/// standalone replica, not this app), the area below it where the site sits
/// was laid out 1,305 points tall inside a 600-point window with the
/// modifier, and 525 without. Pinned by `UnsavedSettingsNoticeLayoutTests`.
struct UnsavedSettingsNoticeView: View {

    // MARK: - Stored properties

    /// The sentence shown: the preview's, or since #335 a deploy's
    /// (`SpecialNames.deployUsesSavedSettings`).
    let sentence: String

    /// The accessibility identifier: `previewUsesSavedSettingsNotice`, or
    /// `deployUsesSavedSettingsNotice` when the sentence is a deploy's (#335).
    var identifier: String = "previewUsesSavedSettingsNotice"

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(sentence)
                    .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier(identifier)
            Divider()
        }
    }
}
