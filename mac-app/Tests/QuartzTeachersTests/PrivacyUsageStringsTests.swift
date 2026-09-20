import XCTest
@testable import QuartzTeachers

/// macOS protects the Desktop, Documents, Downloads and the folders a sync
/// service manages. The first time Plantoir writes into a working folder in
/// one of them, the teacher is shown a sheet — and what that sheet says
/// underneath "Plantoir would like to access files in your Desktop folder"
/// is whatever `Info.plist` carries for the matching `NS…UsageDescription`
/// key. Until 2026-09-20 it carried nothing, so the one prompt a teacher is
/// meant to see explained nothing.
///
/// `Bundle.main` here is `Plantoir.app` itself: the test target's `TEST_HOST`
/// is the app, so this reads the bundle a teacher would get. That also makes
/// it a guard on the TRACKED `QuartzTeachers/Info.plist`, which is what the
/// build copies in — editing `project.yml` without re-running `xcodegen
/// generate` leaves the tracked file behind and turns this red.
///
/// What this CANNOT test: whether the sheet a teacher actually sees renders
/// our sentence, and whether it appears at all when the file is read by a
/// helper the app spawned rather than by the app. Those are settled by
/// looking at a real prompt — see
/// `documentation/03-launcher-scripts.md` §3.
final class PrivacyUsageStringsTests: XCTestCase {

    // MARK: - Stored properties

    /// The four folders a working folder is really put in. Removable and
    /// network volumes are deliberately absent; documentation/03 §3 says why.
    private let usageKeys: [String] = [
        "NSDesktopFolderUsageDescription",
        "NSDocumentsFolderUsageDescription",
        "NSDownloadsFolderUsageDescription",
        "NSFileProviderDomainUsageDescription",
    ]

    // MARK: - Functions

    /// Every key is present and actually says something.
    func testEveryProtectedFolderCarriesASentence() throws {
        for key in usageKeys {
            let sentence: String = try XCTUnwrap(
                Bundle.main.object(forInfoDictionaryKey: key) as? String,
                "\(key) is missing from the built Info.plist — so macOS shows "
                    + "its bare default and Plantoir explains nothing"
            )
            let trimmed: String = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(trimmed.isEmpty, "\(key) is present but empty")
        }
    }

    /// Rule 1: the interface never names the machinery, and this sentence is
    /// shown to a teacher by macOS itself, in a sheet Plantoir cannot amend
    /// afterwards.
    func testNoSentenceNamesTheMachinery() throws {
        let forbidden: [String] = [
            "toolchain", "script", "docker", "container", "colima",
            "virtual machine", "mount", "quartz", "repository", "config",
            "json", "python", "wsl", "stdout", "engine", "terminal",
        ]
        for key in usageKeys {
            let sentence: String = try XCTUnwrap(
                Bundle.main.object(forInfoDictionaryKey: key) as? String
            )
            let said: String = sentence.lowercased()
            for word in forbidden {
                XCTAssertFalse(
                    said.contains(word),
                    "\(key) says \"\(word)\" to a teacher"
                )
            }
        }
    }

    /// One sentence across all four keys, on purpose: a teacher only ever
    /// sees one of them, and four near-identical strings drift apart. This
    /// pins the decision so a later edit to one of them is deliberate.
    func testTheFourKeysShareOneSentence() throws {
        let firstKey: String = try XCTUnwrap(usageKeys.first)
        let expected: String = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: firstKey) as? String
        )
        for key in usageKeys {
            let sentence: String = try XCTUnwrap(
                Bundle.main.object(forInfoDictionaryKey: key) as? String
            )
            XCTAssertEqual(
                sentence, expected,
                "\(key) has drifted from \(firstKey)"
            )
        }
    }
}
