import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `referenceCourses.groups` and
/// `contracts/file-formats.json` → `referenceShelf` (#572, third piece): the
/// groups a teacher makes on the Reference Courses shelf, and the file that
/// keeps them.
///
/// Every list is data from the contract. The acts run on REAL folders under
/// a temporary working folder, and every course folder is compared byte for
/// byte before and after: groups are a view, and no group act may rename,
/// move, remove or write into a course.
@MainActor
final class ReferenceShelfTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    var shelfFileURL: URL {
        return ReferenceShelfStore.fileURL(inCoursesDirectory: coursesDirectoryURL)
    }

    var trail: String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - Setting up

    /// A throwaway `courses/` folder and a trail of its own.
    func prepareCoursesFolder() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-shelf-\(UUID().uuidString)")
        coursesDirectoryURL = rootURL.appendingPathComponent("workspace").appendingPathComponent("courses")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))
        let root: URL = rootURL
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousStore
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A reference course folder with a page in it.
    func writeReferenceCourse(folder: String, code: String, year: Int?) throws {
        let folderURL: URL = coursesDirectoryURL.appendingPathComponent(folder)
        try FileManager.default.createDirectory(
            at: folderURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        var settings: String = "{\"course_code\": \"\(code)\", \"section_numbers\": [1], \"kept_for_reference\": true"
        if let year {
            settings += ", \"reference_school_year\": \(year)"
        }
        settings += "}\n"
        try Data(settings.utf8).write(to: folderURL.appendingPathComponent("course_config.json"))
        try Data("---\ntitle: Front\n---\nKept.\n".utf8)
            .write(to: folderURL.appendingPathComponent("section1").appendingPathComponent("index.md"))
    }

    /// Writes a case's `file`: an object, `"unreadable"`, or nothing.
    func writeShelfFile(_ file: Any?) throws {
        guard let file, !(file is NSNull) else {
            return
        }
        try FileManager.default.createDirectory(
            at: shelfFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let text = file as? String, text == "unreadable" {
            try Data("{\n  \"version\": 1,\n  \"groups\": [".utf8).write(to: shelfFileURL)
            return
        }
        try JSONSerialization.data(withJSONObject: file, options: [.sortedKeys]).write(to: shelfFileURL)
    }

    /// Every file under `courses/` except the shelf's own, by relative path,
    /// with its bytes: the before-and-after a group act must leave equal.
    func everyCourseFile() -> [String: Data] {
        var result: [String: Data] = [:]
        guard let walker = FileManager.default.enumerator(at: coursesDirectoryURL, includingPropertiesForKeys: nil) else {
            return result
        }
        let rootPath: String = coursesDirectoryURL.standardizedFileURL.path
        for case let fileURL as URL in walker {
            let path: String = fileURL.standardizedFileURL.path
            let relative: String = String(path.dropFirst(rootPath.count))
            if relative.hasPrefix("/.internal") {
                continue
            }
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            if isFolder.boolValue {
                result[relative + "/"] = Data()
            } else {
                result[relative] = (try? Data(contentsOf: fileURL)) ?? Data()
            }
        }
        return result
    }

    // MARK: - The contract

    static func repositoryURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func groupRules() throws -> [String: Any] {
        return try XCTUnwrap(try ReferenceCreationTests.referenceRules(["groups"]))
    }

    static func shelfFormat() throws -> [String: Any] {
        let url: URL = ReferenceShelfTests.repositoryURL().appendingPathComponent("contracts/file-formats.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["referenceShelf"] as? [String: Any])
    }

    /// A case's `courses`, as the shelf sees them.
    static func entries(_ raw: Any?) throws -> [ReferenceShelf.Entry] {
        var result: [ReferenceShelf.Entry] = []
        for course in try XCTUnwrap(raw as? [[String: Any]]) {
            result.append(ReferenceShelf.Entry(
                folderName: try XCTUnwrap(course["folder"] as? String),
                displayCode: try XCTUnwrap(course["code"] as? String),
                schoolYear: course["year"] as? Int
            ))
        }
        return result
    }

    /// A case's `file` as an arrangement, the way the app would read it.
    static func arrangement(_ file: Any?) throws -> ReferenceShelf.Arrangement {
        guard let file, !(file is NSNull) else {
            return ReferenceShelf.Arrangement()
        }
        if let text = file as? String, text == "unreadable" {
            return ReferenceShelf.reading(Data("{".utf8)).arrangement
        }
        let data: Data = try JSONSerialization.data(withJSONObject: file, options: [])
        return ReferenceShelf.reading(data).arrangement
    }

    /// Each folder → the title of the group the shelf draws it in.
    static func whereEach(_ entries: [ReferenceShelf.Entry], in arrangement: ReferenceShelf.Arrangement) -> [String: String] {
        var result: [String: String] = [:]
        for group in ReferenceShelf.groups(of: entries, arrangement: arrangement) {
            for folderName in group.folderNames {
                result[folderName] = group.title
            }
        }
        return result
    }

    /// The id of the made group with that name, in `arrangement`.
    static func madeGroupID(named name: String, in arrangement: ReferenceShelf.Arrangement) -> String? {
        for group in arrangement.groups where group.name == name {
            return group.id
        }
        return nil
    }

    /// A case's `to`: `{"year": n}`, `{"noYear": true}` or `{"made": name}`.
    static func place(_ raw: [String: Any], in arrangement: ReferenceShelf.Arrangement) throws -> ReferenceShelf.Place {
        if let year = raw["year"] as? Int {
            return .year(year)
        }
        if let name = raw["made"] as? String {
            return .made(try XCTUnwrap(ReferenceShelfTests.madeGroupID(named: name, in: arrangement)))
        }
        return .noYear
    }

    /// The sentence a wording key names, with the placeholders a case's
    /// state fills.
    static func sentence(forKey key: String) -> String? {
        switch key {
        case "couldNotReadGroups":
            return ReferenceGroupWording.couldNotReadGroups
        case "arrangedByANewerPlantoir":
            return ReferenceGroupWording.arrangedByANewerPlantoir
        case "couldNotSaveGroups":
            return ReferenceGroupWording.couldNotSaveGroups
        default:
            return nil
        }
    }

    // MARK: - Wording

    func testTheSentencesAreTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["wording"] as? [String: Any])
        let pairs: [(String, String)] = [
            ("newGroupMenuItem", ReferenceGroupWording.newGroupMenuItem),
            ("newGroupTitle", ReferenceGroupWording.newGroupTitle),
            ("nameLabel", ReferenceGroupWording.nameLabel),
            ("createButton", ReferenceGroupWording.createButton),
            ("renameGroupMenuItem", ReferenceGroupWording.renameGroupMenuItem),
            ("renameGroupTitle", ReferenceGroupWording.renameGroupTitle),
            ("renameButton", ReferenceGroupWording.renameButton),
            ("removeGroupMenuItem", ReferenceGroupWording.removeGroupMenuItem),
            ("removeGroupAskingMenuItem", ReferenceGroupWording.removeGroupAskingMenuItem),
            ("removeGroupTitle", ReferenceGroupWording.removeGroupTitle(group: "{group}")),
            ("removeGroupMessageNone", ReferenceGroupWording.removeGroupMessage(courseCount: 0)),
            ("removeGroupMessageOne", ReferenceGroupWording.removeGroupMessage(courseCount: 1)),
            ("removeGroupMessageMany", ReferenceGroupWording.removeGroupMessageMany(count: 0).replacingOccurrences(of: "0", with: "{count}")),
            ("removeButton", ReferenceGroupWording.removeButton),
            ("cancelButton", ReferenceGroupWording.cancelButton),
            ("removeWouldClash", ReferenceGroupWording.removeWouldClash(group: "{group}", course: "{course}", target: "{target}")),
            ("couldNotRemoveTitle", ReferenceGroupWording.couldNotRemoveTitle(group: "{group}")),
            ("moveToGroupMenuItem", ReferenceGroupWording.moveToGroupMenuItem),
            ("couldNotMoveTitle", ReferenceGroupWording.couldNotMoveTitle(course: "{course}")),
            ("groupPickerLabel", ReferenceGroupWording.groupPickerLabel),
            ("groupPickerDefault", ReferenceGroupWording.groupPickerDefault),
            ("summaryGroupLabel", ReferenceGroupWording.summaryGroupLabel),
            ("nameIsEmpty", ReferenceGroupWording.nameIsEmpty),
            ("nameIsTooLong", ReferenceGroupWording.nameIsTooLong),
            ("nameIsAYear", ReferenceGroupWording.nameIsAYear),
            ("startAgainMenuItem", ReferenceGroupWording.startAgainMenuItem),
            ("startAgainTitle", ReferenceGroupWording.startAgainTitle),
            ("startAgainMessage", ReferenceGroupWording.startAgainMessage),
            ("startAgainButton", ReferenceGroupWording.startAgainButton),
            ("couldNotStartAgainTitle", ReferenceGroupWording.couldNotStartAgainTitle),
            ("nameIsTaken", ReferenceGroupWording.nameIsTaken(name: "{name}")),
            ("couldNotReadGroups", ReferenceGroupWording.couldNotReadGroups),
            ("arrangedByANewerPlantoir", ReferenceGroupWording.arrangedByANewerPlantoir),
            ("couldNotSaveGroups", ReferenceGroupWording.couldNotSaveGroups),
        ]
        var named: Set<String> = []
        for (key, said) in pairs {
            XCTAssertEqual(said, wording[key] as? String, key)
            named.insert(key)
        }
        for (key, _) in wording where key != "rule" && key != "machineryCheck" {
            XCTAssertTrue(named.contains(key), "\(key) is in the contract and nothing in the app says it.")
        }
        XCTAssertEqual(ReferenceGroupWording.courses(1), "1 course")
        XCTAssertEqual(ReferenceGroupWording.courses(3), "3 courses")
        XCTAssertTrue(ReferenceGroupWording.removeGroupMessage(courseCount: 3).hasPrefix("Its 3 courses go back"))
        for count in [0, 1, 2, 7] {
            XCTAssertFalse(ReferenceGroupWording.removeGroupMessage(courseCount: count).contains("(s)"))
        }
        XCTAssertFalse(
            ReferenceGroupWording.couldNotReadGroups.localizedCaseInsensitiveContains("try again"),
            "Waiting does not help an unreadable arrangement; the sentence names the way out."
        )

        let shelfWording: [String: Any] = try XCTUnwrap(try ReferenceCreationTests.referenceRules(["wording"]))
        XCTAssertEqual(
            ReferenceCourseRule.Trouble.codeAlreadyInThatGroup(code: "{code}", group: "{group}").sentence,
            shelfWording["codeAlreadyInThatGroup"] as? String
        )

        // Rule 1: nothing a teacher reads names the machinery.
        for (key, said) in pairs {
            for word in ["file", "JSON", "placement", " id", "folder name", "script", "container"] {
                XCTAssertFalse(said.localizedCaseInsensitiveContains(word), "\(key) says \"\(word)\": \(said)")
            }
        }
        XCTAssertEqual(ReferenceShelf.mostCharacters, try XCTUnwrap(
            (try ReferenceShelfTests.groupRules()["nameRule"] as? [String: Any])?["mostCharacters"] as? Int
        ))
    }

    // MARK: - Reading the file

    func testEveryReadingCaseHolds() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ReferenceShelfTests.shelfFormat()["readingCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 15, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var data: Data?
            if let text = testCase["text"] as? String {
                data = Data(text.utf8)
            }
            let reading: ReferenceShelf.Reading = ReferenceShelf.reading(data)
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            var kind: String
            switch reading {
            case .absent:
                kind = "absent"
            case .read:
                kind = "read"
            case .unreadable:
                kind = "unreadable"
            case .newer:
                kind = "newer"
            }
            XCTAssertEqual(kind, expect["reading"] as? String, name)
            XCTAssertEqual(reading.refusal == nil, expect["mayChange"] as? Bool, name)
            let arrangement: ReferenceShelf.Arrangement = reading.arrangement
            var names: [String] = []
            for group in arrangement.groups {
                names.append(group.name)
            }
            XCTAssertEqual(names, expect["groups"] as? [String], name)
            XCTAssertEqual(arrangement.noYearTitle, expect["noYearTitle"] as? String, name)
            var shown: [String: String] = [:]
            for (folderName, id) in arrangement.placements {
                if let group = arrangement.group(withID: id) {
                    shown[folderName] = group.name
                }
            }
            XCTAssertEqual(shown, expect["placements"] as? [String: String], name)
        }
    }

    // MARK: - Writing the file

    func testEveryWritingCaseHolds() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ReferenceShelfTests.shelfFormat()["writingCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 10, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            try prepareCoursesFolder()
            for folder in try XCTUnwrap(testCase["folders"] as? [String]) {
                try FileManager.default.createDirectory(
                    at: coursesDirectoryURL.appendingPathComponent(folder), withIntermediateDirectories: true
                )
            }
            var before: Data?
            if let text = testCase["text"] as? String {
                try FileManager.default.createDirectory(
                    at: shelfFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                before = Data(text.utf8)
                try before?.write(to: shelfFileURL)
            }

            let act: [String: Any] = try XCTUnwrap(testCase["act"] as? [String: Any])
            var said: String?
            if let groupName = act["makeGroup"] as? String {
                let made: Result<String, ReferenceShelfRefusal> = ReferenceShelfStore.makeGroup(
                    named: groupName, coursesDirectoryURL: coursesDirectoryURL
                )
                if case .failure(let refusal) = made {
                    said = refusal.sentence
                }
            }
            if let folderName = act["recordArrival"] as? String {
                said = ReferenceShelfStore.recordArrival(
                    of: folderName, inMadeGroup: nil, coursesDirectoryURL: coursesDirectoryURL
                )?.sentence
            }

            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let after: Data? = try? Data(contentsOf: shelfFileURL)
            XCTAssertEqual(after != before, try XCTUnwrap(expect["written"] as? Bool), name)
            if let key = expect["sentence"] as? String {
                XCTAssertEqual(said, ReferenceShelfTests.sentence(forKey: key), name)
            } else {
                XCTAssertNil(said, name)
            }
            guard let after, let object = try? JSONSerialization.jsonObject(with: after) as? [String: Any] else {
                continue
            }
            if let kept = expect["keptKeys"] as? [String: Any] {
                for (key, value) in kept {
                    XCTAssertEqual(object[key] as? String, value as? String, "\(name): \(key)")
                }
            }
            let groups: [Any] = (object["groups"] as? [Any]) ?? []
            if let count = expect["groupEntries"] as? Int {
                XCTAssertEqual(groups.count, count, name)
            }
            if let names = expect["groups"] as? [String] {
                var written: [String] = []
                for entry in groups {
                    if let group = entry as? [String: Any], let groupName = group["name"] as? String {
                        written.append(groupName)
                    }
                }
                XCTAssertEqual(written, names, name)
            }
            if let folders = expect["placementFolders"] as? [String] {
                let placements: [String: Any] = (object["placements"] as? [String: Any]) ?? [:]
                var written: [String] = []
                for (folderName, _) in placements {
                    written.append(folderName)
                }
                XCTAssertEqual(written.sorted(), folders, name)
            }
            if after != before {
                XCTAssertEqual(object["version"] as? Int, 1, name)
            }
        }
    }

    // MARK: - The name rule

    func testEveryNameRuleCaseHolds() throws {
        let rule: [String: Any] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["nameRule"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 22, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var arrangement: ReferenceShelf.Arrangement = ReferenceShelf.Arrangement(
                noYearGroupName: testCase["noYearGroupName"] as? String
            )
            var index: Int = 0
            for groupName in (testCase["groups"] as? [String]) ?? [] {
                index += 1
                arrangement.groups.append(ReferenceShelf.MadeGroup(id: "g-\(index)", name: groupName))
            }
            var renaming: ReferenceShelf.Place?
            if let renamed = testCase["renaming"] as? String {
                if renamed == "noYear" {
                    renaming = .noYear
                } else {
                    renaming = .made(try XCTUnwrap(ReferenceShelfTests.madeGroupID(named: renamed, in: arrangement)))
                }
            }
            let typed: String = try XCTUnwrap(testCase["typed"] as? String)
            let problem: ReferenceShelf.NameProblem? = ReferenceShelf.nameProblem(
                typed, renaming: renaming, arrangement: arrangement
            )
            var expected: ReferenceShelf.NameProblem?
            switch testCase["expect"] as? String {
            case "empty":
                expected = .empty
            case "tooLong":
                expected = .tooLong
            case "isAYear":
                expected = .isAYear
            default:
                break
            }
            if let taken = testCase["expect"] as? [String: Any] {
                expected = .taken(try XCTUnwrap(taken["taken"] as? String))
            }
            XCTAssertEqual(problem, expected, name)
            if let normalised = testCase["expectName"] as? String {
                // Compared scalar by scalar: a joiner lost or spaced is a
                // different name even where it looks the same.
                XCTAssertEqual(
                    Array(ReferenceShelf.normalizedName(typed).unicodeScalars), Array(normalised.unicodeScalars), name
                )
            }
            if let characters = testCase["expectCharacters"] as? Int {
                XCTAssertEqual(ReferenceShelf.normalizedName(typed).count, characters, name)
            }
        }
    }

    // MARK: - Order and placement

    func testEveryOrderCaseHolds() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["orderCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let groups: [ReferenceShelf.Group] = ReferenceShelf.groups(
                of: try ReferenceShelfTests.entries(testCase["courses"]),
                arrangement: try ReferenceShelfTests.arrangement(testCase["file"]),
                drawsEmptyMadeGroups: (testCase["drawsEmptyMadeGroups"] as? Bool) ?? true
            )
            var titles: [String] = []
            for group in groups {
                titles.append(group.title)
            }
            XCTAssertEqual(titles, testCase["expect"] as? [String], name)
        }
    }

    func testEveryPlacementCaseHolds() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["placementCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 8, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let placed: [String: String] = ReferenceShelfTests.whereEach(
                try ReferenceShelfTests.entries(testCase["courses"]),
                in: try ReferenceShelfTests.arrangement(testCase["file"])
            )
            XCTAssertEqual(placed, testCase["expect"] as? [String: String], name)
        }
    }

    /// The migration is that there is none: with no file, the shelf is the
    /// shelf before groups, title for title and course for course. The
    /// oracle is a copy of the function this piece replaced
    /// (`WorkspaceModel.referenceYearGroups` on `origin/dev` e419ec68c),
    /// kept here so a change to the new one cannot quietly move the old
    /// shelf.
    func testWithNoFileTheShelfIsTheShelfBeforeGroups() throws {
        let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-20"))
        let shelves: [[ReferenceShelf.Entry]] = [
            [],
            [ReferenceShelf.Entry(folderName: "ICS3U-2025", displayCode: "ICS3U", schoolYear: 2025)],
            [
                ReferenceShelf.Entry(folderName: "ICS3U-2024", displayCode: "ICS3U", schoolYear: 2024),
                ReferenceShelf.Entry(folderName: "ADA1O-REF", displayCode: "ADA1O", schoolYear: nil),
                ReferenceShelf.Entry(folderName: "ICS3U-2025", displayCode: "ICS3U", schoolYear: 2025),
                ReferenceShelf.Entry(folderName: "ICS4U-2025", displayCode: "ICS4U", schoolYear: 2025),
                ReferenceShelf.Entry(folderName: "SCH3U-REF", displayCode: "SCH3U", schoolYear: nil),
                ReferenceShelf.Entry(folderName: "ICS3U-2022", displayCode: "ICS3U", schoolYear: 2022),
            ],
            [ReferenceShelf.Entry(folderName: "ADA1O-REF", displayCode: "ADA1O", schoolYear: nil)],
        ]
        _ = day
        for shelf in shelves {
            let oracle: [(title: String, folders: [String])] = ReferenceShelfTests.theShelfBeforeGroups(shelf)
            let now: [ReferenceShelf.Group] = ReferenceShelf.groups(of: shelf, arrangement: ReferenceShelf.Arrangement())
            XCTAssertEqual(now.count, oracle.count, "\(shelf)")
            for index in 0..<min(now.count, oracle.count) {
                XCTAssertEqual(now[index].title, oracle[index].title)
                XCTAssertEqual(now[index].folderNames, oracle[index].folders)
            }
            // The same answer from an empty file, and from one that cannot
            // be read.
            let unreadable: [ReferenceShelf.Group] = ReferenceShelf.groups(
                of: shelf, arrangement: ReferenceShelf.reading(Data("{".utf8)).arrangement
            )
            XCTAssertEqual(unreadable, now)
            let empty: [ReferenceShelf.Group] = ReferenceShelf.groups(
                of: shelf, arrangement: ReferenceShelf.reading(Data("{\"version\": 1}".utf8)).arrangement
            )
            XCTAssertEqual(empty, now)
        }
    }

    /// `WorkspaceModel.referenceYearGroups` as it was before #572's third
    /// piece, reduced to titles and folders.
    static func theShelfBeforeGroups(_ shelf: [ReferenceShelf.Entry]) -> [(title: String, folders: [String])] {
        var byYear: [Int: [String]] = [:]
        var withNoYear: [String] = []
        for course in shelf {
            guard let year = course.schoolYear else {
                withNoYear.append(course.folderName)
                continue
            }
            var inThatYear: [String] = byYear[year] ?? []
            inThatYear.append(course.folderName)
            byYear[year] = inThatYear
        }
        var years: [Int] = []
        for (year, _) in byYear {
            years.append(year)
        }
        years.sort()
        years.reverse()
        var groups: [(title: String, folders: [String])] = []
        for year in years {
            groups.append((title: SchoolYear.label(forStartingYear: year), folders: byYear[year] ?? []))
        }
        if !withNoYear.isEmpty {
            groups.append((title: ReferenceWording.otherYearTitle, folders: withNoYear))
        }
        return groups
    }

    // MARK: - Moving a course, and removing a group

    func testEveryMoveCaseHolds() throws {
        let block: [String: Any] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["moveCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 6, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            try prepareCoursesFolder()
            let entries: [ReferenceShelf.Entry] = try ReferenceShelfTests.entries(testCase["courses"])
            for entry in entries {
                try writeReferenceCourse(folder: entry.folderName, code: entry.displayCode, year: entry.schoolYear)
            }
            try writeShelfFile(testCase["file"])
            let fileBefore: Data? = try? Data(contentsOf: shelfFileURL)
            let coursesBefore: [String: Data] = everyCourseFile()

            let move: [String: Any] = try XCTUnwrap(testCase["move"] as? [String: Any])
            let folder: String = try XCTUnwrap(move["folder"] as? String)
            var moving: ReferenceShelf.Entry?
            for entry in entries where entry.folderName == folder {
                moving = entry
            }
            let arrangementBefore: ReferenceShelf.Arrangement = ReferenceShelfStore.read(
                inCoursesDirectory: coursesDirectoryURL
            ).arrangement
            let target: ReferenceShelf.Place = try ReferenceShelfTests.place(
                try XCTUnwrap(move["to"] as? [String: Any]), in: arrangementBefore
            )
            let refusal: ReferenceShelfRefusal? = ReferenceShelfStore.move(
                try XCTUnwrap(moving), to: target, coursesDirectoryURL: coursesDirectoryURL, entries: entries
            )

            XCTAssertEqual(everyCourseFile(), coursesBefore, "\(name): a course folder changed.")
            let fileAfter: Data? = try? Data(contentsOf: shelfFileURL)
            let expect: String = try XCTUnwrap(testCase["expect"] as? String)
            switch expect {
            case "moved":
                XCTAssertNil(refusal, name)
                XCTAssertNotEqual(fileAfter, fileBefore, name)
            case "unchanged":
                XCTAssertNil(refusal, name)
                XCTAssertEqual(fileAfter, fileBefore, name)
            default:
                XCTAssertNotNil(refusal, name)
                XCTAssertEqual(fileAfter, fileBefore, "\(name): a refusal wrote the file.")
                let arrangement: ReferenceShelf.Arrangement = arrangementBefore
                switch testCase["sentence"] as? String {
                case "codeAlreadyInThatGroup":
                    XCTAssertEqual(refusal?.sentence, ReferenceCourseRule.Trouble.codeAlreadyInThatGroup(
                        code: moving?.displayCode ?? "", group: ReferenceShelf.title(of: target, in: arrangement)
                    ).sentence, name)
                case "codeAlreadyInThatYear":
                    var year: Int?
                    if case .year(let value) = target {
                        year = value
                    }
                    XCTAssertEqual(refusal?.sentence, ReferenceCourseRule.Trouble.codeAlreadyInThatYear(
                        code: moving?.displayCode ?? "", schoolYear: year
                    ).sentence, name)
                default:
                    XCTAssertEqual(
                        refusal?.sentence, ReferenceShelfTests.sentence(forKey: try XCTUnwrap(testCase["sentence"] as? String)),
                        name
                    )
                }
            }
            if let expectGroups = testCase["expectGroups"] as? [String: String] {
                let now: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
                XCTAssertEqual(ReferenceShelfTests.whereEach(entries, in: now), expectGroups, name)
            }
            if let placements = testCase["expectPlacements"] as? [String: Any] {
                let now: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
                XCTAssertEqual(now.placements.count, placements.count, name)
            }
            if let event = testCase["trail"] as? String {
                let line: String = event == "reference course moved to a group"
                    ? "moved \(moving?.displayCode ?? "") (\(folder)) from "
                    : "did not move \(moving?.displayCode ?? "") (\(folder)) to "
                XCTAssertTrue(trail.contains(line), "\(name): \(trail)")
            } else {
                XCTAssertFalse(trail.contains("moved "), "\(name): a move that changed nothing left a line: \(trail)")
            }
        }
    }

    func testEveryRemoveCaseHolds() throws {
        let block: [String: Any] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["removeCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            try prepareCoursesFolder()
            let entries: [ReferenceShelf.Entry] = try ReferenceShelfTests.entries(testCase["courses"])
            for entry in entries {
                try writeReferenceCourse(folder: entry.folderName, code: entry.displayCode, year: entry.schoolYear)
            }
            try writeShelfFile(testCase["file"])
            let fileBefore: Data? = try? Data(contentsOf: shelfFileURL)
            let coursesBefore: [String: Data] = everyCourseFile()
            let before: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
            let removing: String = try XCTUnwrap(testCase["remove"] as? String)
            let id: String = try XCTUnwrap(ReferenceShelfTests.madeGroupID(named: removing, in: before))

            let refusal: ReferenceShelfRefusal? = ReferenceShelfStore.removeGroup(
                withID: id, coursesDirectoryURL: coursesDirectoryURL, entries: entries
            )

            XCTAssertEqual(everyCourseFile(), coursesBefore, "\(name): a course folder changed - Remove Group removed a course.")
            for entry in entries {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: coursesDirectoryURL.appendingPathComponent(entry.folderName).appendingPathComponent("course_config.json").path
                    ),
                    "\(name): \(entry.folderName) is gone."
                )
            }
            let after: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
            var names: [String] = []
            for group in after.groups {
                names.append(group.name)
            }
            XCTAssertEqual(names, testCase["expectGroupNames"] as? [String], name)
            XCTAssertEqual(ReferenceShelfTests.whereEach(entries, in: after), testCase["expectGroups"] as? [String: String], name)
            if testCase["expect"] as? String == "refused" {
                XCTAssertEqual(try? Data(contentsOf: shelfFileURL), fileBefore, name)
                XCTAssertTrue(refusal?.sentence.hasPrefix(
                    ReferenceGroupWording.removeWouldClash(group: "From colleagues", course: "ICS3U", target: "2025–26")
                ) ?? false, "\(name): \(String(describing: refusal))")
                XCTAssertTrue(trail.contains("did not remove the group \"From colleagues\""), trail)
            } else {
                XCTAssertNil(refusal, name)
                XCTAssertTrue(trail.contains("removed the group \"\(removing)\""), trail)
                XCTAssertTrue(trail.contains("no course was removed"), trail)
            }
        }
    }

    // MARK: - Making and renaming

    func testMakingAndRenamingAGroupLeaveTheirLinesAndMoveNothing() throws {
        try prepareCoursesFolder()
        try writeReferenceCourse(folder: "ICS3U-2025", code: "ICS3U", year: 2025)
        let entries: [ReferenceShelf.Entry] = [
            ReferenceShelf.Entry(folderName: "ICS3U-2025", displayCode: "ICS3U", schoolYear: 2025),
        ]
        let coursesBefore: [String: Data] = everyCourseFile()
        let made: Result<String, ReferenceShelfRefusal> = ReferenceShelfStore.makeGroup(
            named: "  From\ncolleagues ", coursesDirectoryURL: coursesDirectoryURL
        )
        guard case .success(let id) = made else {
            return XCTFail("\(made)")
        }
        XCTAssertTrue(id.hasPrefix("g-"))
        XCTAssertEqual(id.count, 10)
        XCTAssertTrue(trail.contains("made the group \"From colleagues\" on the Reference Courses shelf"), trail)

        XCTAssertNil(ReferenceShelfStore.move(
            entries[0], to: .made(id), coursesDirectoryURL: coursesDirectoryURL, entries: entries
        ))
        XCTAssertNil(ReferenceShelfStore.renameGroup(
            .made(id), to: "Exemplars", coursesDirectoryURL: coursesDirectoryURL
        ))
        XCTAssertTrue(trail.contains("renamed the group \"From colleagues\" to \"Exemplars\""), trail)
        XCTAssertNil(ReferenceShelfStore.renameGroup(
            .noYear, to: "Example courses", coursesDirectoryURL: coursesDirectoryURL
        ))
        XCTAssertTrue(trail.contains(
            "renamed the group \"Other\" to \"Example courses\" (the group for courses with no school year)"
        ), trail)
        let taken: ReferenceShelfRefusal? = ReferenceShelfStore.renameGroup(
            .noYear, to: "exemplars", coursesDirectoryURL: coursesDirectoryURL
        )
        XCTAssertEqual(taken?.sentence, ReferenceGroupWording.nameIsTaken(name: "Exemplars"))
        XCTAssertTrue(trail.contains("did not rename a group to \"exemplars\""), trail)

        let arrangement: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
        XCTAssertEqual(arrangement.placements["ICS3U-2025"], id, "The rename moved the course out of its group.")
        XCTAssertEqual(arrangement.noYearTitle, "Example courses")
        XCTAssertEqual(everyCourseFile(), coursesBefore, "A course folder changed.")

        // Renaming the no-year group back to Other removes the key.
        XCTAssertNil(ReferenceShelfStore.renameGroup(
            .noYear, to: "Other", coursesDirectoryURL: coursesDirectoryURL
        ))
        let object: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: shelfFileURL)) as? [String: Any]
        )
        XCTAssertNil(object["noYearGroupName"])
    }

    /// Twenty changes at once, from twenty threads, all land: each is read
    /// and written under the one lock, so none undoes another.
    func testChangesMadeAtOnceAllLand() async throws {
        try prepareCoursesFolder()
        let courses: URL = coursesDirectoryURL
        await withTaskGroup(of: Void.self) { group in
            for index in 1...20 {
                group.addTask {
                    _ = ReferenceShelfStore.makeGroup(named: "Group \(index)", coursesDirectoryURL: courses)
                }
            }
        }
        let arrangement: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: courses).arrangement
        XCTAssertEqual(arrangement.groups.count, 20, "A change made at the same moment as another was lost.")
    }

    // MARK: - Every arrival writes where it goes

    /// Plan review H2: a freed folder name never inherits a group. Through
    /// the real removal and the real restore from Archived.
    func testARecycledFolderNameDoesNotInheritAPlacement() async throws {
        let cases: [[String: Any]] = try XCTUnwrap(
            (try ReferenceShelfTests.groupRules()["arrivals"] as? [String: Any])?["recycledFolderNameCases"] as? [[String: Any]]
        )
        XCTAssertEqual(cases.count, 1, "a case was added or lost; the README census counts them")
        let block: [String: Any] = cases[0]
        try prepareCoursesFolder()
        try writeReferenceCourse(folder: "ICS3U-2025", code: "ICS3U", year: 2025)
        try writeShelfFile(block["file"])
        let folderURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        let course: Course = Course(
            code: "ICS3U-2025", directoryURL: folderURL,
            configuration: try CourseConfiguration(contentsOf: folderURL.appendingPathComponent("course_config.json"))
        )
        let archiveURL: URL = try await CourseArchiver.archiveAndRemoveCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        let afterRemoval: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
        XCTAssertNil(afterRemoval.placements["ICS3U-2025"], "Remove Course… left the course's group behind for its folder name.")

        // A stale placement the removal could not clear (made by an older
        // app, or by hand) is cleared by the arrival.
        var stale: ReferenceShelf.Arrangement = afterRemoval
        stale.placements["ICS3U-2025"] = try XCTUnwrap(afterRemoval.groups.first?.id)
        try ReferenceShelf.encoded(stale).write(to: shelfFileURL)
        let item: ArchivedItem = ArchivedItem(
            courseCode: "ICS3U-2025", sectionNumber: nil, archivedAt: Date(), fileURL: archiveURL
        )
        try CourseRestorer.restore(item, coursesDirectoryURL: coursesDirectoryURL, courses: [])
        let entries: [ReferenceShelf.Entry] = [
            ReferenceShelf.Entry(folderName: "ICS3U-2025", displayCode: "ICS3U", schoolYear: 2025),
        ]
        let now: ReferenceShelf.Arrangement = ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement
        XCTAssertEqual(ReferenceShelfTests.whereEach(entries, in: now), block["expectGroups"] as? [String: String])
        XCTAssertTrue(now.placements.isEmpty)
        XCTAssertEqual(now.groups.count, 1, "The group itself goes nowhere when a course leaves it.")
    }

    /// Every door the contract names writes its placement where the
    /// contract says, and a replace writes none (it keeps the old course's
    /// folder, and so its group). A scan, because each door is its own
    /// long act; the arrivals that matter most are run for real above and
    /// in `ReferenceReplacerTests` and `ReferenceCreationTests`.
    func testEveryArrivalDoorWritesItsPlacement() throws {
        let block: [String: Any] = try XCTUnwrap(try ReferenceShelfTests.groupRules()["arrivals"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 11, "a case was added or lost; the README census counts them")
        let models: URL = ReferenceShelfTests.repositoryURL().appendingPathComponent("mac-app/QuartzTeachers/Models")
        for testCase in cases {
            let door: String = try XCTUnwrap(testCase["door"] as? String)
            let place: String = try XCTUnwrap(testCase["where"] as? String)
            let typeName: String = String(place.split(separator: ".")[0])
            let source: String = try String(
                contentsOf: models.appendingPathComponent("\(typeName).swift"), encoding: .utf8
            )
            switch try XCTUnwrap(testCase["writes"] as? String) {
            case "placement":
                XCTAssertTrue(source.contains("inMadeGroup: prepared.madeGroupID"), door)
            case "noPlacement":
                XCTAssertTrue(source.contains("ReferenceShelfStore.recordArrival("), door)
            case "forgotten":
                XCTAssertTrue(source.contains("ReferenceShelfStore.forgetRemoved("), door)
            default:
                break
            }
        }
        let replacer: String = try String(
            contentsOf: models.appendingPathComponent("ReferenceReplacer.swift"), encoding: .utf8
        )
        XCTAssertFalse(
            replacer.contains("recordArrival(") || replacer.contains("forgetRemoved("),
            "A replace keeps the replaced course's folder, and so its group: it must write no placement."
        )
    }

    // MARK: - Starting the groups again

    func testEveryStartingAgainCaseHolds() throws {
        let block: [String: Any] = try XCTUnwrap(try ReferenceShelfTests.shelfFormat()["startingAgain"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 6, "a case was added or lost; the README census counts them")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            try prepareCoursesFolder()
            let internalURL: URL = shelfFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: internalURL, withIntermediateDirectories: true)
            var before: Data?
            if let text = testCase["text"] as? String {
                before = Data(text.utf8)
                try before?.write(to: shelfFileURL)
            }
            if testCase["folderInsteadOfFile"] as? Bool == true {
                try FileManager.default.createDirectory(at: shelfFileURL, withIntermediateDirectories: true)
            }
            var earlier: [String: Data] = [:]
            for keptName in (testCase["alreadyKept"] as? [String]) ?? [] {
                let data: Data = Data("an earlier copy \(keptName)".utf8)
                try data.write(to: internalURL.appendingPathComponent(keptName))
                earlier[keptName] = data
            }
            let moment: Date = try XCTUnwrap(ArchiveStamp.moment(from: try XCTUnwrap(testCase["atMoment"] as? String)))

            let outcome: Result<String?, ReferenceShelfRefusal> = ReferenceShelfStore.startAgain(
                coursesDirectoryURL: coursesDirectoryURL, at: moment
            )

            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            var keptAs: String?
            var said: String?
            switch outcome {
            case .success(let kept):
                keptAs = kept
            case .failure(let refusal):
                said = refusal.sentence
            }
            XCTAssertEqual(keptAs, expect["keptAs"] as? String, name)
            if let key = expect["sentence"] as? String {
                XCTAssertEqual(said, ReferenceShelfTests.sentence(forKey: key), name)
            } else {
                XCTAssertNil(said, name)
            }
            var readingAfter: String
            switch ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL) {
            case .absent:
                readingAfter = "absent"
            case .read:
                readingAfter = "read"
            case .unreadable:
                readingAfter = "unreadable"
            case .newer:
                readingAfter = "newer"
            }
            XCTAssertEqual(readingAfter, expect["readingAfter"] as? String, name)
            if let keptAs {
                let keptURL: URL = internalURL.appendingPathComponent(keptAs)
                XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path), "\(name): nothing kept aside.")
                if let before {
                    XCTAssertEqual(try? Data(contentsOf: keptURL), before, "\(name): what was kept is not what was there.")
                }
                XCTAssertTrue(trail.contains("started the groups on the Reference Courses shelf again"), trail)
                XCTAssertTrue(trail.contains(keptAs), trail)
                // Every control works again: a group can be made.
                guard case .success = ReferenceShelfStore.makeGroup(named: "Afresh", coursesDirectoryURL: coursesDirectoryURL) else {
                    return XCTFail("\(name): the groups did not start again.")
                }
            } else if let before {
                XCTAssertEqual(try? Data(contentsOf: shelfFileURL), before, "\(name): the file was moved or changed.")
            }
            for (keptName, data) in earlier {
                XCTAssertEqual(try? Data(contentsOf: internalURL.appendingPathComponent(keptName)), data, "\(name): an earlier copy was written over.")
            }
        }
    }

    /// Cancel is the default button of both of the groups' questions, as the
    /// contract says and as the replace warning does: the button carries the
    /// default key itself, rather than leaving SwiftUI to choose.
    func testCancelIsTheDefaultButtonOfBothQuestions() throws {
        let url: URL = ReferenceShelfTests.repositoryURL()
            .appendingPathComponent("mac-app/QuartzTeachers/Views/Wizard/ReferenceGroupPresenter.swift")
        let lines: [String] = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        var cancels: Int = 0
        for index in 0..<lines.count where lines[index].contains("Button(ReferenceGroupWording.cancelButton, role: .cancel)") {
            cancels += 1
            var found: Bool = false
            for next in (index + 1)..<min(index + 5, lines.count) where lines[next].contains(".keyboardShortcut(.defaultAction)") {
                found = true
            }
            XCTAssertTrue(found, "line \(index + 1): a Cancel without the default key")
        }
        XCTAssertEqual(cancels, 2, "the removal question and the start-again question")
        let rule: String = try XCTUnwrap(
            (try ReferenceShelfTests.groupRules()["wording"] as? [String: Any])?["rule"] as? String
        )
        XCTAssertTrue(rule.contains("Cancel is the default button of the removal question and of the start-again question"))
    }

    // MARK: - The three arrival doors, for real (implementation review L5)

    /// Writes a placement for `folderName` in a group "Stale" into the file,
    /// as an older app or a removal made by hand would have left it.
    func writeAStalePlacement(for folderName: String) throws {
        try writeShelfFile([
            "version": 1,
            "groups": [["id": "g-5a1e0001", "name": "Stale"]],
            "placements": [folderName: "g-5a1e0001"],
        ])
    }

    func placementNow(_ folderName: String) -> String? {
        return ReferenceShelfStore.read(inCoursesDirectory: coursesDirectoryURL).arrangement.placements[folderName]
    }

    func testAnImportLandsByItsYearOverAStalePlacement() async throws {
        try prepareCoursesFolder()
        let oldCoursesURL: URL = rootURL.appendingPathComponent("Old Folder").appendingPathComponent("courses")
        let oldCourseURL: URL = oldCoursesURL.appendingPathComponent("ICS4U")
        try FileManager.default.createDirectory(at: oldCourseURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try Data("{\"course_code\": \"ICS4U\", \"section_numbers\": [1]}\n".utf8)
            .write(to: oldCourseURL.appendingPathComponent("course_config.json"))
        try Data("---\ntitle: Front\n---\nOld.\n".utf8)
            .write(to: oldCourseURL.appendingPathComponent("section1").appendingPathComponent("index.md"))
        try writeAStalePlacement(for: "ICS4U-2025")
        guard case .found(let source) = ReferenceImportSource.resolve(
            chosen: oldCoursesURL.deletingLastPathComponent(),
            workingFolderURL: coursesDirectoryURL.deletingLastPathComponent(),
            leavingBehind: ReferenceImporter.leftBehindNames
        ) else {
            return XCTFail("The old folder was refused.")
        }
        let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: try XCTUnwrap(source.courses.first), schoolYear: 2025)],
            into: coursesDirectoryURL, existingFolderNames: [], alreadyShelved: [],
            from: source.rootURL, progress: { _ in }
        )
        guard case .imported(let made) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("\(outcomes)")
        }
        XCTAssertEqual(made.folderName, "ICS4U-2025")
        XCTAssertNil(placementNow("ICS4U-2025"), "The import landed in a stranger's group.")
    }

    func testKeepACopyLandsByItsYearOverAStalePlacement() throws {
        try prepareCoursesFolder()
        let liveURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(at: liveURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try Data("{\"course_code\": \"ICS3U\", \"section_numbers\": [1]}\n".utf8)
            .write(to: liveURL.appendingPathComponent("course_config.json"))
        try Data("---\ntitle: Front\n---\nLive.\n".utf8)
            .write(to: liveURL.appendingPathComponent("section1").appendingPathComponent("index.md"))
        try writeAStalePlacement(for: "ICS3U-2025")
        let live: Course = Course(
            code: "ICS3U", directoryURL: liveURL,
            configuration: try CourseConfiguration(contentsOf: liveURL.appendingPathComponent("course_config.json"))
        )
        let made: ReferenceCopier.Made = try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025, coursesDirectoryURL: coursesDirectoryURL
        )
        XCTAssertEqual(made.folderName, "ICS3U-2025")
        XCTAssertNil(placementNow("ICS3U-2025"), "The copy landed in a stranger's group.")
        ReferenceLock.clearLock(at: coursesDirectoryURL.appendingPathComponent("ICS3U-2025"))
    }

    func testABackupRestoredWhereItsCourseIsGoneLandsByItsYear() async throws {
        try prepareCoursesFolder()
        try writeReferenceCourse(folder: "ICS3U-2025", code: "ICS3U", year: 2025)
        let folderURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        let course: Course = Course(
            code: "ICS3U-2025", directoryURL: folderURL,
            configuration: try CourseConfiguration(contentsOf: folderURL.appendingPathComponent("course_config.json"))
        )
        let backupURL: URL = try await CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        ReferenceLock.clearLock(at: folderURL)
        try FileManager.default.removeItem(at: folderURL)
        try writeAStalePlacement(for: "ICS3U-2025")
        try CourseRestorer.restoreBackup(
            BackupItem(courseCode: "ICS3U-2025", backedUpAt: Date(), fileURL: backupURL, maker: .teacher),
            coursesDirectoryURL: coursesDirectoryURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("course_config.json").path))
        XCTAssertNil(placementNow("ICS3U-2025"), "The restored course landed in a stranger's group.")
        ReferenceLock.clearLock(at: folderURL)
    }

    // MARK: - The window

    /// The sidebar's groups: made groups between the years and the no-year
    /// group, an empty made group drawn, and gone while the filter narrows.
    func testTheSidebarDrawsTheArrangement() throws {
        try prepareCoursesFolder()
        let workingFolderURL: URL = coursesDirectoryURL.deletingLastPathComponent()
        try Data("#!/bin/bash\n".utf8).write(to: workingFolderURL.appendingPathComponent("preview.sh"))
        try writeReferenceCourse(folder: "ICS3U-2025", code: "ICS3U", year: 2025)
        try writeReferenceCourse(folder: "ICS4U-2024", code: "ICS4U", year: 2024)
        try writeShelfFile([
            "version": 1,
            "groups": [["id": "g-00000001", "name": "From colleagues"], ["id": "g-00000002", "name": "Empty"]],
            "placements": ["ICS4U-2024": "g-00000001"],
        ])
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: workingFolderURL)
        workspace.reloadCourses()
        let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-20"))
        var titles: [String] = []
        for group in workspace.referenceShelfGroups(on: day) {
            titles.append(group.title)
        }
        XCTAssertEqual(titles, ["2025–26", "Empty", "From colleagues"])
        var placed: Course?
        for course in workspace.courses where course.code == "ICS4U-2024" {
            placed = course
        }
        XCTAssertEqual(workspace.madeGroupName(of: try XCTUnwrap(placed), on: day), "From colleagues")
        var targets: [String] = []
        for target in workspace.referenceMoveTargets(for: try XCTUnwrap(placed), on: day) {
            targets.append(target.title + (target.isCurrent ? " ✓" : ""))
        }
        XCTAssertEqual(targets, ["2024–25", "Empty", "From colleagues ✓"])

        workspace.filterText = "ICS4U"
        titles = []
        for group in workspace.referenceShelfGroups(on: day) {
            titles.append(group.title)
        }
        XCTAssertEqual(titles, ["From colleagues"])

        // The shelf rule sees the course in its made group, not in 2024–25.
        let shelved: [ReferenceCourseRule.Shelved] = workspace.shelvedReferenceCourses(on: day)
        XCTAssertNil(ReferenceCourseRule.trouble(placing: "ICS4U", inYear: 2024, among: shelved))
    }

    /// A window remembered before groups restores exactly as it did; a made
    /// group's fold state comes back by its id.
    func testFoldStateOfMadeGroupsIsRememberedBesideTheYears() throws {
        XCTAssertEqual(WindowFolderMemory.groupIDs(nil), [])
        XCTAssertEqual(WindowFolderMemory.groupIDs(""), [])
        XCTAssertEqual(WindowFolderMemory.groupIDs("g-00000001,g-00000002"), ["g-00000001", "g-00000002"])
        XCTAssertEqual(WindowFolderMemory.years("2025,0"), [2025, 0])
    }
}
