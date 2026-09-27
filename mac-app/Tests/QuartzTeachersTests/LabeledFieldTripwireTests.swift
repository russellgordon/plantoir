import XCTest

/// No text field inside a labelled row carries a title of its own (#354).
///
/// In a grouped form a `TextField("Unit", …)` draws its title BESIDE the
/// field, so a row already labelled by `LabeledContent` reads its label twice:
/// the setup wizard said "What do you call a unit?  Unit [Unit]". The fix is
/// an empty title, with the placeholder kept through `prompt:` — the shape the
/// wizard's club branch always had. A visual fault no unit test can SEE, so
/// this reads the source instead: every `TextField(` or `SecureField(` inside
/// a `LabeledContent(…) { … }` body under `QuartzTeachers/Views` must have
/// `""` as its title. The opt-in `UnitWordRowUITests` checks the real window.
final class LabeledFieldTripwireTests: XCTestCase {

    // MARK: - Functions

    private static func viewsFolder() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views")
    }

    /// The index just past the bracket that closes the one opened just before
    /// `start`, or nil when the text ends first.
    private static func indexPastClosing(_ open: Character, _ close: Character,
                                         in characters: [Character], from start: Int) -> Int? {
        var depth: Int = 1
        var index: Int = start
        while index < characters.count {
            let character: Character = characters[index]
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return nil
    }

    /// Each titled field found inside a labelled row, as "file:line title".
    static func titledFieldsInLabelledRows(in text: String, fileName: String) -> [String] {
        let characters: [Character] = Array(text)
        let rowOpening: [Character] = Array("LabeledContent(")
        var found: [String] = []
        var index: Int = 0
        while index + rowOpening.count <= characters.count {
            if Array(characters[index..<(index + rowOpening.count)]) != rowOpening {
                index += 1
                continue
            }
            guard let pastLabel = indexPastClosing("(", ")", in: characters, from: index + rowOpening.count) else {
                break
            }
            // Only the trailing-closure form: `LabeledContent("…") {`.
            var braceIndex: Int = pastLabel
            while braceIndex < characters.count && (characters[braceIndex] == " " || characters[braceIndex] == "\n") {
                braceIndex += 1
            }
            guard braceIndex < characters.count, characters[braceIndex] == "{",
                  let pastBody = indexPastClosing("{", "}", in: characters, from: braceIndex + 1) else {
                index = pastLabel
                continue
            }
            let body: String = String(characters[braceIndex..<pastBody])
            let lineOfBody: Int = lineNumber(of: braceIndex, in: characters)
            for fieldKind in ["TextField(", "SecureField("] {
                var searchStart: String.Index = body.startIndex
                while let fieldRange = body.range(of: fieldKind, range: searchStart..<body.endIndex) {
                    let rest: Substring = body[fieldRange.upperBound...]
                    let title: String
                    if let comma = rest.firstIndex(of: ",") {
                        title = rest[rest.startIndex..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        title = ""
                    }
                    if title != "\"\"" {
                        let linesBefore: Int = body[body.startIndex..<fieldRange.lowerBound]
                            .components(separatedBy: "\n").count - 1
                        found.append("\(fileName):\(lineOfBody + linesBefore) \(fieldKind)\(title), …")
                    }
                    searchStart = fieldRange.upperBound
                }
            }
            index = pastBody
        }
        return found
    }

    private static func lineNumber(of position: Int, in characters: [Character]) -> Int {
        var line: Int = 1
        var index: Int = 0
        while index < position {
            if characters[index] == "\n" {
                line += 1
            }
            index += 1
        }
        return line
    }

    // MARK: - Tests

    func testNoFieldInALabelledRowCarriesATitleOfItsOwn() throws {
        let folder: URL = LabeledFieldTripwireTests.viewsFolder()
        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil
        )
        var filesRead: Int = 0
        var labelledRowsSeen: Int = 0
        var offenders: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension != "swift" {
                continue
            }
            let text: String = try String(contentsOf: fileURL, encoding: .utf8)
            filesRead += 1
            labelledRowsSeen += text.components(separatedBy: "LabeledContent(").count - 1
            let found: [String] = LabeledFieldTripwireTests.titledFieldsInLabelledRows(
                in: text, fileName: fileURL.lastPathComponent
            )
            for offender in found {
                offenders.append(offender)
            }
        }
        // Positive controls: the scan read the real folder and met real rows,
        // so an empty list of offenders is not an empty scan.
        XCTAssertGreaterThan(filesRead, 50, "Read too few view files — is the path right? \(folder.path)")
        XCTAssertGreaterThan(labelledRowsSeen, 10)
        XCTAssertEqual(
            offenders, [],
            "A field inside a LabeledContent row has a title, which a grouped form draws beside it (#354). "
            + "Give it \"\" and keep the placeholder with prompt:."
        )
    }

    func testTheScanFindsATitledField() {
        let sample: String = """
        LabeledContent("What do you call a unit?") {
            TextField("Unit", text: $unitWord, prompt: Text("Unit"))
        }
        LabeledContent("Name") {
            TextField("", text: $name)
        }
        """
        XCTAssertEqual(
            LabeledFieldTripwireTests.titledFieldsInLabelledRows(in: sample, fileName: "Sample.swift"),
            ["Sample.swift:2 TextField(\"Unit\", …"]
        )
    }
}
