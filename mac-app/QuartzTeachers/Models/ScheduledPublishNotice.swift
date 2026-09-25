import Foundation
import Synchronization
import UserNotifications

/// Tells the teacher, with a macOS notification, how a scheduled publish went
/// (GitHub issue #212).
///
/// A publish set for half six runs with the app CLOSED, and the section's
/// notice (`ScheduledPublishNoticeView`) reaches only a teacher who opens the
/// app and then that section. Russell's case: publish set for 6:30, laptop
/// opened at 7:45, and nothing anywhere said whether it had gone — "especially
/// when it did not". So the RUN itself, which is Plantoir under
/// `--run-scheduled-deploy`, posts one notification when it finishes, whatever
/// happened, and it waits in Notification Center until the teacher reads it.
///
/// **The text is the section's own sentence** —
/// `ScheduledPublishOutcome.sentence(for:course:section:)`, the words the band
/// in the section shows — and nothing else. No title of our own: macOS heads
/// the notification "Plantoir", and every sentence already begins with the
/// course and the section, so a banner that is cut short still says WHICH
/// section it is about. A second wording would be a second thing to keep in
/// step with the contract.
///
/// **Composed FROM the record, after it is written.** This is not the
/// distributed notification #216 rejected: that was a channel to the APP, which
/// could disagree with the file. This goes to the TEACHER, drives nothing in the
/// app, and reads the one record everything else reads.
///
/// **The run never asks for permission.** A prompt at half six is a prompt to
/// nobody, in a process that is about to exit. Permission is asked when a
/// teacher schedules from Plantoir's own window (`askPermissionIfNotAskedYet`),
/// and a run that is not allowed to post says so on the trail instead.
///
/// Measured on this Mac before any of this was written (2026-09-25, Apple
/// silicon, macOS 26), with the Debug bundle started by a throwaway
/// LaunchAgent exactly as a scheduled run is: see
/// `documentation/07-deployment.md` → "When nobody is looking".
nonisolated enum ScheduledPublishNotice {

    // MARK: - Types

    /// Whether Plantoir may put a notification on screen.
    ///
    /// Three answers, not two, because "the teacher said no" and "nobody has
    /// asked yet" are different lines on the trail and different things to do
    /// about it — the first is a System Settings switch, the second is a
    /// question Plantoir will ask the next time a publish is scheduled.
    enum Permission: String, Sendable, CaseIterable {
        case allowed
        case notAllowed
        case notAskedYet
    }

    /// What one announcement did, for the trail and for the tests.
    enum Announcement: Equatable, Sendable {

        /// There was no record for the section, so there was nothing to say.
        case nothingToSay

        /// The notification was handed to macOS.
        case posted

        /// Plantoir is not allowed to post, by the teacher's choice.
        case notAllowed

        /// Nobody has been asked yet, and a run never asks.
        case notAskedYet

        /// macOS refused it, or did not answer before the ceiling.
        case couldNotBeSent
    }

    // MARK: - Stored properties

    /// The one thing that talks to macOS.
    ///
    /// **Under the suite it is `QuietNotifications`, which does nothing.** The
    /// test host IS Plantoir.app — the same bundle identifier whose permission
    /// this feature reads — so a test that reached the real notification centre
    /// could put a permission prompt on the Mac running the suite, and whatever
    /// was clicked would become Plantoir's real setting. Tests that need to see
    /// what would have been posted put a recording fake here and put
    /// `QuietNotifications` back afterwards (the suite is serial). The real
    /// poster refuses under the suite as well, so a test that forgets cannot
    /// reach the notification centre either way.
    ///
    /// `nonisolated(unsafe)` for the reason `ActivityTrail.store` is: the run
    /// launchd fires is `nonisolated` and reads it once, and only tests write it,
    /// on one thread, before anything reads it.
    nonisolated(unsafe) static var poster: any NotificationPosting = defaultPoster()

    /// How long the run waits for macOS before leaving anyway.
    ///
    /// An intentional guard, not a delay chosen to let something settle: a
    /// notification service that never answers must not hold a publish that
    /// has already FINISHED alive, with its job still registered. Measured, the
    /// whole exchange took 0.03 to 0.13 seconds on this Mac; ten seconds is
    /// generous to a busy machine and still ends.
    static let ceiling: Duration = .seconds(10)

    // MARK: - Functions

    /// The poster a process starts with.
    static func defaultPoster() -> any NotificationPosting {
        if RealHome.isInsideTestBundle {
            return QuietNotifications()
        }
        return SystemNotifications()
    }

    /// One notification per SECTION, keyed like the record file, so a later
    /// run's notification REPLACES the earlier one instead of stacking beside
    /// it, and dismissing the band withdraws exactly this section's.
    ///
    /// The course and section are whole segments of the key, so section 1 and
    /// section 11 can never share one.
    static func identifier(course: String, section: Int) -> String {
        return "scheduled-publish.\(course).section\(section)"
    }

    /// What the notification says: the section's own sentence, and nothing
    /// added to it.
    static func body(for stopped: ScheduledPublishOutcome.Stopped, course: String, section: Int) -> String {
        return ScheduledPublishOutcome.sentence(for: stopped, course: course, section: section)
    }

    /// Tell the teacher how this section's scheduled run went.
    ///
    /// Called by the RUN once its record is written and its trail line is
    /// down, BEFORE the job is booted out — booting it out ends this process.
    /// Reads the record rather than being handed a kind, so the notification
    /// can only ever say what the band will say.
    ///
    /// Leaves exactly one line on the trail for every outcome but
    /// `nothingToSay`, so "I never got told" can be answered: whether the
    /// notification went out, or why not.
    @discardableResult
    static func announce(
        inHomeFolder home: URL,
        course: String,
        section: Int,
        poster: any NotificationPosting = ScheduledPublishNotice.poster,
        ceiling: Duration = ScheduledPublishNotice.ceiling
    ) async -> Announcement {
        guard let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: course, section: section
        ) else {
            return .nothingToSay
        }
        let identifier: String = identifier(course: course, section: section)
        let text: String = body(for: stopped, course: course, section: section)
        let announcement: Announcement = await askAndPost(
            identifier: identifier, body: text, poster: poster, ceiling: ceiling
        )

        // One visible `ActivityTrail.note(.event, …)` per branch, as
        // `noteOnTrail` does, so ActivityTrailWiringTests can see each one.
        // Never the body: it is derived from the record, but the trail's rule
        // is that no sentence a teacher reads is copied onto it.
        switch announcement {
        case .posted:
            ActivityTrail.note(
                .scheduledPublishNotification,
                "told the teacher how a scheduled publish went, with a notification",
                course: course, section: section
            )
        case .notAllowed:
            ActivityTrail.note(
                .scheduledPublishNotification,
                "did not send a notification about a scheduled publish, because notifications "
                + "are turned off for Plantoir",
                course: course, section: section
            )
        case .notAskedYet:
            ActivityTrail.note(
                .scheduledPublishNotification,
                "did not send a notification about a scheduled publish, because Plantoir has "
                + "not been given permission to send them yet",
                course: course, section: section
            )
        case .couldNotBeSent:
            ActivityTrail.note(
                .scheduledPublishNotification,
                "a notification about a scheduled publish could not be sent",
                course: course, section: section
            )
        case .nothingToSay:
            break
        }
        return announcement
    }

    /// Ask macOS whether Plantoir may post and, if it may, post — the whole
    /// exchange bounded by `ceiling`.
    ///
    /// **Bounded by an UNSTRUCTURED race, deliberately.** A task group does not
    /// return until every child has finished, and cancelling a child only sets
    /// a flag; the real post is `UNUserNotificationCenter.add`, which does not
    /// look at that flag. A group racing it against a sleep would therefore
    /// wait for the post however long it took — the ceiling would be decoration.
    /// Here whichever finishes first resumes the caller exactly once, and the
    /// loser is cancelled and simply left behind: the run exits a moment later
    /// and takes it with it.
    static func askAndPost(
        identifier: String,
        body: String,
        poster: any NotificationPosting,
        ceiling: Duration
    ) async -> Announcement {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Announcement, Never>) in
            let once: ResumeOnce = ResumeOnce(continuation)
            let work: Task<Void, Never> = Task {
                let permission: Permission = await poster.permission()
                switch permission {
                case .allowed:
                    do {
                        try await poster.post(identifier: identifier, body: body)
                        once.resume(returning: .posted)
                    } catch {
                        once.resume(returning: .couldNotBeSent)
                    }
                case .notAllowed:
                    once.resume(returning: .notAllowed)
                case .notAskedYet:
                    once.resume(returning: .notAskedYet)
                }
            }
            let deadline: Task<Void, Never> = Task {
                // The deadline IS the behaviour here (see `ceiling`); it is not
                // waiting for anything to settle.
                do {
                    try await Task.sleep(for: ceiling)
                } catch {
                    // Cancelled because the exchange finished first.
                    return
                }
                work.cancel()
                once.resume(returning: .couldNotBeSent)
            }
            once.cancelOnResume(deadline)
        }
    }

    /// Ask the teacher whether Plantoir may send notifications — once, the
    /// first time they schedule a publish from Plantoir's own window.
    ///
    /// Only when nobody has been asked yet: a teacher who said no is not asked
    /// again (macOS would not show the question anyway), and the switch is in
    /// System Settings → Notifications → Plantoir. Never from a run, and never
    /// from an outside assistant over MCP — neither has a teacher in front of
    /// Plantoir to answer.
    ///
    /// Two lines on the trail: one when the question goes up, and one with the
    /// answer when it comes. The first is written straight away because the
    /// answer may never come — macOS shows the question as a notification, and
    /// one that is ignored, or that arrives under a Focus, waits unanswered in
    /// Notification Center.
    static func askPermissionIfNotAskedYet(
        course: String,
        section: Int,
        poster: any NotificationPosting = ScheduledPublishNotice.poster
    ) async {
        let permission: Permission = await poster.permission()
        if permission != .notAskedYet {
            return
        }
        ActivityTrail.note(
            .scheduledPublishNotification,
            "asked whether Plantoir may send a notification when a scheduled publish finishes",
            course: course, section: section
        )
        let allowed: Bool = await poster.askPermission()
        if allowed {
            ActivityTrail.note(
                .scheduledPublishNotification,
                "the teacher allowed notifications about scheduled publishes",
                course: course, section: section
            )
        } else {
            ActivityTrail.note(
                .scheduledPublishNotification,
                "the teacher did not allow notifications about scheduled publishes",
                course: course, section: section
            )
        }
    }

    /// Everything Dismiss does outside the window: the record goes, and so
    /// does the notification about it, so the two can never disagree about
    /// whether it is still news.
    ///
    /// A successful run that clears an old record does NOT come through here:
    /// its own notification replaces the old one by identifier anyway.
    static func teacherDismissed(inHomeFolder home: URL, course: String, section: Int) {
        ScheduledPublishOutcome.clear(inHomeFolder: home, course: course, section: section)
        poster.withdraw(identifier: identifier(course: course, section: section))
    }

    /// What macOS's own answer means here.
    ///
    /// `.provisional` is allowed: macOS will show what is posted, quietly
    /// or otherwise, and whether it is quiet is the teacher's setting.
    /// (`.ephemeral` is an App Clip answer and does not exist on macOS.)
    /// An answer this build does not know is treated as NOT allowed, because
    /// the trail line it produces sends somebody to System Settings, which is
    /// where the answer is.
    static func permission(from status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional:
            return .allowed
        case .notDetermined:
            return .notAskedYet
        case .denied:
            return .notAllowed
        @unknown default:
            return .notAllowed
        }
    }
}

/// What `ScheduledPublishNotice` needs from macOS — four things, so a test can
/// stand in for all of them.
nonisolated protocol NotificationPosting: Sendable {

    /// Whether Plantoir may post. Never asks.
    func permission() async -> ScheduledPublishNotice.Permission

    /// Put the question to the teacher. True when they allowed it.
    func askPermission() async -> Bool

    /// Post one notification, replacing any with the same identifier.
    func post(identifier: String, body: String) async throws

    /// Take a delivered notification away.
    func withdraw(identifier: String)
}

/// The real thing: macOS's notification centre.
///
/// **Refuses under the suite**, whatever it is asked, in the way
/// `LaunchControl.run` refuses: a test that forgot to put a fake in place
/// must fail quietly rather than put a question on the screen of the Mac
/// running it.
nonisolated struct SystemNotifications: NotificationPosting {

    // MARK: - Types

    /// Why a post did not happen.
    enum Refusal: Error {
        case insideTheTestSuite
    }

    // MARK: - Functions

    func permission() async -> ScheduledPublishNotice.Permission {
        if RealHome.isInsideTestBundle {
            return .notAllowed
        }
        let settings: UNNotificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        return ScheduledPublishNotice.permission(from: settings.authorizationStatus)
    }

    /// Alerts only. No sound — a chime at half six in a quiet house, for news
    /// — and no badge, because a Dock badge is the success badge
    /// `scheduledPublishStopped.attention` decided against.
    func askPermission() async -> Bool {
        if RealHome.isInsideTestBundle {
            return false
        }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    func post(identifier: String, body: String) async throws {
        if RealHome.isInsideTestBundle {
            throw Refusal.insideTheTestSuite
        }
        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.body = body
        let request: UNNotificationRequest = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    func withdraw(identifier: String) {
        if RealHome.isInsideTestBundle {
            return
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

/// Does nothing, says nothing is allowed, and never asks. What the suite runs
/// with unless a test puts a recording fake in its place.
nonisolated struct QuietNotifications: NotificationPosting {

    // MARK: - Functions

    func permission() async -> ScheduledPublishNotice.Permission {
        return .notAllowed
    }

    func askPermission() async -> Bool {
        return false
    }

    func post(identifier: String, body: String) async throws {
    }

    func withdraw(identifier: String) {
    }
}

/// Resumes one continuation once, whichever of two tasks gets there first.
nonisolated final class ResumeOnce: Sendable {

    // MARK: - Stored properties

    private let waiting: Mutex<CheckedContinuation<ScheduledPublishNotice.Announcement, Never>?>

    /// The deadline, stopped once the exchange has an answer so it does not
    /// sleep on for the rest of the ceiling.
    private let deadline: Mutex<Task<Void, Never>?> = Mutex(nil)

    /// Whether `resume` has already happened, for a deadline handed over late.
    private let finished: Mutex<Bool> = Mutex(false)

    // MARK: - Initializer

    init(_ continuation: CheckedContinuation<ScheduledPublishNotice.Announcement, Never>) {
        waiting = Mutex(continuation)
    }

    // MARK: - Functions

    func resume(returning announcement: ScheduledPublishNotice.Announcement) {
        let continuation: CheckedContinuation<ScheduledPublishNotice.Announcement, Never>? = waiting.withLock { held in
            let taken: CheckedContinuation<ScheduledPublishNotice.Announcement, Never>? = held
            held = nil
            return taken
        }
        continuation?.resume(returning: announcement)
        finished.withLock { done in
            done = true
        }
        let pending: Task<Void, Never>? = deadline.withLock { held in
            let taken: Task<Void, Never>? = held
            held = nil
            return taken
        }
        pending?.cancel()
    }

    /// Hand over the deadline so the first answer can stop it. If the answer
    /// came before the handover, it is stopped at once.
    func cancelOnResume(_ task: Task<Void, Never>) {
        deadline.withLock { held in
            held = task
        }
        let alreadyFinished: Bool = finished.withLock { done in
            return done
        }
        if alreadyFinished {
            task.cancel()
        }
    }
}
