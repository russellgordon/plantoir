import SwiftUI

/// What a teacher sees when a publish that was set to happen on its own has
/// something to report — the orange notice when an overnight run did not get
/// through, and the green one when it did.
///
/// At the TOP of the section, above the console, because a teacher opening a
/// section after a failed overnight publish is looking for why their site is
/// out of date — and the console below is about what they are doing now, not
/// about what happened while they were asleep.
///
/// Its own view, with nothing read from the environment and Dismiss handed in
/// as a closure, so a test can put it in a hosting view of a known width and
/// MEASURE it. That is the same arrangement, for the same reason, as
/// `CloudSyncNoticeContentView` — and the reason is
/// `ProgressViewSizeTests.heightClaimedWhenSqueezed`, which is what catches a
/// sentence in here going rigid again.
struct ScheduledPublishNoticeView: View {

    // MARK: - Stored properties

    /// The run being reported, as it was written down.
    let outcome: ScheduledPublishOutcome.Stopped

    /// The course code the sentence names.
    let course: String

    /// The section number the sentence names.
    let sectionNumber: Int

    /// What Dismiss does.
    let dismiss: () -> Void

    // MARK: - Computed properties

    /// Whether this is something the teacher should be chased about. A
    /// success is news rather than a problem, so it is green and quiet.
    var needsAttention: Bool {
        return outcome.kind.needsAttention
    }

    /// The sentence itself, which lives in `ScheduledPublishOutcome` because
    /// both apps say one thing about one problem.
    var sentence: String {
        return ScheduledPublishOutcome.sentence(
            for: outcome, course: course, section: sectionNumber
        )
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: needsAttention
                  ? "exclamationmark.triangle.fill"
                  : "checkmark.circle.fill")
                .foregroundStyle(needsAttention ? .orange : .green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // No `fixedSize` on this sentence, on purpose — the rule
                // `CloudSyncNoticeView` and `WebPreviewView.sizeThatFits`
                // already state: never make a wrapping text's height RIGID
                // inside a view a split-view column can measure. A text told
                // to keep its vertical size answers with the lines it needs
                // at the width it is PROPOSED, and the split view measures a
                // column by proposing next to no width at all — where this
                // sentence wraps to a character per line and claimed over
                // 1,800 points. The column took that as its height, the
                // window's content grew past the window, and the sidebar and
                // the console both slid out of the visible band, leaving a
                // teacher a blank window the morning after an overnight
                // publish. Measured, and pinned by `ProgressViewSizeTests`.
                Text(sentence)
                // The DATE as well as the day: a record can sit for a week
                // if nobody dismisses it and no later run gets through, and
                // "Tuesday 6:30 AM" with no date is a teacher wondering
                // WHICH Tuesday.
                Text(outcome.when, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Dismissing is the mac's own addition. Windows clears this only
            // when a later scheduled run gets through, which leaves the message
            // standing after a teacher has already fixed the problem by hand —
            // and the next run that would clear it could be a week away.
            Button("Dismiss") {
                dismiss()
            }
            .accessibilityIdentifier("dismissStoppedPublish")
        }
        .padding(12)
        .background((needsAttention ? Color.orange : Color.green).opacity(0.12))
        .accessibilityIdentifier("stoppedPublishNotice")
    }
}
