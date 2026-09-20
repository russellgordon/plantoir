import Foundation

/// How late a scheduled deploy may still run, and where that answer comes
/// from.
///
/// **The fault this exists to close.** A `StartCalendarInterval` agent carries
/// a month, a day, an hour and a minute — and no year — so a job whose moment
/// passed while the Mac was OFF is loaded again at the next login and comes due
/// on the same date twelve months later. Russell's decision, 2026-09-20: a
/// scheduled deploy is a ONE-OFF and must never recur annually. So the run
/// re-checks its own moment before it does anything, and a job that is too late
/// stands down instead of deploying a site set up for a different day.
///
/// **The window is the TEACHER's, per course.** The default is a week; the
/// choices are in `offeredDays` and the teacher picks one in Course Settings,
/// under Deploying. There is deliberately no "always" — that is the annual
/// recurrence again, wearing a different hat.
///
/// **Elapsed time between two instants, never a calendar.** The comparison is
/// `abs(now − intended)` against the window, with no `Calendar`, no `TimeZone`
/// and no daylight-saving arithmetic anywhere. Measured on 2026-09-20 while
/// planning this (`scratchpad` measurement `dayrule.swift`), a "same calendar
/// day" rule REFUSED four cases it had to allow:
///
/// | what happened | same calendar day | this rule |
/// |---|---|---|
/// | 23:50 job, Mac woken 00:05 — the coalesced wake Apple documents | no | **runs** |
/// | 06:30 job, Mac woken 09:00 the same morning | yes | **runs** |
/// | 06:30 job, Mac off overnight, opened 17:00 the next day | no | **runs** |
/// | a job set in Toronto firing at 06:30 local in Tokyo | yes | **runs** |
/// | the same date a YEAR later — the fault itself | no | **stands down** |
///
/// A fifteen-minute delay turning into a silent non-deploy is the precise harm
/// this piece exists to prevent, so the calendar rule was rejected. The window
/// only has to sit far below eleven months to kill the annual repeat.
///
/// **It FAILS OPEN.** When the intended moment is missing or unreadable — a
/// plist written by a build that did not record one, a stamp somebody edited —
/// the deploy goes ahead. A deploy the teacher asked for beats a refusal nobody
/// sees: fail-closed would turn one unparseable stamp into every scheduled
/// deploy silently not happening, which is worse than the fault being fixed.
nonisolated enum ScheduledDeployLateness {

    // MARK: - Stored properties

    /// The key this is stored under in `course_config.json`.
    ///
    /// `CourseConfiguration` spells the same key out as a literal rather than
    /// using this constant, and that is deliberate — see the comment beside
    /// `CourseConfiguration.scheduledDeployMayRunLateDays`. Both spellings are
    /// pinned against `contracts/file-formats.json` by tests, so they cannot
    /// drift apart without the suite saying so.
    static let configurationKey: String = "scheduled_deploy_may_run_late_days"

    /// What a course says when it has never been asked.
    ///
    /// A week, not the twenty-four hours first proposed: a teacher away sick
    /// on the day opens the laptop twenty-six hours late and still wants the
    /// site updated, and a laptop closed over a weekend is ordinary.
    static let defaultDays: Int = 7

    /// The choices a teacher is offered, in the order they are shown.
    ///
    /// A short fixed list rather than a free number: the value is read at the
    /// scheduled moment with nobody there, and "0" or "365" typed into a field
    /// is a fault nobody would meet until the morning it mattered.
    static let offeredDays: [Int] = [1, 3, 7, 14]

    // MARK: - Functions

    /// The window a stored value means.
    ///
    /// Anything that is not one of the offered choices — an older build's
    /// number, a value hand-edited into the file, a key holding text — reads as
    /// the default rather than as itself. The alternative is honouring a stored
    /// `0`, which would stand every scheduled deploy down.
    static func days(fromStoredValue stored: Int?) -> Int {
        guard let stored else {
            return defaultDays
        }
        for offered in offeredDays {
            if offered == stored {
                return stored
            }
        }
        return defaultDays
    }

    /// How far either side of its moment a deploy may still run.
    static func allowedLateness(days: Int) -> TimeInterval {
        return TimeInterval(days) * 24.0 * 60.0 * 60.0
    }

    /// Whether a deploy set for `intendedMoment` may still go ahead at `now`.
    ///
    /// `abs`, so a job that fires EARLY is allowed too. After a time-zone move
    /// a `StartCalendarInterval` fires at the chosen wall-clock time in the new
    /// zone, which can be hours before the instant that was recorded — and a
    /// lower bound of zero would refuse a legitimate run.
    static func mayStillRun(intendedMoment: Date?, now: Date, allowedDays: Int) -> Bool {
        guard let intendedMoment else {
            // Fails open, on purpose — see the note on the type.
            return true
        }
        let drift: TimeInterval = abs(now.timeIntervalSince(intendedMoment))
        return drift <= allowedLateness(days: allowedDays)
    }

    /// The window one course has chosen, read from its own settings file
    /// inside the working folder the job named.
    ///
    /// Read at the moment the deploy fires rather than baked into the agent
    /// when it was scheduled, so a teacher who changes the setting afterwards
    /// changes what the job already on disk will do.
    ///
    /// A course that is gone, a file that cannot be read, or a key that is not
    /// there all mean the default. A job whose course folder has gone is
    /// refused by `deploy.sh` anyway ("Course folder not found on host") — but
    /// the stand-down still has to remove the plist, or the same job comes back
    /// next year, which is the whole fault.
    static func days(forCourseCode courseCode: String, inWorkingFolder workingFolderURL: URL) -> Int {
        let coursesURL: URL = workingFolderURL.appendingPathComponent("courses")
        guard let folderName = courseFolderName(
            matching: courseCode, inCoursesFolder: coursesURL
        ) else {
            return defaultDays
        }
        let configURL: URL = coursesURL
            .appendingPathComponent(folderName)
            .appendingPathComponent("course_config.json")
        guard let data = try? Data(contentsOf: configURL) else {
            return defaultDays
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return defaultDays
        }
        guard let values = decoded as? [String: Any] else {
            return defaultDays
        }
        guard let stored = values[configurationKey] as? NSNumber else {
            return defaultDays
        }
        return days(fromStoredValue: stored.intValue)
    }

    /// Which course folder a code names, allowing for a code that came back
    /// out of an agent's LABEL rather than out of the agent itself.
    ///
    /// **The direct name first**, which is every modern job: an agent written
    /// by v1.2.0 or later carries the course code as the teacher spells it, so
    /// `courses/Chess Club/` is found by name and the teacher's chosen window
    /// applies.
    ///
    /// **Then a sanitised match**, for a job written before v1.2.0. Those
    /// carry no course code at all, so the only route is the label — and a
    /// label is uppercased with every non-alphanumeric turned into a hyphen,
    /// so "Chess Club" comes back "CHESS-CLUB" and `courses/CHESS-CLUB/` does
    /// not exist. Without this step such a course silently fell back to the
    /// default window at sweep time even though its teacher had chosen
    /// another, and the direction of that mistake is a deploy DROPPED.
    ///
    /// **Only a UNIQUE match counts.** Two codes that sanitise the same way
    /// ("Chess Club" and "Chess-Club") are ambiguous, and guessing between
    /// them would read one course's setting for another's job; with no unique
    /// answer the caller gets the default, which is the same thing a course
    /// that has gone gets.
    static func courseFolderName(matching courseCode: String, inCoursesFolder coursesURL: URL) -> String? {
        // The NAMES, never `fileExists` on a built path — and that is measured
        // rather than fastidious. A teacher's volume is case-insensitive by
        // default, so asking whether `courses/CHESS-CLUB` exists answers YES
        // when the folder is really called `Chess-Club`: a lossy code from an
        // old job's label would walk straight into a DIFFERENT course's
        // settings and read its window. The suite caught exactly that on
        // 2026-09-20, against a folder pair one hyphen apart. Comparing the
        // names ourselves takes the filesystem's opinion out of it.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            atPath: coursesURL.path
        ) else {
            return nil
        }
        for entry in entries {
            if entry == courseCode {
                return entry
            }
        }
        let wanted: String = ScheduledDeploy.sanitizedCode(courseCode)
        var matches: [String] = []
        for entry in entries {
            if ScheduledDeploy.sanitizedCode(entry) == wanted {
                matches.append(entry)
            }
        }
        if matches.count == 1 {
            return matches[0]
        }
        return nil
    }

    /// What the teacher reads above the choice in Course Settings.
    ///
    /// Retyped from `contracts/shared-rules.json` →
    /// `scheduledDeployCancellation.wording` and pinned against it by a test,
    /// the same arrangement every other shared sentence uses. No machinery in
    /// it: no "job", no "agent", no "launch", no "plist".
    static let settingTitle: String = "A scheduled deploy may still run this late"

    /// The sentence under the choice.
    ///
    /// It says what happens in the ordinary missed case — the Mac was off or
    /// asleep — because that is the only way a teacher ever meets this, and it
    /// says what Plantoir does past the window in terms of the harm rather
    /// than of the rule.
    static let settingCaption: String =
        "A deploy set to happen on its own runs at the time you chose. If this Mac was off or "
        + "asleep then, it runs at the next wake instead — and this is how long after your chosen "
        + "time that is still worth doing. Later than this, Plantoir leaves it alone rather than "
        + "putting up a site you set up for a different day, and tells you it did."

    /// "1 day", "3 days", "1 week", "2 weeks" — what a choice is called in the
    /// settings form.
    ///
    /// Weeks rather than "7 days" and "14 days" because that is how a teacher
    /// says it. The stored value is still a number of days, so nothing
    /// downstream has to know about the wording.
    static func choiceLabel(days: Int) -> String {
        if days == 7 {
            return "1 week"
        }
        if days == 14 {
            return "2 weeks"
        }
        if days == 1 {
            return "1 day"
        }
        return "\(days) days"
    }
}
