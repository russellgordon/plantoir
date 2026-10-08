import XCTest
@testable import QuartzTeachers

/// A scheduled offer the updater held is brought forward later, and looked
/// for again at the next launch (#472). The logic alone: no updater is ever
/// created under tests (`AppUpdates.shouldStart`), so Sparkle's calls are
/// not exercised here — `documentation/09-mac-app.md` says what was read
/// from Sparkle's source instead.
@MainActor
final class UpdateRemindersTests: XCTestCase {

    // MARK: - Helpers

    private func make() -> (UpdateReminders, UserDefaults) {
        let defaults: UserDefaults = TestDefaults.make()
        return (UpdateReminders(defaults: defaults), defaults)
    }

    // MARK: - Tests

    /// A held offer is pending and retried; one shown at once is pending
    /// (so a quit before answering still re-checks) but never retried.
    func testOnlyAHeldOfferIsBroughtForward() {
        let (reminders, _) = make()
        reminders.noteOffered(version: "1.4.5 (3140)", shownAtOnce: false)
        XCTAssertTrue(reminders.shouldBringForward(appIsActive: true, secondsSinceInput: 30))
        XCTAssertTrue(reminders.shouldBringForward(appIsActive: true, secondsSinceInput: nil), "a source that cannot say is taken as idle")
        XCTAssertFalse(reminders.shouldBringForward(appIsActive: true, secondsSinceInput: 2), "not mid-keystroke")
        XCTAssertFalse(reminders.shouldBringForward(appIsActive: false, secondsSinceInput: 30), "an inactive app's alert is Sparkle's to show on activation")
        reminders.noteOffered(version: "1.4.5 (3140)", shownAtOnce: true)
        XCTAssertFalse(reminders.shouldBringForward(appIsActive: true, secondsSinceInput: 30))
        XCTAssertEqual(reminders.pendingVersion, "1.4.5 (3140)")
    }

    /// Seen or answered clears it; so does "nothing new"; so does running
    /// that version or newer.
    func testWhatClearsAPendingOffer() {
        let (reminders, defaults) = make()
        reminders.noteOffered(version: "1.4.5 (3140)", shownAtOnce: false)
        XCTAssertEqual(defaults.string(forKey: UpdateReminders.pendingOfferKey), "1.4.5 (3140)")
        reminders.noteSeenOrAnswered()
        XCTAssertNil(reminders.pendingVersion)
        XCTAssertNil(defaults.string(forKey: UpdateReminders.pendingOfferKey))

        reminders.noteOffered(version: "1.4.5 (3140)", shownAtOnce: false)
        reminders.noteNothingNew()
        XCTAssertNil(reminders.pendingVersion)

        reminders.noteOffered(version: "1.4.5 (3140)", shownAtOnce: false)
        reminders.noteRunning(version: "1.4.4 (3130)")
        XCTAssertNotNil(reminders.pendingVersion, "still older than the offer")
        reminders.noteRunning(version: "1.4.5 (3140)")
        XCTAssertNil(reminders.pendingVersion, "installed by hand or by the updater")
    }

    /// The record outlives the process, and the next launch checks again —
    /// only while the running version is still older.
    func testTheNextLaunchChecksAgainForAnOfferNobodySaw() {
        let (first, defaults) = make()
        first.noteOffered(version: "1.4.5 (3140)", shownAtOnce: false)
        let second: UpdateReminders = UpdateReminders(defaults: defaults)
        XCTAssertTrue(second.shouldCheckAgainAtLaunch(runningVersion: "1.4.4 (3130)"))
        XCTAssertFalse(second.shouldCheckAgainAtLaunch(runningVersion: "1.4.5 (3140)"))
        XCTAssertFalse(second.shouldCheckAgainAtLaunch(runningVersion: "1.5.0 (3200)"))
    }

    /// Doubling from one minute, capped at the hour.
    func testTheRetriesDoubleToAnHour() {
        XCTAssertEqual((0..<9).map { attempt in UpdateReminders.minutesBeforeRetry(attempt) }, [1, 2, 4, 8, 16, 32, 60, 60, 60])
    }

    /// The version text the app writes, compared as numbers.
    func testVersionsCompareAsNumbers() {
        XCTAssertTrue(UpdateReminders.isNewer("1.4.5 (3140)", than: "1.4.4 (3130)"))
        XCTAssertTrue(UpdateReminders.isNewer("1.10.0 (4000)", than: "1.9.9 (3999)"))
        XCTAssertTrue(UpdateReminders.isNewer("1.4.5 (3141)", than: "1.4.5 (3140)"))
        XCTAssertFalse(UpdateReminders.isNewer("1.4.5 (3140)", than: "1.4.5 (3140)"))
        XCTAssertFalse(UpdateReminders.isNewer("1.4.4 (3130)", than: "1.4.5 (3140)"))
    }
}
