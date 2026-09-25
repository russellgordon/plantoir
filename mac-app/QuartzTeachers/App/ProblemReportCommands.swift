import AppKit
import SwiftUI

/// "Report a Problem…", in the Help menu.
///
/// The words a teacher reads here never mention logs, records or files that
/// only make sense to whoever built this. What they are being offered is a
/// thing they can send to the person helping them, and a chance to read it
/// first.
struct ProblemReportCommands: View {

    // MARK: - Body

    var body: some View {
        Button("Report a Problem…") {
            ProblemReportPresenter.offerToMakeOne()
        }
    }
}

/// Asks the teacher what to include, saves the report where they choose, and
/// shows it to them in Finder.
@MainActor
enum ProblemReportPresenter {

    // MARK: - Functions

    /// The whole flow, from the menu item to a file on their Desktop.
    static func offerToMakeOne(now: Date = Date()) {
        let store: ProblemReportStore = ProblemReportStore.standard
        // Asked first. Walking somebody through a choice and a save panel and
        // THEN telling them there was nothing to send is a small rudeness
        // that costs nothing to avoid.
        if !store.hasAnythingToReport {
            showNothingYet()
            return
        }
        let builder: ProblemReportBuilder = ProblemReportBuilder(store: store)
        let workingParent: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: workingParent, withIntermediateDirectories: true)

        // Only ask about the assistant if there is anything to ask about.
        // A teacher who has never used it should not be shown a question
        // implying they might have.
        guard let choice = askWhatToInclude(offeringAssistantPrompts: store.hasAssistantPrompts) else {
            return
        }
        guard let folderURL = builder.assembleFolder(
            includingAssistantPrompts: choice, in: workingParent, now: now
        ) else {
            showNothingYet()
            return
        }
        guard let destination = askWhereToSave(now: now) else {
            try? FileManager.default.removeItem(at: workingParent)
            return
        }
        if zip(folderURL, to: destination) {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } else {
            showCouldNotSave()
        }
        try? FileManager.default.removeItem(at: workingParent)
    }

    /// The one question worth asking. Returns nil if they back out.
    ///
    /// Their own sentences are the only thing in the report that is
    /// unmistakably theirs rather than the app's, so it is the only thing
    /// they are asked about — and it starts unticked. Everything else is
    /// described rather than offered, because a list of nine checkboxes is a
    /// list nobody reads.
    static func askWhatToInclude(offeringAssistantPrompts: Bool) -> Bool? {
        let alert: NSAlert = NSAlert()
        alert.messageText = "Send a report about a problem"
        alert.informativeText = """
            This gathers what Plantoir did on the last few things you asked it \
            to do, so somebody can see what went wrong.

            It includes the messages Plantoir showed you while it worked, your \
            course codes and section numbers, the names of your pages, and what \
            kind of Mac this is. It leaves out what you have written on your \
            pages, your sign-in details for Netlify or Cloudflare, and your name.

            Save the report, then send it — with the file attached — to:
            """
        alert.addButton(withTitle: "Save Report…")
        alert.addButton(withTitle: "Cancel")

        var includePrompts: NSButton?
        if offeringAssistantPrompts {
            let checkbox: NSButton = NSButton(
                checkboxWithTitle: ProblemReportPresenter.includePromptsLabel,
                target: nil,
                action: nil
            )
            checkbox.state = .off
            includePrompts = checkbox
        }
        alert.accessoryView = ProblemReportPresenter.accessoryView(withCheckbox: includePrompts)

        if alert.runModal() != .alertFirstButtonReturn {
            return nil
        }
        return includePrompts?.state == .on
    }

    /// "the LOCAL AI assistant", not "the assistant".
    ///
    /// Plantoir will grow ways to connect a teacher's own account with a
    /// hosted assistant, and at that point an unqualified "the assistant" is
    /// a question about the wrong thing — with the wrong answer about where
    /// their words have been.
    static let includePromptsLabel: String = "Include what I typed to the local AI assistant" 

    /// The address, as a link they can click, above the one question.
    ///
    /// The address has to live in the accessory view rather than in the
    /// alert's own text, because `informativeText` is a plain string and
    /// nothing in it can be clicked. An address a teacher has to retype by
    /// hand from a dialog is an address that gets retyped wrong.
    static func accessoryView(withCheckbox checkbox: NSButton?) -> NSView {
        // The alert takes its width from the widest thing in it, so the
        // accessory view is what decides it. This is the width the dialog
        // already read well at; it is not a number to tune for anything else.
        let width: CGFloat = 420
        var rows: [NSView] = [supportLink()]
        if let checkbox {
            rows.append(checkbox)
        }
        let stack: NSStackView = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = ProblemReportPresenter.stackSpacing
        // Line the link and the checkbox up with the left edge of the text
        // above them. An alert whose lower half starts a few points further
        // left reads as two dialogs glued together, and a checkbox draws its
        // box slightly inside its own frame, so the two need different nudges
        // to LOOK aligned — which is the only kind of aligned that matters.
        stack.edgeInsets = NSEdgeInsets(
            top: ProblemReportPresenter.stackEndInset,
            left: ProblemReportPresenter.textInset,
            bottom: ProblemReportPresenter.stackEndInset,
            right: 0
        )
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height)
        return stack
    }

    /// How far the alert insets its own message and informative text from
    /// the left edge of the accessory view.
    static let textInset: CGFloat = 6

    /// The gap the alert leaves between its own paragraphs, which everything
    /// below them is spaced to match.
    ///
    /// Measured from the running dialog rather than guessed: the informative
    /// text is 146 points tall for nine line-heights, so a line — and
    /// therefore the blank one between paragraphs — is a shade over 16.
    static let paragraphGap: CGFloat = 16

    /// What the stack must be told, to LOOK like `paragraphGap`.
    ///
    /// A text field and a checkbox each leave about a point of their own
    /// space above and below the glyphs, so a stack spaced at 10 measures 8
    /// on screen. The difference is added back here rather than left as a
    /// mystery for whoever next wonders why these are not the same number.
    static let stackSpacing: CGFloat = paragraphGap + 2

    /// The alert's own padding above and below an accessory view comes out at
    /// 14, so each end needs a little more to match the paragraphs.
    static let stackEndInset: CGFloat = 2

    /// The support address as a real link: clicking it opens the teacher's
    /// mail app with the subject already filled in.
    static func supportLink() -> NSTextField {
        let field: NSTextField = NSTextField(labelWithString: ProblemReportBuilder.supportEmail)
        field.isSelectable = true
        field.allowsEditingTextAttributes = true
        guard let mailURL = ProblemReportBuilder.supportMailURL else {
            // No link is still an address they can read and copy.
            return field
        }
        let linked: NSMutableAttributedString = NSMutableAttributedString(
            string: ProblemReportBuilder.supportEmail
        )
        linked.addAttributes(
            [
                .link: mailURL,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ],
            range: NSRange(location: 0, length: linked.length)
        )
        field.attributedStringValue = linked
        return field
    }

    /// Where it goes. Their Desktop, unless they say otherwise.
    static func askWhereToSave(now: Date) -> URL? {
        let panel: NSSavePanel = NSSavePanel()
        panel.nameFieldStringValue = ProblemReportBuilder.suggestedFileName(now: now)
        panel.directoryURL = RealHome.forFiles.appendingPathComponent("Desktop", isDirectory: true)
        panel.canCreateDirectories = true
        if panel.runModal() != .OK {
            return nil
        }
        return panel.url
    }

    /// Zips a folder using the same machinery the Finder's own "Compress"
    /// uses, so what lands on the Desktop is an ordinary zip a teacher can
    /// open by double-clicking and an email client will accept.
    static func zip(_ folderURL: URL, to destination: URL) -> Bool {
        let coordinator: NSFileCoordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var succeeded: Bool = false
        coordinator.coordinate(
            readingItemAt: folderURL, options: [.forUploading], error: &coordinationError
        ) { zippedURL in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                succeeded = true
            } catch {
                succeeded = false
            }
        }
        if coordinationError != nil {
            return false
        }
        return succeeded
    }

    /// Nothing has happened yet worth reporting.
    static func showNothingYet() {
        let alert: NSAlert = NSAlert()
        alert.messageText = "There is nothing to report yet"
        alert.informativeText = """
            Plantoir keeps a note of the things it does for you, and it has not \
            done anything yet. Try what went wrong once more, then make the \
            report — it will have what happened in it.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// The save itself failed.
    static func showCouldNotSave() {
        let alert: NSAlert = NSAlert()
        alert.messageText = "The report could not be saved"
        alert.informativeText = """
            Nothing was written. Try saving it somewhere else — your Desktop is \
            usually a safe choice.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
