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
/// Watches every top-level window on the desktop. The windows open when the
/// driver starts are the desktop and are left alone. A window that appears
/// later must be ALLOWED: by the current step's own list (the windows that
/// step expects and answers), or by the short list of the desktop's own
/// passing windows below. Anything else ends the run, named, with a
/// screenshot and the words it showed.
/// </summary>
internal sealed class WindowWatch
{
    private readonly UIA3Automation _automation;
    private readonly HashSet<IntPtr> _baseline = new();
    private readonly HashSet<IntPtr> _reported = new();
    private readonly List<string> _baselineNames = new();

    /// <summary>
    /// Windows of the desktop itself that can come and go during any step and
    /// say nothing about Plantoir: the taskbar, Start and search, the
    /// notification area's pop-ups, the input panel, and Parallels' own tools.
    /// Matched by process, because a title is the part that changes.
    /// </summary>
    private static readonly string[] DesktopProcesses =
    {
        "explorer:Shell_TrayWnd", "explorer:Shell_SecondaryTrayWnd", "explorer:Progman", "explorer:WorkerW",
        "explorer:NotifyIconOverflowWindow", "explorer:Xaml_WindowedPopupClass", "explorer:TopLevelWindowForOverflowXamlIsland",
        "ShellExperienceHost:", "StartMenuExperienceHost:", "SearchHost:", "SearchApp:", "TextInputHost:",
        "ShellHost:", "LockApp:", "prl_cc:", "prl_tools:", "prl_tools_service:", "ApplicationFrameHost:Windows.UI.Core.CoreWindow",
        "PlantoirFirstInstall:",
    };

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

    private static bool IsDesktopWindow(SeenWindow window)
    {
        // Parallels Tools updating itself in a terminal window: the virtual
        // machine's own plumbing, which a teacher's PC does not have.
        if (window.Process.Equals("WindowsTerminal", StringComparison.OrdinalIgnoreCase)
            && window.Title.Contains(@"Parallels\Parallels Tools", StringComparison.OrdinalIgnoreCase))
            return true;
        foreach (string entry in DesktopProcesses)
        {
            int colon = entry.IndexOf(':');
            string process = entry[..colon];
            string windowClass = entry[(colon + 1)..];
            if (string.Equals(window.Process, process, StringComparison.OrdinalIgnoreCase)
                && (windowClass.Length == 0 || window.Class == windowClass))
                return true;
        }
        return false;
    }

    /// <summary>
    /// Looks once. Each new window is offered to <paramref name="expected"/>,
    /// which answers it and returns true when the step knows it. A window
    /// nobody knows ends the run. Returns the new windows the step knew.
    /// </summary>
    public List<SeenWindow> Check(Func<SeenWindow, bool> expected)
    {
        var known = new List<SeenWindow>();
        foreach (var window in New())
        {
            if (IsDesktopWindow(window)) continue;
            bool knew;
            try { knew = expected(window); }
            catch (Stopped) { throw; }
            catch (Exception error) { throw Stopped.Driver($"answering {window} failed: {error.Message}"); }
            if (knew) { known.Add(window); continue; }
            // A window with no title and nothing in it, of a process already
            // allowed in this step, is a frame being drawn; look again later.
            if (window.Title.Length == 0 && Words(window.Element).Length == 0)
            {
                if (_reported.Add(window.Handle))
                    Program.Note($"note: an empty untitled window appeared, {window}; watching it");
                continue;
            }
            string shot = Program.Shot("unexpected");
            throw Stopped.Product($"an unexpected window appeared: {window}, saying \"{Words(window.Element)}\" [screenshot {shot}]");
        }
        return known;
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
    /// answering what the step expects and ending the run on anything else.
    /// Returns false when the time ran out.
    /// </summary>
    public bool WaitFor(Func<bool> done, TimeSpan within, Func<SeenWindow, bool> expected)
    {
        var until = DateTime.UtcNow + within;
        while (DateTime.UtcNow < until)
        {
            Check(expected);
            bool finished;
            try { finished = done(); }
            catch (Stopped) { throw; }
            catch { finished = false; }
            if (finished) return true;
            Thread.Sleep(1000);
        }
        Check(expected);
        try { return done(); } catch (Stopped) { throw; } catch { return false; }
    }
}
