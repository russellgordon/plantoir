import AppKit
import SwiftUI

/// Marks the course-code field's bounds as an ANCHOR, for the wizard to
/// resolve into an actual on-screen rect and position
/// `CourseCodeSuggestionsOverlay` flush against — the way the Human
/// Interface Guidelines show a combo box's popup sitting exactly under
/// its field, with no overhang on either side.
///
/// An anchor, not a plain `CGRect` read from a `GeometryReader`
/// (2026-08-22, same day, second attempt): the field lives inside a
/// `Form`'s grouped `Section`, which on macOS is backed by `List`/table
/// machinery, and a `GeometryReader`-computed `CGRect` preference from a
/// descendant of THAT never reliably reached this view's ancestors — the
/// overlay rendered at a stuck `.zero` frame, invisibly. An `Anchor<CGRect>`
/// doesn't have that problem: it carries no coordinates of its own, so
/// there's nothing for the `List` to fail to propagate: SwiftUI resolves
/// it into real coordinates at the point of USE, via
/// `GeometryProxy[anchor]`, walking the actual live view hierarchy rather
/// than depending on an eagerly-computed value bubbling up through
/// containers along the way.
struct CourseCodeFieldAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The course-code field itself — just the field, not the Province
/// picker above it (that moved out to be its own sibling `Form` row —
/// see `NewCourseWizardView.wizardForm`). This view's whole job is: hold
/// the typed text, own the field's focus state, publish an anchor to its
/// own bounds, and publish its focus out to the wizard via a binding.
/// The popup itself (`CourseCodeSuggestionsOverlay`) is rendered by the
/// wizard at the top level of its own sheet, not nested inside this
/// view's `Form` section, so it can float over the rest of the form
/// rather than push it downward and so it is never clipped by the
/// Form/List machinery a `Section` sits inside.
///
/// The `TextField` is this view's ROOT — every visual addition (the
/// custom background, the border, the reveal button) is attached as a
/// MODIFIER (`.background`, `.overlay`), never as a sibling in a
/// wrapping container (2026-08-23, reworked from an earlier `ZStack`
/// version). Keeping it a decorated `TextField` rather than a `ZStack`
/// of siblings is what lets the wizard's `LabeledContent` row treat it
/// as an ordinary control — sized to the trailing column, aligned with
/// Course Name's field, with the native `Divider` between rows.
///
/// The row's "Course code" LABEL is NOT drawn here, and is not drawn by
/// `Form` either — `NewCourseWizardView` writes it as an explicit
/// `LabeledContent`. An earlier version of this file claimed `Form`
/// auto-labels a `TextField` used as a row's content; that is only true
/// when the row's content IS that `TextField`, and this view is a view
/// of ours, so nothing was extracted and "Course code" showed as
/// placeholder text INSIDE the field instead (Russell, 2026-08-23,
/// comparing it to Course name). Hence the empty title below.
///
/// A real `NSComboBox` was tried here first and reverted twice in one
/// session (2026-08-22): its popup only shows plain strings, losing the
/// "example content" badge Russell specifically asked to keep, and
/// correcting its auto-widened popup frame after the fact proved
/// unreliable two different ways — deferred a runloop turn, it flashed
/// the wrong frame first; made synchronous, it silently missed the
/// "click the arrow with an empty field" case because the popup's child
/// window doesn't exist yet when `comboBoxWillPopUp` fires. A plain
/// SwiftUI overlay, explicitly given the field's own measured width
/// rather than asking AppKit to auto-size anything, has no equivalent
/// failure mode — but see the note on `CourseCodeFieldAnchorKey` above
/// for the ONE thing that still had to change about how that measuring
/// happens.
struct CourseCodePickerView: View {

    // MARK: - Stored properties

    @Binding var courseCode: String

    /// Whether the field currently has keyboard focus — also what the
    /// wizard gates showing the popup on. A plain `Bool` binding rather
    /// than threading `FocusState` itself through, since `@FocusState`
    /// only projects a `Binding<Bool>` from the view that declares it.
    @Binding var isFocused: Bool

    /// Escape, pressed while this field has focus — the wizard uses this
    /// to close the popup WITHOUT dismissing the whole sheet (see
    /// `courseCodeSuggestionsManuallyDismissed`). Escape isn't wired to
    /// blur the field itself here; only the wizard's popup-visibility
    /// bookkeeping reacts to it, so a teacher can keep typing right after
    /// dismissing the list, same as a native combo box's popup. Returns
    /// whether the popup WAS shown: with none, Escape reaches the sheet and
    /// closes the wizard as Cancel would (`PickerEscape`, #457).
    var onEscape: () -> Bool = { false }

    /// The trailing chevron button, pressed. The wizard TOGGLES on
    /// this: a real `NSComboBox`'s arrow closes the popup as readily as
    /// it opens it, and ours only ever opened (Russell, 2026-08-23). It
    /// still has to be a callback rather than a focus change, because
    /// pressing the arrow while the field is ALREADY focused changes
    /// nothing about focus and so would go unnoticed.
    var onRevealRequested: () -> Void = {}

    /// An arrow key pressed while the field has focus: -1 for up, +1 for
    /// down. Returns whether the wizard did something with it — `false`
    /// lets the key fall through to its ordinary meaning (moving the
    /// insertion point), which is what should happen when there is no
    /// popup to walk.
    var onMoveHighlight: (Int) -> Bool = { _ in false }

    /// Return pressed while the field has focus. Returns whether a
    /// highlighted suggestion was taken; `false` lets Return fall
    /// through to the sheet's default button, so a teacher who has
    /// typed a code and never touched the arrows can still hit Return
    /// to create the course.
    var onCommitHighlight: () -> Bool = { false }

    @FocusState var codeFieldHasFocus: Bool

    /// The chevron button's numbers below were MEASURED off a real
    /// `NSComboBox` — a 260x24pt one rendered offscreen at 2x in both
    /// appearances and read back pixel by pixel (2026-08-23; the harness
    /// and the findings table are in `research/native-control-metrics/`).
    /// The FIELD's own measured numbers (24pt tall, a 6pt radius, a 6pt
    /// text inset, a 3pt baseline nudge) lived here too until #456, when
    /// the drawn imitation of AppKit's bezel they drove was replaced by the
    /// real `.roundedBorder` bezel every other field wears; they are in
    /// git history and in `documentation/09-mac-app.md` → "#456".
    ///
    /// The chevron button: 24 x 19pt, 4pt in from the field's trailing
    /// edge — read straight off the rendered button's fill bounds
    /// (x 464-511, y 4-41 in 2x device pixels on a 520x48 render).
    /// Its 5pt corner radius comes from the same circle fit as the
    /// field's: inset per row 8,5,3,2,2,1,1,1,0, which a 10px (= 5pt)
    /// radius predicts on every row.
    ///
    /// Deliberately NOT derived from the field's height: the button's height
    /// is its own measured number, and tying it to the field height (as
    /// an earlier version did) meant a change to one silently moved the
    /// other away from what AppKit actually draws.
    static let revealButtonWidth: CGFloat = 24
    static let revealButtonHeight: CGFloat = 19
    static let revealButtonCornerRadius: CGFloat = 5
    static let revealButtonTrailingInset: CGFloat = 4

    /// The chevron glyph, sized to the 7.5 x 4.5pt one AppKit draws.
    /// Found by rendering `chevron.down` across sizes 8-13 at four
    /// weights and measuring each glyph's tight bounds: 8.5pt semibold
    /// is the size that lands on 7.5 x 4.5 exactly.
    static let revealButtonGlyphSize: CGFloat = 8.5

    /// The button's fill. A real combo box's button is NOT tinted —
    /// Russell's fifth point, and the measurement agrees: it renders as
    /// a barely-lighter grey than the field itself (41,41,41 on a
    /// 23,23,23 field in dark; 235,235,235 on white in light).
    ///
    /// Two DIFFERENT semantic colours are needed to hit both, because
    /// AppKit draws this button with its own control artwork rather
    /// than from a single named fill: `tertiarySystemFill` composites
    /// to exactly (41,41,41) in dark, and `secondarySystemFill` to
    /// exactly (235,235,235) in light. Using either one alone is
    /// visibly off in the other appearance (dark's secondary lands at
    /// 48, light's tertiary at 243), so this resolves per appearance
    /// rather than picking a compromise.
    static var revealButtonFillColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark: Bool = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor.tertiarySystemFill : NSColor.secondarySystemFill
        })
    }

    // MARK: - Body

    var body: some View {
        TextField("", text: $courseCode)
            .focused($codeFieldHasFocus)
            // Bound to the `TextField` itself, before the chrome adds
            // anything for it to collide with. Chained AFTER the chevron
            // `.overlay` (tried first, 2026-08-23) it applied to the
            // merged TextField+overlay element and silently OVERWROTE
            // the button's own `"courseCodeRevealButton"` identifier —
            // confirmed via the unified log's accessibility snapshot,
            // which showed both elements reporting
            // `"wizardCourseCodeField"`.
            .accessibilityIdentifier("wizardCourseCodeField")
            .anchorPreference(key: CourseCodeFieldAnchorKey.self, value: .bounds) { anchor in
                anchor
            }
            // Consumes Escape while the popup is shown, so that press
            // closes the popup rather than falling through to the
            // sheet's own Escape-dismisses-the-wizard handling
            // (Russell, 2026-08-22: "hitting the escape key … should
            // close the list below, not dismiss the form"). With no
            // popup, Escape reaches the sheet and closes the wizard as
            // Cancel would — until v1.5.0 it was consumed regardless,
            // a keyboard trap (#457, `PickerEscape`).
            .onKeyPress(.escape) {
                return PickerEscape.result(listWasOpen: onEscape())
            }
            // Up/down walk the popup and Return takes the highlighted
            // row, the way a real `NSComboBox` does (Russell,
            // 2026-08-23). Each handler asks the wizard first and
            // reports `.ignored` when the wizard declines, so with no
            // popup open the arrows still move the insertion point and
            // Return still triggers the sheet's default button — the
            // keys keep their ordinary meanings rather than being
            // swallowed whenever this field happens to have focus.
            .onKeyPress(.upArrow) {
                onMoveHighlight(-1) ? .handled : .ignored
            }
            .onKeyPress(.downArrow) {
                onMoveHighlight(1) ? .handled : .ignored
            }
            .onKeyPress(.return) {
                onCommitHighlight() ? .handled : .ignored
            }
            // The ONE bezel every field in Plantoir wears (#374), since
            // #456: the 24pt imitation of an AppKit bezel this used to draw
            // is gone, so this field, Course name beside it and every other
            // field are the same height by construction. The chevron is
            // overlaid on the real field; text long enough to reach it runs
            // under it, the accepted trade (#456).
            .borderedTextField()
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            // The visual cue a Mac user already knows: a trailing
            // chevron reads as "this field also has a menu behind it"
            // the way `NSComboBox` itself always shows one (Russell,
            // 2026-08-22, pointing at Apple's own HIG combo-box
            // illustration). Tapping it opens the popup and puts the
            // cursor in the field, same as clicking the field itself
            // would — it's a second way in, not a different control.
            // A real AppKit button (`RevealChevronButton`): the real bezel's
            // `NSTextField` takes a click meant for a SwiftUI overlay (#456).
            // Untinted, the way a real combo box's button is — see
            // `revealButtonFillColor`; the history of the tint and the glyph
            // colour is on those constants.
            .overlay(alignment: .trailing) {
                RevealChevronButton(
                    accessibilityIdentifier: "courseCodeRevealButton",
                    accessibilityLabel: "Browse course codes"
                ) {
                    // The wizard's own focus flag as well as the field's:
                    // the popup follows the former, and a focus write from
                    // an AppKit button's action is not always mirrored into
                    // `@FocusState` in the same turn (#456).
                    isFocused = true
                    codeFieldHasFocus = true
                    onRevealRequested()
                }
                .padding(.trailing, CourseCodePickerView.revealButtonTrailingInset)
            }
            .onChange(of: codeFieldHasFocus) {
                isFocused = codeFieldHasFocus
            }
            .onChange(of: isFocused) {
                // Lets the wizard close the popup (e.g. after a
                // selection) by dropping the binding — mirrored back
                // into this view's own `@FocusState` so the field
                // actually loses focus too, not just the wizard's
                // bookkeeping.
                if codeFieldHasFocus != isFocused {
                    codeFieldHasFocus = isFocused
                }
            }
            // A wizard that opens with focus here (#457, the HIG sweep)
            // asked for it before this view existed, so `onChange` never
            // fires for it — the same seam `SearchablePickerField` has.
            .onAppear {
                if isFocused {
                    codeFieldHasFocus = true
                }
            }
    }
}


/// What the wizard compares, frame to frame, to decide whether the popup
/// deserves an animated transition: whether it's shown at all, and which
/// rows are in it — typing a further letter narrows `rowIDs`, and that
/// narrowing should animate too, not just the popup's initial appearance.
struct CourseCodeSuggestionsAnimationKey: Equatable {
    let isShown: Bool
    let rowIDs: [String]
}

/// The popup itself: a floating card of rich, two-line rows — the same
/// look the wizard used before the `NSComboBox` detour, and what Russell
/// asked to keep — positioned flush with `fieldFrame`'s own edges rather
/// than left to auto-size. Rendered by the wizard OUTSIDE its `Form`, at
/// the top level of the sheet, so it draws over the rest of the form
/// instead of being pushed-into-layout or row-clipped.
struct CourseCodeSuggestionsOverlay: View {

    // MARK: - Stored properties

    let fieldFrame: CGRect
    let province: String
    let entries: [CourseCatalogEntry]
    let onSelect: (CourseCatalogEntry) -> Void

    /// The row the arrow keys are currently sitting on, or `nil` when
    /// the teacher has not walked the list. Kept by the wizard rather
    /// than here so that the KEY HANDLERS — which live on the field,
    /// the only thing with focus — and the drawing stay in agreement.
    var highlightedID: String? = nil

    /// Enough rows visible at once to feel like browsing rather than
    /// peeking, without the card outgrowing the sheet.
    static let maxVisibleRows: Int = 6
    static let rowHeight: CGFloat = 42

    // MARK: - Body

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("No \(CourseCatalog.provinceName(forCode: province)) course matches — this will be added as a custom code, e.g. for a club.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(width: fieldFrame.width, alignment: .leading)
                    .background(card)
                    .accessibilityIdentifier("courseCodeNoMatches")
            } else {
                ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            Button {
                                onSelect(entry)
                            } label: {
                                row(for: entry)
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                            .accessibilityIdentifier("courseCodeSuggestion-\(entry.code)")
                            // Individual rows fade in and out as typing
                            // narrows the list, rather than the whole
                            // list just jumping to its new row count.
                            .transition(.opacity)

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(
                    width: fieldFrame.width,
                    height: min(CGFloat(entries.count), CGFloat(CourseCodeSuggestionsOverlay.maxVisibleRows)) * CourseCodeSuggestionsOverlay.rowHeight
                )
                .background(card)
                .accessibilityIdentifier("courseCodeSuggestionsList")
                // Walking past the visible rows scrolls rather than
                // running the highlight off the bottom of the card —
                // the list can be the whole province catalog, and only
                // six rows are on screen.
                .onChange(of: highlightedID) { _, newValue in
                    if let newValue {
                        scroller.scrollTo(newValue, anchor: .bottom)
                    }
                }
                }
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .offset(x: fieldFrame.minX, y: fieldFrame.maxY + 4)
        // `fieldFrame` itself must never be what's animating — only the
        // popup's ENTRANCE (the `.transition` the wizard applies) should.
        // Without this, the wizard's ambient `.animation` (there for that
        // transition) also sweeps up any change to `fieldFrame` that
        // lands in the same render pass — and on the very FIRST focus,
        // the `Form` hasn't finished settling its layout yet, so the
        // anchor briefly resolves to a too-wide provisional frame before
        // correcting; caught animating, that correction reads as the
        // popup stretching past the field's edges for an instant before
        // snapping back (Russell, 2026-08-22). Every later focus is
        // unaffected because the `Form` has already settled by then.
        .animation(nil, value: fieldFrame)
    }

    var card: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.quaternary)
            )
    }

    func row(for entry: CourseCatalogEntry) -> some View {
        let isHighlighted: Bool = entry.id == highlightedID
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.code)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                    if entry.hasExampleContent {
                        ExampleContentBadge(isOnHighlightedRow: isHighlighted)
                    }
                }
                // A trailing `Spacer` here (an earlier version) leaves
                // this `Text` an UNBOUNDED width proposal — nothing
                // stops it rendering at its full intrinsic width for a
                // long formal name, wider than the card. Ordinarily the
                // `ScrollView` clips that quietly, but during this
                // popup's own appear TRANSITION, the clip and the
                // transition's opacity/offset don't always land in the
                // same composited frame — a real SwiftUI-on-macOS
                // rendering quirk, not a timing issue — so the untruncated
                // width could flash visible for an instant (Russell,
                // 2026-08-22). `.lineLimit(1)` on a `Text` given an
                // actually BOUNDED proposal (via `.frame(maxWidth:
                // .infinity)` below, replacing the `Spacer`) truncates
                // instead of ever wanting to be wider in the first
                // place — nothing left to clip, so nothing left to
                // flicker.
                Text(entry.formalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(height: CourseCodeSuggestionsOverlay.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        // The accent fill a native popup gives its selected row, with
        // white text over it. Applied to the WHOLE row rather than to
        // the code alone so the formal name underneath is legible
        // against it too.
        .background(isHighlighted ? Color.accentColor : Color.clear)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// The small pill marking a course code that ships with ready-made
/// example content — the same marker the standalone course-code
/// reference list uses, so a teacher who has seen that list recognises
/// it here.
struct ExampleContentBadge: View {

    // MARK: - Stored properties

    /// Whether this badge is sitting on the popup row the keyboard has
    /// highlighted. That row is filled with the accent colour, and an
    /// accent capsule on an accent row is invisible — the badge read as
    /// plain white text, losing the pill entirely (seen the moment
    /// keyboard highlighting landed, 2026-08-23). On a highlighted row
    /// the badge INVERTS instead: white capsule, accent text.
    var isOnHighlightedRow: Bool = false

    // MARK: - Body

    var body: some View {
        Text("Example content")
            .font(.caption2.bold())
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(isOnHighlightedRow ? Color.accentColor : Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(isOnHighlightedRow ? Color.white : Color.accentColor))
    }
}
