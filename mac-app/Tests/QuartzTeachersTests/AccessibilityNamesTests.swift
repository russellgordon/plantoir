import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Every control has a name VoiceOver can read, and no state is shown by
/// colour alone (#993, the Mac HIG review's findings D16 to D20, D40, D41).
///
/// Apple's VoiceOver guidance: "Provide alternative labels for all key
/// interface elements" and "Exclude purely decorative images from
/// VoiceOver"; its Accessibility guidance: "Convey information with more
/// than color alone."
///
/// Two kinds of check. Where a control can be drawn on its own, it is
/// hosted in a window and its name is read back from the accessibility
/// tree AppKit builds for it, the tree VoiceOver reads. Where a control
/// lives deep inside a sheet that needs a whole course to draw, the check
/// reads the view's source for the modifier that names it; each of those
/// fails on the code before #993.
@MainActor
final class AccessibilityNamesTests: XCTestCase {

    // MARK: - Functions

    /// The section's and the course's tab bars are named (D16): before, the
    /// segmented control's group had only an identifier.
    @MainActor
    func testTheTabBarIsNamedInTheAccessibilityTree() throws {
        let bar: DetailTabs<Int> = DetailTabs(
            tabs: [(tab: 0, title: "Website"), (tab: 1, title: "Coverage")],
            selection: .constant(0),
            name: AccessibilityNames.sectionTabs,
            identifier: "sectionTabs"
        )
        let label: String? = AccessibilityNamesTests.label(ofIdentifier: "sectionTabs", in: bar)
        XCTAssertEqual(label, AccessibilityNames.sectionTabs)
    }

    /// The emoji palette button is named in words (D18), not "face.smiling".
    @MainActor
    func testTheEmojiButtonIsNamedInTheAccessibilityTree() throws {
        let field: EmojiChoiceField = EmojiChoiceField(label: "Header emoji", emoji: .constant("🧪"))
        let buttonLabel: String? = AccessibilityNamesTests.label(ofIdentifier: "emojiPaletteButton", in: field)
        XCTAssertEqual(buttonLabel, AccessibilityNames.chooseEmoji)
        // The emoji field itself takes its row's label (D40).
        let fieldLabel: String? = AccessibilityNamesTests.label(ofIdentifier: "emojiChoiceField", in: field)
        XCTAssertEqual(fieldLabel, "Header emoji")
    }

    /// Both bars are given their names where they are drawn.
    func testBothTabBarsArePassedTheirNames() throws {
        let section: String = try AccessibilityNamesTests.source("Views/Section/SectionDetailView.swift")
        XCTAssertNotNil(section.range(of: "name: AccessibilityNames.sectionTabs,"))
        let course: String = try AccessibilityNamesTests.source("Views/CourseSettings/CourseDetailView.swift")
        XCTAssertNotNil(course.range(of: "name: AccessibilityNames.courseTabs,"))
        XCTAssertNotEqual(AccessibilityNames.sectionTabs, AccessibilityNames.courseTabs)
    }

    /// The send button says "Send" (D17), not its symbol's name.
    func testTheSendButtonIsNamed() throws {
        let view: String = try AccessibilityNamesTests.source("Views/Assist/AssistWindowView.swift")
        let named: String = ".accessibilityLabel(Text(AccessibilityNames.send))\n            .accessibilityIdentifier(\"assistSendButton\")"
        XCTAssertNotNil(view.range(of: named))
        XCTAssertEqual(AccessibilityNames.send, "Send")
    }

    /// The sheets' unnamed controls and tables (D18, D41) each carry a name.
    func testTheSheetsControlsAndTablesAreNamed() throws {
        let expected: [(file: String, name: String, identifier: String)] = [
            ("Views/Section/SectionVerbSheet.swift", "classDate", "sectionVerbSheetDay"),
            ("Views/Section/SectionVerbSheet.swift", "makeRoomClass", "sectionVerbSheetClass"),
            ("Views/Section/SectionVerbSheet.swift", "makeRoomHowMany", "sectionVerbSheetHowMany"),
            ("Views/Section/SectionVerbSheet.swift", "addClassWay", "sectionVerbSheetAddClassWay"),
            ("Views/Section/SectionVerbSheet.swift", "planTable", "sectionVerbSheetPlanTable"),
            ("Views/Section/SectionVerbSheet.swift", "sourceTable", "sectionVerbSheetSourceTable"),
            ("Views/Section/SectionVerbSheet.swift", "pagesTable", "sectionVerbSheetPickerTable"),
            ("Views/Section/SectionVerbSheetRollOver.swift", "rollOverWebsite", "sectionVerbSheetRollOverWebsite"),
            ("Views/Section/StartOfYearSheet.swift", "planTable", "startOfYearPlanTable"),
            ("Views/Section/SectionScheduleSheet.swift", "classDates", "sectionScheduleTypedField"),
            ("Views/Wizard/AddSectionSheet.swift", "sectionNumber", "addSectionNumberField"),
            ("Views/Wizard/AddSectionSheet.swift", "sectionNumber", "addSectionStepper"),
        ]
        for entry in expected {
            let view: String = try AccessibilityNamesTests.source(entry.file)
            let named: String = ".accessibilityLabel(Text(AccessibilityNames.\(entry.name)))"
            XCTAssertTrue(
                AccessibilityNamesTests.modifier(named, comesJustBefore: entry.identifier, in: view),
                "\(entry.identifier) in \(entry.file) is not named \(entry.name)"
            )
        }
        let verbSheet: String = try AccessibilityNamesTests.source("Views/Section/SectionVerbSheet.swift")
        XCTAssertNotNil(verbSheet.range(of: ".flexibleTableHeight(laterClassesTableHeight)\n        .accessibilityLabel(Text(AccessibilityNames.laterClassesTable))"))
    }

    /// The wizard's and Keep a Copy's text fields, drawn with an empty title
    /// beside a written-out label, are named by that label (D18).
    func testTheWizardsTextFieldsAreNamed() throws {
        let wizard: String = try AccessibilityNamesTests.source("Views/Wizard/NewCourseWizardView.swift")
        let expected: [(label: String, identifier: String)] = [
            ("WizardWording.panelWords(isClub: isClubCourse).nameLabel", "wizardCourseNameField"),
            ("\"Short label\"", "wizardCustomShortNameField"),
            ("\"Timetable section numbers\"", "wizardSectionNumbersField"),
            ("WizardWording.clubClassFolderLabel", "clubClassFolderField"),
            ("WizardWording.clubFrontPageHeadingLabel", "clubFrontPageHeadingField"),
            ("WizardWording.clubPageWordLabel", "unitWordField"),
            ("UnitWordRenameWording.fieldLabel", "unitWordField"),
        ]
        for entry in expected {
            let named: String = ".accessibilityLabel(Text(\(entry.label)))"
            XCTAssertTrue(
                AccessibilityNamesTests.modifier(named, comesJustBefore: entry.identifier, in: wizard),
                "\(entry.identifier) is not named \(entry.label)"
            )
        }
        let keepACopy: String = try AccessibilityNamesTests.source("Views/Wizard/KeepACopyForReferenceSheet.swift")
        XCTAssertTrue(AccessibilityNamesTests.modifier(
            ".accessibilityLabel(Text(\"Folder name\"))", comesJustBefore: "keepACopyFolderName", in: keepACopy
        ))
    }

    /// Course Settings' tables are named by their titles (D40).
    func testCourseSettingsTablesAreNamed() throws {
        let lists: String = try AccessibilityNamesTests.source("Views/CourseSettings/StringListEditorView.swift")
        XCTAssertTrue(AccessibilityNamesTests.modifier(".accessibilityLabel(Text(title))", comesJustBefore: "table-\\(title)", in: lists))
        let toggles: String = try AccessibilityNamesTests.source("Views/CourseSettings/MembershipToggleListView.swift")
        XCTAssertTrue(AccessibilityNamesTests.modifier(".accessibilityLabel(Text(title))", comesJustBefore: "table-\\(title)", in: toggles))
        let sidebar: String = try AccessibilityNamesTests.source("Views/CourseSettings/SidebarVisibilityTableView.swift")
        XCTAssertTrue(AccessibilityNamesTests.modifier(".accessibilityLabel(Text(\"Sidebar Visibility\"))", comesJustBefore: "sidebarVisibilityTable", in: sidebar))
        let settings: String = try AccessibilityNamesTests.source("Views/CourseSettings/CourseSettingsView.swift")
        XCTAssertTrue(AccessibilityNamesTests.modifier(".accessibilityLabel(Text(\"Course name\"))", comesJustBefore: "courseNameField", in: settings))
    }

    /// An information icon beside a sentence is hidden from VoiceOver (D20),
    /// which read the unsaved-settings one as "Info".
    func testInformationIconsBesideASentenceAreHidden() throws {
        let files: [String] = [
            "Views/Section/ScheduleDeploySheet.swift",
            "Views/Section/UnsavedSettingsNoticeView.swift",
            "Views/CourseSettings/CourseSettingsView.swift",
            "Views/CourseSettings/PublishingChoiceView.swift",
            "Views/AgentGuidanceSheet.swift",
        ]
        for file in files {
            let view: String = try AccessibilityNamesTests.source(file)
            let icons: Int = AccessibilityNamesTests.count(of: "Image(systemName: \"info.circle\")", in: view)
            let hidden: Int = AccessibilityNamesTests.count(of: "Image(systemName: \"info.circle\")\n", followedWithin: 260, by: ".accessibilityHidden(true)", in: view)
            XCTAssertGreaterThan(icons, 0, file)
            XCTAssertEqual(hidden, icons, "an info icon in \(file) is still read by VoiceOver")
        }
        let token: String = try AccessibilityNamesTests.source("Views/Section/DeployTokenEndNoticeView.swift")
        XCTAssertEqual(AccessibilityNamesTests.count(of: "Image(systemName: \"exclamationmark.triangle\")\n", followedWithin: 260, by: ".accessibilityHidden(true)", in: token), 1)
    }

    /// The deploy checklist says each destination's state in a word (D19),
    /// one word per state, the four told apart.
    func testEachDeployDestinationStateHasItsOwnWord() {
        let waiting: String = DeployDestinationChecklist.stateName(isFinished: false, succeeded: false, isRunning: false)
        let deploying: String = DeployDestinationChecklist.stateName(isFinished: false, succeeded: false, isRunning: true)
        let done: String = DeployDestinationChecklist.stateName(isFinished: true, succeeded: true, isRunning: false)
        let failed: String = DeployDestinationChecklist.stateName(isFinished: true, succeeded: false, isRunning: false)
        XCTAssertEqual(waiting, AccessibilityNames.destinationWaiting)
        XCTAssertEqual(deploying, AccessibilityNames.destinationDeploying)
        XCTAssertEqual(done, AccessibilityNames.destinationDone)
        XCTAssertEqual(failed, AccessibilityNames.destinationFailed)
        XCTAssertEqual(Set([waiting, deploying, done, failed]).count, 4)
    }

    /// Copy a Page's problem line carries a named warning symbol (D19), so
    /// it is told apart by more than its orange.
    func testCopyAPageProblemLineIsNotColourAlone() throws {
        let view: String = try AccessibilityNamesTests.source("Views/CopyPage/CopyPageSheet.swift")
        XCTAssertNotNil(view.range(of: ".accessibilityLabel(Text(AccessibilityNames.warning))\n                    Text(problem)"))
    }

    /// The assistant's breathing dots stand still under Reduce Motion.
    func testTheTypingDotsStandStillUnderReduceMotion() throws {
        XCTAssertTrue(AssistTypingIndicator.breathes(whenReduceMotionIsOn: false))
        XCTAssertFalse(AssistTypingIndicator.breathes(whenReduceMotionIsOn: true))
        let view: String = try AccessibilityNamesTests.source("Views/Assist/AssistChatBubble.swift")
        XCTAssertNotNil(view.range(of: "@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertNotNil(view.range(of: "reducesMotion ? nil : Animation.easeInOut"))
    }

    /// A view's source, read from the app's own folder.
    static func source(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// True when `modifier` is the line just above the
    /// `.accessibilityIdentifier("identifier")` line somewhere in `text`.
    static func modifier(_ modifier: String, comesJustBefore identifier: String, in text: String) -> Bool {
        let lines: [String] = text.components(separatedBy: "\n")
        let identifierLine: String = ".accessibilityIdentifier(\"\(identifier)\")"
        var index: Int = 1
        while index < lines.count {
            let current: String = lines[index].trimmingCharacters(in: .whitespaces)
            let above: String = lines[index - 1].trimmingCharacters(in: .whitespaces)
            if current == identifierLine && above == modifier {
                return true
            }
            index += 1
        }
        return false
    }

    static func count(of needle: String, in text: String) -> Int {
        return text.components(separatedBy: needle).count - 1
    }

    /// How many times `needle` is followed, within `distance` characters,
    /// by `follower`.
    static func count(of needle: String, followedWithin distance: Int, by follower: String, in text: String) -> Int {
        var found: Int = 0
        var searchStart: String.Index = text.startIndex
        while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
            let windowEnd: String.Index = text.index(range.upperBound, offsetBy: distance, limitedBy: text.endIndex) ?? text.endIndex
            if text.range(of: follower, range: range.upperBound..<windowEnd) != nil {
                found += 1
            }
            searchStart = range.upperBound
        }
        return found
    }

    /// Hosts `view` in a window and reads the accessibility label of the
    /// element carrying `identifier`, from the tree AppKit builds for
    /// VoiceOver. Nil when no element carries it.
    @MainActor
    static func label(ofIdentifier identifier: String, in view: some View) -> String? {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 480, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host: NSHostingView<AnyView> = NSHostingView(rootView: AnyView(view))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }
        var found: String?
        let deadline: Date = Date().addingTimeInterval(5)
        while found == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            found = labelOfElement(withIdentifier: identifier, from: host, depth: 0)
        }
        return found
    }

    @MainActor
    static func labelOfElement(withIdentifier identifier: String, from element: Any, depth: Int) -> String? {
        if depth > 40 {
            return nil
        }
        guard let object = element as? NSObject else {
            return nil
        }
        if object.responds(to: NSSelectorFromString("accessibilityIdentifier")) {
            let elementIdentifier: String? = object.perform(NSSelectorFromString("accessibilityIdentifier"))?.takeUnretainedValue() as? String
            if elementIdentifier == identifier {
                if object.responds(to: NSSelectorFromString("accessibilityLabel")) {
                    return object.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String
                }
                return nil
            }
        }
        guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else {
            return nil
        }
        guard let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [Any] else {
            return nil
        }
        for child in children {
            if let label = labelOfElement(withIdentifier: identifier, from: child, depth: depth + 1) {
                return label
            }
        }
        return nil
    }
}
