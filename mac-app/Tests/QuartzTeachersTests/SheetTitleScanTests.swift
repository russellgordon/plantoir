import XCTest
@testable import QuartzTeachers

/// Every sheet's title is `SheetTitle` — `.headline`, in a 52-point band, or
/// the two-line shape when an explanation sits under it (#457 item 4, the HIG
/// sweep; Canopy's mac-window-conventions §3a).
///
/// Pinned by an explicit LIST of sheet views, plus a census that every
/// `.sheet(` in the app presents something on that list: "the body starts
/// with SheetTitle(" could not see the rename sheet (a function, not a file),
/// Class Dates (its title is inside `header`) or the wizard (inside
/// `wizardContent`) — the plan review's finding 7.
@MainActor
final class SheetTitleScanTests: XCTestCase {

    // MARK: - Stored properties

    /// Each sheet, the file it is written in, and whether its title carries
    /// an explanation (the two-line shape) or sits in the band.
    static let sheets: [(view: String, file: String, explained: Bool)] = [
        ("NewCourseWizardView", "Wizard/NewCourseWizardView.swift", false),
        ("KeepACopyForReferenceSheet", "Wizard/KeepACopyForReferenceSheet.swift", true),
        ("ImportCoursesForReferenceSheet", "Wizard/ImportCoursesForReferenceSheet.swift", false),
        ("SetSchoolYearSheet", "Wizard/SetSchoolYearSheet.swift", false),
        ("AddSectionSheet", "Wizard/AddSectionSheet.swift", true),
        ("CopyPageSheet", "CopyPage/CopyPageSheet.swift", false),
        ("LinksChecklistSheet", "Section/LinksChecklistSheet.swift", false),
        ("StartOfYearSheet", "Section/StartOfYearSheet.swift", false),
        ("ScheduleDeploySheet", "Section/ScheduleDeploySheet.swift", false),
        ("SectionScheduleSheet", "Section/SectionScheduleSheet.swift", true),
        ("SectionScheduleCourseMissingView", "Section/SectionScheduleSheet.swift", false),
        ("SpecialFoldersHelpView", "CourseSettings/SpecialFoldersHelpView.swift", true),
        ("UnitWordRenameSheet", "CourseSettings/UnitWordRenameSheet.swift", false),
        ("CredentialRequestSheet", "Console/CredentialRequestSheet.swift", true),
        ("renameSheet", "CourseSettings/StringListEditorView.swift", false),
        // Batch B's sheet for the Section menu's functions (#457 item 3);
        // its Class Dates kind presents `SectionScheduleSheet` itself.
        ("SectionVerbSheet", "Section/SectionVerbSheet.swift", false),
        // #454: asking before adding Plantoir's section to a teacher's own
        // AGENTS.md or CLAUDE.md; the file it found is said under the title.
        ("AgentGuidanceSheet", "AgentGuidanceSheet.swift", true),
    ]

    // MARK: - Tests

    /// Seventeen sheets (fifteen, batch B's and #454's), each titled through `SheetTitle`, in the shape it is
    /// listed with — and no title in those files at `.title2` or larger.
    func testEverySheetIsTitledByTheOneShape() throws {
        XCTAssertEqual(SheetTitleScanTests.sheets.count, 17)
        var problems: [String] = []
        for sheet in SheetTitleScanTests.sheets {
            let source: String = try SheetTitleScanTests.source(of: sheet.file)
            let body: String = SheetTitleScanTests.body(of: sheet.view, in: source)
            if body.isEmpty {
                problems.append(sheet.view + ": not found in " + sheet.file)
                continue
            }
            let titled: Bool = SheetTitleScanTests.callsSheetTitle(body)
            let explained: Bool = body.contains("explanation:")
            let banded: Bool = titled && !explained
            if !titled {
                problems.append(sheet.view + " is not titled by SheetTitle")
            } else if sheet.explained && !explained {
                problems.append(sheet.view + " has an explanation under its title and must use the two-line shape")
            } else if !sheet.explained && !banded {
                problems.append(sheet.view + " sits in the band")
            }
            let code: String = TextFieldStyleScanTests.codeWithoutComments(source)
            for size in [".title2", ".title)", ".title3", ".largeTitle"] {
                if code.contains(".font(" + size) {
                    problems.append(sheet.file + " sets a title at " + size)
                }
            }
        }
        XCTAssertEqual(problems, [], "One shape for every sheet's title (#457, C15/C16)")
    }

    /// Every `.sheet(` in the app presents a view on the list above, so a
    /// new sheet cannot arrive without being looked at.
    func testEverySheetPresentedIsOnTheList() throws {
        var names: [String] = []
        for sheet in SheetTitleScanTests.sheets {
            names.append(sheet.view)
        }
        var presentations: Int = 0
        var problems: [String] = []
        let root: URL = UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers")
        for file in UserFacingLabelWordsTests.swiftFiles(under: root) {
            let text: String = try String(contentsOf: file, encoding: .utf8)
            var blocks: [SheetConventionScanTests.Block] = []
            for marker in [".sheet(isPresented:", ".sheet(item:"] {
                for block in SheetTitleScanTests.presentations(after: marker, in: text, file: file.lastPathComponent) {
                    blocks.append(block)
                }
            }
            for block in blocks {
                presentations += 1
                var found: Bool = false
                for name in names where block.text.contains(name + "(") {
                    found = true
                }
                if !found {
                    problems.append(block.location + " presents a sheet that is not on SheetTitleScanTests.sheets")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(presentations, 16, "The census found only \(presentations) sheets; its pattern has stopped matching")
        XCTAssertEqual(problems, [], "Every sheet is on the list, so each is titled the one way")
    }

    /// The scan itself: a wording function named `sheetTitle` is not the
    /// modifier, and the modifier is seen after a closing bracket.
    func testTheScanTellsTheModifierFromAWordingFunction() {
        XCTAssertFalse(SheetTitleScanTests.callsSheetTitle("Text(CopyPageWording.sheetTitle(course: code))"))
        XCTAssertTrue(SheetTitleScanTests.callsSheetTitle("VStack { }\n.sheetTitle(\"Schedule a deploy\")"))
        XCTAssertTrue(SheetTitleScanTests.callsSheetTitle("SheetTitle(\"New Course or Club\")"))
        XCTAssertFalse(SheetTitleScanTests.callsSheetTitle("// .sheetTitle(\"in a comment\")"))
    }

    // MARK: - Helpers

    /// Whether `body` applies `.sheetTitle(` as a modifier or builds a
    /// `SheetTitle(` — not a wording function that happens to share the
    /// name (`CopyPageWording.sheetTitle(course:)`).
    static func callsSheetTitle(_ body: String) -> Bool {
        let characters: [Character] = Array(TextFieldStyleScanTests.codeWithoutComments(body))
        var index: Int = 0
        while index < characters.count {
            for word in [".sheetTitle(", "SheetTitle("] where TextFieldStyleScanTests.matches(word, in: characters, at: index) {
                let before: Character? = index > 0 ? characters[index - 1] : nil
                if before == nil || !(before!.isLetter || before!.isNumber || before! == "_" || before! == ".") {
                    return true
                }
            }
            index += 1
        }
        return false
    }

    static func source(of file: String) throws -> String {
        return try String(contentsOf: TextFieldStyleScanTests.viewsURL().appendingPathComponent(file), encoding: .utf8)
    }

    /// A view's `var body` (or, for a function, its own body), with any
    /// computed parts it is built from that carry the title (`header`,
    /// `wizardContent`).
    static func body(of view: String, in source: String) -> String {
        if view.first?.isLowercase == true {
            return SheetConventionScanTests.functionBody(named: view, in: source)
        }
        guard let start = source.range(of: "struct " + view + ":") ?? source.range(of: "struct " + view + " ") else {
            return ""
        }
        var rest: String = String(source[start.upperBound...])
        if let next = rest.range(of: "\nstruct ") {
            rest = String(rest[rest.startIndex..<next.lowerBound])
        }
        var result: String = ""
        for part in ["var body: some View", "var header: some View", "var wizardContent: some View"] {
            if let found = rest.range(of: part) {
                let tail: String = String(rest[found.lowerBound...])
                let blocks: [SheetConventionScanTests.Block] = SheetConventionScanTests.blocks(after: part, in: tail, file: view)
                if let first = blocks.first {
                    result += first.text
                }
            }
        }
        return result
    }

    /// The content closure of each `.sheet(…)` presentation.
    static func presentations(after marker: String, in source: String, file: String) -> [SheetConventionScanTests.Block] {
        let original: [Character] = Array(source)
        let masked: [Character] = TextFieldStyleScanTests.maskingStrings(Array(TextFieldStyleScanTests.codeWithoutComments(source)))
        var result: [SheetConventionScanTests.Block] = []
        var index: Int = 0
        while index < masked.count {
            if TextFieldStyleScanTests.matches(marker, in: masked, at: index) {
                let open: Int = index + 6
                let end: Int = TextFieldStyleScanTests.closing(from: open, in: masked, open: "(", close: ")")
                var cursor: Int = end
                while cursor < masked.count && masked[cursor].isWhitespace {
                    cursor += 1
                }
                var closureEnd: Int = end
                if cursor < masked.count && masked[cursor] == "{" {
                    closureEnd = TextFieldStyleScanTests.closing(from: cursor, in: masked, open: "{", close: "}")
                }
                result.append(SheetConventionScanTests.Block(
                    location: file + ":" + String(SheetConventionScanTests.lineNumber(of: index, in: original)),
                    text: String(original[index..<closureEnd])
                ))
            }
            index += 1
        }
        return result
    }
}
