using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// One run of the real Plantoir, with a working folder and a state directory
/// of its own, driven through UI Automation and torn down afterwards.
///
/// <para><b>Nothing here touches the teacher's own state.</b> The app is
/// launched with <c>--state-dir</c>, which moves its ENTIRE Plantoir folder —
/// settings, the breadcrumb trail, the startup log, scheduled-deploy
/// sentinels, models, built sites — into a temporary folder deleted at the
/// end. The working folder is built from scratch, not borrowed.</para>
///
/// <para>The one thing that made this more than tidiness: the app consumes
/// pending scheduled-deploy sentinels on launch AND on every activation, and
/// applying one writes publish state into the course folder the sentinel
/// names — an absolute path to a REAL course. An earlier version redirected
/// only settings and the trail, so a test run could have marked a teacher's
/// section as published and put the line explaining it in the redirected
/// trail, where nobody would ever look.</para>
///
/// <para>Still NOT isolated, so nobody assumes otherwise: Credential Manager,
/// and anything a CHILD process resolves for itself. The LAUNCHERS are the sharp edge and are worth
/// naming separately: <c>preview.ps1</c> and <c>deploy.ps1</c> compute the
/// builds root from the environment themselves, and the scheduled-task
/// wrapper bakes the same into the script it registers. So a redirected run
/// that PREVIEWED would look for its build where the launcher did not put it,
/// and one that SCHEDULED a deploy would register a REAL Task Scheduler task
/// whose sentinels land in the teacher's real pending folder. Neither is done
/// by any test today, and neither should be without reading this first.</para>
///
/// <para><b>One launcher IS run now</b> — <c>NewCourseWizardUiTests</c> presses
/// Create, which runs <c>setup.ps1</c> — and it is safe for narrow reasons
/// that nothing enforces. They are written out once, in
/// <c>documentation/12-windows-app.md</c> under "The flags the app answers";
/// read them before a test runs a DIFFERENT launcher, because preview and
/// schedule would NOT be safe.</para>
///
/// <para><b>A running Plantoir is closed, not worked around.</b> Russell's
/// standing instruction (2026-09-06, and CLAUDE.md's Windows setup notes):
/// stopping to ask every time is a hassle, and it is his own development copy
/// with no unsaved state of its own. The one obligation that comes with it is
/// to SAY so — <c>run-ui-tests.ps1</c> prints it, and so does the runner's
/// output — so nobody is left wondering where their window went.</para>
/// </summary>
public sealed class DrivenApp : IDisposable
{
    private readonly Application? _app;
    private readonly UIA3Automation _automation;
    private readonly string _root;

    public Window Window { get; } = null!;
    public string WorkspacePath { get; }

    /// <summary>How long to wait for the interface to catch up. Generous: a
    /// cold first launch loads the Windows App SDK, and a machine under load
    /// is slow rather than broken.</summary>
    private static readonly TimeSpan Patience = TimeSpan.FromSeconds(30);

    public static string ExecutablePath
    {
        get
        {
            // The x64 Debug build — the same one Russell's "PT - Dev" shortcut
            // runs, so the tests exercise what he is about to test by hand.
            string here = AppContext.BaseDirectory;
            var dir = new DirectoryInfo(here);
            while (dir is not null && dir.Name != "windows-app") dir = dir.Parent;
            if (dir is null) throw new InvalidOperationException("Could not locate windows-app/ from " + here);
            string exe = Path.Combine(dir.FullName, "Plantoir", "bin", "x64", "Debug",
                                      "net9.0-windows10.0.19041.0", "win-x64", "Plantoir.exe");
            if (!File.Exists(exe))
                throw new InvalidOperationException(
                    $"No x64 Debug build at {exe}. Build it first:\n" +
                    "  dotnet build Plantoir\\Plantoir.csproj -c Debug -p:Platform=x64");
            return exe;
        }
    }

    public DrivenApp(Action<string> buildCourses)
    {
        // Closed rather than refused: two copies would fight over the
        // foreground, and a physical click meant for the sidebar would land in
        // whichever window happened to be in front.
        foreach (var other in Process.GetProcessesByName("Plantoir"))
        {
            Console.WriteLine($"Closing a running Plantoir (pid {other.Id}) so the tests can drive their own.");
            try { other.Kill(true); other.WaitForExit(5000); } catch { }
        }

        // The folder name carries THIS RUN's token when the runner supplied
        // one, so run-ui-tests.ps1's orphan sweep can match its own children
        // and nothing else. Without it two parallel runs would sweep each
        // other's live launchers, and a developer reading a kept folder — say
        // `Get-Content ...\plantoir-ui-*\state\Logs\startup.log -Wait` — would
        // have the pattern in their own command line and be force-killed.
        string run = Environment.GetEnvironmentVariable("PLANTOIR_UI_RUN") is { } token
                     && !string.IsNullOrWhiteSpace(token) ? token : "solo";
        _root = Path.Combine(Path.GetTempPath(),
                             $"plantoir-ui-{run}-{Guid.NewGuid().ToString("N")[..8]}");
        WorkspacePath = Path.Combine(_root, "workspace");
        string stateDir = Path.Combine(_root, "state");
        Directory.CreateDirectory(WorkspacePath);
        Directory.CreateDirectory(stateDir);

        // A folder is only a working folder once it carries the launchers —
        // Workspace.Classify looks for preview.ps1 — so a fixture of nothing
        // but courses/ shows the picker and no sidebar ever appears.
        ToolchainMirror.InitializeWorkspace(
            WorkspacePath, Path.Combine(Path.GetDirectoryName(ExecutablePath)!, "Toolchain"));
        buildCourses(Path.Combine(WorkspacePath, "courses"));

        File.WriteAllText(Path.Combine(stateDir, "settings.json"), new JsonObject
        {
            ["WorkspacePath"] = WorkspacePath,
            ["RestoreWindowsOnLaunch"] = false,
        }.ToJsonString(), new UTF8Encoding(false));

        // UseShellExecute = TRUE, and this is not a detail: it is the one line
        // that decides whether a test can drive anything the app SHELLS OUT to
        // — creating a course, previewing, publishing.
        //
        // WHY is already written down, once, in ConPtyProcess.Start's own
        // CAUTION: the child binds to the pseudo console only when the
        // CREATING process's std handles are clean — console handles or none —
        // and a creator whose stdio is redirected to pipes leaks those handles
        // into the child instead. ShellExecute gives a GUI process no std
        // handles at all, which is the "or none" case, and is also exactly
        // what a teacher's shortcut does. (That the `dotnet test` host's own
        // handles are PIPES is inferred rather than measured — it fits, since
        // console handles would have put the launcher's output in the terminal
        // and the one-second EOF is what a closed pipe gives. Flagged as an
        // inference because the version of this comment before it was exactly
        // that: a plausible story stated as fact.)
        //
        // Measured 2026-09-07 (Lenovo 20QES70500, Intel Core i5-8365U @
        // 1.60 GHz, 16 GB), one variable, three launches of the same build:
        // clean CONSOLE handles (cmd.exe in its own window) → the course is
        // made, setup.ps1 succeeded after 21 s. ShellExecute → the same, 21 s.
        // Output REDIRECTED to a file → the launcher's output lands in the
        // redirect target, the app captures nothing, and the run hangs on the
        // first prompt because the answer never reaches the child. Under
        // `dotnet test` the same leak ends faster and looks worse: "failed
        // (exit code 1) after 1s" with an EMPTY transcript, because the pipe
        // gives the child EOF and `input()` in setup_course.py dies.
        //
        // The trap is REDIRECTED stdio, NOT an inherited console — an earlier
        // version of this comment said the opposite, and the experiment above
        // is what settled it. So `.\Plantoir.exe` at an ordinary prompt is
        // fine; `.\Plantoir.exe > out.txt` is not.
        var psi = new ProcessStartInfo(ExecutablePath) { UseShellExecute = true };
        psi.ArgumentList.Add("--state-dir");
        psi.ArgumentList.Add(stateDir);   // ArgumentList quotes for us
        _app = Application.Launch(psi);
        _automation = new UIA3Automation();

        // Everything past the launch is inside a try: a constructor that
        // throws is never Disposed, so without this a single failed launch
        // strands the process AND makes every later test in the run fail with
        // "Plantoir is already running" — a message about the wrong problem,
        // which is the expensive kind of failure.
        try
        {
            Window = Retry.WhileNull(() => _app.GetMainWindow(_automation, TimeSpan.FromSeconds(2)),
                                     Patience, TimeSpan.FromMilliseconds(400)).Result
                     ?? throw new InvalidOperationException("Plantoir never showed its window.");

            // Proof the workspace was ACCEPTED — without it the app is sitting
            // on the folder picker and every later failure is a red herring
            // about a missing button. The whole sidebar is inside the
            // SplitView, which is collapsed until the folder is ready.
            //
            // Not the TreeView itself: WinUI's TreeView template replaces our
            // `coursesSidebar` id with its own part name (`ListControl`), so
            // the id we set never reaches the automation tree — measured, not
            // assumed. `addCourseButton` is our own, on a plain Button, and is
            // there only in the ready state.
            _ = Find("addCourseButton", "the course list");
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    // ---- Finding things ---------------------------------------------------

    /// <summary>An element by automation id, waited for rather than assumed.</summary>
    public AutomationElement Find(string automationId, string describedAs)
    {
        var found = Retry.WhileNull(
            () => Window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
            Patience, TimeSpan.FromMilliseconds(250)).Result;
        return found ?? throw new InvalidOperationException(
            $"Never found {describedAs} (automation id '{automationId}').");
    }

    public AutomationElement? FindOrNull(string automationId, TimeSpan? within = null) =>
        Retry.WhileNull(() => Window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                        within ?? TimeSpan.FromSeconds(3), TimeSpan.FromMilliseconds(200)).Result;

    /// <summary>Select a course in the sidebar, which is what opens its
    /// settings — there is no other way in.</summary>
    public void SelectCourse(string code)
    {
        var node = Find("sidebar-" + code, $"the sidebar entry for {code}");

        // Clicked, and checked, and clicked again if it did not take. This has
        // to be a PHYSICAL click: the sidebar acts on TreeView.ItemInvoked,
        // which SelectionItem.Select does not raise — so the selection travels
        // by mouse, and a mouse click can land while the window is busy or
        // while something else briefly holds the foreground. One missed click
        // then fails a later assertion about the sheet, which is a lie about
        // where the problem was.
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            node.Click();
            var arrived = Retry.WhileNull(
                () => Window.FindFirstDescendant(cf => cf.ByAutomationId("openFoldersHelpButton")),
                TimeSpan.FromSeconds(6), TimeSpan.FromMilliseconds(250)).Result;
            if (arrived is not null) return;
        }

        throw new InvalidOperationException(
            $"Course Settings for {code} never opened after three clicks on its sidebar entry.");
    }

    /// <summary>Every Text element under an element, in tree order, with the
    /// empty ones dropped. This is what a teacher actually reads.</summary>
    public static List<string> TextsUnder(AutomationElement root)
    {
        var said = new List<string>();
        foreach (var t in root.FindAllDescendants(cf => cf.ByControlType(ControlType.Text)))
        {
            string name;
            try { name = t.Name ?? ""; } catch { continue; }
            if (!string.IsNullOrWhiteSpace(name)) said.Add(name);
        }
        return said;
    }

    public void Dispose()
    {
        try { _automation.Dispose(); } catch { }
        // Ours by pid, not everything called Plantoir. The constructor closes
        // whatever was running when it STARTED; a copy opened during the run is
        // somebody else's and is not ours to close.
        try
        {
            if (_app is not null && !_app.HasExited) _app.Kill();   // Kill waits for exit
        }
        catch { }
        // Deleted last, and never fatally: a locked file must not turn a
        // passing test red, and the folder is under TEMP either way.
        //
        // PLANTOIR_UI_KEEP=1 leaves it behind instead — EVERY test's, since
        // teardown does not know whether the test passed. A UI test that fails
        // inside the app has almost nothing to say from out here: the useful
        // evidence is the run's own startup.log, breadcrumb trail, per-run
        // launcher log and working folder, and all of it is inside this folder
        // being deleted. Written after an afternoon of guessing at a launcher
        // failure whose reason was sitting in a log already thrown away.
        //
        // run-ui-tests.ps1 prints the kept paths too, and THAT is the notice
        // to rely on: plain Console output from Dispose is not attached to a
        // test result and often does not surface in `dotnet test`.
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_KEEP") == "1")
        {
            Console.WriteLine($"PLANTOIR_UI_KEEP: leaving this run's files at {_root}");
            return;
        }
        try { Directory.Delete(_root, recursive: true); } catch { }
    }
}
