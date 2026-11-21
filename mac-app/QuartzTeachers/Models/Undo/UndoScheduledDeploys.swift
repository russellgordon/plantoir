import Foundation

/// A deploy set for later as an `external` target, `scheduledDeploy:<label>`
/// (#899 U3b; #897 piece B, seam 2): the LaunchAgent's plist in
/// `~/Library/LaunchAgents` (`ScheduledDeploy.plistURL(label:)`) and the
/// wrapper script it runs (`ScheduledDeploy.scriptURL(label:)`). A rollover
/// onto a new website removes the section's schedule as one op of its step;
/// undoing that registers it again, but only while its moment is still
/// ahead (`canSet`), and otherwise the op stands apart: it is left as it is
/// and reported, and the rest of the rollover is undone (`UndoOp.standsApart`).
///
/// The value is this Mac's own: `{"plist": <base64>, "script": <base64>}`,
/// the two files' exact bytes (no script when there was none). Windows'
/// counterpart (a Task Scheduler task) defines its own value for the same
/// family; a value is only ever read back by the platform that wrote it,
/// because a step names a working folder on one computer.
///
/// launchd is reached through the runner the action was given
/// (`LaunchControlRunning`, which is the main actor's), so a write made off
/// the main thread is refused (`write` answers false) rather than guessed
/// at. Making a step reads that as a change that could not be made, nothing
/// changed; an Undo or a Redo leaves the schedule as it is and names it as
/// left apart, as it does a launchd refusal, and moves the rest of the step
/// (`UndoSwap.swap`'s `leaveApart`), so a label that stays loaded never
/// blocks its step for good. Every action that makes such a step runs on
/// the main actor.
nonisolated struct UndoScheduledDeploys: UndoExternalPlaces, @unchecked Sendable {

    // MARK: - Stored properties

    /// The runner launchd is asked through: the real `LaunchControl` in the
    /// app, a fake in a test (never the real one under the suite).
    nonisolated(unsafe) let runner: LaunchControlRunning

    /// The clock `canSet` judges a moment against.
    let now: @Sendable () -> Date

    // MARK: - Initializer

    init(runner: LaunchControlRunning, now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.now = now
    }

    // MARK: - Functions

    /// The target for a job's label.
    static func target(label: String) -> String {
        return UndoOp.scheduledDeployFamily + ":" + label
    }

    /// The label a target names, or nil when it is not this family's.
    static func label(of target: String) -> String? {
        let prefix: String = UndoOp.scheduledDeployFamily + ":"
        if !target.hasPrefix(prefix) {
            return nil
        }
        let label: String = String(target.dropFirst(prefix.count))
        if label.isEmpty || label.contains("/") || !label.hasPrefix(ScheduledDeploy.labelPrefix) {
            return nil
        }
        return label
    }

    func read(_ target: String) -> UndoExternalReading {
        guard let label = UndoScheduledDeploys.label(of: target) else {
            return .cannotTell
        }
        let plistData: Data
        switch UndoItem.read(at: ScheduledDeploy.plistURL(label: label)) {
        case .absent:
            return .notSet
        case .file(let data):
            plistData = data
        case .notAFile, .unreadable:
            return .cannotTell
        }
        var members: [String: UndoJSON] = ["plist": .string(plistData.base64EncodedString())]
        switch UndoItem.read(at: ScheduledDeploy.scriptURL(label: label)) {
        case .absent:
            break
        case .file(let data):
            members["script"] = .string(data.base64EncodedString())
        case .notAFile, .unreadable:
            return .cannotTell
        }
        return .value(.object(members))
    }

    /// A job can be registered again only while the moment it was set for
    /// is KNOWN to be still ahead (seam 2): one whose moment has gone by
    /// would either never fire or fire at once, late, for a section a
    /// teacher has since moved on. A plist that does not say its moment
    /// (`PLANTOIR_SCHEDULED_FOR`, which older jobs lack) is never set again:
    /// its calendar entry carries no year, so it would fire on that day
    /// NEXT year (the review of U3b, LOW 2). Removing one is always possible.
    func canSet(_ target: String, _ value: UndoJSON?) -> Bool {
        guard let value else {
            return true
        }
        guard let files = UndoScheduledDeploys.files(in: value) else {
            return false
        }
        guard let moment = UndoScheduledDeploys.scheduledFor(plist: files.plist) else {
            return false
        }
        return moment > now()
    }

    func write(_ target: String, _ value: UndoJSON?) -> Bool {
        return writeSaying(target, value) != .notWritten
    }

    /// Sets or removes the job. A job launchd refuses now whose plist cannot
    /// be taken away again stays in LaunchAgents and loads at the next
    /// login: neither set back (it will not run at its moment unless the
    /// teacher logs out and in first) nor left apart (it will run), so it
    /// has its own answer, `startsAtTheNextLogin` (the re-review of U3b's
    /// fixes, LOW 2), and its own trail line, written only once the whole
    /// swap has gone in (`noteItStartsAtTheNextLogin(_:)`, round four, LOW 4).
    func writeSaying(_ target: String, _ value: UndoJSON?) -> UndoExternalWrite {
        guard let label = UndoScheduledDeploys.label(of: target), Thread.isMainThread else {
            return .notWritten
        }
        let plistURL: URL = ScheduledDeploy.plistURL(label: label)
        let scriptURL: URL = ScheduledDeploy.scriptURL(label: label)
        guard let value else {
            // The plist first: it is the one removal that can fail, and a
            // job whose plist is still there loads again at the next login,
            // so nothing else is touched until it has gone.
            if FileManager.default.fileExists(atPath: plistURL.path) {
                do {
                    try FileManager.default.removeItem(at: plistURL)
                } catch {
                    return .notWritten
                }
            }
            let job: LaunchControlRunning = runner
            MainActor.assumeIsolated {
                job.bootOut(label: label)
            }
            try? FileManager.default.removeItem(at: scriptURL)
            return .written
        }
        guard let files = UndoScheduledDeploys.files(in: value) else {
            return .notWritten
        }
        do {
            if let script = files.script {
                try FileManager.default.createDirectory(
                    at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try script.write(to: scriptURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            }
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try files.plist.write(to: plistURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: plistURL)
            if files.script != nil {
                try? FileManager.default.removeItem(at: scriptURL)
            }
            return .notWritten
        }
        let job: LaunchControlRunning = runner
        let refusal: String? = MainActor.assumeIsolated {
            return job.bootstrap(plistURL: plistURL)
        }
        if refusal != nil {
            // launchd refused it now. If its plist cannot be taken away
            // again, it stays in LaunchAgents and loads at the next login:
            // never said to be left apart (it will run), never said to be
            // back (it will not run at its moment unless the teacher logs
            // out and in first). Its script stays with it.
            // Its trail line waits for the whole swap (`noteItStartsAtTheNextLogin`).
            if (try? FileManager.default.removeItem(at: plistURL)) == nil
                && FileManager.default.fileExists(atPath: plistURL.path) {
                return .startsAtTheNextLogin
            }
            if files.script != nil {
                try? FileManager.default.removeItem(at: scriptURL)
            }
            return .notWritten
        }
        return .written
    }

    /// The trail line for a deploy set for later that Undo or Redo put
    /// back and macOS would not start now, written once the whole swap has
    /// gone in (`UndoExternalPlaces.noteItStartsAtTheNextLogin`), from the
    /// plist then on disk. Off the main thread nothing is written: such a
    /// write was refused, so no job of it starts at the next login.
    func noteItStartsAtTheNextLogin(_ target: String) {
        guard let label = UndoScheduledDeploys.label(of: target), Thread.isMainThread,
              let plist = try? Data(contentsOf: ScheduledDeploy.plistURL(label: label)) else {
            return
        }
        MainActor.assumeIsolated {
            UndoScheduledDeploys.noteItStartsAtTheNextLogin(plist: plist)
        }
    }

    /// The trail line for a deploy set for later that Undo or Redo put back
    /// and macOS would not start now: it starts at the next login. Names
    /// the course, the section and the moment from the job's own plist.
    @MainActor
    static func noteItStartsAtTheNextLogin(plist data: Data) {
        var line: String = "put back a scheduled deploy"
        if let moment = UndoScheduledDeploys.scheduledFor(plist: data) {
            line += " for " + ScheduledDeploy.dayAndTimeText(moment)
        }
        line += ", but macOS would not start it now; it starts the next time you log in to this Mac, "
            + "and will not run at its time unless you log out and in before then"
        if let place = UndoScheduledDeploys.courseAndSection(plist: data) {
            ActivityTrail.note(.scheduledDeployCouldNotBeSet, line, course: place.course, section: place.section)
            return
        }
        ActivityTrail.note(.scheduledDeployCouldNotBeSet, line)
    }

    /// The course and section a job deploys, from the arguments its plist
    /// runs (`--scheduled-section <folder> <course> <section>`), or nil.
    static func courseAndSection(plist data: Data) -> (course: String, section: Int)? {
        guard let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = decoded as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else {
            return nil
        }
        var index: Int = 0
        while index < arguments.count {
            if arguments[index] == ScheduledDeploy.sectionFlag && index + 3 < arguments.count {
                guard let section = Int(arguments[index + 3]) else {
                    return nil
                }
                return (course: arguments[index + 2], section: section)
            }
            index += 1
        }
        return nil
    }

    /// The two files a value holds, or nil when it is not this family's shape.
    static func files(in value: UndoJSON) -> (plist: Data, script: Data?)? {
        guard case .object(let members) = value,
              case .string(let plistText)? = members["plist"],
              let plist = Data(base64Encoded: plistText) else {
            return nil
        }
        var script: Data? = nil
        if let scriptValue = members["script"] {
            guard case .string(let scriptText) = scriptValue, let decoded = Data(base64Encoded: scriptText) else {
                return nil
            }
            script = decoded
        }
        return (plist: plist, script: script)
    }

    /// The moment a plist's job is set for (`PLANTOIR_SCHEDULED_FOR`), or
    /// nil when it does not say.
    static func scheduledFor(plist data: Data) -> Date? {
        guard let decoded = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = decoded as? [String: Any],
              let environment = plist["EnvironmentVariables"] as? [String: String],
              let stamp = environment[ScheduledDeploy.scheduledForKey] else {
            return nil
        }
        return ISO8601DateFormatter().date(from: stamp)
    }
}

/// Every `external` family the app changes, each to its own place: the
/// app's preferences (`preference:`) and its deploys set for later
/// (`scheduledDeploy:`). What the app's actions, and U7's Undo and Redo,
/// pass as `places`.
nonisolated struct UndoAppPlaces: UndoExternalPlaces, @unchecked Sendable {

    // MARK: - Stored properties

    let preferences: UndoExternalPlaces

    let schedules: UndoScheduledDeploys

    // MARK: - Initializer

    init(preferences: UndoExternalPlaces = UndoAppPreferences(), schedules: UndoScheduledDeploys) {
        self.preferences = preferences
        self.schedules = schedules
    }

    // MARK: - Functions

    func read(_ target: String) -> UndoExternalReading {
        if UndoScheduledDeploys.label(of: target) != nil {
            return schedules.read(target)
        }
        return preferences.read(target)
    }

    func write(_ target: String, _ value: UndoJSON?) -> Bool {
        if UndoScheduledDeploys.label(of: target) != nil {
            return schedules.write(target, value)
        }
        return preferences.write(target, value)
    }

    func writeSaying(_ target: String, _ value: UndoJSON?) -> UndoExternalWrite {
        if UndoScheduledDeploys.label(of: target) != nil {
            return schedules.writeSaying(target, value)
        }
        return preferences.writeSaying(target, value)
    }

    func canSet(_ target: String, _ value: UndoJSON?) -> Bool {
        if UndoScheduledDeploys.label(of: target) != nil {
            return schedules.canSet(target, value)
        }
        return preferences.canSet(target, value)
    }

    func noteItStartsAtTheNextLogin(_ target: String) {
        if UndoScheduledDeploys.label(of: target) != nil {
            schedules.noteItStartsAtTheNextLogin(target)
            return
        }
        preferences.noteItStartsAtTheNextLogin(target)
    }
}
