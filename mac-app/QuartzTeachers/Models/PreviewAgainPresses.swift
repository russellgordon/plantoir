import Foundation

/// A repair's Preview Again, from the press to the start (#813).
///
/// The button in the repair dialog stops a preview that is up, waits for the
/// stop, then starts the section's preview again. Until #813 the start ran
/// whatever happened during the stop: when the section's view went away
/// meanwhile (a switch of section or course, the window closing, a quit
/// waiting on an update set aside), it ran on the view that had gone, took a
/// lease and started a serve that nothing would stop, and the section read as
/// previewed in another window from then on.
///
/// So the press is recorded AT ONCE, before anything is awaited, as a token
/// for the section view that made it. Leaving the section (`onDisappear`)
/// abandons it, and quitting abandons every one. After the stop the start
/// runs only if the token survives. A second Preview Again replaces the
/// token, so only the last press starts.
///
/// **A field nothing else writes.** #793's first token for Make the Map Again
/// lived in the section's Coverage entry and was wiped by the next reading
/// of the record, which the old run's end always brings, so nothing started.
/// `underWay` is written by `press`, `finish`, `abandon` and `abandonEvery`
/// and by nothing else: no reading, no run ending and no stop touches it.
///
/// The steps take the stop and the start as closures, so
/// `PreviewBuildRecordTests` runs them with no window, from
/// `contracts/shared-rules.json` → `quittingWhileWorkIsUnderWay.previewBuildRecord.previewAgainCases`.
@MainActor
final class PreviewAgainPresses {

    // MARK: - Types

    /// How a press's steps after its checks came out.
    enum Ending: Equatable {
        /// The press still held after the stop, so the start was asked for.
        case started
        /// The page went away, or the app was quitting.
        case abandoned
        /// A later Preview Again of the same page took its place.
        case replaced
    }

    // MARK: - Stored properties

    static let shared: PreviewAgainPresses = PreviewAgainPresses()

    /// The section's page went away, or the app is quitting, before the old
    /// preview had stopped.
    static let abandonedLine: String =
        "Preview Again after a repair started nothing: the section's page went away, or Plantoir was quitting, before the old preview had stopped"

    /// A later Preview Again of the same section page took this one's place.
    static let replacedLine: String =
        "Preview Again after a repair started nothing itself: a later Preview Again of the same section took its place"

    /// The press each section view is still carrying out, by that view's own
    /// id: the token of its latest press.
    private(set) var underWay: [UUID: UUID] = [:]

    /// Presses a later press of the same view took the place of, until each
    /// is finished. Kept apart from `underWay` because the later press can
    /// finish first and clear its own entry, and the earlier press must
    /// still say it was replaced rather than abandoned (#812's review).
    private(set) var replaced: Set<UUID> = []

    // MARK: - Functions

    /// A Preview Again was pressed in the section view `owner`. Returns this
    /// press's token, which replaces any earlier press of that view.
    func press(owner: UUID) -> UUID {
        let token: UUID = UUID()
        if let earlier = underWay[owner] {
            replaced.insert(earlier)
        }
        underWay[owner] = token
        return token
    }

    /// Whether `token` is still the press `owner` is carrying out.
    func stillHolds(_ token: UUID, owner: UUID) -> Bool {
        return underWay[owner] == token
    }

    /// The press is over, however it ended. Leaves a later press of the same
    /// view alone.
    func finish(_ token: UUID, owner: UUID) {
        if underWay[owner] == token {
            underWay[owner] = nil
        }
        replaced.remove(token)
    }

    /// The section view `owner` is going away: its press starts nothing.
    func abandon(owner: UUID) {
        underWay[owner] = nil
    }

    /// The app is quitting: no press starts anything.
    func abandonEvery() {
        underWay = [:]
    }

    /// The press's steps after its checks: stop a preview that is up and
    /// wait for the stop, then start only if the press still holds. Answers
    /// how the press came out.
    ///
    /// A press that no longer holds writes a trail line saying why nothing
    /// started, so "I pressed Preview Again and nothing came up" has an
    /// answer. A preview the teacher started during the stop is not this
    /// press's business: the start asked for here then does nothing
    /// (`PreviewStartRecords.aStartIsUnderWay`, #812), and that build keeps
    /// its record.
    static func carryOut(
        store: PreviewAgainPresses,
        owner: UUID,
        token: UUID,
        courseCode: String,
        sectionNumber: Int,
        previewIsRunning: Bool,
        stop: () async -> Void,
        start: () -> Void
    ) async -> Ending {
        if previewIsRunning {
            await stop()
        }
        if !store.stillHolds(token, owner: owner) {
            let ending: Ending
            let line: String
            if store.replaced.contains(token) {
                ending = .replaced
                line = PreviewAgainPresses.replacedLine
            } else {
                ending = .abandoned
                line = PreviewAgainPresses.abandonedLine
            }
            ActivityTrail.note(.previewAgainAbandoned, line, course: courseCode, section: sectionNumber)
            return ending
        }
        start()
        return .started
    }
}
