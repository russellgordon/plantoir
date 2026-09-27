import XCTest
@testable import QuartzTeachers

/// The tripwire for the preferences door (#154): nothing but
/// `PlantoirDefaults` picks a preferences store.
///
/// **Why it matters.** `--state-dir` moves the home, and preferences do not
/// follow the home (`cfprefsd` resolves it itself, measured). So a product
/// file that reaches for `UserDefaults.standard`, opens a suite of its own,
/// or declares an `@AppStorage` without a store writes the teacher's REAL
/// preferences from the app a UI test drives — exactly what the prompt
/// history and window frames for the fixture course EXC2O found in the real
/// domain on 2026-09-26 were consistent with.
///
/// Read the same way `RealHomeTripwireTests` reads: comments skipped, counts
/// per FILE and per NEEDLE, stale allowances red.
final class PreferencesSeamTripwireTests: XCTestCase {

    // MARK: - Stored properties

    /// Every way a product file could open a preferences store of its own.
    static let storeLookups: [String] = [
        "UserDefaults.standard",
        "NSUserDefaults",
        "CFPreferences",
        "UserDefaults(suiteName:",
        ".defaultAppStorage(",
    ]

    /// The file that IS the seam.
    static let seamFileName: String = "Models/PlantoirDefaults.swift"

    /// Store lookups allowed outside the seam, by file and needle.
    static let allowances: [String: Int] = [
        // The one-time import from the app's earlier bundle identifier. It
        // READS the old domain and writes through the seam, and it is
        // skipped under tests and under a state folder
        // (`WorkspaceModel.mayMigratePreferences`).
        "Models/WorkspaceModel.swift | UserDefaults(suiteName:": 1,
    ]

    // MARK: - The product opens stores only through the seam

    func testOnlyTheSeamPicksAPreferencesStore() throws {
        let productFolder: URL = ActivityTrailWiringTests.productSourceFolderURL()
        let productFiles: [URL] = ActivityTrailWiringTests.swiftFiles(under: productFolder)
        XCTAssertGreaterThan(productFiles.count, 50, "The scan found no product source at \(productFolder.path), so it checked nothing.")
        var found: [String: Int] = [:]
        var unexpected: [String] = []
        for fileURL in productFiles {
            let relativePath: String = RealHomeTripwireTests.path(of: fileURL, under: productFolder)
            if relativePath == PreferencesSeamTripwireTests.seamFileName {
                continue
            }
            let hits: [RealHomeTripwireTests.Hit] = try RealHomeTripwireTests.hits(
                of: PreferencesSeamTripwireTests.storeLookups, in: fileURL
            )
            for hit in hits {
                let key: String = relativePath + " | " + hit.lookup
                found[key, default: 0] += 1
                if PreferencesSeamTripwireTests.allowances[key] == nil {
                    unexpected.append("\(relativePath):\(hit.lineNumber) opens a preferences store with `\(hit.lookup)`")
                }
            }
            let contents: String = try String(contentsOf: fileURL, encoding: .utf8)
            for lineNumber in PreferencesSeamTripwireTests.appStorageWithoutAStore(in: contents) {
                unexpected.append("\(relativePath):\(lineNumber) declares an AppStorage without `store: PlantoirDefaults.shared`")
            }
        }
        XCTAssertEqual(
            unexpected, [],
            "Only PlantoirDefaults may pick a preferences store. Use PlantoirDefaults.shared — the standard store in the app, a file in the state folder under --state-dir."
        )
        RealHomeTripwireTests.assertCounts(found, match: PreferencesSeamTripwireTests.allowances, side: "allowances")
    }

    // MARK: - The AppStorage reader reads what Swift would compile

    func testAnAppStorageIsReadAcrossLines() {
        let withStore: String = """
        _stored = AppStorage(
            wrappedValue: "",
            "key",
            store: PlantoirDefaults.shared
        )
        """
        XCTAssertEqual(PreferencesSeamTripwireTests.appStorageWithoutAStore(in: withStore), [])
        let withoutStore: String = """
        let a = 1
        _stored = AppStorage(
            wrappedValue: "",
            "key(\\(n))"
        )
        """
        XCTAssertEqual(PreferencesSeamTripwireTests.appStorageWithoutAStore(in: withoutStore), [2])
        XCTAssertEqual(
            PreferencesSeamTripwireTests.appStorageWithoutAStore(in: "@AppStorage(\"k\") private var v: String = \"\""),
            [1]
        )
        XCTAssertEqual(
            PreferencesSeamTripwireTests.appStorageWithoutAStore(in: "@AppStorage(\"k\", store: PlantoirDefaults.shared) var v: Int = 0"),
            []
        )
        // A bare attribute names no key; its `AppStorage(` initialiser is
        // where the store is checked.
        XCTAssertEqual(PreferencesSeamTripwireTests.appStorageWithoutAStore(in: "@AppStorage private var v: String"), [])
        XCTAssertEqual(PreferencesSeamTripwireTests.appStorageWithoutAStore(in: "/// `@AppStorage(\"x\")` in a comment"), [])
    }

    // MARK: - Reading source

    /// The line numbers of every `AppStorage(` whose argument list — read
    /// across lines to the matching `)` — has no `store:`. Comments are
    /// skipped; a parenthesis inside a string literal is counted, which can
    /// only make the list longer, and that reads as a failure rather than a
    /// pass — the safe way round.
    static func appStorageWithoutAStore(in contents: String) -> [Int] {
        var codeLines: [String] = []
        for rawLine in contents.components(separatedBy: "\n") {
            codeLines.append(RealHomeTripwireTests.codePart(of: rawLine))
        }
        var result: [Int] = []
        var index: Int = 0
        while index < codeLines.count {
            let line: String = codeLines[index]
            if let start = line.range(of: "AppStorage(") {
                var arguments: String = ""
                var depth: Int = 0
                var lineIndex: Int = index
                var text: Substring = line[start.upperBound...]
                depth = 1
                var finished: Bool = false
                while !finished {
                    for character in text {
                        if character == "(" {
                            depth += 1
                        } else if character == ")" {
                            depth -= 1
                            if depth == 0 {
                                finished = true
                                break
                            }
                        }
                        arguments.append(character)
                    }
                    if finished {
                        break
                    }
                    lineIndex += 1
                    if lineIndex >= codeLines.count {
                        break
                    }
                    arguments.append(" ")
                    text = codeLines[lineIndex][...]
                }
                if !arguments.contains("store:") {
                    result.append(index + 1)
                }
            }
            index += 1
        }
        return result
    }
}
