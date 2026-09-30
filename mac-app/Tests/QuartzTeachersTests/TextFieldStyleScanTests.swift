import XCTest
@testable import QuartzTeachers

/// Every editable text field is bordered (#374), as a scan of the views.
///
/// Russell, 2026-09-27: every text field should wear the bordered, rounded
/// style Course name has, never the borderless "clean" look. The audit found
/// every field already bordered — the two "clean" rows in his picture were
/// read-only values, not fields — so this makes the rule STRUCTURAL: one
/// modifier, `.borderedTextField()`, and a scan that fails on drift.
///
/// A field passes when its modifier chain carries `.borderedTextField()` or
/// one of the two chromes that draw their own border. The few fields that
/// choose another style are listed below by their accessibility identifier,
/// each with its reason; a field anywhere else that chooses a style — even
/// alongside `.borderedTextField()`, where the style nearest the view wins and
/// draws it borderless — fails.
@MainActor
final class TextFieldStyleScanTests: XCTestCase {

    // MARK: - Stored properties

    /// Fields that choose their own style, by identifier, and why each is
    /// still bordered.
    static let exceptions: [String: String] = [
        "renameField": "SidebarView: .plain inside its own bordered card (text-background fill and separator stroke), because the row sits on the selection colour (#293).",
        "assistComposerField": "AssistWindowView: .plain inside the Messages-shaped rounded border the composer strokes itself.",
        "taskAnswerField": "TaskProgressView: inside an .alert, where AppKit draws the field and SwiftUI's styles are ignored.",
    ]

    /// The chromes that draw a border of their own, and why they exist.
    static let chromes: [String: String] = [
        "WizardFieldChrome(": "The wizard's 24pt fields line up with the course-code picker; .roundedBorder is 26pt (Russell, 2026-08-23; documentation/12-windows-app.md → Metrics).",
        "SearchablePickerChrome(": "The searchable picker's field, 24pt for the same reason.",
    ]

    /// The only files allowed to write `.textFieldStyle(`, and how many times.
    static let styleChoosers: [String: Int] = [
        "BorderedTextField.swift": 1,
        "CourseCodePickerView.swift": 1,
        "SearchablePicker.swift": 1,
        "SidebarView.swift": 1,
        "AssistWindowView.swift": 1,
    ]

    // MARK: - Tests

    func testEveryTextFieldIsBordered() throws {
        let fields: [Field] = try TextFieldStyleScanTests.allFields()
        XCTAssertGreaterThanOrEqual(fields.count, 29, "The scan found only \(fields.count) fields; its pattern has stopped matching")
        var problems: [String] = []
        var exceptionsSeen: Set<String> = []
        for field in fields {
            var exceptionIdentifier: String? = nil
            for identifier in TextFieldStyleScanTests.exceptions.keys {
                if field.chain.contains(".accessibilityIdentifier(\"" + identifier + "\")") {
                    exceptionIdentifier = identifier
                }
            }
            if let exceptionIdentifier {
                exceptionsSeen.insert(exceptionIdentifier)
                continue
            }
            if field.chain.contains(".textFieldStyle(") {
                problems.append(field.location + " chooses its own style; the one nearest the field wins, so it is not bordered")
                continue
            }
            var bordered: Bool = field.chain.contains(".borderedTextField()")
            for chrome in TextFieldStyleScanTests.chromes.keys {
                if field.chain.contains(".modifier(" + chrome) {
                    bordered = true
                }
            }
            if !bordered {
                problems.append(field.location + " has no .borderedTextField() and no bordered chrome")
            }
        }
        XCTAssertEqual(problems, [], "Every text field wears .borderedTextField() (#374)")
        // An exception whose field has gone must leave the list.
        XCTAssertEqual(exceptionsSeen, Set(TextFieldStyleScanTests.exceptions.keys), "A listed exception no longer matches a field")
    }

    func testOnlyTheSharedModifierAndTheChromesChooseAStyle() throws {
        var counts: [String: Int] = [:]
        var roundedBorderFiles: [String] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: TextFieldStyleScanTests.viewsURL()) {
            let code: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: file, encoding: .utf8))
            let styles: Int = SaveEnablesTests.occurrences(of: ".textFieldStyle(", in: code)
            if styles > 0 {
                counts[file.lastPathComponent] = styles
            }
            if code.contains(".roundedBorder") {
                roundedBorderFiles.append(file.lastPathComponent)
            }
            // A chrome's own style must sit inside the chrome's definition.
            for chrome in ["WizardFieldChrome", "SearchablePickerChrome"] {
                if let definition = code.range(of: "struct " + chrome), let style = code.range(of: ".textFieldStyle(") {
                    XCTAssertGreaterThan(style.lowerBound, definition.lowerBound, file.lastPathComponent + ": a style before " + chrome + "'s definition")
                }
            }
        }
        XCTAssertEqual(counts, TextFieldStyleScanTests.styleChoosers, "Only the shared modifier, the two chromes and the listed exceptions choose a text field style")
        XCTAssertEqual(roundedBorderFiles, ["BorderedTextField.swift"], ".roundedBorder is written in one place")
    }

    /// The scan itself: comments and strings do not fool it, a chain ends
    /// where the next field begins, and a multi-line initializer is matched.
    func testTheScanReadsChainsAsWritten() {
        let source: String = """
        // TextField("in a comment")
        TextField("https://example.com", text: $a)
        TextField("", text: Binding(
            get: { a },
            set: { value in a = value }
        ))
            .onChange(of: a) { b() }
            .borderedTextField()
        MyTextField(labelWithString: "x")
        """
        let fields: [Field] = TextFieldStyleScanTests.fields(in: source, file: "Example.swift")
        XCTAssertEqual(fields.count, 2)
        if fields.count == 2 {
            XCTAssertFalse(fields[0].chain.contains(".borderedTextField()"), "the first field must not be credited with the second's style")
            XCTAssertTrue(fields[1].chain.contains(".borderedTextField()"))
            XCTAssertEqual(fields[1].location, "Example.swift:3")
        }
    }

    // MARK: - Helpers

    struct Field {
        var location: String
        var chain: String
    }

    static func viewsURL() -> URL {
        return UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers/Views")
    }

    static func allFields() throws -> [Field] {
        var result: [Field] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: viewsURL()) {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            for field in fields(in: text, file: file.lastPathComponent) {
                result.append(field)
            }
        }
        return result
    }

    /// Every `TextField(` / `SecureField(` in `source` with the modifier chain
    /// that follows its initializer.
    static func fields(in source: String, file: String) -> [Field] {
        let original: [Character] = Array(source)
        let code: [Character] = Array(codeWithoutComments(source))
        let masked: [Character] = maskingStrings(code)
        var result: [Field] = []
        var starts: [Int] = []
        var index: Int = 0
        while index < masked.count {
            for name in ["TextField(", "SecureField("] {
                if matches(name, in: masked, at: index) {
                    let before: Character? = index > 0 ? masked[index - 1] : nil
                    if before == nil || !(before!.isLetter || before!.isNumber || before! == "_") {
                        starts.append(index)
                    }
                }
            }
            index += 1
        }
        for (position, start) in starts.enumerated() {
            let openParen: Int = start + (matches("TextField(", in: masked, at: start) ? 9 : 11)
            var end: Int = closing(from: openParen, in: masked, open: "(", close: ")")
            let chainStart: Int = end
            let limit: Int = position + 1 < starts.count ? starts[position + 1] : masked.count
            // Modifiers: `.name`, then an optional (…) and an optional { … }.
            while true {
                var cursor: Int = end
                while cursor < limit && masked[cursor].isWhitespace {
                    cursor += 1
                }
                guard cursor + 1 < limit, masked[cursor] == ".", masked[cursor + 1].isLetter else {
                    break
                }
                cursor += 1
                while cursor < limit && (masked[cursor].isLetter || masked[cursor].isNumber || masked[cursor] == "_") {
                    cursor += 1
                }
                if cursor < limit && masked[cursor] == "(" {
                    cursor = closing(from: cursor, in: masked, open: "(", close: ")")
                }
                var peek: Int = cursor
                while peek < limit && masked[peek] == " " {
                    peek += 1
                }
                if peek < limit && masked[peek] == "{" {
                    cursor = closing(from: peek, in: masked, open: "{", close: "}")
                }
                end = min(cursor, limit)
            }
            let chain: String = String(original[chainStart..<max(chainStart, end)])
            var line: Int = 1
            for character in original[0..<start] where character == "\n" {
                line += 1
            }
            result.append(Field(location: file + ":" + String(line), chain: chain))
        }
        return result
    }

    static func matches(_ word: String, in characters: [Character], at index: Int) -> Bool {
        let letters: [Character] = Array(word)
        if index + letters.count > characters.count {
            return false
        }
        for offset in 0..<letters.count {
            if characters[index + offset] != letters[offset] {
                return false
            }
        }
        return true
    }

    /// The index just past the bracket that closes the one at `openIndex`.
    static func closing(from openIndex: Int, in characters: [Character], open: Character, close: Character) -> Int {
        var depth: Int = 0
        var index: Int = openIndex
        while index < characters.count {
            if characters[index] == open {
                depth += 1
            } else if characters[index] == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return characters.count
    }

    /// `source` with every comment replaced by spaces, same length, strings
    /// left alone — so "https://…" inside a string is not a comment.
    static func codeWithoutComments(_ source: String) -> String {
        var characters: [Character] = Array(source)
        var index: Int = 0
        var inString: Bool = false
        while index < characters.count {
            let character: Character = characters[index]
            if inString {
                if character == "\\" {
                    index += 2
                    continue
                }
                if character == "\"" || character == "\n" {
                    inString = false
                }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
                index += 1
                continue
            }
            if character == "/" && index + 1 < characters.count && characters[index + 1] == "/" {
                while index < characters.count && characters[index] != "\n" {
                    characters[index] = " "
                    index += 1
                }
                continue
            }
            if character == "/" && index + 1 < characters.count && characters[index + 1] == "*" {
                while index < characters.count && !(characters[index] == "*" && index + 1 < characters.count && characters[index + 1] == "/") {
                    if characters[index] != "\n" {
                        characters[index] = " "
                    }
                    index += 1
                }
                if index + 1 < characters.count {
                    characters[index] = " "
                    characters[index + 1] = " "
                }
                index += 2
                continue
            }
            index += 1
        }
        return String(characters)
    }

    /// The contents of every string literal replaced by spaces, so a bracket
    /// or a dot inside one is not read as code.
    static func maskingStrings(_ code: [Character]) -> [Character] {
        var characters: [Character] = code
        var index: Int = 0
        var inString: Bool = false
        while index < characters.count {
            let character: Character = characters[index]
            if inString {
                if character == "\\" {
                    characters[index] = " "
                    if index + 1 < characters.count {
                        characters[index + 1] = " "
                    }
                    index += 2
                    continue
                }
                if character == "\"" || character == "\n" {
                    inString = false
                } else {
                    characters[index] = " "
                }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
            }
            index += 1
        }
        return characters
    }
}
