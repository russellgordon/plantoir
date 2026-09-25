import XCTest
@testable import QuartzTeachers

/// The tripwire for issue #264: nothing but `RealHome` asks the system
/// where the home folder is, and no test reaches the real one on purpose
/// without being named here.
///
/// **Why a scan, and not a probe that watches the file system.** The
/// probes were measured and rejected (doc 09 → "Testing: the real-home
/// tripwire"): DTrace needs System Integrity Protection off, `fs_usage`
/// needs root, and an `open` interposer loaded the way a test bundle is
/// loaded — `dlopen` — intercepted 0 of 12 file operations. So this reads
/// the SOURCE, the way `ActivityTrailWiringTests` does, and fails naming
/// the file and line.
///
/// **What a line is.** Comment lines (`//`, `///`) are skipped, and so is
/// anything after ` //` on a line of code. Block comments (`/* … */`) are
/// not understood; nothing in this project uses them, and one that named a
/// home lookup would be reported rather than missed — the safe way round.
///
/// The allow-lists are counted per FILE and per LOOKUP, so a second call
/// of the same kind in an allowed file is as red as a first call in a new
/// one, and an entry nothing matches any more is red as stale.
final class RealHomeTripwireTests: XCTestCase {

    // MARK: - Stored properties

    /// Every way this project could ask for a home folder, written as the
    /// text a line would contain. Add to it when a new one turns up; the
    /// modern `URL` statics are here because they are the idiom a new
    /// contributor reaches for first.
    static let homeLookups: [String] = [
        "homeDirectoryForCurrentUser",
        "NSHomeDirectory",
        "homeDirectory(forUser",
        "URL.homeDirectory",
        "urls(for:",
        "url(for:",
        "NSSearchPathForDirectoriesInDomains",
        ".applicationSupportDirectory",
        ".desktopDirectory",
        ".libraryDirectory",
        ".documentsDirectory",
        ".downloadsDirectory",
        ".cachesDirectory",
        "expandingTildeInPath",
        "abbreviatingWithTildeInPath",
        "standardizingPath",
        "getpwuid",
        "getpwnam",
        "CFCopyHomeDirectoryURL",
        "environment[\"HOME\"]",
        "getenv(\"HOME\")",
        "\"~/",
        "\"/Users/",
    ]

    /// The file that IS the seam. Nothing else in the product may ask.
    static let seamFileName: String = "Models/RealHome.swift"

    /// Home lookups the PRODUCT is allowed outside the seam, by file (path
    /// under `QuartzTeachers/`) and lookup, with how many. Each one asks for
    /// no home at all; the scan cannot tell that from the text, so it is
    /// said here, once, with the reason.
    static let productAllowances: [String: Int] = [
        // The redactor's pattern and replacement: text that REMOVES a home
        // path from a report. It looks one up nowhere.
        "Scripting/LogRedactor.swift | \"/Users/": 2,
        // A symlink's target and the pages folder, standardised so `..`
        // collapses before two paths are compared. Reads no folder; a link
        // text starting with `~` would compare unequal either way.
        "Models/QuartzCheckoutLayout.swift | standardizingPath": 2,
        // A sentence for a programmer who called the real launchd from a
        // test, naming the folder it would have used.
        "Models/ScheduledDeploy.swift | \"~/": 1,
    ]

    /// Home lookups TESTS are allowed, by file (path under `Tests/`) and
    /// lookup. Every other test goes through `RealHome.forFiles`, or names a
    /// made-up home such as `/Users/teacher` — which is what the suite
    /// should do.
    static let testAllowances: [String: Int] = [
        // Colima mounts only `$HOME`, so the mirror under test has to live
        // under the real one to be visible to the container.
        "QuartzTeachersTests/ToolchainMirrorTests.swift | homeDirectoryForCurrentUser": 1,
        // The guards themselves: each must know where the real folder is in
        // order to say that nothing the suite resolves is it. They compare
        // paths and open nothing.
        "QuartzTeachersTests/SuiteStaysOutOfRealFoldersTests.swift | homeDirectoryForCurrentUser": 1,
        "QuartzTeachersTests/BuildOutputLocationTests.swift | homeDirectoryForCurrentUser": 1,
        "QuartzTeachersTests/AssistScenarioTests.swift | homeDirectoryForCurrentUser": 1,
        "QuartzTeachersTests/ActivityTrailWiringTests.swift | expandingTildeInPath": 1,
        "QuartzTeachersTests/ActivityTrailWiringTests.swift | \"~/": 1,
        "QuartzTeachersTests/ScheduledDeployCleanupTests.swift | expandingTildeInPath": 1,
        "QuartzTeachersTests/ScheduledDeployCleanupTests.swift | \"~/": 1,
        // The contract's builds location, checked against the real rule for
        // the real home — a path built and compared, never created.
        "QuartzTeachersTests/SharedRulesContractTests.swift | homeDirectoryForCurrentUser": 1,
        // A privacy check: the trail must not carry the real home path.
        "QuartzTeachersTests/QuartzCheckoutImportTests.swift | NSHomeDirectory": 1,
        // The path bar drawn for a real Desktop path, read and never written.
        "QuartzTeachersTests/InAppUserInterfaceTests.swift | NSHomeDirectory": 1,
        // The key named HOME in a made-up environment a command was built
        // with, read back to check it survived — not this process's HOME.
        "QuartzTeachersTests/PreviewStopperTests.swift | environment[\"HOME\"]": 1,
        "QuartzTeachersTests/FolderContainerTests.swift | environment[\"HOME\"]": 1,
        // `~/…` as a teacher would type it, expanded by `RealHome` into the
        // suite's throwaway home — the check that it is not the real one.
        "QuartzTeachersTests/SuiteStaysOutOfRealFoldersTests.swift | \"~/": 3,
        // The opt-in UI test, in the RUNNER, looking for the weights the
        // app it drives will load. It is sandboxed, hence the password
        // database rather than `HOME`.
        "QuartzTeachersUITests/AssistantRolloverUITests.swift | getpwuid": 1,
    ]

    /// Which files may call `RealHome.real(for:)` with each `Use`, by the
    /// case's name and the file's path under `QuartzTeachers/`.
    /// Empty because `RealHome.Use` is: nothing needs the real home under
    /// the suite today (doc 09 says how that was measured).
    static let filesAllowedPerUse: [String: [String]] = [:]

    // MARK: - The product asks only the seam

    func testOnlyTheSeamAsksForTheHomeFolder() throws {
        let productFolder: URL = ActivityTrailWiringTests.productSourceFolderURL()
        var found: [String: Int] = [:]
        var unexpected: [String] = []
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: productFolder) {
            let relativePath: String = RealHomeTripwireTests.path(of: fileURL, under: productFolder)
            if relativePath == RealHomeTripwireTests.seamFileName {
                continue
            }
            let hits: [Hit] = try RealHomeTripwireTests.homeLookupHits(in: fileURL)
            for hit in hits {
                let key: String = relativePath + " | " + hit.lookup
                found[key, default: 0] += 1
                if RealHomeTripwireTests.productAllowances[key] == nil {
                    unexpected.append("\(relativePath):\(hit.lineNumber) asks for the home folder with `\(hit.lookup)`")
                }
            }
        }
        XCTAssertEqual(
            unexpected, [],
            "Only RealHome may ask where the home folder is. Use RealHome.forFiles (throwaway under the suite, real in the app), or — only if a TEST needs the real value — add a RealHome.Use case and list this file for it in RealHomeTripwireTests.filesAllowedPerUse."
        )
        RealHomeTripwireTests.assertCounts(found, match: RealHomeTripwireTests.productAllowances, side: "productAllowances")
    }

    // MARK: - The tests reach the real home only where named

    func testTestsReachTheRealHomeOnlyWhereNamed() throws {
        let testsFolder: URL = RealHomeTripwireTests.testsFolderURL()
        let ownName: String = "QuartzTeachersTests/RealHomeTripwireTests.swift"
        var found: [String: Int] = [:]
        var unexpected: [String] = []
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: testsFolder) {
            let relativePath: String = RealHomeTripwireTests.path(of: fileURL, under: testsFolder)
            // This file spells every lookup as the text it looks for, so it
            // is the one test file the scan cannot read.
            if relativePath == ownName {
                continue
            }
            // Made-up homes (`/Users/teacher`) are how tests SHOULD name a
            // home, so the literal is looked for only as the running
            // account's own home.
            var hits: [Hit] = []
            for hit in try RealHomeTripwireTests.homeLookupHits(in: fileURL) where hit.lookup != "\"/Users/" {
                hits.append(hit)
            }
            for hit in try RealHomeTripwireTests.hits(of: ["RealHome.real(", RealHomeTripwireTests.runningAccountHomeLiteral()], in: fileURL) {
                hits.append(hit)
            }
            for hit in hits {
                let key: String = relativePath + " | " + hit.lookup
                found[key, default: 0] += 1
                if RealHomeTripwireTests.testAllowances[key] == nil {
                    unexpected.append("\(relativePath):\(hit.lineNumber) reaches the real home with `\(hit.lookup)`")
                }
            }
        }
        XCTAssertEqual(
            unexpected, [],
            "A test reached the teacher's real home folder. Use RealHome.forFiles or a made-up home (`/Users/teacher`); RealHome.real(for:) is never for tests. If this test genuinely needs the real home, list it in RealHomeTripwireTests.testAllowances with the reason."
        )
        RealHomeTripwireTests.assertCounts(found, match: RealHomeTripwireTests.testAllowances, side: "testAllowances")
    }

    // MARK: - Each real reach is named, used, and used only where allowed

    func testEveryRealReachIsNamedAndUsedOnlyWhereAllowed() throws {
        var caseNames: [String] = []
        for use in RealHome.Use.allCases {
            caseNames.append(String(describing: use))
        }
        XCTAssertEqual(
            Set(caseNames), Set(RealHomeTripwireTests.filesAllowedPerUse.keys),
            "Every RealHome.Use case needs a line in filesAllowedPerUse, and every line there needs a case."
        )

        let productFolder: URL = ActivityTrailWiringTests.productSourceFolderURL()
        var usesSeen: Set<String> = []
        var misplaced: [String] = []
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: productFolder) {
            let relativePath: String = RealHomeTripwireTests.path(of: fileURL, under: productFolder)
            if relativePath == RealHomeTripwireTests.seamFileName {
                continue
            }
            for hit in try RealHomeTripwireTests.hits(of: ["RealHome.real("], in: fileURL) {
                var matchedCase: String?
                for caseName in caseNames where hit.line.contains("RealHome.real(for: ." + caseName + ")") {
                    matchedCase = caseName
                }
                guard let caseName = matchedCase else {
                    misplaced.append("\(relativePath):\(hit.lineNumber) calls RealHome.real without naming a case on the same line")
                    continue
                }
                usesSeen.insert(caseName)
                let allowedFiles: [String] = RealHomeTripwireTests.filesAllowedPerUse[caseName] ?? []
                if !allowedFiles.contains(relativePath) {
                    misplaced.append("\(relativePath):\(hit.lineNumber) uses .\(caseName), which is allowed only from \(allowedFiles)")
                }
            }
        }
        XCTAssertEqual(misplaced, [], "A real-home reach was reused somewhere it was not named for.")

        var unused: [String] = []
        for caseName in caseNames where !usesSeen.contains(caseName) {
            unused.append(caseName)
        }
        XCTAssertEqual(unused, [], "These RealHome.Use cases are named but nothing uses them — remove them, and their lines in filesAllowedPerUse.")
    }

    // MARK: - Reading source

    /// One line that names something the scan looks for.
    struct Hit {
        let lineNumber: Int
        let lookup: String
        let line: String
    }

    static func homeLookupHits(in fileURL: URL) throws -> [Hit] {
        return try hits(of: homeLookups, in: fileURL)
    }

    /// Every (line, needle) pair in the CODE of a file — comments skipped.
    static func hits(of needles: [String], in fileURL: URL) throws -> [Hit] {
        let contents: String = try String(contentsOf: fileURL, encoding: .utf8)
        var result: [Hit] = []
        var lineNumber: Int = 0
        for rawLine in contents.components(separatedBy: "\n") {
            lineNumber += 1
            let code: String = codePart(of: rawLine)
            if code.isEmpty {
                continue
            }
            for needle in needles where code.contains(needle) {
                if needle == "URL.homeDirectory" || needle.hasPrefix(".") {
                    // `.homeDirectory` / `.desktopDirectory` must not match a
                    // longer name that merely starts the same way.
                    if !containsAsWholeName(needle, in: code) {
                        continue
                    }
                }
                result.append(Hit(lineNumber: lineNumber, lookup: needle, line: code))
            }
        }
        return result
    }

    /// A line with its comment taken off, or "" for a comment line.
    static func codePart(of line: String) -> String {
        let trimmed: String = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") {
            return ""
        }
        if let commentStart = trimmed.range(of: " //") {
            return String(trimmed[trimmed.startIndex..<commentStart.lowerBound])
        }
        return trimmed
    }

    /// True when `name` appears and is not followed by a letter, digit or
    /// `:` — so `.desktopDirectory` matches and `.desktopDirectoryName` or a
    /// `homeDirectory:` label does not.
    static func containsAsWholeName(_ name: String, in code: String) -> Bool {
        var searchStart: String.Index = code.startIndex
        while let found = code.range(of: name, range: searchStart..<code.endIndex) {
            if found.upperBound == code.endIndex {
                return true
            }
            let next: Character = code[found.upperBound]
            if !(next.isLetter || next.isNumber || next == ":" || next == "_") {
                return true
            }
            searchStart = found.upperBound
        }
        return false
    }

    /// `"/Users/<this account>` — the running account's own home written
    /// out, which a test should never need. Built from the account name so
    /// that this file does not itself spell a real home.
    static func runningAccountHomeLiteral() -> String {
        return "\"/Users/" + NSUserName() + "/"
    }

    static func testsFolderURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
    }

    static func path(of fileURL: URL, under folderURL: URL) -> String {
        let folderPath: String = folderURL.standardizedFileURL.path + "/"
        let filePath: String = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(folderPath) {
            return String(filePath.dropFirst(folderPath.count))
        }
        return filePath
    }

    /// Every allowance is used exactly as many times as it says: more is a
    /// new reach, fewer is a stale entry that would let one back in.
    static func assertCounts(_ found: [String: Int], match allowances: [String: Int], side: String) {
        for (key, allowed) in allowances {
            let actual: Int = found[key] ?? 0
            XCTAssertEqual(
                actual, allowed,
                "\(side)[\(key)] allows \(allowed) and the source has \(actual). "
                + (actual < allowed ? "Lower or remove the stale entry." : "A new reach was added beside the allowed one.")
            )
        }
    }
}
