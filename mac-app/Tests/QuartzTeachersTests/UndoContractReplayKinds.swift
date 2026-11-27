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
        "moveAFolderWithAPageEditedInside", "addAFileInsideTheMovedFolder", "editThePageInsideByHand",
        "stepEditingInsideAMovesFrom", "renameAFolderInCaseOnly", "spellTheFolderAnotherWay",
        "leaveAKeptCopyInsideTheMovedFolder", "moveAFolderWithAFileMadeInANewFolderInside", "addAFolderInsideTheMadeFolder",
        "moveAFolderHoldingAnEmptyFolderAndMakingAFolderInIt", "moveAFolderHoldingAnEmptyFolderAndMakingFilesInItAndBesideIt",
        "finderRecordsAWindowInTheMadeFolder",
        "moveThePageIntoAFolder", "moveThePageBetweenFolders", "linkItsNewFolderOutside",
        "moveALinkToAFolder", "stepEditingInsideALinksMove",
        "handAPlaceOverAfterALinksMove", "handAPlaceOverBeforeALinksMove", "editTheHandedOverPageByHand",
        "relinkALink", "relinkALinkLeavingAHandedOverPlace", "relinkTwoChainedLinks", "relinkThreeChainedLinks", "relinkThenMoveALinkIntoItsPlace",
        "stepFillingAPlaceBeforeItIsLeft", "stepHandingOverAFoldersPlace",
    ]

    /// U4b: the three spellings of the folder a capitalisation-only rename
    /// moves (`renameAFolderInCaseOnly`), one place on a case-insensitive
    /// volume.
    static let caseOnlyFrom: String = "courses/TST1O/Media"
    static let caseOnlyTo: String = "courses/TST1O/media"
    static let caseOnlyByHand: String = "courses/TST1O/MEDIA"

    /// U4b: the folder `moveAFolderWithAPageEditedInside` moves, and where.
    static let mediaFolder: String = "courses/TST1O/media"
    static let renamedFolder: String = "courses/TST1O/renamed"
    static let mediaFiles: [String: String] = ["a.md": "Intro.\nLine one: old.\nEnd.\n", "b.md": "B\n"]

    /// U4b2-10: the file `moveAFolderWithAFileMadeInANewFolderInside` makes,
    /// in a folder (`sub`) the step makes for it inside the moved folder.
    static let madeFolderFile: String = "courses/TST1O/renamed/sub/x.md"

    /// U4b2-14: the link `moveALinkToAFolder` moves, where, what it holds,
    /// and the folder elsewhere in the course it leads to.
    static let linkFrom: String = "courses/TST1O/section1/media"
    static let linkTo: String = "courses/TST1O/section1/renamed"
    static let linkTarget: String = "../library"
    static let linkedLibrary: String = "courses/TST1O/library"
    static let libraryFiles: [String: String] = ["a.md": "A\n", "pictures/b.md": "B\n"]

    /// U4b3 door-4: the class pages `handAPlaceOverAfterALinksMove` and
    /// `handAPlaceOverBeforeALinksMove` hand over, by day, and the library
    /// their links lead to (relative targets).
    static let handedOverDays: [Int] = [2, 3, 4]

    /// U4b3 relink-3: the class pages `relinkALink` and
    /// `relinkALinkLeavingAHandedOverPlace` change, by day.
    static let relinkedDays: [Int] = [3, 4, 5]

    /// Review D of U4b3: the class pages `relinkTwoChainedLinks` changes.
    static let chainedRelinkDays: [Int] = [4, 5, 6]

    /// Review F of U4b3: the class pages `relinkThreeChainedLinks` changes.
    static let threeChainedRelinkDays: [Int] = [4, 5, 6, 7]

    static func classPage(_ day: Int) -> String {
        return "courses/TST1O/section1/Unit 1, Day \(day).md"
    }

    static func libraryTarget(_ day: Int) -> String {
        return "../library/Day \(day).md"
    }

    static let asidePage: String = "courses/TST1O/old/a.md"
    static let asidePageMoved: String = "courses/TST1O/a.md"

    /// U4b2-2: the pages `moveThePageIntoAFolder` and
    /// `moveThePageBetweenFolders` move, and where; `linkItsNewFolderOutside`
    /// replaces the folder both move into.
    static let pageIntoAFolder: String = "courses/TST1O/b.md"
    static let pageIntoAFolderMoved: String = "courses/TST1O/new/b.md"
    static let pageBetweenFolders: String = "courses/TST1O/old/c.md"
    static let pageBetweenFoldersMoved: String = "courses/TST1O/new/c.md"

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

    /// One step of one `move`: the page at `from` (made first, holding
    /// `page`, when neither place holds it) to `to`.
    static func moveAPage(from: String, to: String, root: URL, journal: UndoJournal, places: UndoMemoryPlaces) throws -> String {
        if text(at: from, in: root) == nil && text(at: to, in: root) == nil {
            try UndoContractReplay.write("page\n", to: from, in: root)
        }
        let op: UndoOp = UndoOp.moveFile(from: from, to: to, sha: UndoHash.sha256(of: Data("page\n".utf8)))
        return word(JournaledWrite.perform(ops: draft(ops: [op], blobs: [], root: root, action: "rollOver"), in: journal, mode: .live, places: places))
    }

    /// Review 1 of U4b2-10: media (a.md, b.md and an empty folder sub,
    /// made when neither place is there), then ONE step: its move to
    /// renamed, the edit of a.md, and one `writeFile` making each of
    /// `making`, in the order of their paths.
    static func moveTheFolderHoldingAnEmptyFolder(
        making: [String: String], root: URL, journal: UndoJournal, places: UndoMemoryPlaces
    ) throws -> String {
        if !somethingIsAt(mediaFolder, in: root) && !somethingIsAt(renamedFolder, in: root) {
            for (name, content) in mediaFiles {
                try UndoContractReplay.write(content, to: mediaFolder + "/" + name, in: root)
            }
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(mediaFolder + "/sub"), withIntermediateDirectories: true
            )
        }
        guard let listingSha = UndoTreeReading.read(at: root.appendingPathComponent(mediaFolder)).listingSha else {
            return "noFolderToMove"
        }
        var ops: [UndoOp] = [
            UndoOp.moveFolder(from: mediaFolder, to: renamedFolder, listingSha: listingSha),
            UndoOp.replaceText(
                path: renamedFolder + "/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
            ),
        ]
        var blobs: [Data] = []
        var paths: [String] = []
        for (path, _) in making {
            paths.append(path)
        }
        paths.sort()
        for path in paths {
            let content: Data = Data((making[path] ?? "").utf8)
            ops.append(UndoOp.writeFile(path: path, beforeSha: nil, afterSha: UndoHash.sha256(of: content)))
            blobs.append(content)
        }
        return word(JournaledWrite.perform(
            ops: draft(ops: ops, blobs: blobs, root: root, action: "renameFolder"), in: journal, mode: .live, places: places
        ))
    }

    /// The folder at `folder`, replaced by a link to the folder beside the
    /// working folder (the second hard review of U2b, MEDIUM 2; U4b2-2).
    static func linkOutside(_ folder: String, root: URL) throws {
        let place: URL = root.appendingPathComponent(folder)
        try? FileManager.default.removeItem(at: place)
        try FileManager.default.createDirectory(at: outside(of: root), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: place, withDestinationURL: outside(of: root))
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
            try linkOutside("courses/TST1O/old", root: root)
            return nil
        case "moveThePageIntoAFolder":
            return try moveAPage(from: pageIntoAFolder, to: pageIntoAFolderMoved, root: root, journal: journal, places: places)
        case "moveThePageBetweenFolders":
            return try moveAPage(from: pageBetweenFolders, to: pageBetweenFoldersMoved, root: root, journal: journal, places: places)
        case "linkItsNewFolderOutside":
            // U4b2-2: the folder a page was moved into, replaced by a link to
            // the same folder outside the working folder.
            try linkOutside("courses/TST1O/new", root: root)
            return nil
        case "moveAFolderWithAPageEditedInside":
            // U4b: one step, the folder moved and then a page inside it
            // edited, named at its new place (opKinds.wholeOps' order).
            if !somethingIsAt(mediaFolder, in: root) && !somethingIsAt(renamedFolder, in: root) {
                for (name, content) in mediaFiles {
                    try UndoContractReplay.write(content, to: mediaFolder + "/" + name, in: root)
                }
            }
            guard let listingSha = UndoTreeReading.read(at: root.appendingPathComponent(mediaFolder)).listingSha else {
                return "noFolderToMove"
            }
            let move: UndoOp = UndoOp.moveFolder(from: mediaFolder, to: renamedFolder, listingSha: listingSha)
            let edit: UndoOp = UndoOp.replaceText(
                path: renamedFolder + "/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
            )
            return word(JournaledWrite.perform(ops: draft(ops: [move, edit], blobs: [], root: root, action: "renameFolder"), in: journal, mode: .live, places: places))
        case "moveAFolderWithAFileMadeInANewFolderInside":
            // U4b2-10: one step, the folder moved, a page inside it edited,
            // and a file made in a folder that was not there, both named at
            // the new place (opKinds.wholeOps' order).
            if !somethingIsAt(mediaFolder, in: root) && !somethingIsAt(renamedFolder, in: root) {
                for (name, content) in mediaFiles {
                    try UndoContractReplay.write(content, to: mediaFolder + "/" + name, in: root)
                }
            }
            guard let listingSha = UndoTreeReading.read(at: root.appendingPathComponent(mediaFolder)).listingSha else {
                return "noFolderToMove"
            }
            let madeContent: Data = Data("X\n".utf8)
            let move: UndoOp = UndoOp.moveFolder(from: mediaFolder, to: renamedFolder, listingSha: listingSha)
            let edit: UndoOp = UndoOp.replaceText(
                path: renamedFolder + "/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
            )
            let made: UndoOp = UndoOp.writeFile(path: madeFolderFile, beforeSha: nil, afterSha: UndoHash.sha256(of: madeContent))
            return word(JournaledWrite.perform(
                ops: draft(ops: [move, edit, made], blobs: [madeContent], root: root, action: "renameFolder"),
                in: journal, mode: .live, places: places
            ))
        case "moveAFolderHoldingAnEmptyFolderAndMakingAFolderInIt":
            // Review 1 of U4b2-10, MEDIUM 1 (a): the content's own empty
            // sub, and a folder the step makes inside it.
            return try moveTheFolderHoldingAnEmptyFolder(
                making: ["courses/TST1O/renamed/sub/deeper/x.md": "X\n"], root: root, journal: journal, places: places
            )
        case "moveAFolderHoldingAnEmptyFolderAndMakingFilesInItAndBesideIt":
            // MEDIUM 1 (b): a file made in the content's own empty sub, and
            // a folder made beside it.
            return try moveTheFolderHoldingAnEmptyFolder(
                making: ["courses/TST1O/renamed/sub/x.md": "X\n", "courses/TST1O/renamed/new/y.md": "Y\n"],
                root: root, journal: journal, places: places
            )
        case "finderRecordsAWindowInTheMadeFolder":
            try UndoContractReplay.write("Finder\n", to: renamedFolder + "/sub/" + UndoTreeListing.ignoredName, in: root)
            return nil
        case "addAFolderInsideTheMadeFolder":
            try UndoContractReplay.write("Y\n", to: renamedFolder + "/sub/mine/y.md", in: root)
            return nil
        case "renameAFolderInCaseOnly":
            // U4b: one step, the folder renamed in its capitals only, then a
            // page inside it edited, named at the new spelling.
            if !somethingIsAt(caseOnlyFrom, in: root) {
                for (name, content) in mediaFiles {
                    try UndoContractReplay.write(content, to: caseOnlyFrom + "/" + name, in: root)
                }
            }
            guard let listingSha = UndoTreeReading.read(at: root.appendingPathComponent(caseOnlyFrom)).listingSha else {
                return "noFolderToMove"
            }
            let move: UndoOp = UndoOp.moveFolder(from: caseOnlyFrom, to: caseOnlyTo, listingSha: listingSha)
            let edit: UndoOp = UndoOp.replaceText(
                path: caseOnlyTo + "/a.md", before: "old", after: "new", contextBefore: "Line one: ", contextAfter: ".\n"
            )
            return word(JournaledWrite.perform(ops: draft(ops: [move, edit], blobs: [], root: root, action: "renameFolder"), in: journal, mode: .live, places: places))
        case "spellTheFolderAnotherWay":
            let listed: URL = root.appendingPathComponent(caseOnlyFolderSpelling(in: root) ?? caseOnlyTo)
            // rename(2), as a Finder rename does: one item, a new spelling.
            if Darwin.rename(listed.path, root.appendingPathComponent(caseOnlyByHand).path) != 0 {
                return "couldNotRename"
            }
            return nil
        case "moveALinkToAFolder":
            // U4b2-14: one step, a link to a folder elsewhere in the course
            // moved as itself, judged by the target it holds.
            if !somethingIsAt(linkFrom, in: root) && !somethingIsAt(linkTo, in: root) {
                for (name, content) in libraryFiles {
                    try UndoContractReplay.write(content, to: linkedLibrary + "/" + name, in: root)
                }
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(linkFrom).deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.createSymbolicLink(
                    atPath: root.appendingPathComponent(linkFrom).path, withDestinationPath: linkTarget
                )
            }
            let move: UndoOp = UndoOp.moveLink(from: linkFrom, to: linkTo, linkSha: UndoHash.sha256(of: Data(linkTarget.utf8)))
            return word(JournaledWrite.perform(ops: draft(ops: [move], blobs: [], root: root, action: "renameFolder"), in: journal, mode: .live, places: places))
        case "stepEditingInsideALinksMove":
            // Review 1 of U4b2-14: written as another version might write
            // it, changing nothing: a link's move and an edit under its `to`.
            let next: Int = try journal.read().highestSeq + 1
            let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
            let moment: String = UndoMoment.text(Date())
            let linkSha: String = UndoHash.sha256(of: Data(linkTarget.utf8))
            let ops: String = "[{\"kind\":\"move\",\"from\":\"\(linkFrom)\",\"to\":\"\(linkTo)\",\"linkSha\":\"\(linkSha)\"},"
                + "{\"kind\":\"replaceText\",\"path\":\"\(linkTo)/a.md\",\"before\":\"old\",\"after\":\"new\",\"contextBefore\":\"Line one: \",\"contextAfter\":\".\\n\"}]"
            let begin: String = "{\"v\":1,\"seq\":\(next),\"event\":\"begin\",\"at\":\"\(moment)\",\"step\":{\"seq\":\(next),\"madeAt\":\"\(moment)\",\"workingFolder\":{\"id\":\"\(folderID)\",\"pathAtTheTime\":\"\(root.path)\"},\"ops\":\(ops)}}"
            try UndoContractReplay.appendRaw(begin, to: journal)
            try UndoContractReplay.appendRaw("{\"v\":1,\"seq\":\(next),\"event\":\"applied\"}", to: journal)
            return nil
        case "handAPlaceOverAfterALinksMove":
            // U4b3 door-4, shape A: Day 3 a link; ONE step: the link moved to
            // Day 4, then a new page at the place it left.
            if !somethingIsAt(classPage(3), in: root) && !somethingIsAt(classPage(4), in: root) {
                try UndoContractReplay.write("Linked.\n", to: "courses/TST1O/library/Day 3.md", in: root)
                try layALink(classPage(3), leadingTo: libraryTarget(3), root: root)
            }
            let new: Data = Data("New.\n".utf8)
            let ops: [UndoOp] = [
                UndoOp.moveLink(from: classPage(3), to: classPage(4), linkSha: UndoHash.sha256(of: Data(libraryTarget(3).utf8))),
                UndoOp.writeFile(path: classPage(3), beforeSha: nil, afterSha: UndoHash.sha256(of: new)),
            ]
            return word(JournaledWrite.perform(ops: draft(ops: ops, blobs: [new], root: root, action: "insertClass"), in: journal, mode: .live, places: places))
        case "handAPlaceOverBeforeALinksMove":
            // U4b3 door-4, shape B: Day 2 a link, Day 3 a page; ONE step:
            // Day 3's page to Day 4, Day 3 removed, the link moved into Day
            // 3, a new page at Day 2.
            if !somethingIsAt(classPage(2), in: root) && !somethingIsAt(classPage(3), in: root) {
                try UndoContractReplay.write("Two.\n", to: "courses/TST1O/library/Day 2.md", in: root)
                try layALink(classPage(2), leadingTo: libraryTarget(2), root: root)
                try UndoContractReplay.write("Three.\n", to: classPage(3), in: root)
            }
            let three: Data = Data("Three.\n".utf8)
            let new: Data = Data("New.\n".utf8)
            let ops: [UndoOp] = [
                UndoOp.writeFile(path: classPage(4), beforeSha: nil, afterSha: UndoHash.sha256(of: three)),
                UndoOp.writeFile(path: classPage(3), beforeSha: UndoHash.sha256(of: three), afterSha: nil),
                UndoOp.moveLink(from: classPage(2), to: classPage(3), linkSha: UndoHash.sha256(of: Data(libraryTarget(2).utf8))),
                UndoOp.writeFile(path: classPage(2), beforeSha: nil, afterSha: UndoHash.sha256(of: new)),
            ]
            return word(JournaledWrite.perform(ops: draft(ops: ops, blobs: [three, new], root: root, action: "insertClass"), in: journal, mode: .live, places: places))
        case "relinkALink", "relinkALinkLeavingAHandedOverPlace":
            // U4b3 relink-3: Day 3 a page, Day 4 a link holding `Unit 1,
            // Day 3.md`; ONE step: the link moved to Day 5 holding `Unit 1,
            // Day 4.md` (a relinking move); leaving a handed-over place, as
            // Insert Class makes it, Day 3's page then moved into Day 4 and
            // `New.` written at Day 3.
            let oldText: Data = Data("Unit 1, Day 3.md".utf8)
            let newText: Data = Data("Unit 1, Day 4.md".utf8)
            if !somethingIsAt(classPage(3), in: root) && !somethingIsAt(classPage(4), in: root) {
                try UndoContractReplay.write("Three.\n", to: classPage(3), in: root)
                try layALink(classPage(4), leadingTo: "Unit 1, Day 3.md", root: root)
            }
            var ops: [UndoOp] = [
                UndoOp.relinkLink(from: classPage(4), to: classPage(5), linkShaBefore: UndoHash.sha256(of: oldText), linkShaAfter: UndoHash.sha256(of: newText)),
            ]
            var blobs: [Data] = [oldText, newText]
            if value == "relinkALinkLeavingAHandedOverPlace" {
                let three: Data = Data("Three.\n".utf8)
                let new: Data = Data("New.\n".utf8)
                ops.append(UndoOp.moveFile(from: classPage(3), to: classPage(4), sha: UndoHash.sha256(of: three)))
                ops.append(UndoOp.writeFile(path: classPage(3), beforeSha: nil, afterSha: UndoHash.sha256(of: new)))
                blobs.append(new)
            }
            return word(JournaledWrite.perform(ops: draft(ops: ops, blobs: blobs, root: root, action: "insertClass"), in: journal, mode: .live, places: places))
        case "relinkTwoChainedLinks":
            // Review D of U4b3, MEDIUM: Day 4 a link holding `Unit 1, Day
            // 1.md`, Day 5 one holding `Unit 1, Day 2.md`; ONE step, as
            // Insert Class makes it, highest first: Day 5's link moved to
            // Day 6 holding `Unit 1, Day 3.md`, then Day 4's moved to Day 5
            // holding `Unit 1, Day 2.md` (the first move's old text).
            let one: Data = Data("Unit 1, Day 1.md".utf8)
            let two: Data = Data("Unit 1, Day 2.md".utf8)
            let three: Data = Data("Unit 1, Day 3.md".utf8)
            if !somethingIsAt(classPage(4), in: root) && !somethingIsAt(classPage(5), in: root) && !somethingIsAt(classPage(6), in: root) {
                try layALink(classPage(4), leadingTo: "Unit 1, Day 1.md", root: root)
                try layALink(classPage(5), leadingTo: "Unit 1, Day 2.md", root: root)
            }
            let ops: [UndoOp] = [
                UndoOp.relinkLink(from: classPage(5), to: classPage(6), linkShaBefore: UndoHash.sha256(of: two), linkShaAfter: UndoHash.sha256(of: three)),
                UndoOp.relinkLink(from: classPage(4), to: classPage(5), linkShaBefore: UndoHash.sha256(of: one), linkShaAfter: UndoHash.sha256(of: two)),
            ]
            return word(JournaledWrite.perform(ops: draft(ops: ops, blobs: [one, two, three], root: root, action: "insertClass"), in: journal, mode: .live, places: places))
        case "relinkThreeChainedLinks":
            // Review F of U4b3, MEDIUM: Day 4, Day 5 and Day 6 links holding
            // `Unit 1, Day 1.md`, `Unit 1, Day 2.md` and `Unit 1, Day
            // 3.md`; ONE step, highest first: Day 6's link moved to Day 7
            // holding `Unit 1, Day 4.md`, then Day 5's to Day 6, then Day
            // 4's to Day 5, each holding the next one's old text.
            var texts: [Data] = []
            var day: Int = 1
            while day <= 4 {
                texts.append(Data("Unit 1, Day \(day).md".utf8))
                day += 1
            }
            if !somethingIsAt(classPage(4), in: root) && !somethingIsAt(classPage(5), in: root) && !somethingIsAt(classPage(6), in: root) && !somethingIsAt(classPage(7), in: root) {
                try layALink(classPage(4), leadingTo: "Unit 1, Day 1.md", root: root)
                try layALink(classPage(5), leadingTo: "Unit 1, Day 2.md", root: root)
                try layALink(classPage(6), leadingTo: "Unit 1, Day 3.md", root: root)
            }
            let ops: [UndoOp] = [
                UndoOp.relinkLink(from: classPage(6), to: classPage(7), linkShaBefore: UndoHash.sha256(of: texts[2]), linkShaAfter: UndoHash.sha256(of: texts[3])),
                UndoOp.relinkLink(from: classPage(5), to: classPage(6), linkShaBefore: UndoHash.sha256(of: texts[1]), linkShaAfter: UndoHash.sha256(of: texts[2])),
                UndoOp.relinkLink(from: classPage(4), to: classPage(5), linkShaBefore: UndoHash.sha256(of: texts[0]), linkShaAfter: UndoHash.sha256(of: texts[1])),
            ]
            return word(JournaledWrite.perform(ops: draft(ops: ops, blobs: texts, root: root, action: "insertClass"), in: journal, mode: .live, places: places))
        case "relinkThenMoveALinkIntoItsPlace":
            // Review F of U4b3: Day 4 and Day 5 links both holding `Unit 1,
            // Day 2.md`; ONE step: Day 5's link relinked to Day 6 holding
            // `Unit 1, Day 3.md`, then Day 4's moved plainly into Day 5.
            let two: Data = Data("Unit 1, Day 2.md".utf8)
            let three: Data = Data("Unit 1, Day 3.md".utf8)
            if !somethingIsAt(classPage(4), in: root) && !somethingIsAt(classPage(5), in: root) && !somethingIsAt(classPage(6), in: root) {
                try layALink(classPage(4), leadingTo: "Unit 1, Day 2.md", root: root)
                try layALink(classPage(5), leadingTo: "Unit 1, Day 2.md", root: root)
            }
            let ops: [UndoOp] = [
                UndoOp.relinkLink(from: classPage(5), to: classPage(6), linkShaBefore: UndoHash.sha256(of: two), linkShaAfter: UndoHash.sha256(of: three)),
                UndoOp.moveLink(from: classPage(4), to: classPage(5), linkSha: UndoHash.sha256(of: two)),
            ]
            return word(JournaledWrite.perform(ops: draft(ops: ops, blobs: [two, three], root: root, action: "insertClass"), in: journal, mode: .live, places: places))
        case "editTheHandedOverPageByHand":
            try? FileManager.default.removeItem(at: root.appendingPathComponent(classPage(3)))
            try UndoContractReplay.write("Hand.\n", to: classPage(3), in: root)
            return nil
        case "stepFillingAPlaceBeforeItIsLeft":
            // Written as another version might write it, changing nothing: a
            // new page at Day 3, THEN the link's move away from Day 3.
            let linkSha: String = UndoHash.sha256(of: Data(libraryTarget(3).utf8))
            let newSha: String = UndoHash.sha256(of: Data("New.\n".utf8))
            let ops: String = "[{\"kind\":\"writeFile\",\"path\":\"\(classPage(3))\",\"beforeSha\":null,\"afterSha\":\"\(newSha)\"},"
                + "{\"kind\":\"move\",\"from\":\"\(classPage(3))\",\"to\":\"\(classPage(4))\",\"linkSha\":\"\(linkSha)\"}]"
            try appendAStepChangingNothing(ops: ops, root: root, journal: journal)
            return nil
        case "stepHandingOverAFoldersPlace":
            // The same, a folder's move away from section 1's media and then
            // a new file at that place: a folder never hands a place over.
            let folder: String = "courses/TST1O/section1/media"
            let newSha: String = UndoHash.sha256(of: Data("New.\n".utf8))
            let ops: String = "[{\"kind\":\"move\",\"from\":\"\(folder)\",\"to\":\"courses/TST1O/section1/renamed\",\"listingSha\":\"\(String(repeating: "a", count: 64))\"},"
                + "{\"kind\":\"writeFile\",\"path\":\"\(folder)\",\"beforeSha\":null,\"afterSha\":\"\(newSha)\"}]"
            try appendAStepChangingNothing(ops: ops, root: root, journal: journal)
            return nil
        case "addAFileInsideTheMovedFolder":
            try UndoContractReplay.write("C\n", to: renamedFolder + "/c.md", in: root)
            return nil
        case "leaveAKeptCopyInsideTheMovedFolder":
            // The part-two review's M1: the newest step's own kept original
            // beside a.md, wherever the folder is now, as a tidy that could
            // not remove it leaves one.
            let seq: Int = try journal.read().highestSeq
            let folder: String = somethingIsAt(renamedFolder, in: root) ? renamedFolder : mediaFolder
            try UndoContractReplay.write("Kept.\n", to: folder + "/.a.md\(UndoSwap.stagedMarker)\(seq)-undo-orig", in: root)
            return nil
        case "editThePageInsideByHand":
            try? FileManager.default.removeItem(at: root.appendingPathComponent(renamedFolder + "/a.md"))
            try UndoContractReplay.write("Hand.\n", to: renamedFolder + "/a.md", in: root)
            return nil
        case "stepEditingInsideAMovesFrom":
            // Written as another version might write it, changing nothing:
            // an edit naming a path inside the place a move leaves.
            let next: Int = try journal.read().highestSeq + 1
            let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
            let moment: String = UndoMoment.text(Date())
            let ops: String = "[{\"kind\":\"move\",\"from\":\"\(mediaFolder)\",\"to\":\"\(renamedFolder)\",\"listingSha\":\"\(String(repeating: "a", count: 64))\"},"
                + "{\"kind\":\"replaceText\",\"path\":\"\(mediaFolder)/a.md\",\"before\":\"old\",\"after\":\"new\",\"contextBefore\":\"Line one: \",\"contextAfter\":\".\\n\"}]"
            let begin: String = "{\"v\":1,\"seq\":\(next),\"event\":\"begin\",\"at\":\"\(moment)\",\"step\":{\"seq\":\(next),\"madeAt\":\"\(moment)\",\"workingFolder\":{\"id\":\"\(folderID)\",\"pathAtTheTime\":\"\(root.path)\"},\"ops\":\(ops)}}"
            try UndoContractReplay.appendRaw(begin, to: journal)
            try UndoContractReplay.appendRaw("{\"v\":1,\"seq\":\(next),\"event\":\"applied\"}", to: journal)
            return nil
        case "forgetTheMaintainer":
            UndoMaintainers.forget("sectionFrontPage")
            return nil
        default:
            return "unknown call \(value)"
        }
    }

    /// What `markers` says of the two places a rollover's marker move names.
    /// U4b's `movedFolder`: which place holds the folder (renamed, media,
    /// both or neither), then what its a.md holds (new, old, byHand, none).
    static func movedFolder(in root: URL) -> String {
        let atNew: Bool = somethingIsAt(renamedFolder, in: root)
        let atOld: Bool = somethingIsAt(mediaFolder, in: root)
        var place: String = "neither"
        var folder: String = renamedFolder
        if atNew && atOld {
            place = "both"
        } else if atNew {
            place = "renamed"
        } else if atOld {
            place = "media"
            folder = mediaFolder
        }
        var page: String = "none"
        if let text = text(at: folder + "/a.md", in: root) {
            if text.contains("Line one: new.") {
                page = "new"
            } else if text.contains("Line one: old.") {
                page = "old"
            } else {
                page = "byHand"
            }
        }
        return place + ", " + page
    }

    /// recoveryCasesHow's `handEdit: carried` (U4b2-13): a.md inside the
    /// moved folder, wherever the folder is now (renamed if it is there,
    /// else media), its line `Line one: …` set to `Line one: by hand.`.
    /// False when there is no such page.
    static func editTheCarriedPageByHand(in root: URL) throws -> Bool {
        let folder: String = somethingIsAt(renamedFolder, in: root) ? renamedFolder : mediaFolder
        guard let text = text(at: folder + "/a.md", in: root) else {
            return false
        }
        var lines: [String] = text.components(separatedBy: "\n")
        var changed: Bool = false
        for index in 0..<lines.count where lines[index].hasPrefix("Line one: ") {
            lines[index] = "Line one: by hand."
            changed = true
        }
        if !changed {
            return false
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: root.appendingPathComponent(folder + "/a.md"))
        return true
    }

    /// U4b2-10's `madeFolder`: what the folder `sub` holds wherever the
    /// moved folder is now (renamed if it is there, else media), every name
    /// in the order of its bytes, `empty` or `none`.
    static func madeFolder(in root: URL) -> String {
        let folder: String = somethingIsAt(renamedFolder, in: root) ? renamedFolder : mediaFolder
        var isAFolder: ObjCBool = false
        let made: URL = root.appendingPathComponent(folder + "/sub")
        if !FileManager.default.fileExists(atPath: made.path, isDirectory: &isAFolder) || !isAFolder.boolValue {
            return "none"
        }
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: made.path)) ?? []
        if names.isEmpty {
            return "empty"
        }
        var inByteOrder: [String] = names
        inByteOrder.sort { first, second in
            Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8))
        }
        return inByteOrder.joined(separator: ", ")
    }

    /// Review 1 of U4b2-10's `foldersInside`: every folder below the moved
    /// folder wherever it is now (renamed if it is there, else media), in
    /// the order of their bytes, or `none`.
    static func foldersInside(in root: URL) -> String {
        let folder: String = somethingIsAt(renamedFolder, in: root) ? renamedFolder : mediaFolder
        guard case .tree(let listing, _) = UndoTreeReading.read(at: root.appendingPathComponent(folder)) else {
            return "none"
        }
        if listing.folders.isEmpty {
            return "none"
        }
        var inByteOrder: [String] = listing.folders
        inByteOrder.sort { first, second in
            Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8))
        }
        return inByteOrder.joined(separator: ", ")
    }

    /// U4b3 door-4: a symbolic link at a place, holding a target as written.
    static func layALink(_ path: String, leadingTo target: String, root: URL) throws {
        let url: URL = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
    }

    /// A begin and an applied line, as another version might write them,
    /// for a step of these ops (JSON) that changes nothing.
    static func appendAStepChangingNothing(ops: String, root: URL, journal: UndoJournal) throws {
        let next: Int = try journal.read().highestSeq + 1
        let folderID: String = try FolderIdentityFile.identifier(forWorkingFolder: root)
        let moment: String = UndoMoment.text(Date())
        let begin: String = "{\"v\":1,\"seq\":\(next),\"event\":\"begin\",\"at\":\"\(moment)\",\"step\":{\"seq\":\(next),\"madeAt\":\"\(moment)\",\"workingFolder\":{\"id\":\"\(folderID)\",\"pathAtTheTime\":\"\(root.path)\"},\"ops\":\(ops)}}"
        try UndoContractReplay.appendRaw(begin, to: journal)
        try UndoContractReplay.appendRaw("{\"v\":1,\"seq\":\(next),\"event\":\"applied\"}", to: journal)
    }

    /// U4b3 door-4's `handedOver`: section 1's class pages Day 2, Day 3
    /// and Day 4, in that order, each as `Day <n>: page <text>` (its text without its last line end),
    /// `Day <n>: link <target>` or `Day <n>: nothing`, then `library:
    /// untouched` when every page the links lead to holds what the call laid
    /// (else `changed`), joined by `; `.
    /// U4b3 relink-3 reads `relinkedDays` instead (Day 3 to Day 5).
    static func handedOver(in root: URL, days: [Int] = handedOverDays) -> String {
        var parts: [String] = []
        for day in days {
            let url: URL = root.appendingPathComponent(classPage(day))
            var what: String = "nothing"
            if let bytes = UndoTreeReading.linkTarget(at: url), let target = UndoText.decode(bytes) {
                what = "link " + target
            } else if let content = text(at: classPage(day), in: root) {
                var trimmed: String = content
                if trimmed.hasSuffix("\n") {
                    trimmed.removeLast()
                }
                what = "page " + trimmed
            } else if somethingIsAt(classPage(day), in: root) {
                what = "other"
            }
            parts.append("Day \(day): " + what)
        }
        // The pages the links lead to, each exactly as the call laid it.
        let laid: [String: String] = ["Day 2.md": "Two.\n", "Day 3.md": "Linked.\n"]
        var library: String = "untouched"
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("courses/TST1O/library").path)) ?? []
        for name in names {
            if let wanted = laid[name], text(at: "courses/TST1O/library/" + name, in: root) == wanted {
                continue
            }
            library = "changed"
        }
        parts.append("library: " + library)
        return parts.joined(separator: "; ")
    }

    /// U4b2-14's `linkedFolder`: which place holds the link (renamed, media,
    /// both or neither), the target it holds there (`notALink` when what is
    /// there is not a link), and whether the folder it leads to is exactly
    /// as the call made it (`untouched`, else `changed`).
    static func linkedFolder(in root: URL) -> String {
        let atNew: Bool = somethingIsAt(linkTo, in: root)
        let atOld: Bool = somethingIsAt(linkFrom, in: root)
        var place: String = "neither"
        var link: String = linkTo
        if atNew && atOld {
            place = "both"
        } else if atNew {
            place = "renamed"
        } else if atOld {
            place = "media"
            link = linkFrom
        }
        var target: String = "notALink"
        if let bytes = UndoTreeReading.linkTarget(at: root.appendingPathComponent(link)), let text = UndoText.decode(bytes) {
            target = text
        }
        var files: [UndoTreeListing.File] = []
        for (path, content) in libraryFiles {
            files.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: Data(content.utf8))))
        }
        let made: UndoTreeListing = UndoTreeListing(folders: ["pictures"], files: files)
        let now: String? = UndoTreeReading.read(at: root.appendingPathComponent(linkedLibrary)).listingSha
        let library: String = now == made.sha ? "untouched" : "changed"
        return place + ", " + target + ", " + library
    }

    /// The spelling courses/TST1O lists for the folder a capitalisation-only
    /// rename moves, as a path, or nil when it lists none (U4b).
    static func caseOnlyFolderSpelling(in root: URL) -> String? {
        let parent: String = (caseOnlyTo as NSString).deletingLastPathComponent
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(parent).path)) ?? []
        for name in names where name.lowercased() == "media" {
            return parent + "/" + name
        }
        return nil
    }

    /// U4b's `caseOnlyFolder`: the spelling listed, then what its a.md
    /// holds (new, old, byHand, none).
    static func caseOnlyFolder(in root: URL) -> String {
        guard let folder = caseOnlyFolderSpelling(in: root) else {
            return "none"
        }
        var page: String = "none"
        if let text = text(at: folder + "/a.md", in: root) {
            if text.contains("Line one: new.") {
                page = "new"
            } else if text.contains("Line one: old.") {
                page = "old"
            } else {
                page = "byHand"
            }
        }
        return (folder as NSString).lastPathComponent + ", " + page
    }

    static func somethingIsAt(_ path: String, in root: URL) -> Bool {
        return UndoItem.read(at: root.appendingPathComponent(path)) != .absent
    }

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
