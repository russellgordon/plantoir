import AppKit
import SwiftUI

/// The assistant, in a window of its own for one section.
///
/// A window rather than a pane inside the main window, and that is a
/// deliberate choice: the teacher needs the section's preview on screen while
/// they talk about it. A pane would put the conversation and the thing it is
/// about in competition for the same space, and the conversation would win,
/// which is the wrong way round.
struct AssistWindowView: View {

    // MARK: - Stored properties

    /// Everything this window needs, assembled when it opens.
    @State private var session: AssistSession

    /// What the teacher is typing.
    @State private var typing: String = ""

    /// Keeps the newest line in view as the conversation grows.
    @Namespace private var bottom

    /// Whether the Restore question is on screen.
    @State private var isConfirmingRestore: Bool = false

    /// What has been asked for before, walked with the arrow keys.
    ///
    /// Per section, and kept across launches, because that is what makes it
    /// worth having: a teacher who works on one section over several days
    /// asks for the same handful of things in the same handful of words, and
    /// a history that emptied every time the window closed would only ever
    /// hold what they had just finished typing anyway.
    @State private var history: AssistPromptHistory = AssistPromptHistory()

    /// Where that history lives between launches. Keyed by section, so one
    /// course's phrasings never surface while working on another.
    @AppStorage private var storedHistory: String

    /// The last line the arrow keys put in the box, so an edit can be told
    /// apart from the walk's own writing.
    @State private var lastRecalled: String?

    /// The window this conversation lives in, so its place can be written
    /// down at the two moments AppKit's own autosave is least likely to get
    /// a turn: closing, and quitting with it open.
    @State private var hostWindow: NSWindow?

    /// Whether the box has the keyboard. Tapping a suggestion puts text in it
    /// and gives it focus, so the teacher can edit straight away rather than
    /// having to click into it first.
    @FocusState private var isComposerFocused: Bool

    /// Whether a send is already parked, waiting for the warm-up to finish.
    ///
    /// One at a time: pressing Return twice during those few seconds must ask
    /// one question, not two.
    @State private var isHoldingForWarmUp: Bool = false

    // MARK: - Initializer

    init(courseCode: String, sectionNumber: Int, workingFolder: URL) {
        _session = State(initialValue: AssistSession(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workingFolder: workingFolder
        ))
        _storedHistory = AppStorage(
            wrappedValue: "",
            "AssistPromptHistory-\(courseCode)-\(sectionNumber)"
        )
    }

    // MARK: - Computed properties

    /// Whether pressing send would do anything — either straight away, or by
    /// holding the message until the warm-up lets go of the engine.
    ///
    /// The warm-up case is included deliberately. `session.canSend` is false
    /// for the few seconds between the window announcing itself ready and the
    /// priming request coming back, and a send button that is simply dead for
    /// that stretch would swallow the first Return a fast teacher presses.
    private var isSendAvailable: Bool {
        if typing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return session.canSend || session.isWarmingUp
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.canRestoreSection {
                restoreBanner
                Divider()
            }
            // Pinned at the top, with the conversation scrolling beneath
            // it. Shut by default, so it costs four scannable lines and
            // stays put however long the conversation grows.
            if session.readiness == .ready {
                // Tapping puts the phrasing in the box; it does NOT send it.
                // These are examples to start from, and most of them want
                // editing before they are true — "Publish Unit 2, Day 3" is a
                // shape, not usually the actual page. A card that fired
                // immediately would make the shelf a row of buttons a teacher
                // learns not to touch.
                AssistPromptShelfView { phrasing in
                    show(phrasing)
                    history.stopBrowsing()
                    isComposerFocused = true
                }
                Divider()
            }
            transcript
            Divider()
            composer
        }
        // Fills whatever the window is, rather than asking for a size.
        //
        // With only a MINIMUM here, SwiftUI's idea of the ideal size came from
        // the content — so when the window swapped "Getting the assistant
        // ready…" for the conversation, the ideal changed and macOS resized
        // the window under the remembered frame. What a teacher saw was the
        // window appearing where they left it and then jumping once the model
        // was ready. Filling the space makes the content's size a consequence
        // of the window rather than a demand on it, so nothing moves.
        .frame(
            minWidth: 460, idealWidth: 620, maxWidth: .infinity,
            minHeight: 420, idealHeight: 640, maxHeight: .infinity
        )
        .navigationTitle("Assistant — \(session.courseCode) section \(session.sectionNumber)")
        // When something in here needs class dates for a section that has
        // none recorded, it asks through SectionSchedulePrompt and the sheet
        // opens on the window the teacher is already looking at.
        .sectionSchedulePrompt(
            courseCode: session.courseCode,
            sectionNumber: session.sectionNumber,
            workingFolder: session.workingFolder
        )
        // Comes back where it was left, per section. The window group stays
        // unrestored on purpose — reopening it at launch would load a model
        // nobody asked for — so this remembers only the PLACEMENT, which is
        // the part a teacher notices: an assistant that reappears in the
        // middle of the screen, on top of the section it is meant to sit
        // beside, gets dragged back every single time.
        .background(WindowAccessor { window in
            hostWindow = window
            AssistWindowPlacement.remember(
                window,
                courseCode: session.courseCode,
                sectionNumber: session.sectionNumber
            )
        })
        // Quitting with the window open is the other moment a teacher has
        // finished arranging it, and `onDisappear` is not guaranteed a turn
        // during termination.
        // Saved as it is moved and resized as well, so an arrangement is not
        // lost to a force-quit or a crash. Cheap: one defaults write, and only
        // when the teacher is actually dragging.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { note in
            if note.object as AnyObject? === hostWindow {
                savePlacement()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { note in
            if note.object as AnyObject? === hostWindow {
                savePlacement()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            AssistWindowPlacement.save(
                hostWindow,
                courseCode: session.courseCode,
                sectionNumber: session.sectionNumber
            )
        }
        .task {
            history = AssistPromptHistory.read(fromStored: storedHistory)
            await session.prepare()
        }
        .onDisappear {
            AssistWindowPlacement.save(
                hostWindow,
                courseCode: session.courseCode,
                sectionNumber: session.sectionNumber
            )
            session.finish()
        }
    }

    /// The way back to how this section was when the conversation started.
    ///
    /// A banner across the top rather than a line in the transcript, because
    /// the moment it is wanted is the moment something has gone wrong, and a
    /// teacher scrolling a long chat for the way out is a teacher already
    /// having a bad time. It appears only once the conversation has actually
    /// changed something, so it is never furniture.
    ///
    /// Hard to press by accident, in three ways: it is a bordered button rather
    /// than a tap target in the flow of the text, its title ends in an ellipsis
    /// promising a question, and the question that follows makes Cancel the
    /// default — a Return pressed out of habit leaves the section alone.
    private var restoreBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(AssistSectionRestore.bannerTitle(sectionNumber: session.sectionNumber))
                    .font(.callout)
                Text(AssistSectionRestore.bannerDetail())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(AssistSectionRestore.buttonTitle(sectionNumber: session.sectionNumber)) {
                isConfirmingRestore = true
            }
            .disabled(session.agent?.isBusy ?? false)
            .accessibilityIdentifier("assistRestoreSectionButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .alert(
            AssistSectionRestore.confirmationTitle(
                courseCode: session.courseCode, sectionNumber: session.sectionNumber
            ),
            isPresented: $isConfirmingRestore
        ) {
            Button("Cancel", role: .cancel) {
                isConfirmingRestore = false
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("assistCancelRestoreButton")

            Button(
                AssistSectionRestore.goAheadTitle(sectionNumber: session.sectionNumber),
                role: .destructive
            ) {
                session.restoreSection()
            }
            .accessibilityIdentifier("assistConfirmRestoreButton")
        } message: {
            Text(AssistSectionRestore.confirmationMessage(
                courseCode: session.courseCode, sectionNumber: session.sectionNumber
            ))
        }
    }

    /// The conversation, or whatever is standing in the way of having one.
    @ViewBuilder
    private var transcript: some View {
        switch session.readiness {
        case .checkingHardware:
            AssistNoticeView(
                title: "Getting ready…",
                detail: "Looking at what this Mac can run."
            )

        case .unsupported(let reason):
            AssistNoticeView(title: "Not available on this Mac", detail: reason)

        case .needsDownload(let tier):
            AssistDownloadView(tier: tier, store: session.store) {
                session.beginDownload()
            }

        case .downloading(let fraction, let received, let total):
            AssistDownloadProgressView(fractionComplete: fraction, receivedBytes: received, totalBytes: total) {
                session.stopDownload()
            }

        case .starting:
            AssistNoticeView(
                title: "Starting the assistant…",
                detail: "Loading \(session.tier.displayName). This takes a moment the first time after opening."
            )

        case .failed(let reason):
            AssistNoticeView(title: "The assistant could not start", detail: reason)

        case .ready:
            conversation
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(transcriptLines.enumerated()), id: \.element.id) { position, line in
                        switch line {
                        case .said(let entry):
                            AssistEntryView(
                                entry: entry,
                                hasTail: AssistChatLayout.showsTail(
                                    at: position, in: transcriptSides
                                )
                            )
                        case .restored(let note):
                            AssistRestoreNoteView(note: note)
                        }
                    }

                    // Three dots while the model is working. It appears for
                    // thinking AND for running a tool: both are waits with
                    // nothing on screen, and a teacher does not care which of
                    // the two the assistant is busy with.
                    if session.agent?.isBusy == true, session.agent?.pendingApproval == nil {
                        AssistTypingIndicator()
                    }
                    if let approval = session.agent?.pendingApproval,
                       let agent = session.agent {
                        AssistApprovalView(isDeploy: agent.pendingIsDeploy) {
                            Task { await agent.approvePending() }
                        } decline: {
                            agent.declinePending()
                        }
                    }
                    // "May I ask you for your class dates?" — the offer that
                    // stands where the sheet used to open by itself.
                    if let offer = SectionSchedulePrompt.shared.offer,
                       offer.courseCode == session.courseCode,
                       offer.sectionNumber == session.sectionNumber {
                        AssistDatesOfferView(reason: offer.reason) {
                            SectionSchedulePrompt.shared.acceptOffer()
                        } decline: {
                            SectionSchedulePrompt.shared.declineOffer()
                            session.agent?.noteDatesDeclined()
                        }
                    }
                    if let agent = session.agent, agent.planMode.shouldOfferToStop {
                        AssistStopAskingOfferView {
                            agent.planMode.stopAsking()
                        } keepAsking: {
                            agent.planMode.keepAsking()
                        }
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding()
            }
            .onChange(of: transcriptLines.count) {
                withAnimation {
                    proxy.scrollTo(bottom, anchor: .bottom)
                }
            }
        }
    }

    /// The box, shaped the way Messages shapes it: one rounded field with the
    /// send button living inside its right end, rather than a plain rule of a
    /// text field with a button parked beside it.
    private var composer: some View {
        HStack(spacing: 6) {
            TextField("Ask about this section…", text: $typing, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit {
                    // Ignored while the assistant is mid-run: it does one
                    // thing at a time, and a second request would interleave
                    // with the first one's tool calls. During the warm-up it
                    // is held rather than ignored — see `sendOrHold()`.
                    sendOrHold()
                }
                // Up and Down walk what has been asked before, the way a
                // Terminal does.
                //
                // Handed back as `.ignored` in two cases, so the keys keep
                // doing their ordinary job when history is not what is
                // wanted: when the box holds more than one line, where the
                // arrows have to move the caret between those lines, and
                // when there is nowhere further to walk — a key that silently
                // does nothing reads as a dropped keystroke, while one that
                // is passed on lets the field answer it.
                .onKeyPress(.upArrow) {
                    if typing.contains("\n") {
                        return .ignored
                    }
                    guard let recalled = history.earlier(startingFrom: typing) else {
                        return .ignored
                    }
                    show(recalled)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if typing.contains("\n") {
                        return .ignored
                    }
                    guard let recalled = history.later() else {
                        return .ignored
                    }
                    show(recalled)
                    return .handled
                }
                // Editing a recalled line makes it a new line, so Down must
                // not come along afterwards and replace what was typed. The
                // walk writes through `show(_:)`, which records what it put
                // there — so anything ELSE that changes the box came from the
                // keyboard, and ends the walk.
                .onChange(of: typing) { _, current in
                    if history.isBrowsing && current != lastRecalled {
                        history.stopBrowsing()
                    }
                }
                .focused($isComposerFocused)
                .disabled(!session.canAcceptTyping)
                .accessibilityIdentifier("assistInputField")

            Button {
                sendOrHold()
            } label: {
                // A spinner while the engine is still reading its tool
                // definitions, so the wait has something to look at. Without
                // it the button is an ordinary arrow that quietly does not
                // answer for a second or two, which reads as a broken button
                // rather than as a machine getting ready.
                if session.isWarmingUp {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isSendAvailable)
            .accessibilityIdentifier("assistSendButton")
        }
        // A continuous rounded rectangle rather than a Capsule: at one line
        // the two are indistinguishable, and when the box grows to four lines
        // a capsule's ends bow outwards while this keeps its shape.
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Which side each line of the transcript belongs to, in order. The tail
    /// rule reads this rather than the views.
    private var transcriptSides: [AssistChatSide] {
        var sides: [AssistChatSide] = []
        for line in transcriptLines {
            switch line {
            case .said(let entry):
                sides.append(AssistChatLayout.side(of: entry.speaker))
            case .restored:
                // A restore is something that HAPPENED, not something said,
                // so it neither wears a tail nor ends anybody's turn.
                sides.append(.neither)
            }
        }
        return sides
    }

    /// The conversation and the restores, laid together in the order they
    /// happened.
    ///
    /// A restore is not something either side said, so it is not among the
    /// agent's own entries — but it IS something that happened during this
    /// conversation, and a teacher reading back afterwards needs to find it at
    /// the point where the section changed under them, not tacked on the end.
    private var transcriptLines: [AssistTranscriptLine] {
        let entries: [AssistAgent.Entry] = session.agent?.entries ?? []
        let notes: [AssistSession.RestoreNote] = session.restoreNotes

        var lines: [AssistTranscriptLine] = []
        var notesPlaced: Int = 0
        for (index, entry) in entries.enumerated() {
            while notesPlaced < notes.count && notes[notesPlaced].saidSoFar <= index {
                lines.append(AssistTranscriptLine.restored(notes[notesPlaced]))
                notesPlaced += 1
            }
            lines.append(AssistTranscriptLine.said(entry))
        }
        while notesPlaced < notes.count {
            lines.append(AssistTranscriptLine.restored(notes[notesPlaced]))
            notesPlaced += 1
        }
        return lines
    }

    // MARK: - Functions

    /// Write down where this window is, for the next time this section's
    /// assistant is opened.
    private func savePlacement() {
        AssistWindowPlacement.save(
            hostWindow,
            courseCode: session.courseCode,
            sectionNumber: session.sectionNumber
        )
    }

    /// Put a recalled line in the box, remembering that the walk is what put
    /// it there rather than the teacher.
    private func show(_ recalled: String) {
        lastRecalled = recalled
        typing = recalled
    }

    /// Send what is in the box, or hold it until the warm-up lets go.
    ///
    /// The engine serves one request at a time, and the ~3,400-token priming
    /// request has the slot for the first couple of seconds. A question sent
    /// into that gap does not arrive sooner for having been sent sooner — it
    /// queues behind the warm-up — so the send waits for the slot instead of
    /// competing for it. What the teacher sees is unchanged: they press
    /// Return once, and their message goes.
    ///
    /// The box is read AFTER the wait rather than captured before it, so
    /// anything typed during those seconds goes with the message rather than
    /// being left behind in a field that has apparently just been sent.
    private func sendOrHold() {
        if session.canSend {
            Task { await send(typing) }
            return
        }
        guard session.isWarmingUp, !isHoldingForWarmUp else {
            return
        }
        isHoldingForWarmUp = true
        Task {
            await session.waitUntilWarmedUp()
            isHoldingForWarmUp = false
            if session.canSend {
                await send(typing)
            }
        }
    }

    private func send(_ text: String) async {
        let message: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return
        }
        history.remember(message)
        storedHistory = history.stored
        lastRecalled = nil
        typing = ""
        // The cursor stays put. A teacher sending two things in a row should
        // not have to click back into the box between them, and losing focus
        // after every send also loses the arrow-key history, which depends on
        // the field having it.
        //
        // This only works because the box is no longer DISABLED while the
        // assistant runs: a disabled field cannot hold focus, so macOS moved
        // the keyboard to the next thing it could find — the first disclosure
        // group in the shelf — and setting focus beforehand could not survive
        // that.
        isComposerFocused = true
        await session.agent?.say(message)
    }
}

/// One line of what a teacher reads back: something said, or a restore.
private enum AssistTranscriptLine: Identifiable {
    case said(AssistAgent.Entry)
    case restored(AssistSession.RestoreNote)

    var id: UUID {
        switch self {
        case .said(let entry):
            return entry.id
        case .restored(let note):
            return note.id
        }
    }
}

/// A restore, written into the conversation so it records what happened.
private struct AssistRestoreNoteView: View {

    // MARK: - Stored properties

    let note: AssistSession.RestoreNote

    // MARK: - Computed properties

    var body: some View {
        Label(note.text, systemImage: note.isProblem ? "exclamationmark.triangle" : "clock.arrow.circlepath")
            .font(.callout)
            .foregroundStyle(note.isProblem ? Color.orange : Color.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("assistRestoreNote")
    }
}

/// One line of the conversation.
private struct AssistEntryView: View {

    // MARK: - Stored properties

    let entry: AssistAgent.Entry

    /// Whether this bubble ends its participant's run, and so wears the tail.
    let hasTail: Bool

    // MARK: - Computed properties

    var body: some View {
        switch entry.speaker {
        // Blue, on the right, the way the person holding the keyboard is
        // shown in every messaging app a teacher already uses. White text
        // rather than the label colour: the accent is a strong fill, and
        // primary text on it fails in one of the two themes.
        case .teacher:
            HStack {
                Spacer(minLength: 48)
                SelectableBubbleText(text: entry.text, colour: .white, bubbleFill: AssistBubbleColour.teacherNS)
                    .padding(.leading, 12)
                    .padding(.trailing, 9)
                    .padding(.top, 7)
                .padding(.bottom, 7 + AssistChatBubbleShape.drop)
                    .background(
                        AssistChatBubbleShape(side: .teacher, hasTail: hasTail)
                            .fill(AssistBubbleColour.teacher)
                    )
            }
            .padding(.bottom, hasTail ? 4 : 0)

        // Grey, on the left. Softer than the teacher's bubble on purpose:
        // the assistant talks more than the teacher does, and a column of
        // strong fills down one side is exhausting to read.
        case .assistant:
            HStack {
                SelectableBubbleText(text: entry.text, colour: .labelColor, bubbleFill: AssistBubbleColour.assistantNS)
                    // The tail's side gets the extra room, so the words sit
                    // the same distance from the bubble's edge on both sides.
                    .padding(.leading, 12)
                    .padding(.trailing, 9)
                    .padding(.top, 7)
                .padding(.bottom, 7 + AssistChatBubbleShape.drop)
                    .background(
                        AssistChatBubbleShape(side: .assistant, hasTail: hasTail)
                            .fill(AssistBubbleColour.assistant)
                    )
                Spacer(minLength: 48)
            }
            .padding(.bottom, hasTail ? 4 : 0)

        // A result is the assistant ANSWERING, so it wears the same grey
        // bubble as anything else it says. As plain lines with an icon these
        // read as a log spliced through a conversation — and that the answer
        // came from a tool is machinery, which the teacher is not the
        // audience for.
        case .toolResult:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    SelectableBubbleText(text: entry.text, colour: .labelColor, bubbleFill: AssistBubbleColour.assistantNS)
                    // When there is a list behind the answer, it unfolds
                    // inside the bubble. A count on its own is not something
                    // a teacher can act on — "1 broken link" says something
                    // is wrong and nothing about where — but the list would
                    // bury the conversation if it were always open.
                    if let detail = entry.detail {
                        DisclosureGroup("Show me") {
                            Text(detail)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .font(.callout)
                        .accessibilityIdentifier("assistResultDetail")
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 9)
                .padding(.top, 7)
                .padding(.bottom, 7 + AssistChatBubbleShape.drop)
                .background(
                    AssistChatBubbleShape(side: .assistant, hasTail: hasTail)
                        .fill(AssistBubbleColour.assistant)
                )
                Spacer(minLength: 48)
            }
            .padding(.bottom, hasTail ? 4 : 0)

        case .problem:
            HStack {
                Label(entry.text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                    .padding(.trailing, 9)
                    .padding(.top, 7)
                .padding(.bottom, 7 + AssistChatBubbleShape.drop)
                    .background(
                        AssistChatBubbleShape(side: .assistant, hasTail: hasTail)
                            .fill(AssistBubbleColour.assistant)
                    )
                Spacer(minLength: 48)
            }
            .padding(.bottom, hasTail ? 4 : 0)
        }
    }
}

/// What the assistant is about to do, waiting on a button.
///
/// Two shapes, one box. A DEPLOY always asks, because it puts something in
/// front of students immediately and cannot be taken back by us. Everything
/// else asks only while plan mode is on, and what it shows is the `plan_`
/// twin's own words rather than a tool name a teacher would have to decode.
/// The two buttons, and nothing else.
///
/// It used to carry a heading and a copy of the plan. Both have moved into the
/// conversation, where they belong: the plan is something the assistant SAID,
/// the question is another thing it said, and what the teacher chose is their
/// own reply. What is left here is the only part that is not a message — the
/// choice itself.
private struct AssistApprovalView: View {

    // MARK: - Stored properties

    let isDeploy: Bool
    let approve: () -> Void
    let decline: () -> Void

    // MARK: - Computed properties

    private var goTitle: String {
        return isDeploy ? "Deploy" : "Go"
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Cancel", action: decline)
                .accessibilityIdentifier("assistDeclineButton")
            Button(goTitle, action: approve)
                .keyboardShortcut(.defaultAction)
                // A deploy is the one act that cannot be taken back, so its
                // button says so in the way macOS says it.
                .buttonStyle(.borderedProminent)
                .tint(isDeploy ? .orange : .accentColor)
                .accessibilityIdentifier("assistApproveButton")
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}


/// "May I ask you for your class dates?" — Yes, or Cancel.
///
/// The schedule sheet used to open the instant anything discovered it needed
/// dates, ON TOP of the sentence explaining why. So the teacher met a form
/// before they had read the request, and the request was behind the form. A
/// form nobody asked for is a demand; this makes it an offer.
///
/// "Yes" is the default button here, unlike the plan gate, and the difference
/// is deliberate: a plan asks permission to CHANGE something, where this asks
/// permission to ask a question. Somebody who pressed Return without reading
/// gets a form they can close, not an edit they did not want.
private struct AssistDatesOfferView: View {

    // MARK: - Stored properties

    let reason: String
    let accept: () -> Void
    let decline: () -> Void

    // MARK: - Computed properties

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AssistWording.mayIAskForYourDates, systemImage: "calendar")
                .font(.headline)
            if !reason.isEmpty {
                Text(reason)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            Text("They can be typed in, chosen from a file, or read from a shared sheet.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            HStack {
                Button("Yes", action: accept)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("assistGiveDatesButton")
                Button(AssistWording.cancelled, action: decline)
                    .accessibilityIdentifier("assistNoDatesButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Told once, ever: there is a setting for this.
///
/// **It exists for DISCOVERABILITY, not to ask for trust.** Whether the
/// assistant checks first is the teacher's decision and lives in Settings; a
/// switch nobody knows about might as well not exist, so after fifteen plans
/// read and agreed to — app-wide, across every conversation and course — the
/// assistant says where it is. That is enough of a feel for the thing to
/// judge whether they want the gate.
///
/// Fifteen rather than five, and app-wide rather than per window, because the
/// old count reset with every conversation: a teacher working in short bursts
/// could accept a hundred plans and never be told, having never hit five in
/// one sitting.
///
/// Once, and then never again — in this window or any other. A suggestion
/// declined is an answer, and asking twice is how a helpful mention becomes
/// nagging. "Keep checking" is the default button: the teacher who pressed
/// Return without reading keeps the safer arrangement.
private struct AssistStopAskingOfferView: View {

    // MARK: - Stored properties

    let stopAsking: () -> Void
    let keepAsking: () -> Void

    // MARK: - Computed properties

    private var message: String {
        return "You have said yes to \(AssistPlanMode.plansBeforeMentioningTheSetting) of my "
             + "plans now. If you would rather I just did what you ask, there is a switch for "
             + "it in Plantoir ▸ Settings — “Ask me before changing anything”. You can turn it "
             + "back on there whenever you like, and “Undo that” still takes back anything I do."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("There is a setting for this", systemImage: "checkmark.seal")
                .font(.headline)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Just do it", action: stopAsking)
                    .accessibilityIdentifier("assistStopAskingButton")
                Button("Keep checking", action: keepAsking)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("assistKeepAskingButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Something standing between the teacher and a conversation.
private struct AssistNoticeView: View {

    // MARK: - Stored properties

    let title: String
    let detail: String

    // MARK: - Computed properties

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
