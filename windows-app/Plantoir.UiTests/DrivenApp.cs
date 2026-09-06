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
/// launched with <c>--state-dir</c>, so its settings file and its breadcrumb
/// trail live in a temporary folder that is deleted at the end. The working
/// folder is built from scratch, not borrowed. What is NOT isolated, and is
/// named here so nobody assumes otherwise: any WebView2 cache, and anything
/// the app would write under its models or builds folders — none of which a
/// Course Settings test reaches.</para>
///
/// <para><b>It refuses to start while a Plantoir is already running</b> rather
/// than killing it. Russell's own copy may be mid-preview or mid-deploy, and
/// a test runner that quietly stops it is exactly the thing CLAUDE.md forbids.
/// Close it first, or pass -Force to the script if you know it is idle.</para>
/// </summary>
public sealed class DrivenApp : IDisposable
{
    private readonly Application _app;
    private readonly UIA3Automation _automation;
    private readonly string _root;

    public Window Window { get; }
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
        if (Process.GetProcessesByName("Plantoir").Length > 0)
            throw new InvalidOperationException(
                "Plantoir is already running. These tests drive the real app and would fight it — " +
                "close it first. (It is not stopped automatically on purpose: it may be mid-preview.)");

        _root = Path.Combine(Path.GetTempPath(), "plantoir-ui-" + Guid.NewGuid().ToString("N")[..8]);
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

        var psi = new ProcessStartInfo(ExecutablePath) { UseShellExecute = false };
        psi.ArgumentList.Add("--state-dir");
        psi.ArgumentList.Add(stateDir);   // ArgumentList quotes for us
        _app = Application.Launch(psi);
        _automation = new UIA3Automation();

        Window = Retry.WhileNull(() => _app.GetMainWindow(_automation, TimeSpan.FromSeconds(2)),
                                 Patience, TimeSpan.FromMilliseconds(400)).Result
                 ?? throw new InvalidOperationException("Plantoir never showed its window.");

        // The sidebar is the proof the workspace was accepted; without it the
        // app is sitting on the picker and every later failure is a red
        // herring about a missing button.
        _ = Find("ListControl", "the course list") ;
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
        node.Click();
        // The form is built on the selection, so wait for its own button
        // rather than sleeping and hoping.
        _ = Find("openFoldersHelpButton", $"Course Settings for {code}");
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
        try
        {
            foreach (var p in Process.GetProcessesByName("Plantoir")) { p.Kill(true); p.WaitForExit(5000); }
        }
        catch { }
        // Deleted last, and never fatally: a locked file must not turn a
        // passing test red, and the folder is under TEMP either way.
        try { Directory.Delete(_root, recursive: true); } catch { }
    }
}
