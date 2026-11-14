import XCTest
@testable import QuartzTeachers

/// Runs `contracts/course-management.json` → `backups.sharedMedia` and
/// `contracts/file-formats.json` → `sharedMediaStore` (#785, piece 785a).
///
/// The sweep is the rule that can lose a teacher's only copy of a picture,
/// and both apps sweep the same store when a working folder is synced
/// between them, so its cases are data both suites run rather than prose
/// either side re-reads.
final class SharedMediaContractTests: XCTestCase {

    // MARK: - Names

    /// Each name is a small backup or not, and every RELEASED parser leaves a
    /// small one unlisted. `FrozenBackupNames` is the parser as v1.9.3
    /// shipped it (unchanged from v1.0.0 in the part that matters), so this
    /// keeps passing after 785b teaches `BackupItem` the new names.
    func testTheNamesAreReadAsTheContractSays() throws {
        let shared: [String: Any] = try SharedMediaContractTests.sharedMedia()
        let cases: [[String: Any]] = try XCTUnwrap(shared["nameCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        XCTAssertEqual(shared["nameEnding"] as? String, SharedMediaStore.smallBackupEnding)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let small: Bool = try XCTUnwrap(testCase["small"] as? Bool)
            XCTAssertEqual(SharedMediaStore.isSmallBackupName(name), small, name)
            XCTAssertEqual(
                SharedMediaStore.smallBackupNameBehindPlaceholder(name),
                testCase["behindPlaceholder"] as? String,
                name
            )
            let readByOlder: Bool = try XCTUnwrap(testCase["readByOlderVersions"] as? Bool)
            XCTAssertEqual(
                FrozenBackupNames.isListed(name, courseCode: "ICS3U"), readByOlder,
                "\(name): what every released Plantoir does with this name"
            )
        }
    }

    /// The frozen parser is still today's: until 785b, `BackupItem.from`
    /// must agree with it on every name case, small ones included, so no
    /// version of the app lists a small backup it cannot restore (#785 plan
    /// review, amendment 7).
    @MainActor
    func testTodaysParserLeavesSmallBackupsUnlisted() throws {
        let shared: [String: Any] = try SharedMediaContractTests.sharedMedia()
        for testCase in try XCTUnwrap(shared["nameCases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let listed: Bool = BackupItem.from(fileURL: URL(fileURLWithPath: "/x/\(name)"), courseCode: "ICS3U") != nil
            XCTAssertEqual(listed, FrozenBackupNames.isListed(name, courseCode: "ICS3U"), name)
        }
    }

    // MARK: - The sweep

    func testEverySweepCaseIsDecidedAsTheContractSays() throws {
        let shared: [String: Any] = try SharedMediaContractTests.sharedMedia()
        let honoured: [String: Any] = try XCTUnwrap(shared["honoured"] as? [String: Any])
        XCTAssertEqual(honoured["pendingListHours"] as? Int, Int(SharedMediaSweepRule.pendingHonouredFor / 3600))
        XCTAssertEqual(honoured["listWithoutItsZipHours"] as? Int, Int(SharedMediaSweepRule.pendingHonouredFor / 3600))
        XCTAssertEqual(honoured["undoListDays"] as? Int, Int(SharedMediaSweepRule.undoHonouredFor / 86_400))
        XCTAssertEqual(honoured["unneededBeforeDeletedHours"] as? Int, Int(SharedMediaSweepRule.unneededFor / 3600))

        let cases: [[String: Any]] = try XCTUnwrap(shared["sweepCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 22)
        let now: Date = Date(timeIntervalSince1970: 1_800_000_000)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let inputs: SharedMediaSweepRule.Inputs = try SharedMediaContractTests.inputs(of: testCase, now: now)
            let decision: SharedMediaSweepRule.Decision = SharedMediaSweepRule.decide(inputs)

            let expectKept: Bool = (testCase["expectKeptEverything"] as? Bool) ?? false
            XCTAssertEqual(decision.keptEverything != nil, expectKept, "\(name): keeps everything")
            var expectedDeleted: [String] = []
            for token in try XCTUnwrap(testCase["expectDeleted"] as? [String]) {
                expectedDeleted.append(SharedMediaContractTests.entryPath(token))
            }
            expectedDeleted.sort()
            XCTAssertEqual(decision.entriesToDelete, expectedDeleted, "\(name): deleted")
            var expectedRecorded: Set<String> = []
            for token in try XCTUnwrap(testCase["expectStillRecorded"] as? [String]) {
                expectedRecorded.insert(SharedMediaContractTests.entryPath(token))
            }
            var recorded: Set<String> = []
            for (path, _) in decision.unneededSince {
                recorded.insert(path)
            }
            XCTAssertEqual(recorded, expectedRecorded, "\(name): recorded as unneeded")
            if let removed = testCase["expectListsRemoved"] as? [String] {
                XCTAssertEqual(decision.listFilesToRemove, removed.sorted(), "\(name): lists removed")
            }
        }
    }

    // MARK: - The restore, through a real store

    func testEveryRestoreCaseIsWhatTheContractSays() throws {
        let shared: [String: Any] = try SharedMediaContractTests.sharedMedia()
        let cases: [[String: Any]] = try XCTUnwrap(shared["restoreCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        let fileManager: FileManager = FileManager.default
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let top: URL = fileManager.temporaryDirectory.appendingPathComponent("shared-media-restore-\(UUID().uuidString)")
            defer {
                try? fileManager.removeItem(at: top)
            }
            let courses: URL = top.appendingPathComponent("courses")
            let current: URL = courses.appendingPathComponent("ICS3U")
            try SharedMediaTestFiles.write(Data("{}".utf8), to: current.appendingPathComponent("course_config.json"))
            let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)

            var media: [SharedMediaList.MediaFile] = []
            var folders: [SharedMediaList.MediaFolder] = [SharedMediaList.MediaFolder(path: "Media", mode: 0o755)]
            var bytesForPath: [String: Data] = [:]
            for file in try XCTUnwrap(testCase["files"] as? [[String: Any]]) {
                let path: String = try XCTUnwrap(file["path"] as? String)
                let bytes: Data = SharedMediaTestFiles.randomData(2000)
                bytesForPath[path] = bytes
                let checksum: String = SharedMediaTestFiles.checksum(of: bytes)
                let parent: String = (path as NSString).deletingLastPathComponent
                if parent != "Media" {
                    folders.append(SharedMediaList.MediaFolder(path: parent, mode: 0o755))
                }
                media.append(SharedMediaList.MediaFile(
                    path: path, sha256: checksum, size: Int64(bytes.count),
                    modified: Date(timeIntervalSince1970: 1_700_000_000), mode: 0o644
                ))
                switch try XCTUnwrap(file["where"] as? String) {
                case "store":
                    try SharedMediaTestFiles.write(bytes, to: store.fileURL(forChecksum: checksum))
                case "damagedInStore":
                    try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(2000), to: store.fileURL(forChecksum: checksum))
                case "course":
                    let elsewhere: URL = current.appendingPathComponent("Media/elsewhere")
                        .appendingPathComponent((path as NSString).lastPathComponent)
                    try SharedMediaTestFiles.write(bytes, to: elsewhere)
                default:
                    break
                }
            }
            let list: SharedMediaList = SharedMediaList(
                course: "ICS3U", backupName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
                writtenAt: Date(), host: "TEST", media: media, folders: folders
            )
            let restore: SharedMediaRestore = store.beginRestore(of: list, currentCourseFolderURL: current)
            let expectedMissing: [String] = try XCTUnwrap(testCase["expectMissing"] as? [String])
            XCTAssertEqual(restore.missing, expectedMissing, "\(name): missing, found before anything changes")
            XCTAssertEqual(restore.canBeRestored, try XCTUnwrap(testCase["expectCanBeRestored"] as? Bool), "\(name)")
            if restore.canBeRestored {
                let payload: URL = top.appendingPathComponent("staging/ICS3U")
                let filled: SharedMediaRestore.Filled = try restore.fill(
                    intoCourseAt: payload, backupFileName: list.backupName
                )
                XCTAssertEqual(filled.missing, expectedMissing, "\(name): the same files named again, never skipped")
                XCTAssertEqual(filled.filesTakenFromTheCourse, try XCTUnwrap(testCase["expectFromTheCourse"] as? Int), name)
                for file in media where !filled.missing.contains(file.path) {
                    XCTAssertEqual(
                        try Data(contentsOf: payload.appendingPathComponent(file.path)), bytesForPath[file.path],
                        "\(name): \(file.path) put back byte for byte"
                    )
                }
                var isFolder: ObjCBool = false
                XCTAssertTrue(
                    fileManager.fileExists(atPath: payload.appendingPathComponent("Media").path, isDirectory: &isFolder)
                        && isFolder.boolValue,
                    "\(name): the Media folder is made, empty or not"
                )
            }
            restore.end()
        }
    }

    // MARK: - The format

    func testTheFormatsExampleListReadsAndWritesBack() throws {
        let format: [String: Any] = try SharedMediaContractTests.contract("file-formats.json", key: "sharedMediaStore")
        let list: [String: Any] = try XCTUnwrap(format["list"] as? [String: Any])
        let example: Data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(list["example"]))
        let decoded: SharedMediaList = try SharedMediaList.decoded(from: example)
        XCTAssertEqual(decoded.media.count, 2)
        XCTAssertEqual(decoded.folders.count, 4)
        XCTAssertEqual(try SharedMediaList.decoded(from: try decoded.encoded()), decoded)
        for unsafe in try XCTUnwrap(list["unsafeExamples"] as? [String]) {
            XCTAssertFalse(SharedMediaList.isSafeMediaPath(unsafe), unsafe)
        }
        let layout: [String: Any] = try XCTUnwrap(format["layout"] as? [String: Any])
        XCTAssertNotNil(layout["files/<aa>/<sha256>"])
        XCTAssertNotNil(layout["lists/undo-<step id>.json"])
        XCTAssertEqual(SharedMediaStore.storeFolderName, ".shared-media")
        XCTAssertEqual(SharedMediaList.nameInsideTheZip, ".plantoir-backup.json")
    }

    // MARK: - Functions

    static func sharedMedia() throws -> [String: Any] {
        let backups: [String: Any] = try contract("course-management.json", key: "backups")
        return try XCTUnwrap(backups["sharedMedia"] as? [String: Any], "No backups.sharedMedia in course-management.json")
    }

    /// One top-level key of one file in `contracts/`.
    static func contract(_ file: String, key: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts")
            .appendingPathComponent(file)
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[key] as? [String: Any], "No \(key) in \(file)")
    }

    /// A single letter a to f is a checksum of 64 of that letter.
    static func checksum(_ token: String) -> String? {
        if token.count == 1 {
            return String(repeating: token, count: 64)
        }
        return nil
    }

    static func entryPath(_ token: String) -> String {
        if let checksum = checksum(token) {
            return "\(checksum.prefix(2))/\(checksum)"
        }
        return "aa/\(token)"
    }

    static func checksums(_ any: Any?) -> Set<String> {
        var result: Set<String> = []
        for token in (any as? [String]) ?? [] {
            if let checksum = checksum(token) {
                result.insert(checksum)
            }
        }
        return result
    }

    static func inputs(of testCase: [String: Any], now: Date) throws -> SharedMediaSweepRule.Inputs {
        var entries: [SharedMediaSweepRule.StoreEntry] = []
        for token in try XCTUnwrap(testCase["store"] as? [String]) {
            entries.append(SharedMediaSweepRule.StoreEntry(
                relativePath: entryPath(token),
                checksum: checksum(token),
                isUnfinishedCopy: token.hasPrefix(".incoming-")
            ))
        }
        var backups: [SharedMediaSweepRule.BackupSeen] = []
        var index: Int = 0
        for backup in (testCase["backups"] as? [[String: Any]]) ?? [] {
            let unreadable: Bool = (backup["unreadable"] as? Bool) ?? false
            backups.append(SharedMediaSweepRule.BackupSeen(
                name: "backup\(index)", checksums: unreadable ? nil : checksums(backup["lists"])
            ))
            index += 1
        }
        var withoutZips: [SharedMediaSweepRule.ListWithoutItsZip] = []
        index = 0
        for list in (testCase["listsWithoutTheirZips"] as? [[String: Any]]) ?? [] {
            let hours: Double = try XCTUnwrap(list["hoursAgo"] as? NSNumber).doubleValue
            withoutZips.append(SharedMediaSweepRule.ListWithoutItsZip(
                fileName: "withoutZip\(index)", writtenAt: now.addingTimeInterval(-hours * 3600),
                checksums: checksums(list["lists"])
            ))
            index += 1
        }
        var holds: [SharedMediaSweepRule.HoldSeen] = []
        index = 0
        for list in (testCase["undoLists"] as? [[String: Any]]) ?? [] {
            let days: Double = try XCTUnwrap(list["daysAgo"] as? NSNumber).doubleValue
            let host: String = list["computer"] as? String == "this" ? "THIS" : "ANOTHER"
            holds.append(SharedMediaSweepRule.HoldSeen(
                fileName: "undo\(index)",
                hold: SharedMediaHold(
                    kind: .undo, id: "step\(index)", writtenAt: now.addingTimeInterval(-days * 86_400),
                    host: host, pid: 0, checksums: checksums(list["lists"])
                ),
                writerIsRunningHere: false
            ))
            index += 1
        }
        index = 0
        for list in (testCase["pendingLists"] as? [[String: Any]]) ?? [] {
            let hours: Double = try XCTUnwrap(list["hoursAgo"] as? NSNumber).doubleValue
            let host: String = list["computer"] as? String == "this" ? "THIS" : "ANOTHER"
            holds.append(SharedMediaSweepRule.HoldSeen(
                fileName: "pending\(index)",
                hold: SharedMediaHold(
                    kind: .pending, id: "pending\(index)", writtenAt: now.addingTimeInterval(-hours * 3600),
                    host: host, pid: 4321, checksums: checksums(list["lists"])
                ),
                writerIsRunningHere: try XCTUnwrap(list["running"] as? Bool)
            ))
            index += 1
        }
        var unreadable: [String] = []
        let unreadableCount: Int = (testCase["unreadableListFiles"] as? Int) ?? 0
        for number in 0..<unreadableCount {
            unreadable.append("lists/unreadable\(number).json")
        }
        var since: [String: Date] = [:]
        for (token, hours) in try XCTUnwrap(testCase["unneededSinceHoursAgo"] as? [String: Any]) {
            let hoursAgo: Double = try XCTUnwrap(hours as? NSNumber).doubleValue
            since[entryPath(token)] = now.addingTimeInterval(-hoursAgo * 3600)
        }
        return SharedMediaSweepRule.Inputs(
            storeEntries: entries,
            backups: backups,
            listsWithoutTheirZips: withoutZips,
            holds: holds,
            unreadableListFiles: unreadable,
            unneededSince: since,
            now: now,
            thisComputer: "THIS"
        )
    }
}

/// The backup-name reader every RELEASED Plantoir carries: copied from
/// `BackupItem.from` at v1.9.3 (the same in this part since v1.0.0, checked
/// by the #785 plan review). Frozen on purpose: when 785b teaches the app to
/// list small backups, this goes on saying what an older version does with
/// one, which is the guard that matters. Extend it if a later release
/// changes the reader; never replace it.
enum FrozenBackupNames {

    // MARK: - Functions

    static func isListed(_ fileName: String, courseCode: String) -> Bool {
        let url: URL = URL(fileURLWithPath: "/x").appendingPathComponent(fileName)
        if url.pathExtension.lowercased() != "zip" {
            return false
        }
        let name: String = url.deletingPathExtension().lastPathComponent
        let expectedPrefix: String = "\(courseCode)_backup_"
        if !name.hasPrefix(expectedPrefix) {
            return false
        }
        let remainder: String = String(name.dropFirst(expectedPrefix.count))
        let pieces: [String] = remainder.components(separatedBy: "_")
        if pieces.count < 2 || pieces.count > 3 {
            return false
        }
        var timePiece: String = pieces[1]
        if let dash = timePiece.firstIndex(of: "-") {
            let counter: String = String(timePiece[timePiece.index(after: dash)...])
            guard let number = Int(counter), number >= 2 else {
                return false
            }
            timePiece = String(timePiece[..<dash])
        }
        if ArchiveStamp.moment(from: pieces[0] + "_" + timePiece) == nil {
            return false
        }
        if pieces.count == 3 {
            let piece: String = pieces[2]
            let makers: [String] = ["assistant-section", "menu-section"]
            for maker in makers where piece.hasPrefix(maker) {
                if Int(piece.dropFirst(maker.count)) != nil {
                    return true
                }
            }
            return false
        }
        return true
    }
}
