import SwiftUI

/// Which side of the conversation something belongs to.
nonisolated enum AssistChatSide: Equatable {

    case teacher
    case assistant

    /// Not part of the back and forth at all — a restore, which is a thing
    /// that HAPPENED rather than a thing anybody said. It sits in the flow
    /// without a bubble, and it neither wears a tail nor interrupts anyone's
    /// turn.
    case neither
}

/// Where a batch of messages ends, and therefore where the tail goes.
///
/// A tail on every bubble makes a run of three messages look like three
/// separate interruptions. One tail, on the LAST message a participant sends
/// before the other one answers, is what reads as a turn — the same rule
/// Messages uses, which is why it is the rule a teacher will already expect
/// without being able to say so.
@MainActor
enum AssistChatLayout {

    // MARK: - Functions

    /// Everything the assistant produces is the assistant talking.
    ///
    /// Results and problems used to sit outside the conversation as plain
    /// lines with an icon, which made the window read as a chat with a log
    /// spliced through it. "The preview is rebuilding now" is the assistant
    /// answering; that it happens to have come from a tool is machinery, and
    /// the teacher is not the audience for machinery.
    static func side(of speaker: AssistAgent.Entry.Speaker) -> AssistChatSide {
        switch speaker {
        case .teacher:
            return .teacher
        case .assistant, .toolResult, .problem:
            return .assistant
        }
    }

    /// Whether the bubble at `index` is the last of its participant's run.
    ///
    /// Takes the SIDES rather than the speakers, because the transcript holds
    /// things nobody said — a restore — which belong to neither participant
    /// and must not end a turn.
    static func showsTail(at index: Int, in sides: [AssistChatSide]) -> Bool {
        guard sides.indices.contains(index) else {
            return false
        }
        let mine: AssistChatSide = sides[index]
        if mine == .neither {
            return false
        }
        var next: Int = index + 1
        while next < sides.count {
            let theirs: AssistChatSide = sides[next]
            if theirs != .neither {
                return theirs != mine
            }
            next += 1
        }
        // Nothing said after it, so it is the end of the run so far.
        return true
    }
}

/// A chat bubble shaped like the one Messages draws.
///
/// **Measured, not eyeballed.** Every number here was read off a screenshot of
/// a real Messages conversation, pixel by pixel, after three attempts at
/// guessing produced three different wrong shapes. Re-measured 2026-08-15
/// against a side-by-side comparison, which corrected one of the originals:
/// the "corner radius 12" below is Messages' MULTI-LINE radius; a single-line
/// bubble is a capsule (see `capsuleLimit`), and the tail ratios below were
/// confirmed exactly (tip inset 0.42r, drop 0.33r, corner end 0.54r).
///
/// | | |
/// |---|---|
/// | corner radius, multi-line | 17 |
/// | corner radius, single line | half the body height |
/// | visible text inset, sides | 13 (see `SelectableBubbleText`) |
/// | tail drop below the body | 5.1, one size for every bubble |
/// | corner landing on the bottom line | 0.47 of the radius |
/// | tail tip, INSIDE the body's edge | 6.5 |
///
/// Two of those corrected assumptions worth stating, because both look right
/// until measured. The tail **hangs below** the bubble — it is not level with
/// the bottom edge. And it stays **within the bubble's width**: its tip is
/// seven points INSIDE the right edge, not outside it. A tail drawn
/// past the side reads as a wedge stuck onto the corner, which is what the
/// last version was.
///
/// So the bubble is a rounded rectangle whose bottom corner, on the speaker's
/// side, dips into a small hook. The hook's underside is concave, curving back
/// up into the bottom edge — that curve, rather than the tip, is what makes
/// the shape read as a tail.
///
/// Proportions are held relative to the corner radius so a short bubble and a
/// tall one are the same design, and everything is drawn inside the rect the
/// background is given, since anything outside it is clipped.
///
/// `nonisolated` because `Shape.path(in:)` is, and SwiftUI may draw a shape off
/// the main thread. The macOS 26 SDK did this implicitly (`Shape` carried a
/// `_RemoveGlobalActorIsolation` marker that undid this target's default
/// MainActor isolation); the macOS 27 SDK does not, and without the keyword
/// Xcode 27 refuses the conformance (#613). The shape is pure geometry, so
/// nothing in it needs the main actor.
nonisolated struct AssistChatBubbleShape: Shape {

    // MARK: - Stored properties

    let side: AssistChatSide
    let hasTail: Bool

    /// The strip below the bubble that the tail hangs into. Nothing is needed
    /// at the sides: the tail never reaches past the bubble's own edge.
    static let drop: CGFloat = 6

    /// Messages' corner radius — an ABSOLUTE of the design, like the tail.
    /// Measured same-screen at ~17pt here and ~16pt in a capture at a
    /// different text size; an earlier 12 came from scaling their radius by
    /// the font ratio, which made every bubble read as having straight ends
    /// beside Messages. At 17, `min(corner, half the height)` is the entire
    /// radius rule: a single-line bubble's half-height is smaller, so it
    /// becomes a capsule with no separate branch — which is exactly the
    /// capsule behaviour Messages shows.
    private let corner: CGFloat = 17

    /// What the tail's measurements scale from — and it is neither the
    /// bubble's corner radius nor anything to do with the text size. A
    /// three-line and a one-line bubble carry the SAME tail while their
    /// corner radii differ, so the tail is a constant of the design, like a
    /// pen width; scaling it with the corner, as this shape originally did,
    /// shrank every multi-line bubble's tail to a nub.
    ///
    /// THIS number must come from a screenshot with both apps in it. It was
    /// first derived by comparing two separate captures, which requires
    /// knowing each one's pixels-per-point — both were guessed, one wrongly,
    /// and the tail shipped a fifth too large. The final value comes from
    /// one screenshot of Messages and this app side by side on the same
    /// screen, where the scale cancels out: 17, giving a 5.7 drop, a 9.2
    /// corner landing, a 7.1 tip inset and a 16.3 hook.
    private let tailScale: CGFloat = 17

    // MARK: - Functions

    func path(in rect: CGRect) -> Path {
        // Every bubble gives up the same strip beneath it, tail or no tail, so
        // a run of them sits on one rhythm rather than jumping wherever a turn
        // ends.
        var body: CGRect = rect
        body.size.height -= AssistChatBubbleShape.drop

        let radius: CGFloat = min(corner, body.height / 2, body.width / 2)

        guard hasTail, side != .neither else {
            return Path(roundedRect: body, cornerRadius: radius)
        }

        // Written for a tail on the right, then mirrored. `at` flips x when
        // the tail belongs on the left, so there is one path to read and one
        // to get right.
        let flip: Bool = (side == .assistant)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: flip ? (rect.maxX - (x - rect.minX)) : x, y: y)
        }

        // Measured off Messages, expressed against `tailScale` — one size of
        // tail for every size of bubble, which is what Messages draws. The
        // tip sits LESS inset than the corner's landing, and that is the
        // whole character of the thing: the outer edge comes in with the
        // corner and then eases back out and down. An outer edge that keeps
        // curving inward gives a fin, which is what two early attempts drew.
        //
        // Retraced 2026-08-15 at native 2x against a side-by-side capture,
        // which settled three complaints at once: the tail was too WIDE (the
        // hook rejoined too far in), the side above it swept in too steeply
        // (the jog needs more height than the radius gives it), and the
        // silhouette had sharp vertices where Messages has none — the tip is
        // rounded about a point and a half across, and the hook meets the
        // bottom edge in a small curve, not a corner.
        let dropBelow: CGFloat = tailScale * 0.30     // 5.1
        // Where the corner lands on the bottom line follows the RADIUS, not
        // the tail scale: measured at just over half of it on a capsule and
        // a multi-line bubble alike.
        let cornerEnd: CGFloat = radius * 0.47
        let tipInset: CGFloat = tailScale * 0.38      // 6.5
        let hookBase: CGFloat = min(tailScale * 0.85, body.width / 2)

        // The jog gets exactly the radius of height, like the corner it
        // replaces: traced on a two-line bubble, Messages spends about 8
        // points of inset over about 16 of descent, with the edge held
        // nearly flat for the first half and the dive concentrated in the
        // last — a LONGER span drifted visibly early and read as a diagonal
        // cut into the side. Clamped so a capsule, whose edge above is
        // already curved, never starts the jog before the side exists.
        let jogSpan: CGFloat = min(radius, body.height - radius)

        var path: Path = Path()

        // Top edge, left to right.
        path.move(to: at(body.minX + radius, body.minY))
        path.addLine(to: at(body.maxX - radius, body.minY))
        path.addQuadCurve(to: at(body.maxX, body.minY + radius),
                          control: at(body.maxX, body.minY))

        // Down the right edge, then the corner into the tail — and the whole
        // character of the joint is the TANGENT it ends on: the silhouette
        // reaches its deepest inset exactly at the bottom line while
        // travelling straight DOWN. A corner curve that lands travelling
        // horizontally — a normal rounded corner — meets the descending tail
        // edge in a cusp, and the tail reads as a comma stuck under the
        // bubble rather than the corner pulled down. Weighted to hug the
        // side and complete the jog late, like the top corner mirrored.
        path.addLine(to: at(body.maxX, body.maxY - jogSpan))
        path.addCurve(
            to: at(body.maxX - cornerEnd, body.maxY),
            control1: at(body.maxX, body.maxY - jogSpan * 0.30),
            control2: at(body.maxX - cornerEnd, body.maxY - jogSpan * 0.215)
        )

        // Still heading down at the bottom line; eases outward toward the
        // tip, stopping where the tip's rounding begins.
        path.addQuadCurve(
            to: at(body.maxX - tipInset + 0.7, body.maxY + dropBelow - 1.3),
            control: at(body.maxX - cornerEnd + 0.4, body.maxY + dropBelow * 0.55)
        )

        // The rounded tip, about a point and a half across.
        path.addQuadCurve(
            to: at(body.maxX - tipInset - 0.9, body.maxY + dropBelow - 0.4),
            control: at(body.maxX - tipInset, body.maxY + dropBelow + 0.4)
        )

        // The hook: back up and in, concave, toward the bottom edge. This
        // curve — not the tip — is what makes the shape read as a tail. The
        // traced inner edge is a diagonal with a mild sag toward the bubble,
        // not a deep scoop.
        path.addQuadCurve(
            to: at(body.maxX - hookBase + 1.2, body.maxY + 0.8),
            control: at(body.maxX - tailScale * 0.72, body.maxY + dropBelow * 0.5)
        )

        // And a small curve into the bottom edge where a corner used to be.
        path.addQuadCurve(
            to: at(body.maxX - hookBase - 1.6, body.maxY),
            control: at(body.maxX - hookBase, body.maxY)
        )

        // Bottom edge back to the far side, and up.
        path.addLine(to: at(body.minX + radius, body.maxY))
        path.addQuadCurve(to: at(body.minX, body.maxY - radius),
                          control: at(body.minX, body.maxY))
        path.addLine(to: at(body.minX, body.minY + radius))
        path.addQuadCurve(to: at(body.minX + radius, body.minY),
                          control: at(body.minX, body.minY))
        path.closeSubpath()
        return path
    }
}

/// The assistant thinking, as three dots that breathe.
///
/// The conversation used to go silent between the teacher pressing return and
/// the answer arriving — several seconds in which the only honest reading was
/// that nothing had happened. Everyone who has used a messaging app knows what
/// three pulsing dots mean, so nothing has to be explained.
///
/// **It is a THOUGHT bubble, not a speech bubble.** Messages draws this one
/// differently from everything else in the conversation: a capsule, with two
/// plain circles stepping down toward the speaker — the comic-strip sign for
/// thinking — rather than the pointed tail that marks something said. Ours
/// wore the speech tail, and that is part of what made it read as off.
///
/// Sized from a screen recording of Messages itself (frame-extracted and
/// measured, 2026-08-15), as ratios of the bubble's height: the capsule
/// about 1.7 times as wide as tall, dots about 0.24 of the height with a
/// gap about half a dot, the larger thought-circle about 0.40 poking two
/// points past the lower corner, the smaller about 0.14 below and outside
/// it. An earlier pass used a piece of reference artwork instead and got
/// the circle small and the dots big; the recording of the real thing
/// corrected both. The height itself matches a single-line message bubble,
/// so the indicator sits in the conversation as exactly the thing it stands
/// for: a message that is on its way.
struct AssistTypingIndicator: View {

    // MARK: - Stored properties

    /// Drives the animation. Toggled once when the view appears; the phase
    /// difference between the dots comes from each dot's delay, not from three
    /// separate pieces of state.
    @State private var isBreathing: Bool = false

    /// A single-line message bubble's body: one line of callout text plus
    /// the 7-point padding above and below it.
    private let bubbleHeight: CGFloat = 29

    /// About a quarter of the bubble's height, measured off the recording;
    /// an earlier 9 came from artwork and crowded the capsule.
    private let dot: CGFloat = 7

    // MARK: - Computed properties

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: dot, height: dot)
                        .opacity(isBreathing ? 0.95 : 0.35)
                        // Each dot lags the one before it, so the three read
                        // as a wave rather than as a single blink.
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                            value: isBreathing
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: bubbleHeight)
            // ONE shape holding the capsule and both thought-circles, filled
            // once. The bubble colour is translucent, so drawing the circles
            // as separate views doubled the fill where they overlapped the
            // capsule — a brighter lens along the join that Messages, drawing
            // one flat shape, does not have.
            .background(AssistThoughtBubbleShape().fill(AssistBubbleColour.assistant))
            .padding(.bottom, AssistChatBubbleShape.drop)
            Spacer(minLength: 48)
        }
        .onAppear {
            isBreathing = true
        }
        // Read out as one thing rather than as three dots.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The assistant is working")
        .accessibilityIdentifier("assistTypingIndicator")
    }
}

/// The typing indicator's outline: the capsule and the two thought-circles
/// stepping down toward the speaker, as one shape.
///
/// One shape because the fill is TRANSLUCENT: separate views double the
/// colour where they overlap, and the join between circle and capsule shows
/// as a brighter lens. Subpaths filled together union cleanly.
///
/// The rect is the capsule; the circles hang below and to the left of it,
/// which a `Shape` is free to draw (`.background` does not clip). Sizes and
/// positions are ratios of the capsule's height, measured from a screen
/// recording of Messages: the larger circle 0.41 of it, poking about two
/// points past the corner; the smaller 0.14, below and outside with a
/// sliver of gap.
///
/// `nonisolated` for the same reason as `AssistChatBubbleShape` (#613).
nonisolated struct AssistThoughtBubbleShape: Shape {

    // MARK: - Functions

    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))

        let large: CGFloat = rect.height * 0.41
        path.addEllipse(in: CGRect(
            x: rect.minX - 2,
            y: rect.maxY + 2 - large,
            width: large,
            height: large
        ))

        let small: CGFloat = rect.height * 0.14
        path.addEllipse(in: CGRect(
            x: rect.minX - 3.5,
            y: rect.maxY + 6 - small,
            width: small,
            height: small
        ))
        return path
    }
}

/// Text the assistant said, with its **bold** rendered.
///
/// `Text(someString)` does NOT parse markdown — only a string LITERAL is
/// treated as a localised key and styled. The plans are built at runtime, so
/// their emphasis would otherwise reach the teacher as literal asterisks.
///
/// `.inlineOnlyPreservingWhitespace` is the interpretation that matters:
/// the default one treats the text as a markdown DOCUMENT and throws the line
/// breaks away, which would run a plan's headings and its list into one
/// paragraph. This keeps the layout and styles only what is inline.
///
/// Anything that fails to parse is shown exactly as it arrived. A stray
/// asterisk in a page title should look odd, never swallow the message.
@MainActor
enum AssistSaid {

    // MARK: - Functions

    static func styled(_ text: String) -> AttributedString {
        if let parsed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return parsed
        }
        return AttributedString(text)
    }
}

/// The two bubble colours.
///
/// **Not `Color.accentColor`.** That is whatever accent the teacher has chosen
/// in System Settings, and it is not always blue: set to graphite it would
/// make the teacher's bubbles grey — the same grey as the assistant's — and
/// the whole left/right, blue/grey distinction the window relies on would
/// quietly disappear. Messages does not follow the accent either; its blue is
/// its own.
///
/// The blue is SAMPLED from a Messages bubble rather than guessed: 20, 147,
/// 255. The obvious candidates are all near it and none is it — the system
/// blue is (0, 122, 255) and its dark variant (10, 132, 255) — and being a
/// few points out is exactly the sort of thing that reads as "nearly right",
/// which is worse than clearly different.
///
/// Taken from a dark-appearance screenshot. Messages appears to use the same
/// blue in both appearances, and this is used in both; if it turns out to
/// differ in light mode, this is the one place to say so.
enum AssistBubbleColour {

    // MARK: - Stored properties

    /// The AppKit forms, for the selectable label inside the bubble — its
    /// selection paints the glyphs in the bubble's own colour, so it needs
    /// these as `NSColor`.
    static let teacherNS: NSColor = NSColor(srgbRed: 20 / 255, green: 147 / 255, blue: 255 / 255, alpha: 1)

    static let teacher: Color = Color(nsColor: AssistBubbleColour.teacherNS)

    /// Messages' grey, not a system token. The token this used to be —
    /// `secondary` at 0.16 — lands on (50, 50, 50) over a dark window while
    /// Messages draws (59, 59, 61), measured from the two apps side by side
    /// on the same backdrop; a translucent fill can only ever be as light as
    /// what sits behind it allows. The dark value is the measured one; the
    /// light value is Messages' long-standing light-mode bubble grey, which
    /// there was no light-mode capture to confirm against — if the light
    /// preview ever looks off, measure before touching either number.
    static let assistantNS: NSColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 59 / 255, green: 59 / 255, blue: 61 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 233 / 255, green: 233 / 255, blue: 235 / 255, alpha: 1)
    }

    static let assistant: Color = Color(nsColor: AssistBubbleColour.assistantNS)
}
