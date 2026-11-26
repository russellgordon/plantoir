import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// What VoiceOver is handed, read from the app's real views (#993, the
/// Mac HIG review's findings D16 to D20, D40, D41, and the first review's
/// findings): each view hosted in an off-screen window and read through the
/// accessibility API an assistive app uses (`AccessibilityTree`). A control
/// with no name, or one that says its name twice, fails here, where reading
/// the source could not tell (Add a Section's stepper read "Section number,
/// Section number" with every naming modifier in its place).
///
/// Apple's VoiceOver guidance: "Provide alternative labels for all key
/// interface elements"; its Accessibility guidance: "Convey information
/// with more than color alone."
@MainActor
final class AccessibilityTreeTests: XCTestCase {

    // MARK: - Functions

    /// Hosts `view` off screen in a window with a title no other window
    /// has, and reads its tree.
    func tree<Content: View>(of view: Content, size: NSSize = NSSize(width: 600, height: 520)) throws -> AccessibilityTree {
        let host: TableHost = TableHost(view, size: size)
        defer {
            host.close()
        }
        let title: String = "accessibility-tree-\(UUID().uuidString)"
        host.window.title = title
        host.pump(0.4)
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(host.window)
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: title)
        XCTAssertTrue(read.foundTheWindow, "the hosted window is not in the accessibility tree")
        return read
    }

    /// Fails with every control in the tree that has no name or says one
    /// twice.
    func assertEveryControlIsNamedOnce(in tree: AccessibilityTree, file: StaticString = #filePath, line: UInt = #line) {
        let faults: [String] = tree.controlsNotNamedOnce()
        XCTAssertEqual(faults, [], "controls not named exactly once:\n\(faults.joined(separator: "\n"))", file: file, line: line)
    }

    /// The reader itself sees both faults: a stepper given its title as a
    /// label too (as Add a Section's was) is named twice, and a text field
    /// with only a placeholder has no name. Without this, a reader that
    /// found nothing would pass every test below.
    func testTheReaderCatchesADoubledAndAMissingName() throws {
        let faulty: some View = VStack {
            Stepper("Section number", onIncrement: {}, onDecrement: {})
                .labelsHidden()
                .accessibilityLabel(Text("Section number"))
                .accessibilityIdentifier("doubledStepper")
            TextField("Filter", text: .constant(""))
                .accessibilityIdentifier("unnamedField")
        }
        let read: AccessibilityTree = try tree(of: faulty)
        let faults: [String] = read.controlsNotNamedOnce()
        var sawTheDoubledStepper: Bool = false
        var sawTheUnnamedField: Bool = false
        for fault in faults {
            if fault.contains("doubledStepper") {
                sawTheDoubledStepper = true
            }
            if fault.contains("unnamedField") && fault.hasPrefix("no name") {
                sawTheUnnamedField = true
            }
        }
        XCTAssertTrue(sawTheDoubledStepper, "a stepper named twice was not caught:\n\(read.described())")
        XCTAssertTrue(sawTheUnnamedField, "a field with no name was not caught:\n\(read.described())")
    }

    /// The tab bar's group is named, by the title it is given: the window's
    /// (D16). Before #993 the radio group had no name at all.
    func testTheTabBarIsNamedByTheTitleItIsGiven() throws {
        let tabs: DetailTabs<Int> = DetailTabs(
            tabs: [(tab: 1, title: "Website"), (tab: 2, title: "Coverage")],
            selection: .constant(1), name: "EXC2O-S1", identifier: "sectionTabs"
        )
        let read: AccessibilityTree = try tree(of: tabs)
        let bar: AccessibilityTree.Element = try XCTUnwrap(read.element(identifiedAs: "sectionTabs"))
        XCTAssertEqual(bar.role, "AXRadioGroup")
        XCTAssertEqual(bar.names, ["EXC2O-S1"])
        assertEveryControlIsNamedOnce(in: read)
    }

    /// The emoji field takes its row's label (D40) and the palette button is
    /// named in words (D18), not "face.smiling".
    func testTheEmojiFieldAndButtonAreNamed() throws {
        let field: some View = Form {
            EmojiChoiceField(label: "Emoji", emoji: .constant("📚"))
        }
        let read: AccessibilityTree = try tree(of: field)
        XCTAssertEqual(read.element(identifiedAs: "emojiChoiceField")?.names, ["Emoji"])
        XCTAssertEqual(read.element(identifiedAs: "emojiPaletteButton")?.names, [AccessibilityNames.chooseEmoji])
        assertEveryControlIsNamedOnce(in: read)
    }

    /// Add a Section: the number field is named by the words printed beside
    /// it, and its stepper says that name once (D18, the first review).
    func testAddASectionNamesTheNumberOnce() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let read: AccessibilityTree = try tree(of: AddSectionSheet(course: made.course, onAdd: { (_: Int) in }))
        XCTAssertEqual(read.element(identifiedAs: "addSectionNumberField")?.names, [AccessibilityNames.sectionNumber])
        XCTAssertEqual(read.element(identifiedAs: "addSectionStepper")?.names, [AccessibilityNames.sectionNumber])
        assertEveryControlIsNamedOnce(in: read)
    }

    /// The Class Dates sheet's typing area (D41) and its "Where these came
    /// from" field (the first review) are named; the field's placeholder
    /// alone gave it no name.
    func testTheClassDatesSheetsFieldsAreNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let read: AccessibilityTree = try tree(of: SectionScheduleSheet(course: made.course, sectionNumber: 1))
        XCTAssertEqual(read.element(identifiedAs: "sectionScheduleTypedField")?.names, [AccessibilityNames.classDates()])
        XCTAssertEqual(read.element(identifiedAs: "sectionScheduleSourceField")?.names, ["Where these came from"])
        assertEveryControlIsNamedOnce(in: read)
    }

    /// Publish Pages: the table of pages (D41) and Find a Page, whose
    /// placeholder alone gave it no name, are named.
    func testThePagePickerSheetIsNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let model: SectionVerbSheetModel = PageTablesSheetTests.pickerModel(course: made.course, classes: 3, pages: 2)
        let read: AccessibilityTree = try tree(of: SectionVerbSheet(model: model, pressDefault: {}, cancel: {}))
        XCTAssertEqual(read.element(identifiedAs: "sectionVerbSheetPickerTable")?.names, [AccessibilityNames.pagesTable])
        XCTAssertEqual(read.element(identifiedAs: "sectionVerbSheetSearch")?.names, [AssistWording.menuFindAPage])
        assertEveryControlIsNamedOnce(in: read)
    }

    /// The spinner a restored window shows while its folder opens is named
    /// (D18); a bare `ProgressView` gave VoiceOver nothing.
    func testTheRestoringFolderSpinnerIsNamed() throws {
        let read: AccessibilityTree = try tree(of: RestoringFolderPlaceholder())
        let spinner: AccessibilityTree.Element = try XCTUnwrap(read.element(identifiedAs: "restoringFolderPlaceholder"))
        XCTAssertEqual(spinner.role, "AXBusyIndicator")
        XCTAssertEqual(spinner.names, [AccessibilityNames.openingFolder])
    }

    /// Copy a Page's problem line (D19) is #994's stopping sentence: the
    /// stop symbol is drawn inside it, so it is told apart by more than its
    /// red, and VoiceOver is handed the words alone, not the symbol's name.
    func testCopyAPageProblemLineIsNotColourAlone() throws {
        let sheet: String = try AccessibilityNamesTests.source("Views/CopyPage/CopyPageSheet.swift")
        XCTAssertNotNil(
            sheet.range(of: "StatusColour.blocking.sentence(problem)"),
            "Copy a Page's problem line is not drawn as a stopping sentence"
        )

        let words: String = "A page called Unit 1 is already there."
        let read: AccessibilityTree = try tree(of: StatusColour.blocking.sentence(words).accessibilityIdentifier("copyPageProblem"))
        let line: AccessibilityTree.Element = try XCTUnwrap(read.element(identifiedAs: "copyPageProblem"))
        XCTAssertEqual(line.value, words, "VoiceOver is not handed the sentence's words alone")
        XCTAssertTrue(line.label.isEmpty || line.label == words, "the line carries a name besides its words: \(line.label)")

        // The symbol is drawn: the sentence is wider than its words alone.
        let sentenceWidth: CGFloat = NSHostingView(rootView: StatusColour.blocking.sentence(words).fixedSize()).fittingSize.width
        let wordsWidth: CGFloat = NSHostingView(rootView: Text(words).fixedSize()).fittingSize.width
        XCTAssertGreaterThan(sentenceWidth, wordsWidth + 8, "no symbol is drawn before the words")
    }

    // MARK: - The sidebar (#997)

    /// The help tags in a sidebar `width` points wide (228, the sidebar's
    /// default) holding one course code's label.
    func helpTags(ofCourseCode code: String, width: CGFloat = 228) throws -> (helps: [String], described: String) {
        // A plain row, because inside the sidebar's folding course row the
        // label is merged into one heading and this reader does not find its
        // help tag there (measured 2026-11-20). The real row was proven by
        // the second review of #997: the folding row's heading carries the
        // help text for a truncated code, a real hover drew the tooltip, and
        // a code that fits has none.
        let row: some View = List {
            CourseCodeLabel(code: code)
        }
        .listStyle(.sidebar)
        let read: AccessibilityTree = try tree(of: row, size: NSSize(width: width, height: 200))
        var helps: [String] = []
        for element in read.elements {
            if !element.help.isEmpty {
                helps.append(element.help)
            }
        }
        return (helps, read.described())
    }

    /// A course code cut short in its row carries its whole code as a help
    /// tag (D44), so it can still be read: a 12-character code, the most a
    /// code may have, in a row 140 points wide, where it is cut short.
    func testATruncatedCourseCodeShowsItsWholeCodeOnHover() throws {
        let code: String = "WWWWWWWWWWWW"
        let read = try helpTags(ofCourseCode: code, width: 140)
        XCTAssertTrue(read.helps.contains(code), "no help tag carries the cut-short code \(code); help tags: \(read.helps)\n\(read.described)")
    }

    /// A code that fits is not repeated in a tag over itself (D44): the
    /// HIG's expansion tooltip is for clipped or truncated text.
    func testACourseCodeThatFitsHasNoHelpTag() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let code: String = made.course.displayCode
        let read = try helpTags(ofCourseCode: code)
        XCTAssertFalse(read.helps.contains(code), "the code \(code) fits, yet carries a help tag; help tags: \(read.helps)\n\(read.described)")
    }

    /// The Backups heading's total keeps the sidebar's margin on its
    /// trailing side (D45). The heading's row, read off the tree, runs to
    /// within a point or two of the sidebar's trailing edge, and the total
    /// is pushed to its end, so the room the total has is the row's own
    /// trailing room plus the margin the heading keeps; that is at least the
    /// room the heading's name has on its leading side. Without the margin
    /// it sat about 2 pt from the divider.
    func testTheBackupsTotalKeepsTheSidebarsMargin() throws {
        let sidebar: some View = List {
            Section(isExpanded: .constant(true)) {
                Label("All Backups", systemImage: "square.stack.3d.up")
            } header: {
                BackupsSectionHeader(total: "271 KB")
            }
        }
        .listStyle(.sidebar)
        let read: AccessibilityTree = try tree(of: sidebar, size: NSSize(width: 228, height: 200))
        let heading: AccessibilityTree.Element = try XCTUnwrap(read.element(identifiedAs: "backupsTotal"))
        var list: AccessibilityTree.Element?
        for element in read.elements {
            if list == nil && element.role == "AXOutline" {
                list = element
            }
        }
        let column: CGRect = try XCTUnwrap(list, "no sidebar list in the tree:\n\(read.described())").frame
        XCTAssertFalse(column.isNull || heading.frame.isNull, "a frame was not read")
        let leadingRoom: CGFloat = heading.frame.minX - column.minX
        let rowTrailingRoom: CGFloat = column.maxX - heading.frame.maxX

        // The margin is really drawn: the heading asks for that much more
        // width than the same heading without it.
        let withMargin: CGFloat = NSHostingView(rootView: BackupsSectionHeader(total: "271 KB").fixedSize()).fittingSize.width
        let without: CGFloat = NSHostingView(rootView: HStack {
            Text("Backups")
            Spacer()
            Text("271 KB")
        }.fixedSize()).fittingSize.width
        let drawnMargin: CGFloat = withMargin - without
        let totalsRoom: CGFloat = rowTrailingRoom + drawnMargin
        print("AccessibilityTreeTests: Backups heading \(heading.frame) in \(column); name's room \(leadingRoom), "
              + "row's trailing room \(rowTrailingRoom), margin drawn \(drawnMargin)")
        XCTAssertEqual(drawnMargin, BackupsSectionHeader.trailingMargin, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            totalsRoom, leadingRoom - 1,
            "the total sits \(totalsRoom) pt from the sidebar's edge; the heading's name has \(leadingRoom) pt"
        )
    }
}
