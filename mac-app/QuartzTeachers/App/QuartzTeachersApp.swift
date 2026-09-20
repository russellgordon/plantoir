import SwiftUI

@main
struct QuartzTeachersApp: App {

    // MARK: - Stored properties

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Used to open the About window from the application menu.
    @Environment(\.openWindow) var openWindow

    // MARK: - Initializer

    init() {
        // Claude Code drives the same tools the built-in assistant does, by
        // launching this binary with --mcp-stdio. Checked FIRST, and it never
        // returns: a server must not put a window on screen, register fonts,
        // or touch the teacher's saved window state.
        //
        // Serving from the app rather than a separate executable is what stops
        // the two clients' tool surfaces drifting — and it cannot be left out
        // of a build by a packaging script, the way Windows' plantoir-mcp.exe
        // was, because it IS the app.
        if let folder = AssistMCPServer.requestedWorkingFolder(from: CommandLine.arguments) {
            AssistMCPServer.serve(workingFolder: folder)
        }

        // A scheduled deploy, fired by launchd. Checked before anything that
        // puts a window on screen, and it never returns.
        //
        // The agent runs THIS binary rather than `/bin/bash` so that macOS can
        // attribute the work: the Background Activity notice names Plantoir
        // instead of "bash", and — the half that actually broke — a script the
        // app spawns inherits the app's permission to read the teacher's
        // files. A working folder on the Desktop is protected, and a bare
        // launchd interpreter is granted nothing, so a real 9:49 PM deploy
        // failed with "Operation not permitted" on every path while the same
        // deploy from the app minutes earlier took 144 seconds and worked.
        if let script = ScheduledDeploy.requestedScript(from: CommandLine.arguments) {
            ScheduledDeploy.runScheduled(
                script: script,
                section: ScheduledDeploy.requestedSection(from: CommandLine.arguments)
            )
        }

        // Writing the contracts in `contracts/` is the other thing this binary
        // does without becoming an app. Same reasoning as the MCP server: the
        // files describe what the app SAYS, which tools it has, and what it
        // asks the launchers to do, so they are written by the app rather than
        // by a script that would have to be kept in step with it by hand.
        if let directory = AssistContract.requestedDirectory(from: CommandLine.arguments) {
            print(AssistContract.write(into: directory))
            exit(0)
        }

        // Register bundled fonts so the settings form can preview the
        // site font choices.
        BundledFontList.registerFonts()
    }

    // MARK: - Body

    var body: some Scene {
        // A plain window group. Per-window SwiftUI persistence is not used
        // for the folder at all: @SceneStorage shared one value across the
        // group's windows, and presented values restored the same way —
        // last writer wins, both windows on one folder. The folder comes
        // from the app's own frame-keyed list instead.
        //
        // `id: "main"` exists only so code (the local assistant, when no
        // section window is open — see AssistToolRunner.revealSectionOnScreen)
        // can call `openWindow(id: "main")` to open a fresh one; there is
        // no bare, id-less `openWindow()` overload that opens "the app's
        // one WindowGroup" the way an earlier draft of this assumed. Giving
        // the group an id changes nothing about restoration (handled
        // entirely outside SwiftUI's own id-keyed mechanism, per the
        // comment above) or Cmd+N (SwiftUI's automatic New Window menu
        // item is generated per-scene regardless of id).
        WindowGroup("Plantoir", id: "main") {
            WindowRootView()
                // A bounded IDEAL size matters as much as the minimum:
                // without it the window's content is sized by whatever
                // its descendants claim, and one overgrown view drags
                // the whole interface (sidebar included) out of view.
                .frame(
                    minWidth: 900,
                    idealWidth: 1100,
                    maxWidth: .infinity,
                    minHeight: 600,
                    idealHeight: 720,
                    maxHeight: .infinity
                )
        }
        .commands {
            // The standard About item is replaced so it opens the custom
            // panel instead of the stock one.
            CommandGroup(replacing: .appInfo) {
                Button("About Plantoir") {
                    openWindow(id: "about")
                }
            }
            PreviewCommands()
            CommandGroup(after: .newItem) {
                WorkspaceCommands()
            }
            // Renaming a course sits in the Edit menu, under the standard
            // cut/copy/paste group, because that is the menu a teacher looks
            // in for "change this thing I have selected".
            CommandGroup(after: .pasteboard) {
                EditCommands()
            }
            // Beside Plantoir Help, because "something has gone wrong and I
            // need a person" is the same errand as looking for help — and it
            // is the menu somebody opens when they have run out of ideas.
            CommandGroup(after: .help) {
                ProblemReportCommands()
            }
        }

        // The assistant, one window per section.
        //
        // Keyed by the section rather than opened as a plain window, so asking
        // for it twice brings the existing one forward. A second window for
        // the same section would start a second engine — several more
        // gigabytes of the teacher's memory — and give them two conversations
        // that each believe they are the only one changing anything.
        //
        // Not restored on relaunch: reopening would load a model before the
        // teacher had asked for one.
        WindowGroup("Assistant", id: "assistant", for: AssistWindowRequest.self) { $request in
            if let request {
                AssistWindowView(
                    courseCode: request.courseCode,
                    sectionNumber: request.sectionNumber,
                    workingFolder: request.workingFolder
                )
            }
        }
        .restorationBehavior(.disabled)

        // The teacher's own settings, at ⌘, where macOS puts them. Declared
        // as a `Settings` scene rather than as a window of our own so the
        // menu item, the keyboard shortcut and the window's behaviour all
        // come from the system and match every other Mac application.
        Settings {
            PlantoirSettingsView()
        }

        // The About panel itself: traffic lights only, sized to content,
        // and never restored on relaunch.
        Window("About Plantoir", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
    }
}
