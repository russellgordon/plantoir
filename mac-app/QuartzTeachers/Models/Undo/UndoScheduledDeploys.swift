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
/// the main thread is refused (`write` answers false, which the door reads
/// as a change that could not be made, nothing changed) rather than
/// guessed at. Every action that makes such a step runs on the main actor.
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
    /// is still ahead (seam 2): one whose moment has gone by would either
    /// never fire or fire at once, late, for a section a teacher has since
    /// moved on. Removing one is always possible.
    func canSet(_ target: String, _ value: UndoJSON?) -> Bool {
        guard let value else {
            return true
        }
        guard let files = UndoScheduledDeploys.files(in: value) else {
            return false
        }
        guard let moment = UndoScheduledDeploys.scheduledFor(plist: files.plist) else {
            return true
        }
        return moment > now()
    }

    func write(_ target: String, _ value: UndoJSON?) -> Bool {
        guard let label = UndoScheduledDeploys.label(of: target), Thread.isMainThread else {
            return false
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
                    return false
                }
            }
            let job: LaunchControlRunning = runner
            MainActor.assumeIsolated {
                job.bootOut(label: label)
            }
            try? FileManager.default.removeItem(at: scriptURL)
            return true
        }
        guard let files = UndoScheduledDeploys.files(in: value) else {
            return false
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
            return false
        }
        let job: LaunchControlRunning = runner
        let refusal: String? = MainActor.assumeIsolated {
            return job.bootstrap(plistURL: plistURL)
        }
        if refusal != nil {
            try? FileManager.default.removeItem(at: plistURL)
            if files.script != nil {
                try? FileManager.default.removeItem(at: scriptURL)
            }
            return false
        }
        return true
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

    func canSet(_ target: String, _ value: UndoJSON?) -> Bool {
        if UndoScheduledDeploys.label(of: target) != nil {
            return schedules.canSet(target, value)
        }
        return preferences.canSet(target, value)
    }
}
