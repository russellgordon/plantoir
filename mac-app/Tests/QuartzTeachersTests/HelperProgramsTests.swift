import XCTest
@testable import QuartzTeachers

/// One definition of where Plantoir's helper programs live.
///
/// The fault these pin is issue #220: the app shelled out to `docker` and
/// `colima` without ever saying where to look, and on a Mac that has never
/// had Homebrew the only copies are the ones the launchers downloaded into
/// `~/Library/Application Support/Plantoir/tools/bin`.
final class HelperProgramsTests: XCTestCase {

    // MARK: - Where to look, and in what order

    /// The pinned copies come FIRST, because that is where `setup.sh` puts
    /// them and the launcher is what actually built the container. The next
    /// test holds the launcher to the same order.
    func testThePinnedProgramsAreLookedForFirst() {
        let home: URL = URL(fileURLWithPath: "/Users/pretend")
        XCTAssertEqual(
            HelperPrograms.searchDirectories(inHomeFolder: home),
            [
                "/Users/pretend/Library/Application Support/Plantoir/tools/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin"
            ]
        )
    }

    /// The app and the launchers must agree about the order, or a Mac with
    /// two `docker`s on it gets a different one depending on who asked. This
    /// reads the launcher rather than trusting a comment about it, so a
    /// launcher edit that reorders the export turns this red instead of
    /// producing a silent disagreement. (`FolderContainerTests` reads a
    /// launcher for the same reason.)
    func testTheLauncherStillPutsThePinnedProgramsFirst() throws {
        let setupURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("setup.sh")
        let text: String = try String(contentsOf: setupURL, encoding: .utf8)
        XCTAssertTrue(
            text.contains("TOOLS_DIR=\"$HOME/Library/Application Support/Plantoir/tools\""),
            "setup.sh no longer keeps the downloaded programs where HelperPrograms looks for them"
        )
        XCTAssertTrue(
            text.contains("export PATH=\"$TOOLS_DIR/bin:$PATH\""),
            "setup.sh no longer searches the downloaded programs FIRST, so the app and the launcher would disagree"
        )
    }

    /// Nothing a teacher already had is taken away, and an empty inheritance
    /// still leaves a usable PATH rather than three directories and a colon.
    func testWhatWasInheritedIsKeptAtTheEnd() {
        let home: URL = URL(fileURLWithPath: "/Users/pretend")
        XCTAssertTrue(
            HelperPrograms.pathValue(inheriting: "/opt/mine/bin", inHomeFolder: home)
                .hasSuffix(":/opt/mine/bin")
        )
        XCTAssertTrue(
            HelperPrograms.pathValue(inheriting: nil, inHomeFolder: home)
                .hasSuffix(":" + HelperPrograms.pathWhenNothingWasInherited)
        )
        XCTAssertTrue(
            HelperPrograms.pathValue(inheriting: "", inHomeFolder: home)
                .hasSuffix(":" + HelperPrograms.pathWhenNothingWasInherited)
        )
    }

    // MARK: - What else the helper is handed

    /// `HOME` above all: `docker` keeps its context store in `~/.docker` and
    /// `colima` its whole state in `~/.colima`. A helper handed a stripped
    /// environment cannot reach the engine at all — and under the quit path's
    /// rules, a question that could not be asked means "stop nothing", so the
    /// symptom would be the same silent no-op this whole piece is about.
    func testEverythingButThePathSurvives() {
        let home: URL = URL(fileURLWithPath: "/Users/pretend")
        let inherited: [String: String] = [
            "HOME": "/Users/pretend",
            "PATH": "/usr/bin",
            "LANG": "en_CA.UTF-8"
        ]
        let result: [String: String] = HelperPrograms.environment(
            basedOn: inherited, inHomeFolder: home
        )
        XCTAssertEqual(result["HOME"], "/Users/pretend")
        XCTAssertEqual(result["LANG"], "en_CA.UTF-8")
        XCTAssertEqual(
            result["PATH"],
            "/Users/pretend/Library/Application Support/Plantoir/tools/bin"
            + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin"
        )
    }

    // MARK: - The app's own copies (GitHub #312)

    /// The launcher installs from the app only when told where the app's
    /// copies are, and only an app that carries them may say so.
    func testTheAppsCopiesAreNamedOnlyWhenTheAppCarriesThem() {
        let home: URL = URL(fileURLWithPath: "/Users/pretend")
        let carried: URL = URL(fileURLWithPath: "/Applications/Plantoir.app/Contents/Resources/helpers")
        let with: [String: String] = HelperPrograms.environment(
            basedOn: ["HOME": "/Users/pretend"], inHomeFolder: home, bundledHelpers: carried
        )
        XCTAssertEqual(with[HelperPrograms.bundledHelpersVariable], carried.path)
        let without: [String: String] = HelperPrograms.environment(
            basedOn: ["HOME": "/Users/pretend"], inHomeFolder: home, bundledHelpers: nil
        )
        XCTAssertNil(without[HelperPrograms.bundledHelpersVariable])
        XCTAssertEqual(HelperPrograms.bundledHelpersVariable, "PLANTOIR_BUNDLED_HELPERS",
                       "the launchers read this exact name")
    }

    /// A value inherited from some other copy of Plantoir (a scheduled run
    /// started by an older app, a developer's shell) must never point a
    /// launcher at a folder that is not this app's.
    func testAnInheritedValueIsNotPassedOnByAnAppThatCarriesNone() {
        let inherited: [String: String] = [
            "HOME": "/Users/pretend",
            "PLANTOIR_BUNDLED_HELPERS": "/Volumes/Old/Plantoir.app/Contents/Resources/helpers"
        ]
        let result: [String: String] = HelperPrograms.environment(
            basedOn: inherited, inHomeFolder: URL(fileURLWithPath: "/Users/pretend"), bundledHelpers: nil
        )
        XCTAssertNil(result[HelperPrograms.bundledHelpersVariable])
    }

    /// The folder is found inside an app bundle when it is there, and not
    /// otherwise. A real bundle on disk, because `Bundle` decides where its
    /// resources are.
    func testTheFolderIsFoundInsideTheAppAndOnlyWhenPresent() throws {
        let scratch: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("helpers-bundle-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: scratch)
        }
        let app: URL = scratch.appendingPathComponent("Pretend.app", isDirectory: true)
        let contents: URL = app.appendingPathComponent("Contents", isDirectory: true)
        let resources: URL = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let information: [String: String] = ["CFBundleIdentifier": "ca.example.pretend-\(UUID().uuidString)"]
        let plist: Data = try PropertyListSerialization.data(fromPropertyList: information, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let empty: Bundle = try XCTUnwrap(Bundle(url: app))
        XCTAssertNil(HelperPrograms.bundledHelpersDirectory(in: empty))

        let helpers: URL = resources.appendingPathComponent("helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let carrying: Bundle = try XCTUnwrap(Bundle(url: app))
        XCTAssertEqual(
            HelperPrograms.bundledHelpersDirectory(in: carrying)?.standardizedFileURL.path,
            helpers.standardizedFileURL.path
        )
    }

    // MARK: - Putting it into a generated script

    /// "Application Support" has a space in it, and a home folder can contain
    /// a quote. A generated script that gets either wrong is a script that
    /// does something else entirely.
    func testTheExportLineSurvivesAnAwkwardHomeFolder() throws {
        let home: URL = URL(fileURLWithPath: "/Users/o'brien tui")
        let line: String = HelperPrograms.exportLine(inHomeFolder: home)

        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "PATH=/nothing; " + line + "; printf '%s' \"$PATH\""]
        let output: Pipe = Pipe()
        shell.standardOutput = output
        try shell.run()
        shell.waitUntilExit()
        let readBack: String = String(
            data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? ""

        XCTAssertEqual(
            readBack,
            "/Users/o'brien tui/Library/Application Support/Plantoir/tools/bin"
            + ":/opt/homebrew/bin:/usr/local/bin:/nothing",
            "The shell read the export line differently from how it was meant"
        )
    }
}
