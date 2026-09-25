import XCTest
@testable import QuartzTeachers

/// One working folder, however it is spelled (GitHub #189).
///
/// The app names a folder's workspace and builds folder by
/// `BuildOutputLocation.folderIdentifier`, and the launchers by the lines at
/// the top of each of them (`cd "$(/bin/pwd -P)"`, then `/bin/pwd -P | shasum`).
/// Until #189 the launchers used bash's own `pwd -P`, which keeps the TYPED
/// case and Unicode form, so a folder reached in the wrong case, or with an
/// accented name stored the Terminal way, had two workspaces and two builds
/// folders that cleared each other. These run the REAL launcher lines — read
/// out of `preview.sh`, never retyped — against every spelling a scratch
/// folder can be given.
///
/// Folder names with accents are made with `mkdir` on explicit bytes: Foundation's
/// `appendingPathComponent` and `URL(fileURLWithPath:)` hand back the other
/// Unicode form, which is exactly what must not decide the answer here.
final class FolderIdentityTests: XCTestCase {

    // MARK: - Stored properties

    private var scratch: String = ""

    // MARK: - Set-up

    override func setUpWithError() throws {
        // NSTemporaryDirectory is /var/folders/…, itself a link to
        // /private/var/…, so the /private spelling comes free.
        scratch = NSTemporaryDirectory() + "folder-identity-\(UUID().uuidString)"
        XCTAssertEqual(mkdir(scratch, 0o755), 0)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: scratch)
    }

    // MARK: - Functions

    /// The disk's own spelling of `path`, as the launchers ask for it.
    private func binPwd(_ path: String) throws -> [UInt8]? {
        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/bash")
        shell.arguments = ["-c", "cd \"$1\" 2>/dev/null && /bin/pwd -P", "bash", path]
        let output: Pipe = Pipe()
        shell.standardOutput = output
        try shell.run()
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        if shell.terminationStatus != 0 {
            return nil
        }
        var bytes: [UInt8] = [UInt8](data)
        if bytes.last == 10 {
            bytes.removeLast()
        }
        return bytes
    }

    /// Makes a folder whose name is stored as exactly these bytes.
    private func makeFolder(named name: String) -> String {
        let path: String = scratch + "/" + name
        XCTAssertEqual(mkdir(path, 0o755), 0, "could not make \(name)")
        return path
    }

    /// Whether the disk ignores case — asked of the disk itself, by
    /// `pathconf`, rather than assumed.
    private func isCaseBlind(_ path: String) -> Bool {
        return pathconf(path, _PC_CASE_SENSITIVE) == 0
    }

    /// Every spelling of one folder this test can make, by what it is.
    private func spellings() -> [(String, String)] {
        let plain: String = makeFolder(named: "Plantoir Courses")
        let composed: String = makeFolder(named: "\u{00C9}coles")
        let decomposed: String = makeFolder(named: "Franc\u{0327}ais")
        let link: String = scratch + "/a link"
        XCTAssertEqual(symlink(plain, link), 0)
        var list: [(String, String)] = [
            ("as the disk spells it", plain),
            ("through a link", link),
            ("an accented name stored as one character, reached as two", scratch + "/E\u{0301}coles"),
            ("an accented name stored as two characters, reached as one", scratch + "/Fran\u{00E7}ais"),
            ("stored as one character", composed),
            ("stored as two characters", decomposed),
        ]
        if isCaseBlind(scratch) {
            list.append(("in the wrong case", scratch + "/plantoir COURSES"))
            list.append(("an accented name in the wrong case", scratch + "/FRAN\u{00C7}AIS"))
        }
        let physical: String = FolderIdentity.canonicalPath(scratch)
        if physical.hasPrefix("/private/") {
            list.append(("without /private", String(physical.dropFirst("/private".count)) + "/Plantoir Courses"))
            list.append(("by the firmlink", "/System/Volumes/Data" + physical + "/Plantoir Courses"))
        }
        return list
    }

    /// The launcher's own lines, cut out of the file between its first `cd`
    /// and its folder id.
    static func launcherLines(_ launcher: String) throws -> String {
        let text: String = try String(contentsOf: FolderIdentityTests.repositoryRoot().appendingPathComponent(launcher), encoding: .utf8)
        let start: Range<String.Index> = try XCTUnwrap(text.range(of: "# ---- One spelling of this folder (GitHub #189)"))
        let end: Range<String.Index> = try XCTUnwrap(text.range(of: "cd \"$(/bin/pwd -P)\"\n", range: start.upperBound..<text.endIndex))
        var idLine: String = ""
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("WORKDIR_ID=") {
                idLine = line
            }
        }
        XCTAssertFalse(idLine.isEmpty, "\(launcher) has no WORKDIR_ID line")
        return String(text[start.lowerBound..<end.upperBound]) + idLine + "\n"
    }

    static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - The app and the launchers agree

    /// THE issue test: the id the launchers derive, run from a launcher reached
    /// by each spelling, is the app's id for that spelling — and one id.
    @MainActor
    func testTheAppAndTheLaunchersNameTheSameFolderHoweverItIsSpelled() throws {
        let lines: String = try FolderIdentityTests.launcherLines("preview.sh")
        for launcher in ["setup.sh", "deploy.sh"] {
            XCTAssertEqual(try FolderIdentityTests.launcherLines(launcher), lines, "\(launcher)'s lines have drifted from preview.sh's")
        }
        let probe: String = "#!/bin/bash\ncd \"$(dirname \"$0\")\"\n" + lines + "printf '%s\\n' \"$WORKDIR_ID\"\n"
        let all: [(String, String)] = spellings()
        for folderName in ["Plantoir Courses", "\u{00C9}coles", "Franc\u{0327}ais"] {
            let probePath: String = scratch + "/" + folderName + "/probe.sh"
            XCTAssertTrue(FileManager.default.createFile(atPath: probePath, contents: Data(probe.utf8)))
        }
        var identifiers: [String: String] = [:]
        for (what, spelling) in all {
            let shell: Process = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/bash")
            shell.arguments = [spelling + "/probe.sh"]
            let output: Pipe = Pipe()
            shell.standardOutput = output
            try shell.run()
            let data: Data = output.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            XCTAssertEqual(shell.terminationStatus, 0, what)
            let fromLauncher: String = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let fromApp: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: spelling)
            XCTAssertEqual(fromApp, fromLauncher, "\(what): the app and the launchers name different folders")
            XCTAssertEqual(FolderContainers.containerName(forFolder: spelling), "teaching-quartz-" + fromLauncher, what)
            identifiers[what] = fromApp
        }
        let plainId: String? = identifiers["as the disk spells it"]
        for what in ["through a link", "in the wrong case", "without /private", "by the firmlink"] {
            if let id = identifiers[what] {
                XCTAssertEqual(id, plainId, "\(what) is a second folder id")
            }
        }
        XCTAssertEqual(identifiers["an accented name stored as one character, reached as two"], identifiers["stored as one character"])
        XCTAssertEqual(identifiers["an accented name stored as two characters, reached as one"], identifiers["stored as two characters"])
        if let wrongCase = identifiers["an accented name in the wrong case"] {
            XCTAssertEqual(wrongCase, identifiers["stored as two characters"])
        }
        XCTAssertGreaterThanOrEqual(identifiers.count, 6, "too few spellings could be made to prove anything")
    }

    /// `canonicalPath` is byte for byte what `/bin/pwd -P` prints — compared as
    /// bytes, because `String ==` would call the two Unicode forms equal and
    /// hide exactly the difference that split the hash.
    func testCanonicalPathIsWhatBinPwdPrints() throws {
        var compared: Int = 0
        for (what, spelling) in spellings() {
            guard let fromShell = try binPwd(spelling) else {
                XCTFail("\(what): bash could not reach \(spelling)")
                continue
            }
            XCTAssertEqual(Array(FolderIdentity.canonicalPath(spelling).utf8), fromShell, what)
            compared += 1
        }
        XCTAssertGreaterThanOrEqual(compared, 6)
    }

    /// The spellings measured for #189 that live outside the temporary folder
    /// — the firmlink spelling of the home folder, iCloud Drive, Dropbox and
    /// another disk, each in the right and the wrong case. Opt-in, because
    /// asking about them can put a macOS permission question on screen in the
    /// middle of a run, and a question nobody answers hangs the suite.
    /// PLANTOIR_TEST_EVERY_PLACE=1 (TEST_RUNNER_PLANTOIR_TEST_EVERY_PLACE=1
    /// through xcodebuild) runs it; a place that is not there is skipped by name.
    func testCanonicalPathIsWhatBinPwdPrintsInEveryPlace() throws {
        if ProcessInfo.processInfo.environment["PLANTOIR_TEST_EVERY_PLACE"] != "1" {
            throw XCTSkip("Asks about folders outside the temporary folder; set PLANTOIR_TEST_EVERY_PLACE=1 to run it.")
        }
        let home: String = RealHome.forFiles.path
        var places: [String] = [
            "/System/Volumes/Data" + home,
            "/System/Volumes/Data" + home.uppercased(),
            home + "/Library/Mobile Documents/com~apple~CloudDocs",
            home + "/library/mobile documents/COM~APPLE~CLOUDDOCS",
            home + "/Library/CloudStorage/Dropbox",
            home + "/library/cloudstorage/dropbox",
        ]
        let volumes: [String] = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        for volume in volumes.sorted() {
            let path: String = "/Volumes/" + volume
            let isLink: Bool = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
            if isLink || volume.hasPrefix("com.apple") {
                continue
            }
            places.append(path)
            places.append("/volumes/" + volume.lowercased())
        }
        var compared: Int = 0
        var skipped: [String] = []
        for place in places {
            guard let fromShell = try binPwd(place) else {
                skipped.append(place)
                continue
            }
            XCTAssertEqual(Array(FolderIdentity.canonicalPath(place).utf8), fromShell, place)
            compared += 1
        }
        print("FolderIdentityTests: compared \(compared) places; not there, so skipped: \(skipped)")
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - Comparing two spellings

    func testTwoSpellingsAreTheSameFolder() {
        for (what, spelling) in spellings() {
            XCTAssertTrue(FolderIdentity.isSameFolder(spelling, spelling), what)
        }
        let plain: String = scratch + "/Plantoir Courses"
        XCTAssertTrue(FolderIdentity.isSameFolder(plain, scratch + "/a link"))
        if isCaseBlind(scratch) {
            XCTAssertTrue(FolderIdentity.isSameFolder(plain, scratch + "/PLANTOIR courses"))
        }
    }

    func testTwoFoldersAreNot() {
        let first: String = makeFolder(named: "This Year")
        let second: String = makeFolder(named: "Last Year")
        XCTAssertFalse(FolderIdentity.isSameFolder(first, second))
    }

    /// A folder that is gone (or on a disk that is not plugged in) cannot be
    /// asked, so it compares by its text — what every comparison did before.
    func testAFolderThatIsGoneComparesByItsText() {
        let gone: String = scratch + "/not here"
        XCTAssertEqual(FolderIdentity.canonicalPath(gone), gone)
        XCTAssertTrue(FolderIdentity.isSameFolder(gone, gone))
        XCTAssertFalse(FolderIdentity.isSameFolder(gone, scratch + "/NOT HERE"))
    }

    // MARK: - The places that compare two folders

    /// Re-choosing the open folder in another spelling must not stop the
    /// workspace the open window is using — `folderIsInUse` is what gates it.
    @MainActor
    func testReChoosingTheOpenFolderSpelledDifferentlyDoesNotReleaseIt() throws {
        let folder: String = makeFolder(named: "Plantoir Courses")
        let link: String = scratch + "/a link"
        XCTAssertEqual(symlink(folder, link), 0)
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        model.chooseWorkspace(at: URL(fileURLWithPath: folder))
        WorkspaceModel.registerWindowModel(model)
        defer {
            WorkspaceModel.unregisterWindowModel(model)
        }
        XCTAssertTrue(WorkspaceModel.folderIsInUse(link))
        if isCaseBlind(scratch) {
            XCTAssertTrue(WorkspaceModel.folderIsInUse(scratch + "/PLANTOIR COURSES"))
        }
        XCTAssertFalse(WorkspaceModel.folderIsInUse(makeFolder(named: "Another")))
        XCTAssertTrue(AssistToolRunner.openWindowModel(forFolderPath: link) === model)
    }

    /// One folder's workspace publishes the ports, so a second spelling of the
    /// folder must be refused the section it already has, and must not be
    /// handed a port already in use.
    @MainActor
    func testPreviewLeasesTreatTwoSpellingsAsOneFolder() throws {
        let folder: String = makeFolder(named: "Plantoir Courses")
        let link: String = scratch + "/a link"
        XCTAssertEqual(symlink(folder, link), 0)
        PreviewLeases.reset()
        defer {
            PreviewLeases.reset()
        }
        let first: PreviewLeases.Lease = try PreviewLeases.lease(folderPath: folder, courseCode: "SNC1W", sectionNumber: 1)
        XCTAssertThrowsError(try PreviewLeases.lease(folderPath: link, courseCode: "SNC1W", sectionNumber: 1))
        let second: PreviewLeases.Lease = try PreviewLeases.lease(folderPath: link, courseCode: "SNC1W", sectionNumber: 2)
        XCTAssertNotEqual(first.port, second.port)
        XCTAssertTrue(CourseActivity.courseIsBusy(folderPath: link, courseCode: "SNC1W"))
    }

    /// Keys built from a folder path are built from ONE spelling, because a
    /// dictionary never asks `isSameFolder`.
    @MainActor
    func testKeysAreBuiltFromOneSpelling() throws {
        let folder: String = makeFolder(named: "Plantoir Courses")
        let link: String = scratch + "/a link"
        XCTAssertEqual(symlink(folder, link), 0)
        XCTAssertEqual(
            SectionWindowControllers.Key(folderPath: folder, courseCode: "SNC1W", sectionNumber: 1),
            SectionWindowControllers.Key(folderPath: link, courseCode: "snc1w", sectionNumber: 1)
        )
        XCTAssertEqual(
            WorkLeaseRegistry.Wanted(folderPath: folder, courseCode: "SNC1W", kind: "build"),
            WorkLeaseRegistry.Wanted(folderPath: link, courseCode: "SNC1W", kind: "build")
        )
        XCTAssertEqual(
            ReferenceStaging.claimKey(for: "Old Course", inCoursesDirectory: URL(fileURLWithPath: folder)),
            ReferenceStaging.claimKey(for: "Old Course", inCoursesDirectory: URL(fileURLWithPath: link))
        )
    }
}
