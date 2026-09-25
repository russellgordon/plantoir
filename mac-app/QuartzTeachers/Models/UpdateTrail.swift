import Foundation

/// The trail's lines about updating (#204), composed from plain facts so a
/// test can read every one without an updater, a window or a network.
///
/// Each event is in `ActivityTrail.Event` AND in `contracts/shared-rules.json`
/// → `activityTrail.mustRecord`, which says what it carries and why. Versions
/// are written "1.3.2 (3120)" — the version and the build, the pair a problem
/// report already prints. Nothing here carries a web address, a path or
/// anything from the release notes.
nonisolated enum UpdateTrail {

    // MARK: - Types

    /// When an install is happening, for `update installing`.
    enum InstallMoment: Equatable {
        /// The teacher pressed Install and nothing was under way.
        case straightAway
        /// Held while `work` was under way, and that has now finished.
        case afterHeldWork(String)
        /// As Plantoir quits, without opening again — naming the work still
        /// going on in the one case that cannot be prevented, or nil.
        case asPlantoirQuits(workStillGoing: String?)
    }

    /// What the teacher answered in the update window.
    ///
    /// "Remind Me Later" and closing the window are ONE answer to the
    /// updater — it reports both as "dismiss" — so the trail cannot tell them
    /// apart and does not pretend to.
    enum Answer: String {
        case install = "install"
        case skip = "skip this version"
        case notNow = "not now (remind me later, or closed the window)"
    }

    // MARK: - Stored properties

    /// The user-defaults key holding the version the app last launched as.
    static let lastLaunchedVersionKey: String = "UpdateTrail.lastLaunchedVersion"

    /// The version an update was installing to, set as the OLD version hands
    /// over and read by the NEW one's first launch — how `app updated` tells
    /// "by its own updater" from "by hand".
    static let installingVersionKey: String = "UpdateTrail.installingVersion"

    // MARK: - Functions

    /// "1.3.2 (3120)".
    static func versionText(version: String, build: String) -> String {
        return "\(version) (\(build))"
    }

    /// `update found`.
    static func foundLine(found: String, running: String, teacherAsked: Bool, important: Bool) -> String {
        var line: String = "found Plantoir \(found) while running \(running)"
        if teacherAsked {
            line += ", when the teacher checked"
        } else {
            line += ", in the daily check"
        }
        if important {
            line += "; it is marked important"
        }
        return line
    }

    /// `update check found nothing new`.
    static func nothingNewLine(running: String) -> String {
        return "checked for a new version when the teacher asked, and \(running) is the newest"
    }

    /// `update answered`.
    static func answeredLine(answer: Answer, version: String) -> String {
        return "the teacher answered \"\(answer.rawValue)\" to Plantoir \(version)"
    }

    /// `update held while work is under way`.
    static func heldLine(work: String, version: String) -> String {
        return "held Plantoir \(version) back while still \(work)"
    }

    /// `update installing`.
    static func installingLine(from running: String, to version: String, moment: InstallMoment) -> String {
        let base: String = "installing Plantoir \(version) over \(running)"
        switch moment {
        case .straightAway:
            return base + " now; Plantoir will open again"
        case .afterHeldWork(let work):
            return base + " now that it is no longer \(work); Plantoir will open again"
        case .asPlantoirQuits(let workStillGoing):
            if let workStillGoing {
                return base + " as Plantoir quits, while still \(workStillGoing); it will not open again by itself"
            }
            return base + " as Plantoir quits; it will not open again by itself"
        }
    }

    /// `update set aside`.
    static func setAsideLine(version: String, work: String) -> String {
        return "set Plantoir \(version) aside as Plantoir quit while still \(work); it will be offered again"
    }

    /// `update stopped`.
    static func stoppedLine(version: String?, code: Int) -> String {
        var line: String = "could not update"
        if let version {
            line += " to Plantoir \(version)"
        }
        return line + ": \(UpdateTrail.stoppedCategory(code: code)) [\(code)]"
    }

    /// A plain category for the updater's error numbers (`SUErrors.h`).
    static func stoppedCategory(code: Int) -> String {
        switch code {
        case 1000, 1002:
            return "could not read what plantoir.app said about new versions"
        case 2000, 2001:
            return "the download failed"
        case 3000:
            return "the download could not be opened"
        case 1, 2, 3001, 3002, 4009:
            return "the download was not signed as expected"
        case 1003, 1005:
            return "Plantoir is running from a place it cannot be updated (a disk image, or not moved to Applications)"
        case 4001, 4007, 4008, 4012:
            return "an administrator's name and password was needed and not given"
        default:
            return "something else went wrong"
        }
    }

    /// Whether a failure is the managed-Mac one: the updater asked for an
    /// administrator, and nobody gave one (4007) — which it then drops in
    /// silence, so the app says it instead.
    static func needsAnAdministrator(code: Int) -> Bool {
        return code == 4007
    }

    /// `app updated`, when this launch's version is not the last one's — or
    /// nil. Reads and then REWRITES the two keys, so a second call on the
    /// same launch says nothing.
    static func appUpdatedLine(current: String, defaults: UserDefaults) -> String? {
        let previous: String? = defaults.string(forKey: lastLaunchedVersionKey)
        let installing: String? = defaults.string(forKey: installingVersionKey)
        defaults.set(current, forKey: lastLaunchedVersionKey)
        defaults.removeObject(forKey: installingVersionKey)
        guard let previous else {
            return nil
        }
        if previous == current {
            return nil
        }
        if installing == current {
            return "Plantoir was updated from \(previous) to \(current) by its own updater"
        }
        return "Plantoir changed from \(previous) to \(current) by hand"
    }
}
