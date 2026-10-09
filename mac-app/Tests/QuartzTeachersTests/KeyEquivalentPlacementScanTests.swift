import XCTest
@testable import QuartzTeachers

/// Shortcuts live on MENU items (#457): no view under `Views/` hangs a
/// character shortcut on a button.
///
/// A shortcut on a button is one nobody discovers — the menu bar is the only
/// place macOS advertises a key equivalent, and it is where somebody looks
/// for a command they cannot find. ⌘S sat on Course Settings' Save button
/// until v1.5.0; it is Course ▸ Save Course Settings now. The two keys a
/// dialog's buttons answer — Return for the default button, Escape for
/// Cancel — are the exceptions, because they belong to the dialog rather
/// than to the app.
///
/// The scan reads code with comments removed, and matches every spelling
/// the plan review found would otherwise slip through: `.keyboardShortcut(`
/// with any argument, `KeyboardShortcut(` and `KeyEquivalent(`.
@MainActor
final class KeyEquivalentPlacementScanTests: XCTestCase {

    // MARK: - Functions

    /// Every use in `code` of a shortcut that is not a dialog's Return or
    /// Escape, as "file:line".
    static func characterShortcuts(in code: String, file: String) -> [String] {
        var found: [String] = []
        var lineNumber: Int = 0
        for line in code.components(separatedBy: "\n") {
            lineNumber += 1
            var mentions: Bool = false
            for spelling in [".keyboardShortcut(", "KeyboardShortcut(", "KeyEquivalent("] {
                if line.contains(spelling) {
                    mentions = true
                }
            }
            if !mentions {
                continue
            }
            // A key made by name is a character shortcut, whatever else.
            if line.contains("KeyboardShortcut(") || line.contains("KeyEquivalent(") {
                found.append(file + ":" + String(lineNumber))
                continue
            }
            // `.keyboardShortcut(…)`: Return or Escape — including a
            // conditional one, `cond ? nil : .defaultAction` — passes; an
            // argument that opens with a quoted key does not.
            let argument: String = line.components(separatedBy: ".keyboardShortcut(").dropFirst().joined(separator: " ")
            let trimmed: String = argument.trimmingCharacters(in: .whitespaces)
            let namesADialogKey: Bool = argument.contains(".defaultAction") || argument.contains(".cancelAction")
            if !namesADialogKey || trimmed.hasPrefix("\"") {
                found.append(file + ":" + String(lineNumber))
            }
        }
        return found
    }

    // MARK: - Tests

    func testNoViewHangsACharacterShortcut() throws {
        var found: [String] = []
        var filesRead: Int = 0
        for file in UserFacingLabelWordsTests.swiftFiles(under: TextFieldStyleScanTests.viewsURL()) {
            filesRead += 1
            let code: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: file, encoding: .utf8))
            for location in KeyEquivalentPlacementScanTests.characterShortcuts(in: code, file: file.lastPathComponent) {
                found.append(location)
            }
        }
        XCTAssertGreaterThan(filesRead, 50, "the scan read only \(filesRead) files; its folder has moved")
        XCTAssertEqual(found, [], "Shortcuts go on menu items (#457), not on buttons in a view")
    }

    /// The scan itself: a comment does not count, the dialog keys pass, and
    /// each spelling is caught.
    func testTheScanCatchesEverySpelling() {
        let code: String = TextFieldStyleScanTests.codeWithoutComments("""
        // .keyboardShortcut("s") in a comment
        Button("OK") { }.keyboardShortcut(.defaultAction)
        Button("Cancel") { }.keyboardShortcut(.cancelAction)
        Button("Set Up") { }.keyboardShortcut(waiting ? nil : .defaultAction)
        Button("Save") { }.keyboardShortcut("s", modifiers: .command)
        Button("Go") { }.keyboardShortcut(KeyboardShortcut("g"))
        let key = KeyEquivalent("x")
        """)
        XCTAssertEqual(
            KeyEquivalentPlacementScanTests.characterShortcuts(in: code, file: "Example.swift"),
            ["Example.swift:5", "Example.swift:6", "Example.swift:7"]
        )
    }
}
