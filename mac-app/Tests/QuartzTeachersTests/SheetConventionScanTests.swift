import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The HIG sweep's rules for sheets and buttons (#457 item 4), as scans of
/// the views plus the pure functions behind them.
///
/// A scan, like `TextFieldStyleScanTests`, because each rule is about what is
/// WRITTEN at dozens of call sites — a new sheet that forgets one of them is
/// the failure, and no unit test of an existing sheet would see it.
@MainActor
final class SheetConventionScanTests: XCTestCase {

    // MARK: - Stored properties

    /// Buttons allowed to write the default look beside `.disabled(`, by
    /// accessibility identifier, with the reason.
    ///
    /// - `saveButton`: Course Settings' Save swaps `.borderedProminent` for
    ///   `.bordered` on the SAME predicate that enables it (#364); the scan
    ///   sees the prominent branch of an if/else and cannot tell.
    static let disabledDefaultLookAllowed: [String] = [
        "saveButton",
    ]

    // MARK: - Escape (C1)

    /// Escape in a picker field is consumed ONLY while its list is drawn.
    func testPickerEscapeIsHandledOnlyWhileAListIsOpen() {
        XCTAssertEqual(PickerEscape.result(listWasOpen: true), .handled, "the press that closes the list must not also close the sheet")
        XCTAssertEqual(PickerEscape.result(listWasOpen: false), .ignored, "with no list, Escape must reach the sheet and cancel it")
    }

    /// No `.onKeyPress(.escape)` under `Views/` answers `.handled` by itself:
    /// every one asks `PickerEscape`. Until v1.5.0 both picker fields
    /// returned `.handled` unconditionally, so Copy a Page (focus starts in
    /// its field) could not be closed with Escape at all (measured).
    func testEveryEscapeHandlerAsksWhetherAListWasOpen() throws {
        var handlers: [String] = []
        var problems: [String] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: TextFieldStyleScanTests.viewsURL()) {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            for block in SheetConventionScanTests.blocks(after: ".onKeyPress(.escape)", in: text, file: file.lastPathComponent) {
                handlers.append(block.location)
                if !block.text.contains("PickerEscape.result(") {
                    problems.append(block.location + " handles Escape without asking whether a list was open")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(handlers.count, 2, "The scan found \(handlers.count) Escape handlers; its pattern has stopped matching")
        XCTAssertEqual(problems, [], "Escape closes a picker's list, and otherwise reaches the sheet (#457, C1)")
    }

    // MARK: - The default button (C2)

    /// A button that cannot be pressed does not wear the default look. The
    /// system draws a `.keyboardShortcut(.defaultAction)` button in the
    /// accent even while disabled (measured: Copy a Page's Copy, dim blue),
    /// and `.borderedProminent` does the same; `.defaultButton(isEnabled:)`
    /// and `.prominentButton(isEnabled:)` take both off while disabled.
    func testNoDisabledButtonWearsTheDefaultLook() throws {
        let buttons: [Chain] = try SheetConventionScanTests.allButtons()
        XCTAssertGreaterThanOrEqual(buttons.count, 150, "The scan found only \(buttons.count) buttons; its pattern has stopped matching")
        var problems: [String] = []
        for button in buttons {
            let wearsTheDefaultLook: Bool = button.chain.contains(".borderedProminent")
                || SheetConventionScanTests.hasDefaultShortcut(button.chain)
            if !wearsTheDefaultLook || !button.chain.contains(".disabled(") {
                continue
            }
            var allowed: Bool = false
            for identifier in SheetConventionScanTests.disabledDefaultLookAllowed {
                if button.chain.contains("\"" + identifier + "\"") {
                    allowed = true
                }
            }
            if !allowed {
                problems.append(button.location + " wears the default look and can be disabled; use .defaultButton(isEnabled:)")
            }
        }
        XCTAssertEqual(problems, [], "A button that cannot be pressed is grey (#457, C2; #364)")
    }

    func testTheDefaultButtonTakesReturnOnlyWhileItCanBePressed() {
        XCTAssertEqual(DefaultButtonModifier.shortcut(isEnabled: true), .defaultAction)
        XCTAssertNil(DefaultButtonModifier.shortcut(isEnabled: false))
        XCTAssertNil(DefaultButtonModifier.shortcut(isEnabled: true, isTheDefault: false), "a decision must not be made by a Return pressed out of habit")
    }

    /// The scan reads a button's modifiers past its trailing closures,
    /// including a `label:` one, and stops at the next button.
    func testTheButtonScanReadsChainsAsWritten() {
        let source: String = """
        Button("Go") {
            go()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!ready)
        Button {
            other()
        } label: {
            Text("x")
        }
        .buttonStyle(.borderedProminent)
        Button("Cancel", action: cancel)
        """
        let buttons: [Chain] = SheetConventionScanTests.chains(of: "Button(", in: source, file: "Example.swift")
        XCTAssertEqual(buttons.count, 3)
        if buttons.count == 3 {
            XCTAssertTrue(buttons[0].chain.contains(".disabled("))
            XCTAssertTrue(SheetConventionScanTests.hasDefaultShortcut(buttons[0].chain))
            XCTAssertTrue(buttons[1].chain.contains(".borderedProminent"))
            XCTAssertFalse(buttons[1].chain.contains(".disabled("))
            XCTAssertEqual(buttons[2].chain.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }
    }

    // MARK: - Helpers

    struct Chain {
        var location: String
        var chain: String
    }

    struct Block {
        var location: String
        var text: String
    }

    static func hasDefaultShortcut(_ chain: String) -> Bool {
        return chain.contains(".keyboardShortcut(.defaultAction") || chain.contains(": .defaultAction)")
    }

    static func allButtons() throws -> [Chain] {
        var result: [Chain] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: TextFieldStyleScanTests.viewsURL()) {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            for button in chains(of: "Button(", in: text, file: file.lastPathComponent) {
                result.append(button)
            }
        }
        return result
    }

    /// The `{ … }` block that follows each occurrence of `marker`.
    static func blocks(after marker: String, in source: String, file: String) -> [Block] {
        let original: [Character] = Array(source)
        let code: [Character] = Array(TextFieldStyleScanTests.codeWithoutComments(source))
        let masked: [Character] = TextFieldStyleScanTests.maskingStrings(code)
        var result: [Block] = []
        var index: Int = 0
        while index < masked.count {
            if TextFieldStyleScanTests.matches(marker, in: masked, at: index) {
                var cursor: Int = index + marker.count
                while cursor < masked.count && masked[cursor].isWhitespace {
                    cursor += 1
                }
                if cursor < masked.count && masked[cursor] == "{" {
                    let end: Int = TextFieldStyleScanTests.closing(from: cursor, in: masked, open: "{", close: "}")
                    result.append(Block(location: file + ":" + String(lineNumber(of: index, in: original)), text: String(original[cursor..<end])))
                }
            }
            index += 1
        }
        return result
    }

    static func lineNumber(of position: Int, in characters: [Character]) -> Int {
        var line: Int = 1
        for character in characters[0..<position] where character == "\n" {
            line += 1
        }
        return line
    }

    /// Every `name` (a word ending in `(`) in `source`, with the modifier
    /// chain that follows its arguments and trailing closures.
    static func chains(of name: String, in source: String, file: String) -> [Chain] {
        let original: [Character] = Array(source)
        let code: [Character] = Array(TextFieldStyleScanTests.codeWithoutComments(source))
        let masked: [Character] = TextFieldStyleScanTests.maskingStrings(code)
        // `name` is written with its "(" ("Button("), and matches the
        // trailing-closure form too ("Button {").
        let word: String = String(name.dropLast())
        var starts: [Int] = []
        var argumentsAt: [Int?] = []
        var index: Int = 0
        while index < masked.count {
            if TextFieldStyleScanTests.matches(word, in: masked, at: index) {
                let before: Character? = index > 0 ? masked[index - 1] : nil
                if before == nil || !(before!.isLetter || before!.isNumber || before! == "_" || before! == ".") {
                    var next: Int = index + word.count
                    if next < masked.count && masked[next] == "(" {
                        starts.append(index)
                        argumentsAt.append(next)
                    } else {
                        while next < masked.count && masked[next] == " " {
                            next += 1
                        }
                        if next < masked.count && masked[next] == "{" && next > index + word.count {
                            starts.append(index)
                            argumentsAt.append(nil)
                        }
                    }
                }
            }
            index += 1
        }
        var result: [Chain] = []
        for (position, start) in starts.enumerated() {
            var end: Int = start + word.count
            if let open = argumentsAt[position] {
                end = TextFieldStyleScanTests.closing(from: open, in: masked, open: "(", close: ")")
            }
            // Trailing closures: `{ … }`, then any `label: { … }`.
            while true {
                var cursor: Int = end
                while cursor < masked.count && masked[cursor].isWhitespace {
                    cursor += 1
                }
                if cursor < masked.count && masked[cursor] == "{" {
                    end = TextFieldStyleScanTests.closing(from: cursor, in: masked, open: "{", close: "}")
                    continue
                }
                var word: Int = cursor
                while word < masked.count && (masked[word].isLetter || masked[word].isNumber || masked[word] == "_") {
                    word += 1
                }
                if word > cursor && word < masked.count && masked[word] == ":" {
                    var brace: Int = word + 1
                    while brace < masked.count && masked[brace].isWhitespace {
                        brace += 1
                    }
                    if brace < masked.count && masked[brace] == "{" {
                        end = TextFieldStyleScanTests.closing(from: brace, in: masked, open: "{", close: "}")
                        continue
                    }
                }
                break
            }
            let chainStart: Int = end
            // Modifiers: `.name`, then an optional (…) and an optional { … }.
            while true {
                var cursor: Int = end
                while cursor < masked.count && masked[cursor].isWhitespace {
                    cursor += 1
                }
                guard cursor + 1 < masked.count, masked[cursor] == ".", masked[cursor + 1].isLetter else {
                    break
                }
                cursor += 1
                while cursor < masked.count && (masked[cursor].isLetter || masked[cursor].isNumber || masked[cursor] == "_") {
                    cursor += 1
                }
                if cursor < masked.count && masked[cursor] == "(" {
                    cursor = TextFieldStyleScanTests.closing(from: cursor, in: masked, open: "(", close: ")")
                }
                var peek: Int = cursor
                while peek < masked.count && masked[peek] == " " {
                    peek += 1
                }
                if peek < masked.count && masked[peek] == "{" {
                    cursor = TextFieldStyleScanTests.closing(from: peek, in: masked, open: "{", close: "}")
                }
                end = cursor
            }
            let chain: String = String(original[chainStart..<max(chainStart, end)])
            result.append(Chain(location: file + ":" + String(lineNumber(of: start, in: original)), chain: chain))
        }
        return result
    }
}

// MARK: - Context menus (C5)

extension SheetConventionScanTests {

    /// Every context menu that removes or deletes ends with that item,
    /// behind a divider (HIG: destructive last, set apart). The census pins
    /// WHICH menus remove: a course, a live section, a backup, an archive,
    /// a reference course, a Course Settings list's row, and All Backups'
    /// table. Until the HIG
    /// sweep (#457) the course and section rows had no Remove item at all.
    func testEveryRemovalInAContextMenuIsLastBehindADivider() throws {
        var removing: [String] = []
        var problems: [String] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: TextFieldStyleScanTests.viewsURL()) {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            var menus: [Block] = SheetConventionScanTests.blocks(after: ".contextMenu", in: text, file: file.lastPathComponent)
            for block in SheetConventionScanTests.blocks(after: ".contextMenu(forSelectionType: String.self)", in: text, file: file.lastPathComponent) {
                menus.append(block)
            }
            for menu in menus {
                let body: String = SheetConventionScanTests.resolvingMenuFunctions(menu.text, in: text)
                let code: String = TextFieldStyleScanTests.codeWithoutComments(body)
                let removes: Bool = code.contains("role: .destructive") || code.contains("removeItem(")
                if !removes {
                    continue
                }
                removing.append(menu.location)
                guard let lastDivider = code.range(of: "Divider()", options: .backwards) else {
                    problems.append(menu.location + " removes with no divider before it")
                    continue
                }
                let before: String = String(code[code.startIndex..<lastDivider.lowerBound])
                let after: String = String(code[lastDivider.upperBound...])
                let afterRemoves: Bool = after.contains("role: .destructive") || after.contains("removeItem(")
                let beforeRemoves: Bool = before.contains("role: .destructive") || before.contains("removeItem(")
                let othersAfter: Int = SaveEnablesTests.occurrences(of: "Button(", in: after)
                    + SaveEnablesTests.occurrences(of: "Item(", in: after)
                    - SaveEnablesTests.occurrences(of: "removeItem(", in: after)
                if !afterRemoves || beforeRemoves || othersAfter > 1 {
                    problems.append(menu.location + " does not end with its removal alone, behind a divider")
                }
            }
        }
        XCTAssertEqual(problems, [], "Destructive items come last, behind a divider (#457, C5)")
        XCTAssertEqual(removing.count, 7, "Context menus that remove: \(removing)")
    }

    /// A `.contextMenu` body that calls `xxxMenu(…)` is read as that
    /// function's body, so `sectionRowMenu` and `courseRowMenu` are seen.
    static func resolvingMenuFunctions(_ body: String, in file: String) -> String {
        var result: String = body
        for name in ["sectionRowMenu", "courseRowMenu", "backupsMenu"] {
            if body.contains(name + "(") {
                result += SheetConventionScanTests.functionBody(named: name, in: file)
            }
        }
        return result
    }
}

extension SheetConventionScanTests {

    /// The `{ … }` body of `func name(…)` in `source`, or "" when absent.
    static func functionBody(named name: String, in source: String) -> String {
        let original: [Character] = Array(source)
        let masked: [Character] = TextFieldStyleScanTests.maskingStrings(Array(TextFieldStyleScanTests.codeWithoutComments(source)))
        let marker: String = "func " + name + "("
        var index: Int = 0
        while index < masked.count {
            if TextFieldStyleScanTests.matches(marker, in: masked, at: index) {
                var cursor: Int = index + marker.count - 1
                cursor = TextFieldStyleScanTests.closing(from: cursor, in: masked, open: "(", close: ")")
                while cursor < masked.count && masked[cursor] != "{" {
                    cursor += 1
                }
                if cursor >= masked.count {
                    return ""
                }
                let end: Int = TextFieldStyleScanTests.closing(from: cursor, in: masked, open: "{", close: "}")
                return String(original[cursor..<end])
            }
            index += 1
        }
        return ""
    }
}
