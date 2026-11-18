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
    private readonly List<AutomationElement> _baselineUnreadable = new();
    private readonly UnreadableWindows<AutomationElement> _unreadableWindows;
    private readonly List<string> _pending = new();
    private int _looks;
    private int _failedLooks;
    private int _unreadable;

    private static readonly string[] DialogButtonIds = { "PrimaryButton", "SecondaryButton", "CloseButton" };

    public WindowWatch(UIA3Automation automation)
    {
        _automation = automation;
        _unreadableWindows = new UnreadableWindows<AutomationElement>(SameElement);
        var (windows, unreadable, read) = Desktop();
        if (!read) throw Stopped.Driver("the desktop could not be read when the driver started, so no baseline of its windows exists");
        foreach (var window in windows)
        {
            _baseline.Add(window.Handle);
            _baselineNames.Add(window.ToString());
        }
        // Already up when the driver started, so the desktop's, not the run's;
        // named in the baseline so a reader knows they were there.
        foreach (var (element, error) in unreadable)
        {
            _baselineUnreadable.Add(element);
            _baselineNames.Add($"a window that could not be read ({error})");
        }
    }

    /// <summary>
    /// Whether two elements are the same window, by UI Automation's own
    /// comparison (CompareElements). Not by handle: every window whose
    /// properties cannot be read gives 0x0, and the review of 2026-11-18 found
    /// that made two of them look like one. It may throw: the tracker records
    /// a comparison that throws, and its presence clock does not depend on it.
    /// </summary>
    private bool SameElement(AutomationElement first, AutomationElement second) => _automation.Compare(first, second);

    /// <summary>
    /// The windows still in a grace state at the last look (settling, empty,
    /// or unreadable). While any is, no watch or step may finish (<see cref="Settle"/>).
    /// </summary>
    public IReadOnlyList<string> Pending => _pending;

    /// <summary>Set while a watch or step is looking on past its end for windows still in a grace state; Program.Finish records it.</summary>
    public string? SettlingAfter { get; private set; }

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

    /// <summary>Different top-level windows that could not be read in this run, each recorded in the log and judged.</summary>
    public int Unreadable => _unreadableWindows.Seen;

    /// <summary>Popups inside Plantoir's window that could not be read, each noted.</summary>
    public int UnreadablePopups => _unreadable;

    /// <summary>
    /// Every top-level window now; those whose properties could not be read,
    /// with the error; and whether the desktop itself could be read. Nothing
    /// is noted here: <see cref="Check"/> records and judges the unreadable
    /// ones, through <see cref="UnreadableWindows{T}"/>.
    /// </summary>
    private (List<SeenWindow> Windows, List<(AutomationElement Element, string Error)> Unreadable, bool Read) Desktop()
    {
        var found = new List<SeenWindow>();
        var unreadable = new List<(AutomationElement, string)>();
        AutomationElement[] children;
        try { children = _automation.GetDesktop().FindAllChildren(); }
        catch (Exception error)
        {
            NoteUnreadable("desktop|" + error.GetType().Name, $"note: the desktop could not be read at this look ({error.GetType().Name}: {error.Message}); not counted as a look");
            return (found, unreadable, false);
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
                // Either way it is judged (Check), not skipped.
                if (handle != IntPtr.Zero && _baseline.Contains(handle)) continue;
                unreadable.Add((child, $"handle 0x{handle.ToInt64():X}, {error.GetType().Name}: {error.Message}"));
            }
        }
        return (found, unreadable, true);
    }

    private void NoteUnreadable(string key, string line)
    {
        if (_unreadableNoted.Add(key)) Program.Note(line);
    }

    /// <summary>Every top-level window now (for the steps' own searches).</summary>
    public List<SeenWindow> TopLevel() => Desktop().Windows;

    /// <summary>
    /// Records and judges the top-level windows that could not be read at
    /// this look (the review of 2026-11-18: they were noted once, then never
    /// judged). Each is recorded when it appears and when it stops being
    /// unreadable; one still unreadable after <see cref="WindowRules.UnreadableLimit"/>
    /// ends the run, at any stage, the final watch included.
    /// </summary>
    private void JudgeUnreadable(List<(AutomationElement Element, string Error)> unreadable, List<SeenWindow> readable)
    {
        var fresh = new List<(AutomationElement Window, string Error)>();
        int baselineFailures = 0;
        string baselineError = "";
        foreach (var (element, error) in unreadable)
        {
            bool atStart = false;
            foreach (var known in _baselineUnreadable)
            {
                // A comparison that throws is "not the desktop's": the window
                // is judged rather than excused.
                try { if (SameElement(known, element)) { atStart = true; break; } }
                catch (Exception compareError) { baselineFailures++; baselineError = compareError.GetType().Name + ": " + compareError.Message; }
            }
            if (!atStart) fresh.Add((element, error));
        }
        if (baselineFailures > 0)
            Program.Note($"note: comparing an unreadable window with the desktop's own threw {baselineFailures} times at this look ({baselineError}); it is judged as new");
        var readableElements = new List<AutomationElement>();
        foreach (var window in readable) readableElements.Add(window.Element);
        foreach (var change in _unreadableWindows.Look(fresh, readableElements, DateTime.UtcNow))
        {
            switch (change.Change)
            {
                case UnreadableChange.Appeared:
                    Program.Note($"note: unreadable window {change.Number} appeared at {Stage}: UI Automation lists it but cannot read it ({change.Error}); "
                                 + $"judged at each look, and it ends the run if still unreadable after {WindowRules.UnreadableLimit.TotalSeconds:0} s");
                    break;
                case UnreadableChange.BecameReadable:
                    Program.Note($"note: unreadable window {change.Number} can be read after {change.SeenFor.TotalSeconds:0} s ({change.Sightings} looks); from now on judged by the ordinary rules");
                    break;
                case UnreadableChange.Gone:
                    Program.Note($"note: unreadable window {change.Number} is gone after {change.SeenFor.TotalSeconds:0} s ({change.Sightings} looks)");
                    break;
                case UnreadableChange.ComparisonFailed:
                    Program.Note($"note: comparing unreadable windows threw {change.Sightings} times at this look ({change.Error}); each such comparison counts as a different window, and the presence clock still runs");
                    break;
                case UnreadableChange.TooLong:
                    throw Stopped.Product($"a window UI Automation could not read stayed up at {Stage} for {change.SeenFor.TotalSeconds:0} s "
                                          + $"(unreadable window {change.Number}, {change.Sightings} looks; {change.Error}): a window of a higher integrity level, such as an elevation prompt, "
                                          + $"is the usual cause [screenshot {Program.Shot("unreadable-window")}]", "unreadable-window");
                case UnreadableChange.PresentTooLong:
                    throw Stopped.Product($"at least one window UI Automation could not read was on screen at every look for {change.SeenFor.TotalSeconds:0} s at {Stage} "
                                          + $"({change.Sightings} looks; {change.Error}), whichever windows they were: a window of a higher integrity level, such as an elevation prompt, "
                                          + $"is the usual cause [screenshot {Program.Shot("unreadable-window")}]", "unreadable-window");
            }
        }
        if (_unreadableWindows.Pending) _pending.Add("an unreadable window (inside its 20 s)");
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
        var (windows, unreadable, read) = Desktop();
        if (!read)
        {
            Interlocked.Increment(ref _failedLooks);
            return;
        }
        _pending.Clear();
        JudgeUnreadable(unreadable, windows);
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
                    _pending.Add($"settling: {window}");
                    if (_reported.Add(window.Handle))
                        Program.Note($"note: a window is still being made, {window}, showing \"{facts.Words}\"; judged again at each look for up to {WindowRules.SettlingLimit.TotalSeconds:0} s");
                    continue;
                case Verdict.Empty:
                    _pending.Add($"empty: {window}");
                    if (_reported.Add(window.Handle))
                        Program.Note($"note: an empty untitled window appeared, {window}; judged again at each look for up to {WindowRules.EmptyLimit.TotalSeconds:0} s");
                    continue;
                case Verdict.Blocked:
                    throw Stopped.Product($"Windows put up {judgement.Kind}: {window}, saying \"{facts.Words}\" [screenshot {Program.Shot("windows-notice")}]",
                                          "blocked", window.Process);
                case Verdict.Unexpected:
                    throw Stopped.Product($"an unexpected window appeared at {Stage}: {window}{(judgement.Kind.Length > 0 ? " (" + judgement.Kind + ")" : "")}, saying \"{facts.Words}\" [screenshot {Program.Shot("unexpected")}]",
                                          UnexpectedCause(facts), window.Process);
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

    /// <summary>
    /// The fixed word for an unexpected window, for result.txt: one that
    /// outlasted the Empty grace (no title, no words) or Plantoir's Settling
    /// grace, or any other.
    /// </summary>
    private static string UnexpectedCause(WindowFacts facts)
    {
        if (facts.Title.Length == 0 && facts.Words.Length == 0) return "empty-window";
        if (string.Equals(facts.Process, "Plantoir", StringComparison.OrdinalIgnoreCase)
            && (facts.Class.Length == 0 || facts.Class == "WinUIDesktopWin32WindowClass" && facts.Title.Length == 0)) return "settling-window";
        return "unexpected-window";
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
        int looks = Looks - before;
        Settle($"the {period.TotalSeconds:0} s watch", answer);
        return looks;
    }

    /// <summary>
    /// The rule every watch and every finished step ends by (the fourth
    /// review): it may finish only when no window is in a grace state at the
    /// last look. Until then it goes on looking, a look a second, so each such
    /// window becomes readable and is judged, goes, or outlasts its grace and
    /// ends the run; at <see cref="WindowRules.SettleLimit"/> the run ends too,
    /// not PASSED. Returns at once when nothing is pending.
    /// </summary>
    public void Settle(string what, Action<SeenWindow, string>? answer = null)
    {
        var started = DateTime.UtcNow;
        bool noted = false;
        while (true)
        {
            var decision = WindowRules.Settle(_pending.Count, DateTime.UtcNow - started);
            if (decision == Settling.Done) break;
            if (decision == Settling.OutOfTime)
                throw Stopped.Product($"{what} could not finish: after {WindowRules.SettleLimit.TotalSeconds:0} s more, windows were still in a grace state ({string.Join("; ", _pending)}) [screenshot {Program.Shot("unsettled")}]",
                                      "unsettled");
            if (!noted)
            {
                noted = true;
                SettlingAfter = what;
                Program.Note($"SETTLING: {what} is over, but {_pending.Count} window(s) are still in a grace state ({string.Join("; ", _pending)}); looking on until each is judged, for at most {WindowRules.SettleLimit.TotalSeconds:0} s");
            }
            Thread.Sleep(1000);
            Check(answer);
        }
        if (noted)
        {
            Program.Note($"SETTLED: {what}: no window is in a grace state after {(DateTime.UtcNow - started).TotalSeconds:0} s more");
            SettlingAfter = null;
        }
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
                throw Stopped.Product($"Plantoir showed a dialog not expected at {Stage}: \"{title}\", saying \"{Words(popup)}\" [screenshot {Program.Shot("unexpected-dialog")}]", "unexpected-dialog", "Plantoir");
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
            if (finished)
            {
                Settle($"a step at {Stage}", answer);
                return true;
            }
            Thread.Sleep(1000);
        }
        Check(answer);
        bool last;
        try { last = done(); } catch (Stopped) { throw; } catch { last = false; }
        if (last) Settle($"a step at {Stage}", answer);
        return last;
    }
}
