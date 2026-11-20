import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Fields that showed only a placeholder get a name of their own (#1012,
/// left by #993). A placeholder disappears as soon as a teacher types, and
/// assistive apps read it as a hint, not as the field's name: measured on
/// 2026-11-19, a `TextField("Filter", …)` reads with no description at all.
/// Each test hosts the real view off screen and reads what VoiceOver is
/// handed through the accessibility API (`AccessibilityTree`), as
/// `AccessibilityTreeTests` does, so a name that is missing, or said twice,
/// fails here.
///
/// The words are the ones the teacher can already see: a printed label
/// beside the field where there is one ("Cloudflare Account ID", "Netlify
/// token"), otherwise the placeholder's own words, as #993 named the
/// sidebar's Filter field. Apple's VoiceOver guidance: "Provide alternative
/// labels for all key interface elements."
@MainActor
final class PlaceholderFieldNamesTests: XCTestCase {

    // MARK: - Functions

    /// Hosts `view` off screen in a window with a title no other window
    /// has, and reads its tree.
    func tree<Content: View>(of view: Content, size: NSSize = NSSize(width: 640, height: 560)) throws -> AccessibilityTree {
        let host: TableHost = TableHost(view, size: size)
        defer {
            host.close()
        }
        let title: String = "placeholder-names-\(UUID().uuidString)"
        host.window.title = title
        host.pump(0.4)
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(host.window)
        var read: AccessibilityTree = AccessibilityTree(ofWindowTitled: title)
        // A larger view can take a few more turns of the run loop before
        // its content reaches the tree.
        var turns: Int = 0
        while read.elements.count < 4 && turns < 10 {
            host.pump(0.3)
            read = AccessibilityTree(ofWindowTitled: title)
            turns += 1
        }
        XCTAssertTrue(read.foundTheWindow, "the hosted window is not in the accessibility tree")
        return read
    }

    /// Fails unless the one element with `identifier` carries exactly
    /// `name`, once.
    func assertField(_ identifier: String, in tree: AccessibilityTree, isNamed name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let field = tree.element(identifiedAs: identifier, file: file, line: line) else {
            return
        }
        XCTAssertEqual(field.names, [name], "\(identifier) is not named \"\(name)\":\n\(tree.described())", file: file, line: line)
    }

    /// Fails with every control in the tree that has no name or says one
    /// twice.
    func assertEveryControlIsNamedOnce(in tree: AccessibilityTree, file: StaticString = #filePath, line: UInt = #line) {
        let faults: [String] = tree.controlsNotNamedOnce()
        XCTAssertEqual(faults, [], "controls not named exactly once:\n\(faults.joined(separator: "\n"))", file: file, line: line)
    }

    /// A workspace for views that read one from the environment.
    func workspace() -> WorkspaceModel {
        return WorkspaceModel(defaults: TestDefaults.make())
    }

    /// A runner that reads as a task under way.
    func runningRunner() -> ScriptRunner {
        let runner: ScriptRunner = ScriptRunner()
        runner.milestones = TaskMilestones.preview
        runner.isRunning = true
        return runner
    }

    // MARK: - The assistant

    /// The assistant's composer is named by its placeholder's words, without
    /// the ellipsis.
    func testTheAssistantsComposerIsNamed() throws {
        let composer: some View = ComposerHost()
        let read: AccessibilityTree = try tree(of: composer)
        assertField("assistInputField", in: read, isNamed: AccessibilityNames.askAboutThisSection)
        assertEveryControlIsNamedOnce(in: read)
    }

    // MARK: - Class Dates

    /// Class Dates' Google Sheet link, whose placeholder is an address, is
    /// named in words.
    func testTheGoogleSheetLinkIsNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let sheet: SectionScheduleSheet = SectionScheduleSheet(course: made.course, sectionNumber: 1, route: .googleSheet)
        let read: AccessibilityTree = try tree(of: sheet)
        assertField("sectionScheduleGoogleSheetField", in: read, isNamed: AccessibilityNames.googleSheetAddress)
        assertEveryControlIsNamedOnce(in: read)
    }

    // MARK: - The sidebar

    /// The sidebar's rename field is named "Course code", its placeholder's
    /// words.
    func testTheSidebarsCourseCodeFieldIsNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let field: some View = CourseCodeField(course: made.course).environment(workspace())
        let read: AccessibilityTree = try tree(of: field)
        assertField("renameField", in: read, isNamed: "Course code")
        assertEveryControlIsNamedOnce(in: read)
    }

    // MARK: - Course Settings

    /// Course Settings' folder path, for a course published to a folder, is
    /// named "Folder": not placeholder-only after all. Inside the `Form` the
    /// title is drawn as the row's label and linked to the field as its title
    /// element (measured 2026-11-20), so it passed before #1012 and is pinned
    /// here so it stays named.
    func testThePublishingFolderPathIsNamed() throws {
        let choice: PublishingChoiceView = PublishingChoiceView(
            deployTarget: .constant("local_folder"),
            deployFolderPath: .constant(""),
            cloudflareAccountID: "",
            additionalDeployTargets: .constant([])
        )
        let read: AccessibilityTree = try tree(of: Form { choice })
        assertField("deployFolderField", in: read, isNamed: "Folder")
        assertEveryControlIsNamedOnce(in: read)
    }

    /// A list editor's rename sheet: its New name field.
    func testTheListEditorsNewNameIsNamed() throws {
        let editor: StringListEditorView = StringListEditorView(
            title: "Shared folders (all sections)",
            removalTrail: RemovalTrail(place: .courseSettings, courseCode: "EXC2O", list: .sharedFolders),
            items: .constant(["media"])
        )
        let read: AccessibilityTree = try tree(of: editor.renameSheet(for: "media", interruptedTarget: nil))
        assertField("renameField", in: read, isNamed: "New name")
        assertEveryControlIsNamedOnce(in: read)
    }

    /// A list editor's add popover: its field is named by the words of its
    /// prompt ("Type new folder name here").
    func testTheListEditorsAddFieldIsNamed() throws {
        let editor: StringListEditorView = StringListEditorView(
            title: "Shared folders (all sections)",
            removalTrail: RemovalTrail(place: .courseSettings, courseCode: "EXC2O", list: .sharedFolders),
            items: .constant(["media"])
        )
        let read: AccessibilityTree = try tree(of: editor.addPopover)
        assertField("addField-Shared folders (all sections)", in: read, isNamed: "New folder name")
        assertEveryControlIsNamedOnce(in: read)
    }

    /// The footer's box is named by its section's heading.
    func testTheFooterBoxIsNamed() throws {
        let read: AccessibilityTree = try tree(of: FooterEditorView(footerHTML: .constant("")))
        assertField("footerEditor", in: read, isNamed: "Footer")
    }

    /// Printing's school name field is named by its row's label, linked as
    /// its title element inside the `Form` (named before #1012; pinned).
    func testThePrintingSchoolNameIsNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let print: PrintSettingsView = PrintSettingsView(configuration: made.course.configuration, displayedCourseCode: "EXC2O")
        let read: AccessibilityTree = try tree(of: Form { print })
        assertField("printSchoolNameField", in: read, isNamed: CourseSettingsWording.printingSchoolName)
        assertEveryControlIsNamedOnce(in: read)
    }

    /// Renaming the unit word: the field is named by the question printed
    /// beside it, which its `LabeledContent` links as the field's title
    /// element (named before #1012; pinned).
    func testTheUnitWordRenameFieldIsNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let sheet: some View = UnitWordRenameSheet(course: made.course, onRenamed: { (_: String) in }).environment(workspace())
        let read: AccessibilityTree = try tree(of: sheet)
        assertField("unitWordRenameField", in: read, isNamed: UnitWordRenameWording.fieldLabel)
        assertEveryControlIsNamedOnce(in: read)
    }

    // MARK: - Settings

    /// Settings' Cloudflare Account ID field is named by the label beside it:
    /// a `LabeledContent` links its label to the field as its title element
    /// (named before #1012; pinned).
    func testTheCloudflareAccountFieldIsNamed() throws {
        let read: AccessibilityTree = try tree(of: DeployingSettingsView())
        assertField("cloudflareAccountField", in: read, isNamed: "Cloudflare Account ID")
    }

    // MARK: - The console

    /// The console's answer box, shown while a task runs.
    func testTheConsolesAnswerFieldIsNamed() throws {
        let console: TaskConsoleView = TaskConsoleView(runner: runningRunner(), allLegs: nil)
        let read: AccessibilityTree = try tree(of: console)
        assertField("consoleInputField", in: read, isNamed: AccessibilityNames.yourAnswer)
        XCTAssertEqual(read.elements(withRole: "AXBusyIndicator").count, 1, "the console's spinner is not in the tree:\n\(read.described())")
        assertEveryControlIsNamedOnce(in: read)
    }

    /// A credential is asked for with the label printed above its field
    /// ("Netlify token"); the field's placeholder says what to do.
    func testTheCredentialFieldIsNamed() throws {
        let request: CredentialRequest = CredentialRequest.netlifyToken
        let sheet: CredentialRequestSheet = CredentialRequestSheet(request: request, onSend: { (_: String) in }, onCancel: {})
        let read: AccessibilityTree = try tree(of: sheet)
        assertField("credentialField", in: read, isNamed: request.fieldLabel)
        assertEveryControlIsNamedOnce(in: read)
    }

    // MARK: - New Course and Copy a Page

    /// The New Course window's code field, a view of ours inside a printed
    /// label, is named by that label, linked inside the `Form` (named before
    /// #1012; pinned).
    func testTheWizardsCourseCodeFieldIsNamed() throws {
        let wizard: some View = NewCourseWizardView(courseCode: "", prepopulatesExampleContent: false)
            .environment(workspace())
        let read: AccessibilityTree = try tree(of: wizard, size: NSSize(width: 760, height: 720))
        assertField("wizardCourseCodeField", in: read, isNamed: WizardWording.panelWords(isClub: false).codeLabel)
    }

    /// Copy a Page's page field is named by the question printed beside it,
    /// linked inside the `Form` (named before #1012; pinned).
    func testCopyAPagesPageFieldIsNamed() throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let sheet: some View = CopyPageSheet(source: made.course).environment(workspace())
        let read: AccessibilityTree = try tree(of: sheet)
        assertField("copyPagePicker", in: read, isNamed: CopyPageWording.whichPage)
    }
}

/// The composer's field with state of its own, as the assistant's window
/// holds it.
private struct ComposerHost: View {

    // MARK: - Stored properties

    @State var typing: String = ""
    @State var history: AssistPromptHistory = AssistPromptHistory()
    @State var lastRecalled: String?
    @FocusState var isFocused: Bool

    // MARK: - Body

    var body: some View {
        AssistComposerField(
            typing: $typing,
            history: $history,
            lastRecalled: $lastRecalled,
            isFocused: $isFocused,
            canAcceptTyping: true,
            onSubmit: {}
        )
        .padding()
    }
}
