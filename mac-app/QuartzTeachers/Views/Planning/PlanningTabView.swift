import SwiftUI

/// What the Planning tab keeps while the course's page is open (#708), so
/// switching to Settings and back finds the plan where the teacher left it:
/// the web view and its history, and the unit chosen in the popup.
@Observable
final class PlanningTabModel {

    // MARK: - Stored properties

    /// Made the first time a plan is shown, so a course page whose Planning
    /// tab is never opened makes no web view.
    var controller: PlanWebController?

    /// The planning folder as last read.
    var look: PlanningTab.Look = PlanningTab.Look(plans: [], choices: [])

    /// The unit popup's choice; nil before the folder is first read, or
    /// while there is nothing to offer.
    var choice: PlanningTab.Choice?

    /// Whether the folder has been read at all yet, so the empty tab's
    /// offer is not flashed before it has.
    var hasLooked: Bool = false
}

/// The course page's Planning tab (#708): the course's unit plans, shown
/// from `courses/<CODE>/.internal/planning/` on this Mac, with a popup of
/// units, Back, Forward and Reload; or, while there are none, an offer to
/// plan one with Claude or Codex.
///
/// Drawn OVER the course's settings by `CourseDetailView`, never instead of
/// them, so a half-typed setting is still there after a look at the plan.
///
/// **When it looks again**: when it appears, when the window becomes key
/// (the teacher was in their terminal while an assistant built the plan,
/// and came back), and on Reload. Each time it first makes the plan's
/// `assets/` the app's own (`PlanningAssets`). No file watcher and no
/// timer: coming back to the window is the moment a teacher expects to see
/// what changed.
struct PlanningTabView: View {

    // MARK: - Stored properties

    let course: Course

    /// The working folder, for the doors.
    let folder: URL

    let model: PlanningTabModel

    @Environment(WorkspaceModel.self) var workspace

    @Environment(\.controlActiveState) var controlActiveState: ControlActiveState

    /// Why a door did not open, for its alert.
    @State var doorProblem: String?

    /// Which door's alert `doorProblem` is.
    @State var doorThatFailed: FixWithAssistant.Assistant = .claude

    /// A Claude or Codex session already open on the course, or the course
    /// busy: the refusal Revise With ▸ makes at the click (#458).
    @State var reviseRefusal: WorkspaceModel.ReviseRefusal?

    // MARK: - Computed properties

    var presence: OutsideAssistantPresence {
        return OutsideAssistantPresence.shared
    }

    var planningFolder: URL {
        return course.directoryURL.appendingPathComponent(UnitPlans.folderPath, isDirectory: true)
    }

    /// The popup's selection, writing through to the model.
    var choiceBinding: Binding<PlanningTab.Choice> {
        return Binding(
            get: {
                return model.choice ?? .allPlans
            },
            set: { (newChoice: PlanningTab.Choice) in
                if newChoice != model.choice {
                    model.choice = newChoice
                    show(newChoice)
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if !model.hasLooked {
                Color.clear
            } else if model.look.choices.isEmpty {
                emptyOffer
            } else {
                VStack(spacing: 0) {
                    planBar
                    if let controller = model.controller {
                        PlanWebView(controller: controller)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("planningWebView")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityIdentifier("planningTab")
        .task {
            // Reloaded when the tab is drawn again after Settings: the plan
            // may have changed meanwhile, and its history is kept.
            lookAgain(reloadingThePage: true)
        }
        .onChange(of: controlActiveState) { (_: ControlActiveState, newState: ControlActiveState) in
            if newState == .key {
                lookAgain(reloadingThePage: true)
            }
        }
        .alert(
            doorThatFailed == .claude ? ClaudeCodeLauncher.didNotOpenTitle : CodexLauncher.didNotOpenTitle,
            isPresented: Binding(
                get: { doorProblem != nil },
                set: { (showing: Bool) in
                    if !showing {
                        doorProblem = nil
                    }
                }
            )
        ) {
            Button("OK") {
                doorProblem = nil
            }
        } message: {
            Text(doorProblem ?? "")
        }
        .alert(
            reviseRefusal?.title ?? "",
            isPresented: Binding(
                get: { reviseRefusal != nil },
                set: { (showing: Bool) in
                    if !showing {
                        reviseRefusal = nil
                    }
                }
            )
        ) {
            Button("OK") {
                reviseRefusal = nil
            }
        } message: {
            Text(reviseRefusal?.message ?? "")
        }
    }

    /// The thin bar above the plan: the unit popup, Back, Forward, Reload.
    var planBar: some View {
        HStack(spacing: 8) {
            Picker(PlanningWording.unitPopup, selection: choiceBinding) {
                ForEach(model.look.choices, id: \.self) { (choice: PlanningTab.Choice) in
                    Text(PlanningTab.title(for: choice, plans: model.look.plans)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("planningUnitPopup")
            Spacer()
            Button(PlanningWording.back, systemImage: "chevron.left") {
                model.controller?.goBack()
            }
            .labelStyle(.iconOnly)
            .help(PlanningWording.back)
            .disabled(!(model.controller?.canGoBack ?? false))
            .accessibilityIdentifier("planningBack")
            Button(PlanningWording.forward, systemImage: "chevron.right") {
                model.controller?.goForward()
            }
            .labelStyle(.iconOnly)
            .help(PlanningWording.forward)
            .disabled(!(model.controller?.canGoForward ?? false))
            .accessibilityIdentifier("planningForward")
            Button(PlanningWording.reload, systemImage: "arrow.clockwise") {
                lookAgain(reloadingThePage: true)
            }
            .labelStyle(.iconOnly)
            .help(PlanningWording.reload)
            .accessibilityIdentifier("planningReload")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// The empty tab: what a unit plan is, and a door to each assistant
    /// that is installed, Claude's first.
    var emptyOffer: some View {
        ContentUnavailableView {
            Label(PlanningWording.emptyTitle, systemImage: "calendar")
        } description: {
            Text(PlanningWording.emptyDescription)
        } actions: {
            HStack(spacing: 8) {
                if presence.claudeIsInstalled {
                    Button(PlanAUnit.claudeButtonTitle) {
                        planAUnit(with: .claude)
                    }
                    .accessibilityIdentifier("planAUnitWithClaude")
                }
                if presence.codexIsInstalled {
                    Button(PlanAUnit.codexButtonTitle) {
                        planAUnit(with: .codex)
                    }
                    .accessibilityIdentifier("planAUnitWithCodex")
                }
            }
        }
        .accessibilityIdentifier("planningEmpty")
    }

    // MARK: - Functions

    /// Reads the planning folder again, after making its `assets/` the
    /// app's own, and shows what is chosen: the same unit when it is still
    /// there (reloaded when asked), otherwise the unit the popup starts on.
    func lookAgain(reloadingThePage: Bool) {
        PlanningAssets.refresh(planningFolder: planningFolder)
        let look: PlanningTab.Look = PlanningTab.look(in: planningFolder, courseDirectory: course.directoryURL)
        if look != model.look {
            model.look = look
        }
        model.hasLooked = true
        if look.choices.isEmpty {
            model.choice = nil
            return
        }
        if let current = model.choice, look.choices.contains(current), model.controller != nil {
            if reloadingThePage {
                model.controller?.reload()
            }
            return
        }
        let starting: PlanningTab.Choice? = PlanningTab.startingChoice(
            plans: look.plans, choices: look.choices, today: CalendarDay.today()
        )
        model.choice = starting
        if let starting {
            show(starting)
        }
    }

    /// Loads a choice's page, making the web view the first time.
    func show(_ choice: PlanningTab.Choice) {
        if model.controller == nil {
            model.controller = PlanWebController()
        }
        model.controller?.show(
            page: PlanningTab.page(for: choice, planningFolder: planningFolder),
            planningFolder: planningFolder
        )
    }

    /// Opens `assistant`'s door with the planning message, after the
    /// refusal Revise With ▸ makes at the click; and, once it has opened,
    /// says so on the trail.
    func planAUnit(with assistant: FixWithAssistant.Assistant) {
        let item: CourseActivity.ReviseItem = assistant == .claude ? .claude : .codex
        if let refusal = workspace.reviseRefusal(item: item, courseCode: course.code, sectionNumber: nil) {
            reviseRefusal = refusal
            return
        }
        let message: String = PlanAUnit.openingMessage(
            courseCode: course.code, courseName: course.configuration.courseName
        )
        let opened: Bool
        switch assistant {
        case .claude:
            opened = ClaudeCodeLauncher.open(
                workspacePath: folder.path,
                courseCode: course.code,
                courseName: course.configuration.courseName,
                greeting: message
            )
        case .codex:
            opened = CodexLauncher.open(
                workspacePath: folder.path,
                courseCode: course.code,
                courseName: course.configuration.courseName,
                greeting: message
            )
        }
        if opened {
            PlanAUnit.noteOnTheTrail(courseCode: course.code, assistant: assistant)
            return
        }
        doorThatFailed = assistant
        if assistant == .claude {
            doorProblem = ClaudeCodeLauncher.couldNotStartSentence(courseCode: course.code)
        } else {
            doorProblem = CodexLauncher.couldNotStartSentence(courseCode: course.code)
        }
    }
}
