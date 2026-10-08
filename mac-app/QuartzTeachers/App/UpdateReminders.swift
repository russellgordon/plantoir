import Foundation

/// A scheduled update offer the updater HELD, and what the app does about
/// it (#472, 2026-10-08) — the mac's answer to the rule Windows wrote after
/// #465, `appUpdates.anOfferNobodySawIsNotAnAnswer`.
///
/// **Why there is anything to do.** Sparkle's standard driver shows a
/// scheduled offer at once only when the app is active and the check began
/// within the last 3 s or the system is idle; otherwise it holds the alert
/// until the app is next activated (SPUStandardUserDriver.m, 2.9.6, 265-281
/// and 340-346) — and it stamps the day's check when the check STARTS
/// (SPUUpdater.m :789), so a held alert uses up the day. A teacher who keeps
/// Plantoir in front all day, or quits before switching back to it, would
/// otherwise be offered the update by the next day's check rather than
/// today's. No false "not now" is ever written — only a click in the alert
/// replies — so the first half of the rule holds on its own; this class is
/// the second half, by another route than Windows': the held offer is
/// brought forward later in the session, and looked for again at the next
/// launch.
///
/// **Logic only, no Sparkle.** Everything that touches the updater is in
/// `AppUpdates`, which asks this what to do; the tests drive this class with
/// their own defaults and clock. The updater is never created under tests.
@MainActor
final class UpdateReminders {

    // MARK: - Stored properties

    /// Where a held offer outlives the process.
    static let pendingOfferKey: String = "AppUpdates.pendingOffer"

    /// Minutes between tries to bring a held alert forward: doubling from
    /// one, capped at the hour — Windows' own cadence under #465.
    nonisolated static let retryMinutes: [Int] = [1, 2, 4, 8, 16, 32, 60]

    private let defaults: UserDefaults

    /// The version of the offer Sparkle is holding, or nil.
    private(set) var pendingVersion: String?

    /// Whether the current pending offer was held rather than shown at once
    /// — the only case the retries are for.
    private(set) var pendingOfferWasHeld: Bool = false

    // MARK: - Initializer

    init(defaults: UserDefaults) {
        self.defaults = defaults
        pendingVersion = defaults.string(forKey: UpdateReminders.pendingOfferKey)
    }

    // MARK: - Functions: what happened

    /// Sparkle was handed a scheduled offer for `version`. `shownAtOnce` is
    /// what its driver told the delegate it would do.
    func noteOffered(version: String, shownAtOnce: Bool) {
        pendingVersion = version
        pendingOfferWasHeld = !shownAtOnce
        defaults.set(version, forKey: UpdateReminders.pendingOfferKey)
    }

    /// The alert was seen (the driver reported user attention), or answered.
    func noteSeenOrAnswered() {
        clear()
    }

    /// A check found nothing newer (1001): whatever was pending is gone from
    /// the feed, so nothing is re-checked for ever.
    func noteNothingNew() {
        clear()
    }

    /// This launch's own version: an offer for it, or for anything older,
    /// arrived another way (installed by hand, or by the updater) and is
    /// no longer pending.
    func noteRunning(version: String) {
        guard let pending = pendingVersion else {
            return
        }
        if !UpdateReminders.isNewer(pending, than: version) {
            clear()
        }
    }

    // MARK: - Functions: what to do

    /// Whether `start()` should ask for a background check straight away:
    /// an offer was held in an earlier run and never seen or answered, and
    /// the running version is still older than it.
    func shouldCheckAgainAtLaunch(runningVersion: String) -> Bool {
        guard let pending = pendingVersion else {
            return false
        }
        return UpdateReminders.isNewer(pending, than: runningVersion)
    }

    /// Whether a retry is due now: the offer is still pending, was held, and
    /// the app is active (an inactive app's alert is shown by Sparkle itself
    /// the moment the app is activated, and bringing it forward from behind
    /// would pull Plantoir in front of whatever the teacher is doing).
    func shouldBringForward(appIsActive: Bool, secondsSinceInput: TimeInterval?) -> Bool {
        guard pendingVersion != nil, pendingOfferWasHeld, appIsActive else {
            return false
        }
        // And not mid-keystroke: the alert comes up key with Install
        // focused. A source that cannot say is taken as idle.
        return (secondsSinceInput ?? UpdateReminders.quietSeconds) >= UpdateReminders.quietSeconds
    }

    /// How long the keyboard and mouse must have been quiet before a held
    /// alert is brought forward.
    nonisolated static let quietSeconds: TimeInterval = 10

    /// The wait before try number `attempt` (0-based), in minutes.
    nonisolated static func minutesBeforeRetry(_ attempt: Int) -> Int {
        let clamped: Int = min(max(attempt, 0), retryMinutes.count - 1)
        return retryMinutes[clamped]
    }

    // MARK: - Functions: versions

    /// "1.4.5 (3140)" against "1.4.4 (3130)": the dotted part first, then
    /// the build in brackets; a text that does not parse compares as 0.
    nonisolated static func isNewer(_ candidate: String, than running: String) -> Bool {
        let candidateParts: [Int] = numbers(in: candidate)
        let runningParts: [Int] = numbers(in: running)
        let count: Int = max(candidateParts.count, runningParts.count)
        for index in 0..<count {
            let left: Int = index < candidateParts.count ? candidateParts[index] : 0
            let right: Int = index < runningParts.count ? runningParts[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    nonisolated private static func numbers(in text: String) -> [Int] {
        var result: [Int] = []
        var current: String = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                result.append(Int(current) ?? 0)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(Int(current) ?? 0)
        }
        return result
    }

    // MARK: - Functions: private

    private func clear() {
        pendingVersion = nil
        pendingOfferWasHeld = false
        defaults.removeObject(forKey: UpdateReminders.pendingOfferKey)
    }
}
