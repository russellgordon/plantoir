import AppKit
import SwiftUI

/// What the assistant tells a teacher it is good at — kept on screen for
/// the whole conversation, not just at the start.
///
/// These nineteen are not decoration. They are measured — the routing suite
/// probes them word for word — and most are matched in code rather than
/// routed, precisely so that what the window promises is what the window
/// delivers. A card offering something the assistant is unreliable at is worse
/// than a card with nothing on it: "What would publishing Unit 3, Day 1
/// change?" was removed for exactly that reason, having gone to the wrong tool
/// on both models ten times out of ten.
///
/// (It said "twelve" until 2026-09-19, from a shelf that had grown by seven
/// without the sentence being re-counted. Count the list rather than trusting
/// a number here, and correct it when you do.)
///
/// **Two tests, and a card has to pass both.** It sat at nine for a while and
/// was missing things the assistant could genuinely do, so nobody was told
/// about them; the fix for that is the first test:
///
/// 1. **Is it reliable?** A phrasing with NO arguments to read out belongs in
///    `AssistCardCommand.fixedShapes` and is then reliable by construction; a
///    phrasing carrying a page title or a date has to go to the model, so it
///    is measured BEFORE it goes on the card, not after.
/// 2. **Is it worth asking for?** Listing a section's pages and reading one
///    back passed the first test at 10/10 and failed this one — a teacher has
///    Obsidian and Plantoir's sidebar open, so a chat bubble is a worse way to
///    see a page than the two windows already in front of them.
///
/// The second test is the one that keeps this a list rather than an inventory.
/// The tool surface is thirteen; the shelf is nineteen of a different set, and
/// the gap is deliberate.
///
/// **Sixteen of the nineteen are answered in code and three reach the model**,
/// measured 2026-09-18 and changed by one on 2026-09-19: "Deploy at 6:30 AM"
/// was among the four that reached it, and the smaller assistant answered it
/// with an immediate deploy ten trials out of ten — so it became a parsed
/// family in `AssistCardCommand` instead (issue #168). Which card is which is
/// pinned by `AssistPromptShelfTests`, not by this comment.
///
/// **Why it stays, and why it folds.** It used to appear only while the
/// conversation was empty, which meant the teacher saw the list once, at the
/// moment they knew least about what to do with it, and never again. But a
/// list this long sitting open would push the conversation off the screen it
/// belongs on. So each kind of request is a disclosure group, shut by
/// default: five short lines a teacher can scan, and open when they want
/// reminding.
struct AssistPromptShelfView: View {

    // MARK: - Stored properties

    /// What this shelf offers: `groups` for an ordinary course, a club's own
    /// list for a course whose pages carry one number (#267) — see
    /// `groups(naming:noun:)`.
    let offered: [(String, [String])]

    /// Called with the phrasing the teacher chose, verbatim — the wording
    /// matters, so nothing paraphrases it on the way through.
    let choose: (String) -> Void

    /// Which groups are open, remembered across windows and launches.
    ///
    /// `@AppStorage` rather than `@SceneStorage` on purpose. Scene storage is
    /// per-window: it would restore this window's shape when THIS window came
    /// back, but opening the assistant on a different section is a different
    /// scene, so a teacher who had opened "Taking it back" would find it shut
    /// again. This is a preference about how they like the shelf, not a fact
    /// about one window — and the app already has a note about scene storage
    /// sharing one value across a window group and losing to the last writer.
    ///
    /// Stored as one string because `@AppStorage` holds no sets. Group titles
    /// contain no `|`, so it is a safe separator; a title that ever does will
    /// simply be forgotten rather than corrupting the rest.
    @AppStorage("AssistPromptShelfOpenGroups", store: PlantoirDefaults.shared) private var openGroupsRaw: String = ""

    /// How tall the groups actually are, measured.
    @State private var contentHeight: CGFloat = 0

    /// The most the shelf may take. Past this it scrolls, so a teacher who
    /// opens every group gives up their own scroll position rather than the
    /// conversation.
    private static let mostHeight: CGFloat = 240

    // MARK: - Computed properties

    /// The open groups, read back from the stored string.
    private var expanded: Set<String> {
        var titles: Set<String> = []
        for piece in openGroupsRaw.split(separator: "|") {
            let title: String = String(piece)
            if !title.isEmpty {
                titles.insert(title)
            }
        }
        return titles
    }

    // MARK: - Computed properties

    /// Grouped the way a teacher thinks about them, not the way the tools
    /// are organised.
    ///
    /// Static, and not private, so a test can read the real list rather than a
    /// copy of it. What a test must NOT do is take the group TITLES from here
    /// — those are checked against a list written out by hand, or the test
    /// would simply agree with whatever the view said. The PHRASINGS are the
    /// opposite case: reading them here is the only way to catch a card whose
    /// wording has drifted away from the matcher that was supposed to serve
    /// it, which is a button that quietly goes to the model on a shape the
    /// model was measured getting wrong.
    static let groups: [(String, [String])] = [
            // NOT "showing work to students". Publishing a page marks it for
            // inclusion — it goes into the next preview and the next deploy —
            // and DEPLOYING is the act that reaches students. A title saying
            // otherwise teaches a teacher that pressing Publish is the moment
            // of no return, which is both wrong and the opposite of
            // reassuring: publishing is the safe, undoable half.
            //
            // The group titles are UI only — never sent to the model — so this
            // costs no routing accuracy. The phrasings inside it are the
            // measured ones and are untouched.
            ("Making pages visible", [
                // No "and everything it links to" any more: publishing a page
                // publishes what it links to by rule, so the short phrasing is
                // the true one. Still true since #173 — the reach now stops at
                // another CLASS page, which makes the short phrasing more
                // accurate rather than less: a teacher who typed "and
                // everything it links to" would be promised more than they get.
                "Publish Unit 2, Day 3",
                "Publish tomorrow's class",
                // Reads the way a teacher says it, and — unlike the earlier
                // "Publish the class on Monday" — it never reaches the model:
                // all seven weekdays are fixed phrasings, so the date is
                // worked out in code and cannot be one the model invented.
                //
                // The model still handles a teacher's own phrasing at 10/10,
                // because every message carries the date. That measurement is
                // in research/ai-assist/shelf-phrasings-results.txt, along with
                // the near-miss worth knowing: probed WITHOUT the dateline the
                // same request landed a month away, 10 out of 10, and a good
                // card was nearly dropped for a fault that belonged to the
                // harness.
                "Publish Monday's class",
                // A whole unit, one class at a time. Parsed rather than
                // listed, because there is no fixed set of unit numbers.
                "Publish Unit 5",
            ]),
            ("Taking it back", [
                "Unpublish Unit 2, Day 3",
                "Unpublish Unit 4",
                "Undo that",
            ]),
            ("Checking", [
                // Kept because `check_section` finds what a preview cannot: a
                // link into a page students can't see, and a visible page
                // nothing links to.
                "What would students see in this section right now?",
                // "Preview", not "Rebuild the preview": it does exactly what
                // the Preview button in the section window does, so it wears
                // the same word.
                "Preview",
                // Listing a section's pages and reading one back were both
                // tried here and REMOVED, and the reason is not routing —
                // both measured 10/10. They are simply not worth a card. A
                // teacher has the pages in front of them in Obsidian and in
                // Plantoir's own sidebar, so reading one back into a chat
                // bubble is a worse way to see it than the two windows they
                // already have open, and a list of file names answers a
                // question nobody with a folder open is asking.
                //
                // The TOOLS stay (`list_pages`, `read_page`): the model uses
                // them to look things up before it acts, which is the job
                // they are actually good for. Not everything the assistant
                // can do is worth telling a teacher they can ask for — a
                // shelf is a list of things worth ASKING FOR, not an
                // inventory of the tool surface.
            ]),
            ("Planning classes", [
                "Add the next class page",
                "Start a new unit for the next class",
                "Add five more days to Unit 4",
                "Duplicate Unit 3, Day 2 as my next class",
                "When are my next classes?",
                "I have a revised list of class dates",
                "Re-date my classes",
            ]),
            ("Putting the site online", [
                "Deploy now",
                "Deploy at 6:30 AM",
                "Cancel scheduled deploy",
            ]),
    ]


    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Says what tapping one DOES. Without it a teacher either never
            // taps — assuming it fires something — or taps once, is surprised,
            // and does not tap again. Saying "then change it" is the important
            // half: these are shapes to start from, and "Publish Unit 2, Day
            // 3" is almost never the page actually wanted.
            Text("Here are some things you can ask me for. Tap one to put it in the box, change it to suit, then press Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Hugs its content when shut, caps and scrolls when open.
            //
            // A ScrollView takes every point it is offered, so on its own it
            // reserved the full cap even with all four groups closed — a
            // stripe of empty space between the shelf and the conversation.
            // Measuring the content and asking for the SMALLER of the two is
            // what makes four closed lines occupy four lines.
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(offered, id: \.0) { group in
                        DisclosureGroup(isExpanded: binding(for: group.0)) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.1, id: \.self) { phrasing in
                                    Button {
                                        choose(phrasing)
                                    } label: {
                                        Text(phrasing)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.secondary.opacity(0.10),
                                                        in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                    // The pointing hand is macOS's own signal
                                    // that something is clickable. A plain
                                    // button style keeps the chip looking the
                                    // way it should and takes the cursor with
                                    // it, so it is put back by hand.
                                    .onHover { isInside in
                                        if isInside {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                    .accessibilityIdentifier("assistSuggestion-\(phrasing)")
                                }
                            }
                            .padding(.top, 4)
                            .padding(.leading, 2)
                        } label: {
                            Text(group.0)
                                .font(.callout)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.bottom, 8)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AssistShelfHeightKey.self, value: proxy.size.height
                        )
                    }
                )
            }
            .frame(height: min(contentHeight, AssistPromptShelfView.mostHeight))
            .onPreferenceChange(AssistShelfHeightKey.self) { measured in
                contentHeight = measured
            }
        }
        .background(.bar)
    }

    // MARK: - Initializer

    init(groups: [(String, [String])] = AssistPromptShelfView.groups, choose: @escaping (String) -> Void) {
        self.offered = groups
        self.choose = choose
    }

    // MARK: - Functions

    /// The shelf for one course.
    ///
    /// An ordinary course gets `groups`, unchanged. A course whose pages carry
    /// ONE number — a club's "Week 3" (#267) — gets a list of its own, in its
    /// own noun and with its own page names, because most of `groups` is about
    /// units and days it does not have: "Publish Unit 5", "Start a new unit",
    /// "Add five more days to Unit 4" would each be refused there.
    ///
    /// **Every card on it is matched in code** (`AssistCardCommand`), so it
    /// promises nothing a model was never measured on. That is why the club
    /// shelf has no "Publish Week 2": publishing one page by its title goes to
    /// the model, and no routing measurement has been made in a club course.
    /// "Duplicate Week 2 as my next meeting" carries a title too, but its frame
    /// is parsed in code, the title lifted out rather than read by a model.
    static func groups(naming: ClassPageNaming, noun: ClassNoun) -> [(String, [String])] {
        if !naming.isNumbered {
            return AssistPromptShelfView.groups
        }
        let one: String = noun.singular
        let many: String = noun.plural
        let second: String = naming.title(unit: 1, day: 2)
        let third: String = naming.title(unit: 1, day: 3)
        return [
            ("Making pages visible", [
                "Publish tomorrow's \(one)",
                "Publish Monday's \(one)",
            ]),
            ("Taking it back", [
                "Undo that",
            ]),
            ("Checking", [
                "What would students see in this section right now?",
                "Preview",
            ]),
            ("Planning \(many)", [
                "Add the next \(one) page",
                "Duplicate \(second) as my next \(one)",
                "Make room for one \(one) at \(third)",
                "When are my next \(many)?",
                "I have a revised list of \(one) dates",
                "Re-date my \(many)",
            ]),
            ("Putting the site online", [
                "Deploy now",
                "Deploy at 6:30 AM",
                "Cancel scheduled deploy",
            ]),
        ]
    }


    /// One group's open/shut state, as a binding a `DisclosureGroup` can
    /// drive, written straight back to the stored preference.
    private func binding(for title: String) -> Binding<Bool> {
        return Binding(
            get: {
                return expanded.contains(title)
            },
            set: { isOpen in
                var titles: Set<String> = expanded
                if isOpen {
                    titles.insert(title)
                } else {
                    titles.remove(title)
                }
                // Sorted so the stored value does not churn between launches
                // just because a Set enumerated differently.
                var ordered: [String] = []
                for stored in titles {
                    ordered.append(stored)
                }
                ordered.sort()
                openGroupsRaw = ordered.joined(separator: "|")
            }
        )
    }
}

/// The one-off download, before it starts.
struct AssistDownloadView: View {

    // MARK: - Stored properties

    let tier: AssistModelTier
    let store: AssistModelStore
    let begin: () -> Void

    // MARK: - Computed properties

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text("The assistant needs a one-time download")
                .font(.headline)

            // Said plainly and up front. A teacher on a school connection or a
            // metered tether deserves to know the size before it starts, not
            // to discover it from a progress bar.
            Text("""
                 It runs entirely on this Mac — nothing you write is sent anywhere. \
                 Plantoir picked \(tier.displayName) to suit this Mac's memory: a \
                 \(tier.downloadDescription) download, kept for next time.
                 """)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Download \(tier.downloadDescription)", action: begin)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("assistDownloadButton")

            if case .failed(let reason) = store.state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The download, while it runs.
struct AssistDownloadProgressView: View {

    // MARK: - Stored properties

    let fractionComplete: Double
    let receivedBytes: Int64
    let totalBytes: Int64
    let cancel: () -> Void

    // MARK: - Computed properties

    private var received: String {
        return AssistDownloadProgressView.formatter.string(fromByteCount: receivedBytes)
    }

    private var total: String {
        return AssistDownloadProgressView.formatter.string(fromByteCount: totalBytes)
    }

    private static let formatter: ByteCountFormatter = {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: fractionComplete)
                .frame(maxWidth: 320)
            Text("\(received) of \(total)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("You can carry on working; this window will be ready when it finishes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Stop", action: cancel)
                .accessibilityIdentifier("assistCancelDownloadButton")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Carries the shelf's measured height out of its content.
private struct AssistShelfHeightKey: PreferenceKey {

    // MARK: - Stored properties

    static let defaultValue: CGFloat = 0

    // MARK: - Functions

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
