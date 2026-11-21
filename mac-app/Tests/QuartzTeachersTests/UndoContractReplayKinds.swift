import Foundation
@testable import QuartzTeachers

/// The stack cases' calls that make steps of the kinds U2 defines (#899):
/// a rollover's marker moved, a folder made and removed, a settings member,
/// a body hunk and a preference, each through `JournaledWrite.perform(ops:)`,
/// the door that plans a step forward exactly as a Redo does. Written
/// without XCTest, like `UndoContractReplay`, so the standalone harness runs
/// it too.
nonisolated enum UndoContractKinds {

    // MARK: - Stored properties

    static let markerFrom: String = "courses/TST1O/.netlify_sites/section1.json"
    static let markerTo: String = "courses/TST1O/.netlify_sites/section1.previous.json"
    static let oldMarker: String = "{\"site_id\": \"aaa-111\"}\n"
    static let newMarker: String = "{\"site_id\": \"bbb-222\"}\n"
    static let extraFolder: String = "courses/TST1O/extra"
    static let extraFiles: [String: String] = ["a.md": "A\n", "sub/b.md": "B\n"]
    static let settings: String = "courses/TST1O/settings.json"
    static let notes: String = "courses/TST1O/notes.md"
    static let preference: String = "preference:undoCasesPreference"
    static let cloudflareFrom: String = "courses/TST1O/.cloudflare_sites/section1.json"
    static let cloudflareTo: String = "courses/TST1O/.cloudflare_sites/section1.previous.json"
    static let cloudflareMarker: String = "{\"project\": \"tst1o-s1-2025\"}\n"
    static let schedule: String = "scheduledDeploy:org.plantoir.deploy.undo-cases"
    static let scheduleValue: UndoJSON = .object(["plist": .string("cGxpc3Q="), "script": .string("c2NyaXB0")])
    static let leftoverFrom: String = "courses/TST1O/.netlify_sites/section1.from-built-output.json"
    static let leftoverTo: String = "courses/TST1O/.netlify_sites/section1.from-built-output.previous.json"
    static let leftover: String = "{\"site_id\": \"ccc-333\"}\n"

    /// Every call this file answers.
    static let calls: Set<String> = [
        "moveTheMarker", "rollOverOntoANewWebsite", "deployANewMarker", "makeAFolder", "addAFileToTheFolder", "removeTheFolder",
        "editTheSettings", "editTheSettingsByHand", "editAHunk", "setAPreference",
        "changeThePreferenceByHand", "forgetTheMaintainer", "moveThePageAside", "linkItsOldFolderOutside",
        "rollOverOntoNewWebsitesOnTwoHosts", "rollOverTurningOffASchedule", "theScheduleCannotBeSetNow",
        "rollOverSettingALeftoverAside", "removeTheKeptLeftover", "theScheduleStartsOnlyAtTheNextLogin",
    ]

    static let asidePage: String = "courses/TST1O/old/a.md"
    static let asidePageMoved: String = "courses/TST1O/a.md"

    /// Where `linkItsOldFolderOutside` points: beside the working folder.
    static func outside(of root: URL) -> URL {
        return root.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
    }

    // MARK: - Functions

    static func draft(ops: [UndoOp], blobs: [Data], root: URL?, action: String) -> UndoOpsDraft {
        return UndoOpsDraft(
            action: UndoAction(key: action, arguments: [:]),
            madeBy: "menu",
            workingFolderURL: root,
            workingFolderPath: root?.path,
            course: root == nil ? nil : "TST1O",
            section: root == nil ? nil : 1,
            actionClass: "A",
            holds: root == nil ? nil : "section",
            ops: ops,
            blobs: blobs
        )
    }

    static func word(_ outcome: JournaledWriteOutcome) -> String {
        if case .applied = outcome {
            return "applied"
        }
        return "\(outcome)"
    }

    /// The settings file's school year, or nil.
    static func schoolYear(in root: URL) -> String? {
        let reading: UndoJSONMember.Reading = UndoJSONMember.reading(["school_year"], in: Data((text(at: settings, in: root) ?? "").utf8))
        if case .value(.string(let year)) = reading {
            return year
        }
        return nil
    }

    static func text(at path: String, in root: URL) -> String? {
        guard let data = UndoItem.read(at: root.appendingPathComponent(path)).data else {
            return nil
        }
        return UndoText.decode(data)
    }

    /// Makes one call; answers what `last` becomes (nil: unchanged).
    static func call(_ value: String, root: URL, journal: UndoJournal, places: UndoMemoryPlaces) throws -> String? {
        switch value {
        case "moveTheMarker":
            if text(at: markerFrom, in: root) == nil && text(at: markerTo, in: root) == nil {
                try UndoContractReplay.write(oldMarker, to: markerFrom, in: root)
            }
            let content: String = text(at: markerFrom, in: root) ?? ""
            let op: UndoOp = UndoOp.moveFile(from: markerFrom, to: markerTo, sha: UndoHash.sha256(of: Data(content.utf8)))
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
        case "rollOverOntoANewWebsite":
            // U3b: one step of the year's setting and the marker moved aside
            // as a `moveApart`, which stands apart from the rest of its step.
            if text(at: markerFrom, in: root) == nil && text(at: markerTo, in: root) == nil {
                try UndoContractReplay.write(oldMarker, to: markerFrom, in: root)
            }
            if text(at: settings, in: root) == nil {
                try UndoContractReplay.write("{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n", to: settings, in: root)
            }
            let content: String = text(at: markerFrom, in: root) ?? ""
            let year: UndoOp = UndoOp.editJSON(path: settings, keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
            let marker: UndoOp = UndoOp.moveFileApart(from: markerFrom, to: markerTo, sha: UndoHash.sha256(of: Data(content.utf8)))
            return word(JournaledWrite.perform(ops: draft(ops: [year, marker], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
        case "rollOverOntoNewWebsitesOnTwoHosts":
            // U3b, records as a group: the year's setting and BOTH hosts'
            // markers moved aside, each a `moveApart`, in one step.
            if text(at: markerFrom, in: root) == nil && text(at: markerTo, in: root) == nil {
                try UndoContractReplay.write(oldMarker, to: markerFrom, in: root)
            }
            if text(at: cloudflareFrom, in: root) == nil && text(at: cloudflareTo, in: root) == nil {
                try UndoContractReplay.write(cloudflareMarker, to: cloudflareFrom, in: root)
            }
            if text(at: settings, in: root) == nil {
                try UndoContractReplay.write("{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n", to: settings, in: root)
            }
            let year: UndoOp = UndoOp.editJSON(path: settings, keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
            let netlify: UndoOp = UndoOp.moveFileApart(from: markerFrom, to: markerTo, sha: UndoHash.sha256(of: Data(oldMarker.utf8)))
            let cloudflare: UndoOp = UndoOp.moveFileApart(from: cloudflareFrom, to: cloudflareTo, sha: UndoHash.sha256(of: Data(cloudflareMarker.utf8)))
            return word(JournaledWrite.perform(ops: draft(ops: [year, netlify, cloudflare], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
        case "rollOverTurningOffASchedule":
            // U3b: the year's setting and the section's deploy set for later
            // turned off (`external` on `scheduledDeploy:`), in one step.
            if text(at: settings, in: root) == nil {
                try UndoContractReplay.write("{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n", to: settings, in: root)
            }
            _ = places.write(schedule, scheduleValue)
            let year: UndoOp = UndoOp.editJSON(path: settings, keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
            let off: UndoOp = UndoOp.external(target: schedule, before: scheduleValue, after: nil)
            return word(JournaledWrite.perform(ops: draft(ops: [year, off], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
        case "rollOverSettingALeftoverAside":
            // U3b, the review of U3b's fixes, LOW 3: the year, the record as
            // a `moveApart`, and a leftover no deploy reads as a `setAside`.
            if text(at: markerFrom, in: root) == nil && text(at: markerTo, in: root) == nil {
                try UndoContractReplay.write(oldMarker, to: markerFrom, in: root)
            }
            if text(at: leftoverFrom, in: root) == nil && text(at: leftoverTo, in: root) == nil {
                try UndoContractReplay.write(leftover, to: leftoverFrom, in: root)
            }
            if text(at: settings, in: root) == nil {
                try UndoContractReplay.write("{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n", to: settings, in: root)
            }
            let year: UndoOp = UndoOp.editJSON(path: settings, keyPath: ["school_year"], before: .string("2025-2026"), after: .string("2026-2027"))
            let marker: UndoOp = UndoOp.moveFileApart(from: markerFrom, to: markerTo, sha: UndoHash.sha256(of: Data(oldMarker.utf8)))
            let aside: UndoOp = UndoOp.setFileAside(from: leftoverFrom, to: leftoverTo, sha: UndoHash.sha256(of: Data(leftover.utf8)))
            return word(JournaledWrite.perform(ops: draft(ops: [year, marker, aside], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
        case "removeTheKeptLeftover":
            try? FileManager.default.removeItem(at: root.appendingPathComponent(leftoverTo))
            return nil
        case "theScheduleStartsOnlyAtTheNextLogin":
            // launchd would not start the job now and its plist cannot be
            // taken away again: every later write that sets a deploy for
            // later answers that it starts at the next login.
            places.schedulesStartAtTheNextLogin = true
            return nil
        case "theScheduleCannotBeSetNow":
            // launchd refuses the job, or the write is off the main thread:
            // every write to a deploy set for later answers false from now.
            places.refusesSchedules = true
            return nil
        case "deployANewMarker":
            // What a deploy after a rollover onto a new website does: a new
            // marker in the place the rollover emptied, nothing in the list.
            let url: URL = root.appendingPathComponent(markerFrom)
            try? FileManager.default.removeItem(at: url)
            try UndoContractReplay.write(newMarker, to: markerFrom, in: root)
            return nil
        case "makeAFolder":
            var files: [UndoTreeListing.File] = []
            var blobs: [Data] = []
            for (path, content) in extraFiles {
                files.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: Data(content.utf8))))
                blobs.append(Data(content.utf8))
            }
            let listing: UndoTreeListing = UndoTreeListing(folders: ["sub"], files: files)
            blobs.append(listing.data)
            let op: UndoOp = UndoOp.tree(.createTree, path: extraFolder, listing: listing)
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: blobs, root: root, action: "newFolder"), in: journal, mode: .live, places: places))
        case "addAFileToTheFolder":
            try UndoContractReplay.write("C\n", to: extraFolder + "/c.md", in: root)
            return nil
        case "removeTheFolder":
            guard case .tree(let listing, let contents) = UndoTreeReading.read(at: root.appendingPathComponent(extraFolder), keepingContents: true) else {
                return "noFolderToRemove"
            }
            var blobs: [Data] = [listing.data]
            for (_, data) in contents {
                blobs.append(data)
            }
            let op: UndoOp = UndoOp.tree(.removeTree, path: extraFolder, listing: listing)
            // The door makes the change itself: the folder is taken out
            // by the same staged swap that later puts it back.
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: blobs, root: root, action: "removeFolder"), in: journal, mode: .live, places: places))
        case "editTheSettings":
            if text(at: settings, in: root) == nil {
                try UndoContractReplay.write("{\n  \"course_name\" : \"Test\",\n  \"school_year\" : \"2025-2026\"\n}\n", to: settings, in: root)
            }
            let reading: UndoJSONMember.Reading = UndoJSONMember.reading(["school_year"], in: Data((text(at: settings, in: root) ?? "").utf8))
            var before: UndoJSON? = nil
            var after: UndoJSON = .string("2026-2027")
            if case .value(let value) = reading {
                before = value
                if value == .string("2026-2027") {
                    after = .string("2025-2026")
                }
            }
            let op: UndoOp = UndoOp.editJSON(path: settings, keyPath: ["school_year"], before: before, after: after)
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: [], root: root, action: "setSchoolYear"), in: journal, mode: .live, places: places))
        case "editTheSettingsByHand":
            let url: URL = root.appendingPathComponent(settings)
            try? FileManager.default.removeItem(at: url)
            try UndoContractReplay.write("{\"course_name\": \"Test\", \"school_year\": \"2030-2031\"}\n", to: settings, in: root)
            return nil
        case "editAHunk":
            if text(at: notes, in: root) == nil {
                try UndoContractReplay.write("Intro.\nLine one: old.\nEnd.\n", to: notes, in: root)
            }
            let now: String = text(at: notes, in: root) ?? ""
            let isNew: Bool = now.contains("Line one: new.")
            let op: UndoOp = UndoOp.replaceText(
                path: notes, before: isNew ? "new" : "old", after: isNew ? "old" : "new",
                contextBefore: "Line one: ", contextAfter: ".\n"
            )
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: [], root: root, action: "editPage"), in: journal, mode: .live, places: places))
        case "setAPreference":
            var before: UndoJSON? = nil
            var after: UndoJSON = .string("b")
            if case .value(let value) = places.read(preference) {
                before = value
                if value == .string("b") {
                    after = .string("a")
                }
            }
            let op: UndoOp = UndoOp.external(target: preference, before: before, after: after)
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: [], root: nil, action: "setPreference"), in: journal, mode: .live, places: places))
        case "changeThePreferenceByHand":
            _ = places.write(preference, .string("z"))
            return nil
        case "moveThePageAside":
            if text(at: asidePage, in: root) == nil {
                try UndoContractReplay.write("page\n", to: asidePage, in: root)
            }
            let op: UndoOp = UndoOp.moveFile(from: asidePage, to: asidePageMoved, sha: UndoHash.sha256(of: Data("page\n".utf8)))
            return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
        case "linkItsOldFolderOutside":
            // The folder the page was moved out of, replaced by a link to a
            // folder outside the working folder (the second hard review of
            // U2b, MEDIUM 2).
            let old: URL = root.appendingPathComponent("courses/TST1O/old")
            try? FileManager.default.removeItem(at: old)
            try FileManager.default.createDirectory(at: outside(of: root), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: old, withDestinationURL: outside(of: root))
            return nil
        case "forgetTheMaintainer":
            UndoMaintainers.forget("sectionFrontPage")
            return nil
        default:
            return "unknown call \(value)"
        }
    }

    /// What `markers` says of the two places a rollover's marker move names.
    static func markers(in root: URL) -> String {
        let from: String? = text(at: markerFrom, in: root)
        let to: String? = text(at: markerTo, in: root)
        if from == nil && to == oldMarker {
            return "moved"
        }
        if from == oldMarker && to == nil {
            return "movedBack"
        }
        if from == newMarker && to == oldMarker {
            return "bothKept"
        }
        return "from \(String(describing: from)), to \(String(describing: to))"
    }

    /// What `cloudflareMarkers` says of the two places the second host's
    /// marker move names.
    static func cloudflareMarkers(in root: URL) -> String {
        let from: String? = text(at: cloudflareFrom, in: root)
        let to: String? = text(at: cloudflareTo, in: root)
        if from == nil && to == cloudflareMarker {
            return "moved"
        }
        if from == cloudflareMarker && to == nil {
            return "movedBack"
        }
        return "from \(String(describing: from)), to \(String(describing: to))"
    }

    /// What `leftoverMarkers` says of the two places the leftover's
    /// `setAside` names.
    static func leftoverMarkers(in root: URL) -> String {
        let from: String? = text(at: leftoverFrom, in: root)
        let to: String? = text(at: leftoverTo, in: root)
        if from == nil && to == leftover {
            return "moved"
        }
        if from == leftover && to == nil {
            return "movedBack"
        }
        if from == nil && to == nil {
            return "gone"
        }
        return "from \(String(describing: from)), to \(String(describing: to))"
    }

    /// Every staged file or folder (`.plantoir-undo-` in its name) anywhere
    /// in the working folder: none may be left once a call has answered.
    static func stagedLeftovers(in root: URL) -> [String] {
        var found: [String] = []
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return found
        }
        while let next = walker.nextObject() as? String {
            if next.contains(UndoSwap.stagedMarker) {
                found.append(next)
            }
        }
        return found
    }

    /// Whether the folder `makeAFolder` makes is there.
    static func folderIsThere(in root: URL) -> Bool {
        if case .tree = UndoTreeReading.read(at: root.appendingPathComponent(extraFolder)) {
            return true
        }
        return false
    }
}

/// An external place in memory, for the cases: one dictionary, safe to read
/// and write from any thread.
nonisolated final class UndoMemoryPlaces: UndoExternalPlaces, @unchecked Sendable {

    // MARK: - Stored properties

    private var values: [String: UndoJSON] = [:]

    private let guardLock: NSLock = NSLock()

    /// Whether every write to a deploy set for later fails, as a launchd
    /// refusal does (`theScheduleCannotBeSetNow`).
    var refusesSchedules: Bool = false

    /// Whether every write that SETS a deploy for later answers that it
    /// starts at the next login (`theScheduleStartsOnlyAtTheNextLogin`).
    var schedulesStartAtTheNextLogin: Bool = false

    // MARK: - Functions

    func read(_ target: String) -> UndoExternalReading {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        guard let value = values[target] else {
            return .notSet
        }
        return .value(value)
    }

    func write(_ target: String, _ value: UndoJSON?) -> Bool {
        guardLock.lock()
        if refusesSchedules && target.hasPrefix(UndoOp.scheduledDeployFamily + ":") {
            guardLock.unlock()
            return false
        }
        values[target] = value
        guardLock.unlock()
        return true
    }

    func writeSaying(_ target: String, _ value: UndoJSON?) -> UndoExternalWrite {
        if !write(target, value) {
            return .notWritten
        }
        if schedulesStartAtTheNextLogin && value != nil && target.hasPrefix(UndoOp.scheduledDeployFamily + ":") {
            return .startsAtTheNextLogin
        }
        return .written
    }
}
