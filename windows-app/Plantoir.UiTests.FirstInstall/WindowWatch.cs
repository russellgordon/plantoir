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
    private readonly Dictionary<IntPtr, DateTime> _firstSeen = new();
    private readonly HashSet<string> _unreadableNoted = new();
    private readonly List<string> _baselineNames = new();
    private int _looks;
    private int _failedLooks;
    private int _unreadable;

    private static readonly string[] DialogButtonIds = { "PrimaryButton", "SecondaryButton", "CloseButton" };

    public WindowWatch(UIA3Automation automation)
    {
        _automation = automation;
        var (windows, read) = Desktop();
        if (!read) throw Stopped.Driver("the desktop could not be read when the driver started, so no baseline of its windows exists");
        foreach (var window in windows)
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

    /// <summary>
    /// How many REAL looks there have been: a look whose reading of the
    /// desktop failed is not counted (the review of 2026-11-18). Read from the
    /// installer's launch thread too, hence the volatile read.
    /// </summary>
    public int Looks => Volatile.Read(ref _looks);

    /// <summary>Looks whose reading of the desktop failed, for the log.</summary>
    public int FailedLooks => Volatile.Read(ref _failedLooks);

    /// <summary>Top-level windows that could not be read, each noted in the log.</summary>
    public int Unreadable => _unreadable;

    /// <summary>
    /// Every top-level window now, and whether the desktop itself could be
    /// read. A window that cannot be read is noted (once per window and
    /// reason), never skipped in silence.
    /// </summary>
    private (List<SeenWindow> Windows, bool Read) Desktop()
    {
        var found = new List<SeenWindow>();
        AutomationElement[] children;
        try { children = _automation.GetDesktop().FindAllChildren(); }
        catch (Exception error)
        {
            NoteUnreadable("desktop|" + error.GetType().Name, $"note: the desktop could not be read at this look ({error.GetType().Name}: {error.Message}); not counted as a look");
            return (found, false);
        }
        foreach (var child in children)
        {
            IntPtr handle = IntPtr.Zero;
            try
            {
                handle = child.Properties.NativeWindowHandle.ValueOrDefault;
                int pid = child.Properties.ProcessId.ValueOrDefault;
                string process = "";
                try { process = Process.GetProcessById(pid).ProcessName; } catch { }
                found.Add(new SeenWindow(handle, child.Properties.Name.ValueOrDefault ?? "",
                                         child.Properties.ClassName.ValueOrDefault ?? "", process, pid, child));
            }
            catch (Exception error)
            {
                // Gone between the listing and the reading is the usual cause;
                // a window of a higher integrity level is the one that matters.
                if (handle != IntPtr.Zero && _baseline.Contains(handle)) continue;
                _unreadable++;
                NoteUnreadable($"{handle}|{error.GetType().Name}",
                               $"note: a top-level window could not be read (handle 0x{handle.ToInt64():X}, {error.GetType().Name}: {error.Message})");
            }
        }
        return (found, true);
    }

    private void NoteUnreadable(string key, string line)
    {
        if (_unreadableNoted.Add(key)) Program.Note(line);
    }

    /// <summary>Every top-level window now (for the steps' own searches).</summary>
    public List<SeenWindow> TopLevel() => Desktop().Windows;

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
        var (windows, read) = Desktop();
        if (!read)
        {
            Interlocked.Increment(ref _failedLooks);
            return;
        }
        var contentWindows = new List<AutomationElement>();
        foreach (var window in windows)
        {
            if (_baseline.Contains(window.Handle)) continue;
            if (!_firstSeen.TryGetValue(window.Handle, out DateTime firstSeen))
                _firstSeen[window.Handle] = firstSeen = DateTime.UtcNow;
            var facts = new WindowFacts(window.Title, window.Class, window.Process, () => Words(window.Element),
                                        id => ControlName(window.Element, id));
            var judgement = WindowRules.Judge(Stage, facts, DateTime.UtcNow - firstSeen);
            switch (judgement.Verdict)
            {
                case Verdict.Desktop:
                    continue;
                case Verdict.Settling:
                    if (_reported.Add(window.Handle))
                        Program.Note($"note: a window is still being made, {window}, showing \"{facts.Words}\"; judged again at each look for up to {WindowRules.SettlingLimit.TotalSeconds:0} s");
                    continue;
                case Verdict.Empty:
                    if (_reported.Add(window.Handle))
                        Program.Note($"note: an empty untitled window appeared, {window}; judged again at each look for up to {WindowRules.EmptyLimit.TotalSeconds:0} s");
                    continue;
                case Verdict.Blocked:
                    throw Stopped.Product($"Windows put up {judgement.Kind}: {window}, saying \"{facts.Words}\" [screenshot {Program.Shot("windows-notice")}]");
                case Verdict.Unexpected:
                    throw Stopped.Product($"an unexpected window appeared at {Stage}: {window}{(judgement.Kind.Length > 0 ? " (" + judgement.Kind + ")" : "")}, saying \"{facts.Words}\" [screenshot {Program.Shot("unexpected")}]");
            }
            if (judgement.Kind == "plantoir content") contentWindows.Add(window.Element);
            if (_allowedSeen.Add($"{Stage}|{window.Handle}"))
                Program.Note($"window allowed at {Stage} as {judgement.Kind}: {window}"
                             + (judgement.Kind is "plantoir content" or "plantoir popup" or "browser warning" ? $", showing \"{facts.Words}\"" : ""));
            try { answer?.Invoke(window, judgement.Kind); }
            catch (Stopped) { throw; }
            catch (Exception error) { throw Stopped.Driver($"answering {window} failed: {error.Message}"); }
        }
        if (PlantoirWindow is { } main) CheckDialogs(main);
        // Plantoir's content seen outside its window (WindowRules.IsPlantoirContent):
        // a dialog in it is judged exactly as one in the main window.
        foreach (var content in contentWindows) CheckDialogs(content);
        // Counted only now: a look that ended the run, or could not read the
        // desktop, is not a look the run can lean on.
        Interlocked.Increment(ref _looks);
    }

    /// <summary>The name of the control with this automation id, or null when the window has none.</summary>
    private static string? ControlName(AutomationElement window, string automationId)
    {
        try
        {
            var control = window.FindFirstDescendant(cf => cf.ByAutomationId(automationId));
            return control is null ? null : control.Properties.Name.ValueOrDefault ?? "";
        }
        catch { return null; }
    }

    /// <summary>
    /// Watches the desktop for <paramref name="period"/>, a look a second, and
    /// returns how many real looks there were. Used once, after the last step
    /// (<see cref="WindowRules.FinalWatchLength"/>): a deliberate observation
    /// window, not a wait for a condition.
    /// </summary>
    public int Observe(TimeSpan period, Action<SeenWindow, string>? answer = null)
    {
        int before = Looks;
        var until = DateTime.UtcNow + period;
        while (DateTime.UtcNow < until)
        {
            Check(answer);
            Thread.Sleep(1000);
        }
        Check(answer);
        return Looks - before;
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
        catch (Exception error)
        {
            NoteUnreadable("dialogs|" + error.GetType().Name, $"note: the dialogs inside Plantoir's window could not be read at this look ({error.GetType().Name}: {error.Message})");
            return;
        }
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
            catch (Exception error)
            {
                _unreadable++;
                NoteUnreadable("dialog|" + error.GetType().Name, $"note: a popup inside Plantoir's window could not be read ({error.GetType().Name}: {error.Message})");
                continue;
            }
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
