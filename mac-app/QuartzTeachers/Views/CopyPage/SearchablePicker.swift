import AppKit
import SwiftUI

/// A combo box that can draw a real view in its list.
///
/// **This came home.** Plantoir's course-code combo box
/// (`CourseCodePickerView`) was ported into Russell's Canopy project and made
/// GENERIC there — a field, a chrome modifier and a sectioned overlay over any
/// `Identifiable` item with any row view, used twice. This is that generic
/// version brought back, with its comments, so Plantoir has one of these
/// rather than a third hand-written one. The two headline warnings below are
/// the ones that cost a day the first time.
///
/// **THE ONE THING THAT WILL COST YOU A DAY IF YOU CHANGE IT.** The list is
/// positioned from an `Anchor<CGRect>`, never from a `GeometryReader`-computed
/// rect. A rect measured inside a `Form`'s `Section` does not reliably reach
/// its ancestors, because a `Section` on macOS is backed by `List` machinery —
/// the list then renders at a stuck `.zero` frame and is simply invisible. An
/// anchor carries no coordinates of its own, so there is nothing for the
/// `List` to fail to propagate: SwiftUI resolves it at the point of USE,
/// walking the live hierarchy.
///
/// **AND THE SECOND THING:** the list is rendered by the HOST at the top level
/// of its window or sheet, never nested inside the `Form` the field sits in,
/// or the form clips it. That is why this file gives two pieces to place
/// separately rather than one view that does everything.
///
/// **The measured numbers are not copied.** Every metric is read off
/// `CourseCodePickerView`'s own `static let`s, which came from a real
/// `NSComboBox` rendered offscreen at 2x and read back pixel by pixel
/// (`research/native-control-metrics/`). A second copy of nine numbers is a
/// second set to keep in step; the wizard's screen is not touched.

// MARK: - A titled run of rows

/// A heading and the rows under it.
///
/// A plain data type rather than anything view-shaped, so a model can build
/// the list and a test can assert it. An EMPTY title draws no heading, which
/// is what a flat, ranked list of search results wants — a heading above the
/// best match says nothing and costs a row of height to say it.
struct PickerSection<Item: Identifiable>: Identifiable {

    // MARK: - Stored properties

    let title: String
    let rows: [Item]

    // MARK: - Computed properties

    var id: String {
        return title
    }
}

// MARK: - Where the field is

/// See the note at the top of this file: an anchor, not a rect.
struct SearchablePickerAnchorKey: PreferenceKey {

    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - The field

struct SearchablePickerField: View {

    // MARK: - Stored properties

    @Binding var text: String

    /// Whether the field has keyboard focus, published out so the host can
    /// gate the list on it. A plain `Bool` binding rather than threading
    /// `FocusState` through, because `@FocusState` only projects a binding
    /// from the view that declares it.
    @Binding var isFocused: Bool

    /// The placeholder shown while the field is EMPTY. See the note where it
    /// is used: it is bound as `prompt:` and never as the field's title.
    var prompt: String = ""

    var fieldIdentifier: String = "searchable-picker-field"

    /// Escape, pressed while this field has focus. It closes the list rather
    /// than dismissing the window's sheet, and does NOT blur the field, so
    /// somebody can carry on typing straight afterwards.
    var onEscape: () -> Void = { }

    /// The trailing chevron. A toggle rather than an open, because a real
    /// combo box's arrow closes its popup as readily as it opens it.
    var onRevealRequested: () -> Void = { }

    /// -1 for up, +1 for down. Returns whether the list took the key; `false`
    /// lets it fall through to moving the insertion point, which is what
    /// should happen when there is no list to walk.
    var onMoveHighlight: (Int) -> Bool = { _ in false }

    /// Return. `false` lets it reach the window's default button, so somebody
    /// who typed and never touched the arrows can still submit.
    var onCommitHighlight: () -> Bool = { false }

    @FocusState private var hasFocus: Bool

    // MARK: - Body

    var body: some View {
        // `prompt:`, NOT the title. A `TextField`'s first argument is its
        // TITLE, and a title does not clear when somebody types — so "Search"
        // sat there behind the name being entered. The `prompt` is the
        // placeholder proper: it shows while the field is empty and gets out
        // of the way the moment it is not. The title is empty because the row
        // this sits in is already labelled by its `LabeledContent`.
        TextField("", text: $text, prompt: Text(prompt))
            .focused($hasFocus)
            // Bound to the `TextField` itself, BEFORE the chrome gives it
            // anything to collide with. Chained after the chevron's
            // `.overlay` it applies to the merged element and silently
            // overwrites the button's own identifier.
            .accessibilityIdentifier(fieldIdentifier)
            .anchorPreference(key: SearchablePickerAnchorKey.self, value: .bounds) { anchor in
                return anchor
            }
            // Consumed here so Escape closes the list rather than falling
            // through to a sheet's dismiss.
            .onKeyPress(.escape) {
                onEscape()
                return .handled
            }
            .onKeyPress(.upArrow) {
                return onMoveHighlight(-1) ? .handled : .ignored
            }
            .onKeyPress(.downArrow) {
                return onMoveHighlight(1) ? .handled : .ignored
            }
            .onKeyPress(.return) {
                return onCommitHighlight() ? .handled : .ignored
            }
            .modifier(SearchablePickerChrome(
                isFocused: hasFocus,
                backgroundIdentifier: "\(fieldIdentifier)-background"
            ))
            // The cue a Mac user already knows: a trailing chevron reads as
            // "there is a menu behind this field", the way a combo box always
            // shows one. It is a second way in, not a different control.
            .overlay(alignment: .trailing) {
                Button {
                    hasFocus = true
                    onRevealRequested()
                } label: {
                    RoundedRectangle(cornerRadius: CourseCodePickerView.revealButtonCornerRadius)
                        .fill(CourseCodePickerView.revealButtonFillColor)
                        .overlay(
                            Image(systemName: "chevron.down")
                                .font(.system(
                                    size: CourseCodePickerView.revealButtonGlyphSize,
                                    weight: .semibold
                                ))
                                .foregroundStyle(.primary)
                        )
                        .frame(
                            width: CourseCodePickerView.revealButtonWidth,
                            height: CourseCodePickerView.revealButtonHeight
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, CourseCodePickerView.revealButtonTrailingInset)
                .accessibilityIdentifier("\(fieldIdentifier)-reveal")
                .accessibilityLabel("Browse the whole list")
            }
            .onChange(of: hasFocus) {
                isFocused = hasFocus
            }
            .onChange(of: isFocused) {
                // Lets the host drop focus — after a selection, say — and
                // have the field actually lose it rather than only the
                // bookkeeping.
                if hasFocus != isFocused {
                    hasFocus = isFocused
                }
            }
    }
}

// MARK: - The field's chrome

/// It exists because `.textFieldStyle(.roundedBorder)` renders 26pt tall while
/// every AppKit control it stands in for is 24.
///
/// `.frame(height: 24)` does NOT achieve that, which is worth knowing before
/// anybody tries it again: SwiftUI draws the `.roundedBorder` bezel at its own
/// intrinsic height whatever frame it is given, so the field measures 26
/// anyway and merely overflows its box. The only way to 24 is to stop asking
/// SwiftUI for a bezel and draw one.
///
/// The cost, stated plainly: this is an imitation of a real AppKit bezel. It
/// is measured against the real thing rather than eyeballed, and the
/// alternative — an `NSViewRepresentable` around a real `NSTextField` — buys
/// genuine chrome at the price of hand-managing first responder and binding
/// updates.
struct SearchablePickerChrome: ViewModifier {

    // MARK: - Stored properties

    /// A `ViewModifier` cannot own focus for the view it decorates, so the
    /// ring has to be told rather than discovered.
    let isFocused: Bool

    /// Identifies the background SHAPE to a UI test.
    ///
    /// It has to be the shape rather than the `TextField`, and that is not a
    /// preference: an `NSTextField` reports its accessibility frame as the
    /// underlying CONTROL's bounds — its roughly 18pt text box — wherever in
    /// the modifier chain the identifier is bound. So the field's own
    /// identifier can never report the 24pt bezel a test needs in order to
    /// check that this control ends where the controls around it end.
    var backgroundIdentifier: String? = nil

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .padding(.leading, CourseCodePickerView.textLeadingInset)
            .padding(.trailing, CourseCodePickerView.textTrailingInset)
            .padding(.bottom, CourseCodePickerView.textBaselineNudge)
            .frame(
                maxWidth: .infinity,
                minHeight: CourseCodePickerView.fieldHeight,
                maxHeight: CourseCodePickerView.fieldHeight
            )
            .background(
                RoundedRectangle(cornerRadius: CourseCodePickerView.fieldCornerRadius)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .accessibilityIdentifier(backgroundIdentifier ?? "")
            )
            .overlay(
                RoundedRectangle(cornerRadius: CourseCodePickerView.fieldCornerRadius)
                    .strokeBorder(
                        isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
    }
}

// MARK: - The floating list

/// Generic over what it lists and how a row is drawn.
///
/// Rendered by the HOST at the top level of its window or sheet. See the file
/// header for why it cannot live inside the `Form`.
struct SearchablePickerOverlay<Item: Identifiable, Row: View>: View {

    // MARK: - Stored properties

    let fieldFrame: CGRect
    let sections: [PickerSection<Item>]

    /// The row the arrow keys are sitting on. Held by the host rather than
    /// here, so the key handlers — which live on the field, the only thing
    /// with focus — and the drawing cannot disagree.
    let highlightedRowId: Item.ID?

    let emptyMessage: String

    let onSelect: (Item) -> Void

    /// What each row calls itself to a UI test. Bound to the BUTTON rather
    /// than to the row's content: an identifier on the label is merged into
    /// the button's element and the two can overwrite each other.
    let rowIdentifier: (Item) -> String

    @ViewBuilder let row: (Item, Bool) -> Row

    /// Enough rows to feel like browsing rather than peeking, without the card
    /// outgrowing the window. Taken from the wizard's own popup so the two
    /// controls open to the same size.
    static var maxVisibleRows: Int {
        return CourseCodeSuggestionsOverlay.maxVisibleRows
    }

    static var rowHeight: CGFloat {
        return CourseCodeSuggestionsOverlay.rowHeight
    }

    /// A heading is shorter than a row. This number is NEW here — the wizard's
    /// popup has no headings — and it was not measured off an `NSComboBox`.
    static var headingHeight: CGFloat {
        return 22
    }

    // MARK: - Computed properties

    private var allRows: [Item] {
        var result: [Item] = []
        for section in sections {
            for item in section.rows {
                result.append(item)
            }
        }
        return result
    }

    private var isEmpty: Bool {
        return allRows.isEmpty
    }

    /// Tall enough for what is in it, up to the cap.
    ///
    /// **Headings inside the cap only.** Adding every heading regardless of
    /// the row cap is what the ported version did, and on a real course it
    /// opened a card of nearly half a screen that was mostly headings:
    /// measured, ICS4U offers 156 pages in 11 folders, so six rows of 42 plus
    /// eleven headings of 22 is 494pt for a card meant to show 252. Canopy's
    /// own two uses have two or three sections, so it never showed there.
    /// Walking the sections and stopping when the row cap is reached counts
    /// exactly the headings a teacher can see.
    private var cardHeight: CGFloat {
        var rowsCounted: Int = 0
        var headingsCounted: Int = 0
        for section in sections {
            if rowsCounted >= SearchablePickerOverlay.maxVisibleRows {
                break
            }
            if !section.title.isEmpty {
                headingsCounted += 1
            }
            rowsCounted += section.rows.count
        }
        let rowsShown: CGFloat = min(
            CGFloat(allRows.count), CGFloat(SearchablePickerOverlay.maxVisibleRows)
        )
        return rowsShown * SearchablePickerOverlay.rowHeight
            + CGFloat(headingsCounted) * SearchablePickerOverlay.headingHeight
    }

    /// The height a test reads, so the cap above is asserted rather than
    /// looked at.
    var cardHeightForTests: CGFloat {
        return cardHeight
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.quaternary)
            )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(width: fieldFrame.width, alignment: .leading)
                    .background(card)
                    .accessibilityIdentifier("searchable-picker-no-matches")
            } else {
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.rows) { item in
                                        Button {
                                            onSelect(item)
                                        } label: {
                                            row(item, item.id == highlightedRowId)
                                        }
                                        .buttonStyle(.plain)
                                        .id(item.id)
                                        .accessibilityIdentifier(rowIdentifier(item))
                                        // Rows fade as typing narrows the
                                        // list, rather than the list jumping
                                        // to its new count.
                                        .transition(.opacity)
                                    }
                                } header: {
                                    if !section.title.isEmpty {
                                        heading(section.title)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: fieldFrame.width, height: cardHeight)
                    .background(card)
                    .accessibilityIdentifier("searchable-picker-list")
                    // Walking past the visible rows scrolls, rather than
                    // running the highlight off the bottom of a card showing
                    // six of a hundred and fifty-six.
                    .onChange(of: highlightedRowId) { _, newValue in
                        if let newValue {
                            scroller.scrollTo(newValue, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .offset(x: fieldFrame.minX, y: fieldFrame.maxY + 4)
        // `fieldFrame` itself must never be what animates — only the list's
        // entrance. Without this, the host's ambient animation also sweeps up
        // any change to the frame landing in the same render pass, and on the
        // FIRST focus the `Form` has not finished settling, so the anchor
        // briefly resolves too wide before correcting. Caught animating, that
        // correction reads as the card stretching past the field and snapping
        // back.
        .animation(nil, value: fieldFrame)
    }

    // MARK: - Functions

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
    }
}
