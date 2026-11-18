using System.Diagnostics;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.UIA3;

namespace Plantoir.FirstInstall;

/// <summary>One top-level window as UI Automation sees it.</summary>
internal sealed record SeenWindow(IntPtr Handle, string Title, string Class, string Process, int ProcessId, AutomationElement Element)
{
    public override string ToString() => $"\"{Title}\" (class {Class}, process {Process})";
}

/// <summary>
/// Watches every top-level window on the desktop, and every dialog inside
/// Plantoir's window. The windows open when the driver starts are the desktop
/// and are left alone. A window that appears later is judged by
/// <see cref="WindowRules"/> for the current <see cref="Stage"/>: the stage
/// names the windows it expects, and anything else ends the run, named, with
/// a screenshot and the words it showed.
/// </summary>
internal sealed class WindowWatch
{
    private readonly UIA3Automation _automation;
    private readonly HashSet<IntPtr> _baseline = new();
    private readonly HashSet<IntPtr> _reported = new();
    private readonly HashSet<string> _allowedSeen = new();
    private readonly List<string> _baselineNames = new();

    private static readonly string[] DialogButtonIds = { "PrimaryButton", "SecondaryButton", "CloseButton" };

    public WindowWatch(UIA3Automation automation)
    {
        _automation = automation;
        foreach (var window in TopLevel())
        {
            _baseline.Add(window.Handle);
            _baselineNames.Add(window.ToString());
        }
    }

    public string BaselineDescription => string.Join("; ", _baselineNames);

    /// <summary>The stage whose allow-list applies. Set by each step as it starts.</summary>
    public Stage Stage { get; set; } = Stage.Starting;

    /// <summary>Plantoir's main window once it is open; its dialogs are judged too.</summary>
    public AutomationElement? PlantoirWindow { get; set; }

    /// <summary>How many times the desktop has been looked at, for the log.</summary>
    public int Looks { get; private set; }

    /// <summary>Every top-level window now, skipping any that vanish while being read.</summary>
    public List<SeenWindow> TopLevel()
    {
        var found = new List<SeenWindow>();
        AutomationElement[] children;
        try { children = _automation.GetDesktop().FindAllChildren(); }
        catch (System.Runtime.InteropServices.COMException) { return found; }
        foreach (var child in children)
        {
            try
            {
                IntPtr handle = child.Properties.NativeWindowHandle.ValueOrDefault;
                int pid = child.Properties.ProcessId.ValueOrDefault;
                string process = "";
                try { process = Process.GetProcessById(pid).ProcessName; } catch { }
                found.Add(new SeenWindow(handle, child.Properties.Name.ValueOrDefault ?? "",
                                         child.Properties.ClassName.ValueOrDefault ?? "", process, pid, child));
            }
            catch { }
        }
        return found;
    }

    /// <summary>Windows that were not there when the driver started.</summary>
    public List<SeenWindow> New()
    {
        var result = new List<SeenWindow>();
        foreach (var window in TopLevel())
            if (!_baseline.Contains(window.Handle)) result.Add(window);
        return result;
    }

    /// <summary>
    /// Looks once. Each new window is judged for the current stage; an
    /// expected one is handed to <paramref name="answer"/> with its kind (the
    /// step answers it there), anything else ends the run. Then the dialogs
    /// inside Plantoir's window are judged the same way.
    /// </summary>
    public void Check(Action<SeenWindow, string>? answer)
    {
        Looks++;
        var contentWindows = new List<AutomationElement>();
        foreach (var window in New())
        {
            var facts = new WindowFacts(window.Title, window.Class, window.Process, () => Words(window.Element));
            var judgement = WindowRules.Judge(Stage, facts);
            switch (judgement.Verdict)
            {
                case Verdict.Desktop:
                    continue;
                case Verdict.Empty:
                    if (_reported.Add(window.Handle))
                        Program.Note($"note: an empty untitled window appeared, {window}; watching it");
                    continue;
                case Verdict.Blocked:
                    throw Stopped.Product($"Windows put up {judgement.Kind}: {window}, saying \"{facts.Words}\" [screenshot {Program.Shot("windows-notice")}]");
                case Verdict.Unexpected:
                    throw Stopped.Product($"an unexpected window appeared at {Stage}: {window}, saying \"{facts.Words}\" [screenshot {Program.Shot("unexpected")}]");
            }
            if (judgement.Kind == "plantoir content") contentWindows.Add(window.Element);
            if (_allowedSeen.Add($"{Stage}|{window.Handle}"))
                Program.Note($"window allowed at {Stage} as {judgement.Kind}: {window}"
                             + (judgement.Kind is "plantoir content" or "plantoir popup" ? $", showing \"{facts.Words}\"" : ""));
            try { answer?.Invoke(window, judgement.Kind); }
            catch (Stopped) { throw; }
            catch (Exception error) { throw Stopped.Driver($"answering {window} failed: {error.Message}"); }
        }
        if (PlantoirWindow is { } main) CheckDialogs(main);
        // Plantoir's content seen outside its window (WindowRules.IsPlantoirContent):
        // a dialog in it is judged exactly as one in the main window.
        foreach (var content in contentWindows) CheckDialogs(content);
    }

    /// <summary>
    /// Plantoir's own dialogs. UI Automation shows a ContentDialog as a
    /// Window of class Popup named by its title, beside empty popups; a
    /// dialog is told apart by holding a dialog's buttons (as the UI suite's
    /// DrivenApp.OpenDialog does). Expected questions are answered with their
    /// Close button and recorded; any other dialog ends the run.
    /// </summary>
    private void CheckDialogs(AutomationElement window)
    {
        AutomationElement[] popups;
        try { popups = window.FindAllDescendants(cf => cf.ByClassName("Popup").And(cf.ByControlType(ControlType.Window))); }
        catch { return; }
        foreach (var popup in popups)
        {
            string title;
            bool isDialog = false, isNewCourseSheet;
            AutomationElement? close = null;
            try
            {
                title = popup.Properties.Name.ValueOrDefault ?? "";
                foreach (string id in DialogButtonIds)
                    if (popup.FindFirstDescendant(cf => cf.ByAutomationId(id)) is not null) isDialog = true;
                // The sheet's id is on the ContentDialog itself (NewCourseDialog.cs),
                // which UI Automation shows as the popup: asked of the popup first.
                // Rehearsal 2026-11-18-093556 stopped on the sheet for want of this.
                isNewCourseSheet = popup.Properties.AutomationId.ValueOrDefault == "newCourseDialog"
                                   || popup.FindFirstDescendant(cf => cf.ByAutomationId("newCourseDialog")) is not null;
                if (isNewCourseSheet) isDialog = true;
                close = popup.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"));
            }
            catch { continue; }
            if (!isDialog) continue;
            string? kind = WindowRules.DialogKind(Stage, title, isNewCourseSheet);
            if (kind is null)
                throw Stopped.Product($"Plantoir showed a dialog not expected at {Stage}: \"{title}\", saying \"{Words(popup)}\" [screenshot {Program.Shot("unexpected-dialog")}]");
            if (!kind.StartsWith("question", StringComparison.Ordinal)) continue;
            if (close is null || !close.IsEnabled) continue;
            Program.Note($"FINDING: Plantoir asked ({kind}) \"{title}: {Words(popup)}\"; answered with \"{close.Name}\" [screenshot {Program.Shot("question")}]");
            if (close.Patterns.Invoke.TryGetPattern(out var invoke)) invoke.Invoke();
        }
    }

    /// <summary>The words a window shows, as UI Automation reads them (text, buttons, links), in tree order.</summary>
    public static string Words(AutomationElement root, int limit = 40)
    {
        var words = new List<string>();
        try
        {
            string own = root.Properties.Name.ValueOrDefault ?? "";
            if (own.Length > 0) words.Add(own);
            foreach (var element in root.FindAllDescendants())
            {
                if (words.Count >= limit) break;
                ControlType type;
                try { type = element.Properties.ControlType.ValueOrDefault; } catch { continue; }
                if (type is not (ControlType.Text or ControlType.Button or ControlType.Hyperlink or ControlType.CheckBox
                                 or ControlType.Document or ControlType.Edit)) continue;
                string name;
                try { name = element.Properties.Name.ValueOrDefault ?? ""; } catch { continue; }
                name = name.Trim();
                if (name.Length > 0 && !words.Contains(name)) words.Add(name);
            }
        }
        catch { }
        return string.Join(" | ", words);
    }

    /// <summary>
    /// Wait for <paramref name="done"/>, checking the desktop every second,
    /// answering what the stage expects and ending the run on anything else.
    /// Returns false when the time ran out.
    /// </summary>
    public bool WaitFor(Func<bool> done, TimeSpan within, Action<SeenWindow, string>? answer = null)
    {
        var until = DateTime.UtcNow + within;
        while (DateTime.UtcNow < until)
        {
            Check(answer);
            bool finished;
            try { finished = done(); }
            catch (Stopped) { throw; }
            catch { finished = false; }
            if (finished) return true;
            Thread.Sleep(1000);
        }
        Check(answer);
        try { return done(); } catch (Stopped) { throw; } catch { return false; }
    }
}
