import XCTest
@testable import QuartzTeachers

/// Pins that the activity trail is WIRED, not merely declared.
///
/// Windows shipped the gap this file exists to close (2026-08-19): three
/// events sat in their `ActivityTrail.Event`, the contract test compared the
/// enum against `shared-rules.json` and passed — and nothing ever CALLED
/// them, so a release smoke's course creation, preview and deploy left zero
/// lines on the trail. A list pin cannot see that; these tests can.
final class ActivityTrailWiringTests: XCTestCase {

    // MARK: - Every declared event has a call site

    /// A declared event with no call site is a promise the app is not
    /// keeping: the contract says the trail records it, and nothing does.
    /// This scans the product source for a reference to each case outside
    /// its declaration — it cannot prove the call is REACHED, but it turns
    /// "declared and never called anywhere" from a months-later discovery
    /// into a red test today.
    func testEveryEventIsReferencedSomewhereInProductCode() throws {
        let productFolderURL: URL = ActivityTrailWiringTests.productSourceFolderURL()
        let swiftFileURLs: [URL] = ActivityTrailWiringTests.swiftFiles(under: productFolderURL)
        XCTAssertGreaterThan(swiftFileURLs.count, 50, "The product source folder was not found where this test expects it — the scan below would pass vacuously.")

        var unreferencedEventNames: [String] = []
        for event in ActivityTrail.Event.allCases {
            let caseName: String = String(describing: event)
            var isReferenced: Bool = false
            for fileURL in swiftFileURLs {
                if ActivityTrailWiringTests.file(fileURL, referencesCase: caseName) {
                    isReferenced = true
                    break
                }
            }
            if !isReferenced {
                unreferencedEventNames.append(caseName)
            }
        }

        XCTAssertEqual(
            unreferencedEventNames, [],
            "These trail events are declared but nothing in the app refers to them, so nothing can ever record them. Wire a call site (ActivityTrail.note(.\(unreferencedEventNames.first ?? "event"), …)) as part of the feature, or remove the event AND its entry in contracts/shared-rules.json → activityTrail.mustRecord."
        )
    }

    // MARK: - The suite never writes the real trail

    /// The whole suite runs against a throwaway trail because
    /// `ProblemReportStore.standard` notices XCTest hosting — including the
    /// host app's own launch lines, which are written before any test-bundle
    /// code loads. That redirect is load-bearing: without it every test run
    /// salts `~/Library/Logs/Plantoir/activity.txt` with fixture courses a
    /// genuine problem report would gather. This pins it so a refactor of
    /// `standard` cannot silently lose it.
    func testTheSuiteWritesToAThrowawayTrail() {
        XCTAssertTrue(ProblemReportStore.isRunningTests, "This suite does not know it is a test run, so every trail line it provokes is landing in the teacher-facing log.")
        let realLogsPath: String = ("~/Library/Logs/Plantoir" as NSString).expandingTildeInPath
        XCTAssertFalse(
            ActivityTrail.store.folderURL.path.hasPrefix(realLogsPath),
            "The trail store points at the real log folder during a test run — the throwaway redirect in ProblemReportStore.standard has been lost."
        )
    }

    // MARK: - Launch fires its events

    /// `noteLaunch` is the call site for three of the contract's events
    /// (`appOpened`, `machine`, `helpers`). This actually runs it against a
    /// scratch store and counts the lines, so those events are verified as
    /// FIRING rather than merely referenced.
    func testLaunchWritesItsThreeLines() throws {
        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trail-wiring-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }

        ActivityTrail.noteLaunch()

        let trailText: String = ActivityTrail.store.activityText(includingPrompts: true)
        var writtenLines: [String] = []
        for line in trailText.components(separatedBy: "\n") {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                writtenLines.append(line)
            }
        }
        XCTAssertEqual(writtenLines.count, 3, "A launch must leave exactly its three lines — the app, the machine, and the helpers.")
    }

    // MARK: - Functions

    /// The product source folder, reached from this file's own location so
    /// the test works wherever the repository is checked out.
    static func productSourceFolderURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers", isDirectory: true)
    }

    /// Every Swift file under a folder.
    static func swiftFiles(under folderURL: URL) -> [URL] {
        var result: [URL] = []
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil)
        while let entry = enumerator?.nextObject() as? URL {
            if entry.pathExtension == "swift" {
                result.append(entry)
            }
        }
        return result
    }

    /// True when a file refers to `.caseName` outside the enum's own
    /// declaration and outside comments — the shape of a call site.
    static func file(_ fileURL: URL, referencesCase caseName: String) -> Bool {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return false
        }
        for line in contents.components(separatedBy: "\n") {
            let trimmedLine: String = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("//") {
                continue
            }
            if trimmedLine.hasPrefix("case ") {
                continue
            }
            if ActivityTrailWiringTests.line(trimmedLine, mentions: "." + caseName) {
                return true
            }
        }
        return false
    }

    /// True when the line contains the token followed by a non-identifier
    /// character, so `.taskStarted` does not count as a mention of `.task`.
    static func line(_ line: String, mentions token: String) -> Bool {
        var searchRange: Range<String.Index>? = line.startIndex..<line.endIndex
        while let range = searchRange, let found = line.range(of: token, range: range) {
            if found.upperBound == line.endIndex {
                return true
            }
            let nextCharacter: Character = line[found.upperBound]
            if !(nextCharacter.isLetter || nextCharacter.isNumber || nextCharacter == "_") {
                return true
            }
            searchRange = found.upperBound..<line.endIndex
        }
        return false
    }
}
