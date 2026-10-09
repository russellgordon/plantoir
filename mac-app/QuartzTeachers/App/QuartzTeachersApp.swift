import SwiftUI

@main
struct QuartzTeachersApp: App {

    // MARK: - Stored properties

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Used to open the About window from the application menu.
    @Environment(\.openWindow) var openWindow

    // MARK: - Initializer

    init() {
        // A folder standing in for the home folder (#154), checked before
        // ANYTHING else — before the server, the scheduled run and the
        // contracts below, which all keep state of their own. A malformed flag
        // ends the launch here: a redirect that silently did not happen is a
        // test that reports success while writing the teacher's real trail.
        do {
            if let stateDirectory = try RealHome.stateDirectory(fromArguments: CommandLine.arguments) {
                try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            }
        } catch let problem as RealHome.StateDirectoryProblem {
            FileHandle.standardError.write(Data(("Plantoir: " + problem.explanation + "\n").utf8))
            exit(64)
        } catch {
            FileHandle.standardError.write(Data(("Plantoir: could not create the state folder: \(error)\n").utf8))
            exit(64)
        }

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
        // comment above). ⌘N is File ▸ New Window, which `FileCommands`
        // draws in place of SwiftUI's automatic New submenu (#457).
        WindowGroup("Plantoir", id: "main") {
            WindowRootView()
                // A bounded IDEAL size matters as much as the minimum:
                // without it the window's content is sized by whatever
                // its descendants claim, and one overgrown view drags
                // the whole interface (sidebar included) out of view.
                .frame(
                    minWidth: WindowChrome.minimumWindowWidth,
                    idealWidth: 1100,
                    maxWidth: .infinity,
                    minHeight: WindowChrome.minimumWindowHeight,
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
            // Where every Mac application puts it (#204). Drawn only when the
            // app has an updater, which a development build never does.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
            // The menu bar reads Plantoir · File · Edit · View · Course ·
            // Section · Window · Help (#457). File works with no window open;
            // View carries the preview's Back, Forward and Reload Page; Course
            // and Section carry every action on a course or a section, which
            // the context menus and buttons also reach. Edit is the system's
            // own again: Rename moved to Course, where a teacher looks for
            // "do something to this course".
            FileCommands(openWindow: openWindow)
            ViewCommands()
            CourseMenu()
            SectionMenu()
            // Plantoir Help opens plantoir.app's support page, in place of
            // the system's "Help isn't available" (#457, the HIG sweep).
            CommandGroup(replacing: .help) {
                PlantoirHelpCommand()
            }
            // Beside Plantoir Help, because "something has gone wrong and I
            // need a person" is the same errand as looking for help — and it
            // is the menu somebody opens when they have run out of ideas.
            CommandGroup(after: .help) {
                ProblemReportCommands()
            }
        }

        // The assistant, one window per section — opened from Revise With ▸
        // Local AI Assistant… for a section, and never on its own: File
        // offers no "New Assistant Window" since #457, because an assistant
        // with no section behind it has nothing to talk about (Russell,
        // 2026-10-08).
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
            // A window is never opened on a course kept for reference. The
            // menu item is not drawn on one, so this catches the ways round
            // that: a restored scene, or a stale `openWindow(value:)`.
            if let request, !request.namesACourseKeptForReference() {
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
        // Out of the Window menu, which manages windows (#457): without this
        // the scene is listed there as a second "About Plantoir", beside the
        // application menu's own (measured, step 0).
        .commandsRemoved()
    }
}
