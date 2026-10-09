import XCTest
@testable import QuartzTeachers

/// CLAUDE.md rule 1, as a scan of the views (#369): no label a teacher reads
/// names the machinery. Until this test the rule was enforced only by word
/// lists inside individual features' tests, and "Language / region (Quartz
/// locale)" shipped from v1.1.0 to v1.4.0 in the first row of Course Settings.
///
/// The list, the matching and the scope are `contracts/shared-rules.json` →
/// `userFacingLabelWords`; the Course Settings sentences that replaced the two
/// hits are `courseSettingsWording`.
@MainActor
final class UserFacingLabelWordsTests: XCTestCase {

    // MARK: - Tests

    /// Every Course Settings sentence is the contract's, word for word.
    func testTheCourseSettingsWordsAreTheContracts() throws {
        let block: [String: Any] = try SharedRulesContractTests.section("courseSettingsWording")
        XCTAssertEqual(CourseSettingsWording.localeLabel, block["localeLabel"] as? String)
        XCTAssertEqual(CourseSettingsWording.localeCaption, block["localeCaption"] as? String)
        XCTAssertEqual(CourseSettingsWording.colourSchemeNoneChosen, block["colourSchemeNoneChosen"] as? String)
        let template: String = try XCTUnwrap(block["saveHeldBack"] as? String)
        XCTAssertTrue(template.contains("{reason}"), "saveHeldBack must be a {reason} template")
        let reason: String = "That folder doesn’t exist."
        XCTAssertEqual(
            CourseSettingsWording.saveHeldBack(reason: reason),
            template.replacingOccurrences(of: "{reason}", with: reason)
        )
    }

    /// Course Settings' Printing section (#454): every word is the contract's.
    func testThePrintingWordsAreTheContracts() throws {
        let block: [String: Any] = try SharedRulesContractTests.section("courseSettingsWording")
        let pairs: [(String, String)] = [
            ("printingHeader", CourseSettingsWording.printingHeader),
            ("printingSchoolName", CourseSettingsWording.printingSchoolName),
            ("printingBlanks", CourseSettingsWording.printingBlanks),
            ("printingBlankName", CourseSettingsWording.printingBlankName),
            ("printingBlankDate", CourseSettingsWording.printingBlankDate),
            ("printingBlankClassNumber", CourseSettingsWording.printingBlankClassNumber),
            ("printingSchoolNameGoes", CourseSettingsWording.printingSchoolNameGoes),
            ("printingCourseCodeGoes", CourseSettingsWording.printingCourseCodeGoes),
            ("printingTopLeft", CourseSettingsWording.printingTopLeft),
            ("printingBottomLeft", CourseSettingsWording.printingBottomLeft),
            ("printingNotPrinted", CourseSettingsWording.printingNotPrinted),
            ("printingCaption", CourseSettingsWording.printingCaption),
        ]
        let forbidden: [String] = try UserFacingLabelWordsTests.forbiddenWords()
        for (key, said) in pairs {
            XCTAssertEqual(said, block[key] as? String, key)
            XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: said, from: forbidden), [], key)
        }
        // The blanks a student fills in are printed with the same words the
        // settings use for them (printablePages.words).
        let printed: [String: Any] = try SharedRulesContractTests.section("printablePages")
        let words: [String: Any] = try XCTUnwrap(printed["words"] as? [String: Any])
        XCTAssertEqual(CourseSettingsWording.printingBlankName, words["blankName"] as? String)
        XCTAssertEqual(CourseSettingsWording.printingBlankDate, words["blankDate"] as? String)
        XCTAssertEqual(CourseSettingsWording.printingBlankClassNumber, words["blankClassNumber"] as? String)
    }

    /// And none of them names the machinery.
    func testNoCourseSettingsSentenceNamesTheMachinery() throws {
        let forbidden: [String] = try UserFacingLabelWordsTests.forbiddenWords()
        let sentences: [String] = [
            CourseSettingsWording.localeLabel,
            CourseSettingsWording.localeCaption,
            CourseSettingsWording.colourSchemeNoneChosen,
            CourseSettingsWording.saveHeldBack(reason: ""),
        ]
        for sentence in sentences {
            let hits: [String] = UserFacingLabelWordsTests.forbiddenWords(in: sentence, from: forbidden)
            XCTAssertEqual(hits, [], "“\(sentence)” names the machinery")
        }
    }

    /// The scan itself: every string literal passed to a label-bearing call
    /// in the views, matched whole-word against the contract's list.
    func testNoLabelNamesTheMachinery() throws {
        let forbidden: [String] = try UserFacingLabelWordsTests.forbiddenWords()
        let viewsURL: URL = UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers/Views")
        let files: [URL] = UserFacingLabelWordsTests.swiftFiles(under: viewsURL)
        // A floor, so a scan that found no files cannot pass having read nothing.
        XCTAssertGreaterThan(files.count, 50, "The scan found only \(files.count) view files")

        var labelsRead: Int = 0
        var findings: [String] = []
        for file in files {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            var lineNumber: Int = 0
            for line in text.components(separatedBy: "\n") {
                lineNumber += 1
                for literal in UserFacingLabelWordsTests.labelLiterals(in: line) {
                    labelsRead += 1
                    let wordsOnScreen: String = UserFacingLabelWordsTests.withoutInterpolations(literal)
                    let hits: [String] = UserFacingLabelWordsTests.forbiddenWords(in: wordsOnScreen, from: forbidden)
                    if !hits.isEmpty {
                        findings.append(file.lastPathComponent + ":" + String(lineNumber) + " “" + literal + "” names " + hits.joined(separator: ", "))
                    }
                }
            }
        }
        XCTAssertGreaterThan(labelsRead, 250, "The scan read only \(labelsRead) labels; its pattern has stopped matching")
        XCTAssertEqual(findings, [], "Labels that name the machinery (CLAUDE.md rule 1)")
    }

    /// The matcher is whole-word, so "description" is not "script".
    func testTheMatchIsWholeWord() {
        let forbidden: [String] = ["script", "quartz", "json"]
        XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: "A description of the page", from: forbidden), [])
        XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: "Language / region (Quartz locale)", from: forbidden), ["quartz"])
        XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: "course_config.json", from: forbidden), ["json"])
        XCTAssertEqual(UserFacingLabelWordsTests.labelLiterals(in: "    // Text(\"Quartz\")"), [])
        XCTAssertEqual(UserFacingLabelWordsTests.labelLiterals(in: "Picker(\"Language\", selection: $x) {"), ["Language"])
        XCTAssertEqual(UserFacingLabelWordsTests.labelLiterals(in: "    .help(\"Edit this\")"), ["Edit this"])
        XCTAssertEqual(UserFacingLabelWordsTests.labelLiterals(in: "MyText(\"not a label call\")"), [])
    }

    /// Code interpolated into a label is not a word on screen: the sidebar's
    /// "No course or club matches “\(workspace.filterText)”." names a
    /// variable, not the machinery. The words around it are still read.
    func testInterpolatedCodeIsNotRead() {
        let forbidden: [String] = ["workspace", "docker"]
        let variable: String = "No course or club matches “\\(workspace.filterText)”."
        XCTAssertEqual(UserFacingLabelWordsTests.withoutInterpolations(variable), "No course or club matches “”.")
        XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: UserFacingLabelWordsTests.withoutInterpolations(variable), from: forbidden), [])
        let nested: String = "Opened \\(names(for: (a, b)).joined()) in the docker"
        XCTAssertEqual(UserFacingLabelWordsTests.withoutInterpolations(nested), "Opened  in the docker")
        XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: UserFacingLabelWordsTests.withoutInterpolations(nested), from: forbidden), ["docker"])
    }

    // MARK: - Helpers

    static func forbiddenWords() throws -> [String] {
        let block: [String: Any] = try SharedRulesContractTests.section("userFacingLabelWords")
        let words: [String] = try XCTUnwrap(block["forbidden"] as? [String])
        XCTAssertTrue(words.contains("quartz"))
        return words
    }

    /// The forbidden words `text` contains, whole-word and case-insensitive.
    static func forbiddenWords(in text: String, from forbidden: [String]) -> [String] {
        var hits: [String] = []
        for word in forbidden {
            let pattern: String = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z0-9_])"
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                hits.append(word)
            }
        }
        return hits
    }

    /// `literal` (as written in the source) with every interpolation —
    /// a backslash, then parentheses, nesting counted — taken out, so only
    /// the words a teacher reads are left to match.
    static func withoutInterpolations(_ literal: String) -> String {
        var wordsOnScreen: String = ""
        var depth: Int = 0
        var previousWasBackslash: Bool = false
        for character in literal {
            if depth > 0 {
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                }
                continue
            }
            if previousWasBackslash && character == "(" {
                // Drop the backslash already kept, and start skipping.
                wordsOnScreen.removeLast()
                depth = 1
                previousWasBackslash = false
                continue
            }
            wordsOnScreen.append(character)
            previousWasBackslash = (character == "\\") && !previousWasBackslash
        }
        return wordsOnScreen
    }

    /// The string literals passed straight to a label-bearing call on one
    /// line; nothing from a comment line.
    static func labelLiterals(in line: String) -> [String] {
        let trimmed: String = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") {
            return []
        }
        let calls: String = "Text|Picker|Toggle|Button|LabeledContent|TextField|SecureField|Label|DisclosureGroup|ExampleCaption|FormSectionHeader|Section"
        let modifiers: String = "help|navigationTitle|alert|confirmationDialog"
        let pattern: String = "(?:(?<![A-Za-z0-9_.])(?:" + calls + ")|\\.(?:" + modifiers + "))\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        var literals: [String] = []
        let range: NSRange = NSRange(line.startIndex..<line.endIndex, in: line)
        for match in expression.matches(in: line, options: [], range: range) {
            if let literalRange = Range(match.range(at: 1), in: line) {
                literals.append(String(line[literalRange]))
            }
        }
        return literals
    }

    static func macAppRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func swiftFiles(under folder: URL) -> [URL] {
        var files: [URL] = []
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return files
        }
        for case let url as URL in walker {
            if url.pathExtension == "swift" {
                files.append(url)
            }
        }
        files.sort { first, second in
            return first.path < second.path
        }
        return files
    }
}
