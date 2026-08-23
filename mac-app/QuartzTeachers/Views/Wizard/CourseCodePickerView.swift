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

/// The course-code row of the new-course wizard: a Province picker above
/// a plain, bordered text field. This view is only the INPUT half — the
/// popup itself (`CourseCodeSuggestionsOverlay`) is rendered by the
/// wizard at the top level of its own sheet, not nested inside this
/// view's `Form` section, so it can float over the rest of the form
/// rather than push it downward and so it is never clipped by the
/// Form/List machinery a `Section` sits inside. This view's whole job is
/// therefore: hold the typed text, own the field's focus state, publish
/// an anchor to its own bounds, and publish its focus out to the wizard
/// via a binding.
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
    @Binding var province: String

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
    /// dismissing the list, same as a native combo box's popup.
    var onEscape: () -> Void = {}

    /// The trailing chevron button, pressed — the wizard uses this to
    /// re-open the popup even when the field is ALREADY focused (e.g.
    /// Escape had just closed it), which a plain focus change wouldn't
    /// trigger on its own since nothing about focus is changing.
    var onRevealRequested: () -> Void = {}

    @FocusState var codeFieldHasFocus: Bool

    /// The whole field's height. Measured against the plain
    /// `.roundedBorder` `TextField` below it (Course Name) at 46pt —
    /// this field was a visibly shorter 40pt, so it's 6pt taller here
    /// (3pt top, 3pt bottom around the text) to close that gap
    /// (Russell, 2026-08-23). The `TextField` inside is centred
    /// vertically by the `ZStack`'s default alignment, so growing this
    /// value alone is what adds that 3pt top/bottom — no separate
    /// padding on the `TextField` itself is needed.
    static let fieldHeight: CGFloat = 30
    static let fieldCornerRadius: CGFloat = 6

    /// Sized and inset for an explicit 3pt margin on every side that
    /// touches the field: 3pt above and below (so `revealButtonHeight`
    /// is `fieldHeight` minus 6), and 3pt in from the field's own
    /// trailing edge (Russell, 2026-08-23).
    static let revealButtonWidth: CGFloat = 22
    static let revealButtonHeight: CGFloat = fieldHeight - 6
    static let revealButtonCornerRadius: CGFloat = 5
    static let revealButtonTrailingInset: CGFloat = 3

    /// White or black, chosen by the SYSTEM accent colour's own
    /// luminance — never hard-coded, since `Color.accentColor` can be a
    /// pale colour (Graphite, or a light custom choice in System
    /// Settings), and a fixed white glyph on a pale pill would fail
    /// contrast for exactly those users. Standard relative-luminance
    /// weighting (ITU-R BT.601); 0.6 is a deliberately generous
    /// threshold — the pill is small, so erring toward black on
    /// medium-brightness accents reads more reliably than erring toward
    /// white.
    static var revealButtonGlyphColor: Color {
        let accent: NSColor = (NSColor.controlAccentColor.usingColorSpace(.deviceRGB)) ?? NSColor.controlAccentColor
        let luminance: CGFloat = 0.299 * accent.redComponent + 0.587 * accent.greenComponent + 0.114 * accent.blueComponent
        return luminance > 0.6 ? .black : .white
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Province", selection: $province) {
                Text("Ontario").tag("ON")
                Text("British Columbia").tag("BC")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("wizardProvincePicker")
            .padding(.bottom, 6)

            // The trailing chevron sits ON its own filled pill, inset
            // inside the field with room to spare on every side — not a
            // bare glyph floating over the field's own background. This
            // is drawn as one composite control rather than an overlay
            // on top of `.textFieldStyle(.roundedBorder)`: that style's
            // exact internal geometry (how much of its own trailing edge
            // is padding versus the visible rounded pill) isn't
            // something SwiftUI exposes, and overlaying a plain glyph on
            // it — tried first, same day — rendered detached from the
            // field rather than contained inside it. Drawing the field's
            // own background and border here removes the guesswork:
            // the chevron's pill is inset from bounds THIS view
            // controls completely.
            //
            // Proportions match the reference Russell gave (2026-08-22,
            // an HIG combo-box illustration): the pill is most of the
            // field's height (leaving a small margin top and bottom),
            // close to square, sitting a small margin in from the
            // field's own trailing edge.
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: CourseCodePickerView.fieldCornerRadius)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: CourseCodePickerView.fieldCornerRadius)
                    .strokeBorder(
                        codeFieldHasFocus ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: codeFieldHasFocus ? 2 : 1
                    )

                TextField("Course code", text: $courseCode)
                    .textFieldStyle(.plain)
                    .focused($codeFieldHasFocus)
                    .padding(.leading, 8)
                    // Room for the chevron pill so typed text and the
                    // cursor never run underneath it.
                    .padding(.trailing, CourseCodePickerView.revealButtonWidth + CourseCodePickerView.revealButtonTrailingInset + 6)
                    .accessibilityIdentifier("wizardCourseCodeField")
                    .anchorPreference(key: CourseCodeFieldAnchorKey.self, value: .bounds) { anchor in
                        anchor
                    }
                    // Consumes Escape whenever this field has focus, so it
                    // closes the popup rather than falling through to the
                    // sheet's own Escape-dismisses-the-wizard handling
                    // (Russell, 2026-08-22: "hitting the escape key … should
                    // close the list below, not dismiss the form").
                    .onKeyPress(.escape) {
                        onEscape()
                        return .handled
                    }

                // The visual cue a Mac user already knows: a trailing
                // chevron reads as "this field also has a menu behind
                // it" the way `NSComboBox` itself always shows one
                // (Russell, 2026-08-22, pointing at Apple's own HIG
                // combo-box illustration). Tapping it opens the popup
                // and puts the cursor in the field, same as clicking the
                // field itself would — it's a second way in, not a
                // different control.
                Button {
                    codeFieldHasFocus = true
                    onRevealRequested()
                } label: {
                    RoundedRectangle(cornerRadius: CourseCodePickerView.revealButtonCornerRadius)
                        // Filled with the accent colour specifically so
                        // there's always strong contrast against the
                        // field's own background, in both light and dark
                        // appearance — Russell's explicit requirement,
                        // and the one thing missing from the very first
                        // attempt at this same day.
                        .fill(Color.accentColor)
                        .overlay(
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                // NOT hard-coded white: `Color.accentColor`
                                // tracks the user's chosen SYSTEM accent
                                // colour, which includes pale ones
                                // (Graphite, or a light custom colour) —
                                // a white glyph on a pale pill can fail
                                // Russell's "sufficient contrast" rule
                                // for exactly those users. Picked from the
                                // accent colour's own luminance instead,
                                // so the pill stays high-contrast whatever
                                // colour it ends up being.
                                .foregroundStyle(CourseCodePickerView.revealButtonGlyphColor)
                        )
                        .frame(
                            width: CourseCodePickerView.revealButtonWidth,
                            height: CourseCodePickerView.revealButtonHeight
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, CourseCodePickerView.revealButtonTrailingInset)
                .accessibilityIdentifier("courseCodeRevealButton")
                .accessibilityLabel("Browse course codes")
            }
            .frame(height: CourseCodePickerView.fieldHeight)
            // `.accessibilityElement(children: .contain)` FIRST, before
            // the identifier — without it, SwiftUI's default behaviour
            // merges a container that has one dominant interactive child
            // into a SINGLE accessibility element, and the identifier
            // set here would silently overwrite the `TextField`'s own
            // "wizardCourseCodeField" rather than existing alongside it
            // as a second, separate element. That's exactly what
            // happened the first time this was written: EVERY existing
            // UI test that looks up `textFields["wizardCourseCodeField"]`
            // — none of them about the reveal button — started failing,
            // because the identifier had been silently overwritten, not
            // because the wizard sheet stopped opening (confirmed via
            // the unified log's own accessibility-snapshot dump, which
            // still showed the wizard's title and other fields present,
            // just with `wizardCourseCodeFieldBackground` sitting where
            // `wizardCourseCodeField` used to be). `.contain` keeps this
            // ZStack a real container so the `TextField`'s own identifier
            // survives untouched.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("wizardCourseCodeFieldBackground")
        }
        .onChange(of: codeFieldHasFocus) {
            isFocused = codeFieldHasFocus
        }
        .onChange(of: isFocused) {
            // Lets the wizard close the popup (e.g. after a selection)
            // by dropping the binding — mirrored back into this view's
            // own `@FocusState` so the field actually loses focus too,
            // not just the wizard's bookkeeping.
            if codeFieldHasFocus != isFocused {
                codeFieldHasFocus = isFocused
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            Button {
                                onSelect(entry)
                            } label: {
                                row(for: entry)
                            }
                            .buttonStyle(.plain)
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
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.code)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                    if entry.hasExampleContent {
                        ExampleContentBadge()
                    }
                }
                // A trailing `Spacer` here (the earlier version) leaves
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
    }
}

/// The small pill marking a course code that ships with ready-made
/// example content — the same marker the standalone course-code
/// reference list uses, so a teacher who has seen that list recognises
/// it here.
struct ExampleContentBadge: View {

    // MARK: - Body

    var body: some View {
        Text("Example content")
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
    }
}
