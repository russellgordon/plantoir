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
/// and anything a CHILD process resolves for itself. The LAUNCHERS are the
/// sharp edge: <c>preview.ps1</c>, <c>deploy.ps1</c> and <c>setup.ps1</c>
/// compute the builds root from <c>$env:LOCALAPPDATA</c> themselves, so a
/// preview or a deploy driven from a test builds into the REAL
/// <c>%LOCALAPPDATA%\Plantoir\builds\&lt;id of the temp working folder&gt;</c>
/// (<see cref="RealBuildsRoot"/>), not into the state folder. The scheduled-task
/// wrapper would bake the same into a REAL Task Scheduler task, so no test
/// schedules a deploy.</para>
///
/// <para><b>Since bundle 11 (2026-10-01) the tests DO run the launchers end to
/// end</b> — Russell lifted the old "never preview or publish from a test"
/// rule, because nothing proved the newest features through the window. What
/// remains is hygiene, and it lives HERE, in <see cref="Dispose"/>, so it runs
/// when a test fails too: every preview a test declared with
/// <see cref="WillServe"/> is stopped with the launcher's own
/// <c>preview.ps1 CODE N --stop</c>, any process still naming this run's
/// folders is ended, the real builds-root folder for this working folder is
/// deleted, and a course the app locked for reference is unlocked so the
/// temporary folder can go. <c>documentation/12-windows-app.md</c> → "Driving
/// the real interface" says what a test that runs a launcher owes.</para>
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

    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr window);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [System.Runtime.InteropServices.DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int count);

    /// <summary>
    /// A real mouse click in the middle of an element's bounding rectangle.
    /// Not <c>element.Click()</c>, which asks the element for its "clickable
    /// point": at 200% display scale the page picker answered with a point at
    /// TWICE its real coordinates (measured 2026-10-03 on a 3840-wide remote
    /// session: the pointer went to x=3839, the screen's edge, and y=1168 for a
    /// box whose middle was at y=584), so the click landed on whatever was
    /// behind the window and the typing followed it there. The bounding
    /// rectangle is in real pixels at every scale.
    /// </summary>
    public void ClickMiddleOf(AutomationElement element)
    {
        BringToFront();
        FlaUI.Core.Input.Mouse.Click(MiddleOf(element, Window.BoundingRectangle));
    }

    /// <summary>The right-click twin of <see cref="ClickMiddleOf"/> (#428 item 4), for a row's menu.</summary>
    public void RightClickMiddleOf(AutomationElement element)
    {
        BringToFront();
        FlaUI.Core.Input.Mouse.RightClick(MiddleOf(element, Window.BoundingRectangle));
    }

    /// <summary>
    /// Presses an item of a menu that is OPEN (#428 item 4): through its Invoke
    /// pattern when it has one, which is not real input and so cannot land
    /// anywhere else; otherwise a real click in the middle of its box. Not
    /// <see cref="ClickMiddleOf"/>: bringing the main window forward first can
    /// dismiss the open menu, which is in front already.
    /// </summary>
    public static void PressMenuItem(AutomationElement item)
    {
        if (item.Patterns.Invoke.IsSupported) item.Patterns.Invoke.Pattern.Invoke();
        else FlaUI.Core.Input.Mouse.Click(MiddleOf(item));
    }

    /// <summary>
    /// The middle of an element's bounding rectangle, which is in real pixels
    /// at every scale — or a <see cref="ClickWouldMissException"/> when a click
    /// there would land on something else (#428 review, ruling 1).
    /// <paramref name="within"/>: the main window's box, for anything inside
    /// it; null for an item of an OPEN menu, a popup that may sit outside it.
    /// </summary>
    public static System.Drawing.Point MiddleOf(AutomationElement element, System.Drawing.Rectangle? within = null)
    {
        bool offscreen;
        try { offscreen = element.IsOffscreen; } catch { offscreen = false; }
        string name;
        try { name = element.AutomationId is { Length: > 0 } id ? id : element.Name ?? "an element"; } catch { name = "an element"; }
        return MiddleWithin(element.BoundingRectangle, offscreen, within, name);
    }

    /// <summary>
    /// The rule of <see cref="MiddleOf"/>, apart from UI Automation so a plain
    /// test can pin it. The old <c>element.Click()</c> threw
    /// <c>NoClickablePointException</c> in each of these cases; the middle of
    /// a box does not, and FlaUI neither clamps the box of a row scrolled out
    /// of view nor refuses an empty one (whose middle is 0,0) — so without
    /// this a real click would go to the taskbar, the desktop or another app.
    /// </summary>
    internal static System.Drawing.Point MiddleWithin(System.Drawing.Rectangle box, bool offscreen,
                                                      System.Drawing.Rectangle? within, string describedAs)
    {
        if (offscreen)
            throw new ClickWouldMissException($"{describedAs} is off screen, so a click on it would land somewhere else.");
        if (box.Width <= 0 || box.Height <= 0)
            throw new ClickWouldMissException($"{describedAs} has an empty box ({box}), so a click on it would land somewhere else.");
        var middle = new System.Drawing.Point(box.Left + box.Width / 2, box.Top + box.Height / 2);
        if (within is { } window && !window.Contains(middle))
            throw new ClickWouldMissException($"The middle of {describedAs} ({middle.X},{middle.Y}) is outside Plantoir's window ({window}), so a click there would land somewhere else.");
        return middle;
    }

    /// <summary>
    /// Puts the app's window in front, for a test about to send REAL input (a
    /// mouse click, typed keys), which goes to whatever is in front. Windows
    /// refuses SetForegroundWindow from a process that is not itself in front,
    /// and this suite is started from a terminal that is. Joining the input queue of the
    /// window that IS in front is what lets the request through. Throws,
    /// naming the window in the way, rather than letting a test type into it.
    /// </summary>
    public void BringToFront()
    {
        IntPtr window = Window.Properties.NativeWindowHandle.Value;
        for (int attempt = 0; attempt < 5 && GetForegroundWindow() != window; attempt++)
        {
            uint front = GetWindowThreadProcessId(GetForegroundWindow(), out _);
            uint mine = GetCurrentThreadId();
            bool joined = front != 0 && front != mine && AttachThreadInput(mine, front, true);
            try
            {
                BringWindowToTop(window);
                SetForegroundWindow(window);
            }
            finally { if (joined) AttachThreadInput(mine, front, false); }
            Thread.Sleep(200);
        }
        if (GetForegroundWindow() != window)
        {
            var title = new System.Text.StringBuilder(200);
            GetWindowText(GetForegroundWindow(), title, title.Capacity);
            throw new InvalidOperationException(
                $"Plantoir could not be brought in front of \"{title}\", so a click or typed keys would go there instead.");
        }
    }
    public string WorkspacePath { get; }

    /// <summary>The folder this run's <c>--state-dir</c> points at — where the
    /// app keeps its settings, trail and any test-run record (#191).</summary>
    public string StateDirectory { get; }

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

    /// <param name="buildCourses">Writes the fixture's courses into <c>courses\</c>.</param>
    /// <param name="beforeLaunch">Given the working folder after it is set up and
    /// before the app starts — #473's test uses it to make the folder's copy of
    /// the tools stale, so the app has something to copy.</param>
    /// <param name="waitUntilReady">Whether to wait, after the sidebar appears,
    /// until the window says its folder is ready (#473): until then Preview,
    /// Deploy and New Course are disabled by design, and a test that pressed
    /// one would be testing the wait rather than what it meant to.</param>
    public DrivenApp(Action<string> buildCourses, Action<string>? beforeLaunch = null, bool waitUntilReady = true)
    {
        // Closed rather than refused: two copies would fight over the
        // foreground, and a physical click meant for the sidebar would land in
        // whichever window happened to be in front.
        //
        // But never a BUSY one (#155): a build, publish or any other live
        // lease in a folder the real settings know, or any running
        // plantoir-mcp, is work a kill would cut short. MachineWork holds the
        // rule (shared with the updater); the leases a kill orphans are swept,
        // by the killed pid only.
        var running = Process.GetProcessesByName("Plantoir");
        if (running.Length > 0)
        {
            var folders = Plantoir.Core.Assist.MachineWork.KnownFolders(Plantoir.Core.Assist.MachineWork.RealSettingsPath());
            if (Plantoir.Core.Assist.MachineWork.WhyBusy(Plantoir.Core.Assist.MachineWork.Read(folders)) is { } why)
                throw new InvalidOperationException($"{why} Not closing it; run again when it finishes.");
            foreach (var other in running)
            {
                Console.WriteLine($"Closing a running Plantoir (pid {other.Id}) so the tests can drive their own.");
                try { other.Kill(true); other.WaitForExit(5000); } catch { }
                foreach (string swept in Plantoir.Core.Assist.MachineWork.SweepLeasesOf(other.Id, folders))
                    Console.WriteLine($"Removed the lease it left: {swept}");
            }
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
        StateDirectory = stateDir;
        Directory.CreateDirectory(WorkspacePath);
        Directory.CreateDirectory(stateDir);

        // A folder is only a working folder once it carries the launchers —
        // Workspace.Classify looks for preview.ps1 — so a fixture of nothing
        // but courses/ shows the picker and no sidebar ever appears.
        ToolchainMirror.InitializeWorkspace(
            WorkspacePath, Path.Combine(Path.GetDirectoryName(ExecutablePath)!, "Toolchain"));
        buildCourses(Path.Combine(WorkspacePath, "courses"));
        beforeLaunch?.Invoke(WorkspacePath);

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

            // #473: the app copies what it needs into the folder in the
            // background after the window appears, and Preview, Deploy and
            // New Course stay disabled until it is done. On the fixture
            // InitializeWorkspace has already brought up to date, that is the
            // ordinary pass that only compares files — about half a second.
            if (waitUntilReady) WaitUntilReady(ReadyPatience);
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    // ---- Getting the folder ready (#473) ---------------------------------

    /// <summary>
    /// How long a folder may take to be got ready before a test gives up.
    /// The ordinary pass, with nothing to copy, is about half a second; a
    /// whole copy into an empty folder took 119.7 s on this PC (i5-8365U)
    /// after an update, so this covers a slow machine's ordinary pass with
    /// room to spare and says so when it does not.
    /// </summary>
    public static readonly TimeSpan ReadyPatience = TimeSpan.FromSeconds(90);

    /// <summary>
    /// The window's readiness as UI Automation reads it: the menu bar's
    /// ItemStatus, "copying", "ready" or "failed", present from the moment
    /// the window exists. Empty when the tree did not answer.
    /// </summary>
    public string Readiness()
    {
        try
        {
            var bar = Window.FindFirstDescendant(cf => cf.ByAutomationId("appMenuBar"));
            return bar?.Properties.ItemStatus.ValueOrDefault ?? "";
        }
        catch (System.Runtime.InteropServices.COMException) { return ""; }
    }

    /// <summary>Wait (polling every 100 ms) until the window says its folder is ready.</summary>
    public void WaitUntilReady(TimeSpan within)
    {
        var until = DateTime.UtcNow + within;
        string last = "";
        while (DateTime.UtcNow < until)
        {
            last = Readiness();
            if (last == "ready") return;
            if (last == "failed")
                throw new InvalidOperationException("Plantoir said it could not finish getting the working folder ready.");
            Thread.Sleep(100);
        }
        throw new InvalidOperationException(
            $"Plantoir was still getting the working folder ready after {within.TotalSeconds:0} s (last status '{last}').");
    }

    // ---- Finding things ---------------------------------------------------

    /// <summary>An element by automation id, waited for rather than assumed.</summary>
    public AutomationElement Find(string automationId, string describedAs)
    {
        var found = Retry.WhileNull(
            () => FirstOrNullOnce(automationId),
            Patience, TimeSpan.FromMilliseconds(250)).Result;
        return found ?? throw new InvalidOperationException(
            $"Never found {describedAs} (automation id '{automationId}').");
    }

    public AutomationElement? FindOrNull(string automationId, TimeSpan? within = null) =>
        Retry.WhileNull(() => FirstOrNullOnce(automationId),
                        within ?? TimeSpan.FromSeconds(3), TimeSpan.FromMilliseconds(200)).Result;

    /// <summary>
    /// "There is no such element", said only when the tree ANSWERED (bundle 11,
    /// V1). <see cref="FindOrNull"/> treats a timed-out query as "not yet",
    /// which is right for something awaited and wrong for an absence: with
    /// every query timing out, a negative check built on it passed whatever
    /// the screen showed. This one waits <paramref name="within"/> for an
    /// answering query to come back empty; an element still found then fails
    /// it, and so does a tree that never answers in that time plus 30 s.
    ///
    /// <para>And it does not stop at the first empty answer (W6): something
    /// drawn a moment late would pass that. From the first empty answer it
    /// keeps WATCHING for <paramref name="settle"/> (the 2 s the old checks
    /// watched for); any answered look that finds the element then fails it.</para>
    /// </summary>
    public void AssertAbsent(string automationId, string describedAs, TimeSpan? within = null, TimeSpan? settle = null) =>
        AssertAbsentWith(() => Window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)),
                         automationId, describedAs, within ?? TimeSpan.FromSeconds(2), settle: settle);

    /// <summary>The rule of <see cref="AssertAbsent"/>, with the query handed in so a plain test can pin it.</summary>
    internal static void AssertAbsentWith(Func<AutomationElement?> query, string automationId, string describedAs,
                                          TimeSpan within, TimeSpan? noAnswerGrace = null, TimeSpan? settle = null)
    {
        var start = DateTime.UtcNow;
        var giveUp = start + within + (noAnswerGrace ?? TimeSpan.FromSeconds(30));
        var watchFor = settle ?? TimeSpan.FromSeconds(2);
        DateTime? emptySince = null;
        string lastError = "";
        while (true)
        {
            try
            {
                if (query() is null)
                {
                    // The tree answered: nothing there. Watched a while longer.
                    emptySince ??= DateTime.UtcNow;
                    if (DateTime.UtcNow - emptySince >= watchFor) return;
                }
                else if (emptySince is not null)
                    throw new Xunit.Sdk.XunitException($"{describedAs} appeared (automation id '{automationId}') after it had been absent, and should not be there.");
                else if (DateTime.UtcNow - start >= within)
                    throw new Xunit.Sdk.XunitException($"{describedAs} is there (automation id '{automationId}') and should not be.");
            }
            catch (System.Runtime.InteropServices.COMException error)
            {
                lastError = error.Message;
                // An empty answer already given, and nothing since to say otherwise.
                if (emptySince is not null && DateTime.UtcNow - emptySince >= watchFor) return;
                if (DateTime.UtcNow >= giveUp)
                    throw new Xunit.Sdk.XunitException(
                        $"Could not tell whether {describedAs} is absent: UI Automation did not answer ({lastError}).");
            }
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// One look. A UI Automation query that TIMES OUT (COMException 0x80131505,
    /// seen once in bundle 11's fourth run while the app was busy drawing a
    /// dialog) counts as "not yet" and is asked again by the caller's retry,
    /// rather than failing a test with a sentence about COM.
    /// </summary>
    private AutomationElement? FirstOrNullOnce(string automationId)
    {
        try { return Window.FindFirstDescendant(cf => cf.ByAutomationId(automationId)); }
        catch (System.Runtime.InteropServices.COMException) { return null; }
    }

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
            ClickMiddleOf(node);
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

    // ---- What the launchers leave behind (bundle 11) ----------------------

    /// <summary>
    /// Where the LAUNCHERS put this run's built sites: the real
    /// <c>%LOCALAPPDATA%\Plantoir\builds\&lt;folder id&gt;</c>. The app's own idea
    /// of it is under <c>--state-dir</c>, which no launcher reads, so this is
    /// the one a test reads a build back from — and the one it must delete.
    /// </summary>
    public string RealBuildsRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "builds",
        FolderContainers.FolderIdentifier(WorkspacePath));

    /// <summary>A folder beside the working folder, deleted with the run — for a
    /// publish destination, or a folder to import from.</summary>
    public string Scratch(string name)
    {
        string path = Path.Combine(_root, name);
        Directory.CreateDirectory(path);
        return path;
    }

    private readonly List<(string Code, int Section)> _served = new();

    /// <summary>Say BEFORE pressing Preview that this section may be served, so
    /// teardown stops it even when the test fails before it presses Stop.</summary>
    public void WillServe(string code, int section) => _served.Add((code, section));

    /// <summary>Every incidental dialog a wait answered, and what it said —
    /// kept so a failure can say what the app put in the way.</summary>
    public List<string> Answered { get; } = new();

    public AutomationElement Desktop => Window.Automation.GetDesktop();

    /// <summary>Right-click a sidebar row and press one item of its menu.</summary>
    public void PressRowMenuItem(string rowAutomationId, string itemName)
    {
        var row = Find(rowAutomationId, $"the sidebar row {rowAutomationId}");
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            // A dialog that is still closing covers the window with its
            // smoke layer, and the row then has no clickable point
            // (NoClickablePointException, run 8 of bundle 11): wait it out.
            // Skipped and retried when the wait runs out, as before #428: the
            // click must not go ahead whatever the wait found.
            if (!Retry.WhileFalse(() => { try { return row.TryGetClickablePoint(out _); } catch { return false; } },
                                  TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result)
                continue;
            try { RightClickMiddleOf(row); }
            catch (ClickWouldMissException) { Thread.Sleep(1000); continue; }
            // The app's own window first — its menus are popups inside it, and
            // a whole-desktop query is the one that timed out (COMException
            // 0x80131505, run 5 of bundle 11); a timeout is "not yet".
            var item = Retry.WhileNull(() =>
            {
                try
                {
                    return Window.FindFirstDescendant(cf => cf.ByName(itemName).And(cf.ByControlType(ControlType.MenuItem)))
                           ?? Desktop.FindFirstDescendant(cf => cf.ByName(itemName).And(cf.ByControlType(ControlType.MenuItem)));
                }
                catch (System.Runtime.InteropServices.COMException) { return null; }
            }, TimeSpan.FromSeconds(8), TimeSpan.FromMilliseconds(250)).Result;
            if (item is null) continue;
            PressMenuItem(item);
            return;
        }
        throw new InvalidOperationException($"The menu of {rowAutomationId} never offered \"{itemName}\".");
    }

    /// <summary>Click a section's row, and wait for its toolbar's title
    /// (<c>CODE-S1</c>, by the code a teacher reads — <paramref name="shownCode"/>
    /// for a reference course whose folder is <c>CODE-2025</c>).</summary>
    public void SelectSection(string code, int section, string? shownCode = null)
    {
        var node = Find($"sidebar-{code}-section{section}", $"the sidebar entry for {code} section {section}");
        string title = $"{shownCode ?? code}-S{section}";
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            ClickMiddleOf(node);
            var arrived = Retry.WhileFalse(
                () => (Window.FindFirstDescendant(cf => cf.ByAutomationId("SectionTitle"))?.Name ?? "").StartsWith(title, StringComparison.Ordinal),
                TimeSpan.FromSeconds(6), TimeSpan.FromMilliseconds(250)).Result;
            if (arrived) return;
        }
        throw new InvalidOperationException($"{code} section {section} never opened after three clicks on its sidebar entry.");
    }

    private static readonly string[] DialogButtonIds = { "PrimaryButton", "SecondaryButton", "CloseButton", "copyPagePrimary", "copyPageClose" };

    /// <summary>
    /// The ContentDialog on screen, if any. Measured on the first unlocked run
    /// (bundle 11): UI Automation shows one as a <c>Window</c> of class
    /// <c>Popup</c> NAMED BY ITS TITLE — there is no "ContentDialog" class in
    /// the tree — beside other, empty popups, so it is told apart by holding a
    /// dialog's own buttons.
    /// </summary>
    public AutomationElement? OpenDialog()
    {
        foreach (var popup in Window.FindAllDescendants(cf => cf.ByClassName("Popup").And(cf.ByControlType(ControlType.Window))))
        {
            try
            {
                foreach (string id in DialogButtonIds)
                    if (popup.FindFirstDescendant(cf => cf.ByAutomationId(id)) is not null) return popup;
            }
            catch { }
        }
        return null;
    }

    /// <summary>
    /// Wait for <paramref name="done"/>, ANSWERING whatever ordinary dialog the
    /// app puts up meanwhile with its Close button — today's class ("Not
    /// Today"), a folder-problem finding, the links checklist offer. Every one
    /// is recorded in <see cref="Answered"/> with what it said, and a timeout
    /// reports them, because a refusal answered here is the likeliest reason
    /// the wait never ended.
    /// </summary>
    public bool WaitAnsweringDialogs(Func<bool> done, TimeSpan within)
    {
        var until = DateTime.UtcNow + within;
        while (DateTime.UtcNow < until)
        {
            try { if (done()) return true; } catch { }
            try
            {
                if (OpenDialog() is { } dialog
                    && dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton")) is { } close
                    && close.IsEnabled)
                {
                    string said = string.Join(" | ", TextsUnder(dialog));
                    Answered.Add($"{dialog.Name}: {said}");
                    Console.WriteLine($"Answered a dialog with Close: {dialog.Name}: {said}");
                    close.AsButton().Invoke();
                }
            }
            catch { }
            Thread.Sleep(750);
        }
        try { return done(); } catch { return false; }
    }

    public string AnsweredSoFar => Answered.Count == 0 ? " No dialog was answered on the way."
        : " Dialogs answered on the way: " + string.Join(" || ", Answered);

    /// <summary>
    /// Ends what a test that ran the launchers left running, and deletes the
    /// real builds-root folder they made. Never fatal: it runs on the way out of
    /// a test that may already have failed for a better reason.
    /// </summary>
    private void CleanUpAfterTheLaunchers()
    {
        string buildsRoot;
        try { buildsRoot = RealBuildsRoot; } catch { return; }
        if (_served.Count == 0 && !Directory.Exists(buildsRoot)) return;

        string? runtime = Path.Combine(Path.GetDirectoryName(ExecutablePath)!, "runtime");
        if (!File.Exists(Path.Combine(runtime, "manifest.json"))) runtime = null;
        foreach (var (code, section) in _served)
        {
            // The launcher's own stop: it ends the section's build and serve by
            // the directories they work in, which is what the app's Stop runs.
            RunPowerShell($"& '{Path.Combine(WorkspacePath, "preview.ps1").Replace("'", "''")}' {code} {section} --stop",
                          WorkspacePath, runtime);
        }

        // Anything still naming this run's folders: a deploy's launcher, its
        // python, a serve the stop missed. Never this sweep's own process.
        string needles = string.Join(",", new[] { _root, buildsRoot }.Select(p => "'" + p.Replace("'", "''") + "'"));
        RunPowerShell(
            "$needles = @(" + needles + "); " +
            "Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine } | " +
            "Where-Object { $line = $_.CommandLine; @($needles | Where-Object { $line.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0 } | " +
            "ForEach-Object { Write-Output (\"ended \" + $_.Name + \" \" + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
            WorkspacePath, runtime: null);

        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_KEEP") == "1")
        {
            Console.WriteLine($"PLANTOIR_UI_KEEP: leaving this run's build at {buildsRoot}");
            return;
        }
        for (int attempt = 1; attempt <= 6 && Directory.Exists(buildsRoot); attempt++)
        {
            try { Directory.Delete(buildsRoot, recursive: true); }
            catch { Thread.Sleep(1000); }
        }
        if (Directory.Exists(buildsRoot))
            Console.WriteLine($"Could not delete this run's build at {buildsRoot}.");
    }

    private static void RunPowerShell(string command, string workingDirectory, string? runtime)
    {
        try
        {
            var psi = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = workingDirectory,
            };
            foreach (string arg in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command })
                psi.ArgumentList.Add(arg);
            if (runtime is not null) psi.Environment["PLANTOIR_RUNTIME"] = runtime;
            using var process = Process.Start(psi)!;
            string output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(90_000);
            if (output.Trim().Length > 0) Console.WriteLine(output.Trim());
        }
        catch (Exception error)
        {
            Console.WriteLine($"Clean-up step failed: {error.Message}");
        }
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
        // And waited for by pid as well: the app locks a reference course OFF
        // its UI thread, so a lock pass still finishing as it dies must be over
        // before the unlock below, or it re-locks what was just unlocked.
        try
        {
            if (_app is not null) Process.GetProcessById(_app.ProcessId).WaitForExit(10_000);
        }
        catch { /* already gone */ }
        CleanUpAfterTheLaunchers();
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
        if (!DeleteRunFolder(_root))
            Console.WriteLine($"Could not delete this run's files at {_root}.");
    }

    /// <summary>
    /// Deletes a run's temporary folder, LIFTING THE REFERENCE LOCK FIRST
    /// (#428 item 5). A course kept for reference is locked by the app (deny
    /// entries) the moment the folder is read, and a locked tree refuses to be
    /// deleted: after the 44-of-44 run of 2026-10-03 two
    /// <c>%TEMP%\plantoir-ui-&lt;run&gt;-*</c> folders remained, <c>rmdir</c>
    /// refused "Access is denied" on <c>courses\ICS3U-…\section1\index.md</c>,
    /// and <c>icacls /reset /T</c> removed them by hand.
    ///
    /// <para>The unlock covers the WHOLE run folder, not only
    /// <c>workspace\courses</c> as it did before: an import test keeps last
    /// year's working folder in a scratch folder beside it, which the app reads
    /// too. And it is asked again between attempts, so a lock written late
    /// (by a pass still finishing when the app died) is lifted as well. Never
    /// throws; says whether the folder is gone.</para>
    /// </summary>
    internal static bool DeleteRunFolder(string root)
    {
        for (int attempt = 1; attempt <= 3 && Directory.Exists(root); attempt++)
        {
            try { Plantoir.Core.Models.ReferenceLock.Unlock(root); } catch { }
            try { Directory.Delete(root, recursive: true); }
            catch { Thread.Sleep(500); }
        }
        return !Directory.Exists(root);
    }
}

/// <summary>A real click that would not land on the element it was meant for (#428 review, ruling 1).</summary>
public sealed class ClickWouldMissException : InvalidOperationException
{
    public ClickWouldMissException(string message) : base(message) { }
}
