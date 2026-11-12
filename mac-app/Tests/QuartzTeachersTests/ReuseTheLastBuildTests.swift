import XCTest
@testable import QuartzTeachers

/// A deploy reuses the last build only when nothing has changed (#768, with
/// #741): every case of `contracts/app-rules.json` →
/// `buildFreshness.reuseTheLastBuild`, run against the app's two readers —
/// `BuildFreshness.whyRebuild` and the scheduled deploy's own shell
/// (`ScheduledDeploy.oneShotCommand`). `scripts/test_build_freshness_reuse.py`
/// runs the same cases against `toolchain_paths` and `deploy.sh`, so the four
/// readers cannot drift apart.
///
/// Each course is made on the REAL clock, step by step with a pause between,
/// exactly as `casesShape` says and as `scripts/freshness_cases.py` makes it:
/// a folder's time and a file's change time cannot be set, only the order
/// things happen in gives them.
@MainActor
final class ReuseTheLastBuildTests: XCTestCase {

    // MARK: - Stored properties

    private var scratchURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reuse-the-last-build-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        // The wrapper removes its own job's plist: never one in the real
        // LaunchAgents folder, as ScheduledPublishOutcomeTests keeps it out.
        let home: URL = scratchURL.appendingPathComponent("home", isDirectory: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = home.appendingPathComponent("Library/LaunchAgents")
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            home.appendingPathComponent("Library/Application Support/Plantoir/scheduled")
        try FileManager.default.createDirectory(
            at: ScheduledDeploy.launchAgentsDirectoryOverride!, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        try? FileManager.default.removeItem(at: scratchURL)
    }

    // MARK: - Functions

    /// `buildFreshness.reuseTheLastBuild` from the contract.
    static func rule() throws -> [String: Any] {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts", isDirectory: true)
        let appRules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try Data(contentsOf: contracts.appendingPathComponent("app-rules.json"))
            ) as? [String: Any]
        )
        let freshness: [String: Any] = try XCTUnwrap(appRules["buildFreshness"] as? [String: Any])
        return try XCTUnwrap(freshness["reuseTheLastBuild"] as? [String: Any])
    }

    /// What the apps' readers expect of a case: `inTheApps` where the case
    /// gives it, since they do not read the toolchain stamp. Nil for reuse.
    static func expectedInTheApps(_ testCase: [String: Any]) throws -> String? {
        var expectation: [String: Any] = testCase
        if let override = testCase["inTheApps"] as? [String: Any] {
            expectation = override
        }
        let expect: String = try XCTUnwrap(expectation["expect"] as? String)
        if expect == "reuse" {
            return nil
        }
        return try XCTUnwrap(expectation["because"] as? String)
    }

    private func pause() {
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Gives `target` exactly `source`'s modification time, to the
    /// nanosecond, which a `Date` could round.
    private func giveExactlyTheModificationTime(of source: URL, to target: URL) throws {
        var status: stat = stat()
        XCTAssertEqual(stat(source.path, &status), 0)
        var times: [timespec] = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), status.st_mtimespec]
        XCTAssertEqual(utimensat(AT_FDCWD, target.path, &times, 0), 0)
    }

    private func apply(_ change: [String: Any], in courseURL: URL) throws {
        let what: String = try XCTUnwrap(change["do"] as? String)
        let url: URL = courseURL.appendingPathComponent(try XCTUnwrap(change["path"] as? String))
        let fileManager: FileManager = FileManager.default
        switch what {
        case "edit":
            let handle: FileHandle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(Data("\nedited\n".utf8))
            try handle.close()
        case "delete":
            try fileManager.removeItem(at: url)
        case "rename":
            let target: URL = courseURL.appendingPathComponent(try XCTUnwrap(change["to"] as? String))
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: target)
        case "replaceKeepingItsOldTime":
            let old: Date = try modificationDate(of: url)
            let beside: URL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".incoming")
            try write("a new copy\n", to: beside)
            try setModificationDate(old, of: beside)
            XCTAssertEqual(rename(beside.path, url.path), 0)
        case "overwriteKeepingItsOldTime":
            let old: Date = try modificationDate(of: url)
            try write("written over where it stands\n", to: url)
            try setModificationDate(old, of: url)
        case "createKeepingAnOldTime":
            try write("restored from a backup\n", to: url)
            try setModificationDate(Date(timeIntervalSinceNow: -365 * 24 * 3600), of: url)
        default:
            XCTFail("no such change in the contract: \(what)")
        }
    }

    private func changes(of testCase: [String: Any], when moment: String) -> [[String: Any]] {
        var found: [[String: Any]] = []
        for change in testCase["changes"] as? [[String: Any]] ?? [] where change["when"] as? String == moment {
            found.append(change)
        }
        return found
    }

    /// Makes the case. Returns the working folder and the course.
    private func build(_ testCase: [String: Any], theCourse: [String]) throws -> (workingFolder: URL, course: Course) {
        let caseURL: URL = scratchURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var workingFolder: URL = caseURL.appendingPathComponent("work", isDirectory: true)
        if testCase["workingFolderUnderAHiddenFolder"] as? Bool == true {
            workingFolder = caseURL.appendingPathComponent(".kept-out-of-sight/work", isDirectory: true)
        }
        let courseURL: URL = workingFolder.appendingPathComponent("courses/C", isDirectory: true)
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let buildsURL: URL = caseURL.appendingPathComponent("builds/C", isDirectory: true)
        try fileManager.createDirectory(at: buildsURL, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: courseURL.appendingPathComponent(".merged_output"), withDestinationURL: buildsURL
        )
        let sectionURL: URL = buildsURL.appendingPathComponent("section1", isDirectory: true)

        let files: [String] = testCase["course"] as? [String] ?? theCourse
        for relative in files {
            try write(relative + "\n", to: courseURL.appendingPathComponent(relative))
        }
        pause()
        for change in changes(of: testCase, when: "beforeTheBuildStarted") {
            try apply(change, in: courseURL)
        }
        pause()

        let configuration: CourseConfiguration = CourseConfiguration(values: ["course_code": "C"], lastSavedData: Data())
        let course: Course = Course(code: "C", directoryURL: courseURL, configuration: configuration)
        if testCase["site"] as? String == "notBuilt" {
            return (workingFolder, course)
        }

        let frontPage: URL = sectionURL.appendingPathComponent("public/index.html")
        let marker: URL = sectionURL.appendingPathComponent(BuildFreshness.buildStartedMarkerName)
        let order: String = testCase["startedMarker"] as? String ?? "beforeTheSite"
        let page: String = "<html><body>Welcome</body></html>\n"
        let started: String = "This build started when this file was made.\n"
        if order == "beforeTheSite" {
            let atTheStart: [[String: Any]] = changes(of: testCase, when: "atTheBuildStart")
            for change in atTheStart {
                try apply(change, in: courseURL)
            }
            try write(started, to: marker)
            for change in atTheStart {
                let edited: URL = courseURL.appendingPathComponent(try XCTUnwrap(change["path"] as? String))
                try giveExactlyTheModificationTime(of: edited, to: marker)
            }
            pause()
            for change in changes(of: testCase, when: "whileItBuilt") {
                try apply(change, in: courseURL)
            }
            pause()
            try write(page, to: frontPage)
        } else if order == "afterTheSite" {
            try write(page, to: frontPage)
            pause()
            for change in changes(of: testCase, when: "whileItBuilt") {
                try apply(change, in: courseURL)
            }
            pause()
            try write(started, to: marker)
        } else {
            for change in changes(of: testCase, when: "whileItBuilt") {
                try apply(change, in: courseURL)
            }
            pause()
            try write(page, to: frontPage)
        }

        if testCase["datedLaterThanNow"] as? Bool == true {
            for dated in [marker, frontPage] where fileManager.fileExists(atPath: dated.path) {
                try setModificationDate(try modificationDate(of: dated).addingTimeInterval(3600), of: dated)
            }
        }
        pause()
        for change in changes(of: testCase, when: "afterTheBuild") {
            try apply(change, in: courseURL)
        }
        return (workingFolder, course)
    }

    // MARK: - The app's own question

    func testEveryCaseThroughTheAppsQuestion() throws {
        let rule: [String: Any] = try ReuseTheLastBuildTests.rule()
        let theCourse: [String] = try XCTUnwrap(rule["theCourse"] as? [String])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 20)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let built: (workingFolder: URL, course: Course) = try build(testCase, theCourse: theCourse)
            let reason: BuildFreshness.RebuildReason? = BuildFreshness.whyRebuild(course: built.course, sectionNumber: 1)
            XCTAssertEqual(reason?.rawValue, try ReuseTheLastBuildTests.expectedInTheApps(testCase), name)
        }
    }

    /// Every reason the contract names that the app can give is a reason the
    /// app has, and the other way round.
    func testTheAppsReasonsAreTheContracts() throws {
        let rule: [String: Any] = try ReuseTheLastBuildTests.rule()
        let reasons: [String: Any] = try XCTUnwrap(rule["reasons"] as? [String: Any])
        for reason in BuildFreshness.RebuildReason.allCases {
            XCTAssertNotNil(reasons[reason.rawValue], reason.rawValue)
        }
    }

    // MARK: - The scheduled deploy's own shell

    /// The real wrapper, with stand-in launchers: whether it built, and the
    /// reason its marker gave.
    private func scheduledRun(in workingFolder: URL) throws -> (built: Bool, marker: String) {
        let home: URL = scratchURL.appendingPathComponent("home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let buildNote: URL = workingFolder.appendingPathComponent("the-build-ran")
        let scripts: [(String, String)] = [
            ("preview.sh", "#!/bin/bash\n/usr/bin/touch '\(buildNote.path)'\nexit 0\n"),
            ("deploy.sh", "#!/bin/bash\nexit 0\n"),
        ]
        for (name, script) in scripts {
            let url: URL = workingFolder.appendingPathComponent(name)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let script: String = ScheduledDeploy.oneShotCommand(
            courseCode: "C",
            sectionNumber: 1,
            workspaceURL: workingFolder,
            deployArgumentsList: [["C", "1", "--to", "the class folder"]],
            destinationTypes: ["folder"],
            destinationDescriptions: ["the class folder"],
            homeFolder: home
        )
        let scriptURL: URL = home.appendingPathComponent("wrapper.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let output: Pipe = Pipe()
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text: String = String(decoding: data, as: UTF8.self)
        var marker: String = ""
        for report in BuiltBeforeDeployingReport.reports(in: text) {
            marker = report.reason
            XCTAssertEqual(report.place, "C/1")
        }
        return (FileManager.default.fileExists(atPath: buildNote.path), marker)
    }

    func testEveryCaseThroughTheScheduledDeploysShell() throws {
        let rule: [String: Any] = try ReuseTheLastBuildTests.rule()
        let theCourse: [String] = try XCTUnwrap(rule["theCourse"] as? [String])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let built: (workingFolder: URL, course: Course) = try build(testCase, theCourse: theCourse)
            let run: (built: Bool, marker: String) = try scheduledRun(in: built.workingFolder)
            let expected: String? = try ReuseTheLastBuildTests.expectedInTheApps(testCase)
            XCTAssertEqual(run.built, expected != nil, name)
            XCTAssertEqual(run.marker, expected ?? "", name)
        }
    }
}
