import SwiftUI

/// The title that names a sheet: `.headline`, leading, in a band 52 points
/// tall — ONE shape for every sheet in Plantoir (#457 item 4, the HIG sweep).
///
/// Taken from Canopy's mac-window-conventions §3a, which made the same
/// correction on 2026-08-30 (Russell: "there is no padding below the title
/// and it runs up against the content area"). Before this, Plantoir's sheets
/// put their titles on the sheet's own `.padding(20)` with 12 or 16 points
/// under them depending on the sheet, and five of fifteen titles were
/// `.title2` (bold in three). **The band is better than two paddings**: a
/// fixed height centres the title by construction, so the space above and
/// below cannot drift apart when somebody edits one of them, and every sheet
/// gets the same title height.
///
/// **A title with an explanation under it cannot use the band** — two lines
/// of caption will not fit 52 points. Those sheets (Add Section, Keep a Copy
/// for Reference, Class Dates, Special Folders and a credential request) put
/// the explanation in the title block and give it a bottom padding that
/// matches the top. Adding an explanation to a banded sheet means moving it
/// to that shape, not enlarging the band.
///
/// The words stay each sheet's own — sentence case, as Russell ruled for the
/// sweep (titles are not title-cased).
struct SheetTitle<Explanation: View>: View {

    // MARK: - Stored properties

    let title: String

    /// The title's own accessibility identifier, for the sheets a UI test
    /// finds by their title (`scheduleDeployTitle`, `sectionScheduleTitle`).
    var identifier: String?

    let explanation: Explanation

    let hasExplanation: Bool

    /// The band's height, from Canopy, where it was settled by eye in both
    /// appearances.
    static var bandHeight: CGFloat {
        return 52
    }

    /// Above the title and below the explanation, in the two-line shape.
    static var explainedPadding: CGFloat {
        return 16
    }

    /// The sheets' own side margin, so the title lines up with the content.
    static var sideMargin: CGFloat {
        return 20
    }

    // MARK: - Computed properties

    var body: some View {
        if hasExplanation {
            VStack(alignment: .leading, spacing: 6) {
                titleText
                explanation
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetTitle.sideMargin)
            .padding(.vertical, SheetTitle.explainedPadding)
        } else {
            titleText
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SheetTitle.sideMargin)
                .frame(height: SheetTitle.bandHeight)
        }
    }

    @ViewBuilder
    var titleText: some View {
        if let identifier {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
        } else {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Initializer

    /// A title with an explanation under it — the two-line shape.
    init(_ title: String, identifier: String? = nil, @ViewBuilder explanation: () -> Explanation) {
        self.title = title
        self.identifier = identifier
        self.explanation = explanation()
        self.hasExplanation = true
    }
}

extension SheetTitle where Explanation == EmptyView {

    // MARK: - Initializer

    /// A title alone — the band.
    init(_ title: String, identifier: String? = nil) {
        self.title = title
        self.identifier = identifier
        self.explanation = EmptyView()
        self.hasExplanation = false
    }
}

extension View {

    /// Puts `SheetTitle` above this sheet's content. The content keeps its
    /// side and bottom margins and drops its top one, which the band (or the
    /// explanation's bottom padding) supplies.
    func sheetTitle(_ title: String, identifier: String? = nil) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title, identifier: identifier)
            self
        }
    }

    /// The same, with an explanation under the title.
    func sheetTitle<Explanation: View>(
        _ title: String,
        identifier: String? = nil,
        @ViewBuilder explanation: () -> Explanation
    ) -> some View {
        let block: SheetTitle<Explanation> = SheetTitle(title, identifier: identifier, explanation: explanation)
        return VStack(alignment: .leading, spacing: 0) {
            block
            self
        }
    }
}
