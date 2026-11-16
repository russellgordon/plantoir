using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace Plantoir.FirstInstall;

/// <summary>
/// The six steps, each with its own allow-list: the windows it expects and
/// how it answers them. Every wait goes through <see cref="WindowWatch.WaitFor"/>,
/// so a window nobody planned for ends the run in whichever step it appears.
/// </summary>
internal static class Steps_
{
    [DllImport("user32.dll")] private static extern IntPtr PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr w, string l);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);

    private const uint BM_CLICK = 0x00F5;
    private const uint WM_SETTEXT = 0x000C;

    private static readonly string Downloads =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

    private static readonly string WorkingFolder =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Course Notes");

    private static readonly string InstalledApp = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Plantoir", "Plantoir.exe");

    // ---- 1. Download --------------------------------------------------------

    /// <summary>
    /// Opens the address in the default browser, as a click on a download link
    /// does, and waits for the finished file in Downloads. The browser's own
    /// windows are expected here (on a clean machine Edge opens on its
    /// first-run pages, which the download does not wait for); its windows are
    /// closed afterwards. Passes only when the file carries the "from the
    /// internet" mark (Zone.Identifier, ZoneId=3), or SmartScreen is not
    /// exercised by the steps after it.
    /// </summary>
    public static string Download(string url)
    {
        Program.Note($"opening {url} in the default browser");
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        string? found = null;
        bool arrived = Program.Watch.WaitFor(() =>
        {
            foreach (string file in Directory.GetFiles(Downloads, "PlantoirSetup*.exe"))
            {
                // Edge writes to a .crdownload (or a "Unconfirmed" name) and renames at the end.
                found = file;
                return true;
            }
            return false;
        }, TimeSpan.FromMinutes(10), IsBrowserWindow);
        if (!arrived || found is null)
            throw Stopped.Product("PlantoirSetup.exe did not arrive in Downloads within ten minutes; the browser showed: "
                                  + BrowserWords() + $" [screenshot {Program.Shot("no-download")}]");
        long size = -1;
        Program.Watch.WaitFor(() =>
        {
            long now = new FileInfo(found).Length;
            bool steady = now == size;
            size = now;
            return steady;
        }, TimeSpan.FromMinutes(2), IsBrowserWindow);
        string zone = "";
        try { zone = File.ReadAllText(found + ":Zone.Identifier"); } catch (Exception error) { zone = "(none: " + error.Message + ")"; }
        string zoneLine = zone.Split('\n').FirstOrDefault(line => line.StartsWith("ZoneId", StringComparison.Ordinal))?.Trim() ?? "no ZoneId line";
        Program.Note($"downloaded {Path.GetFileName(found)}, {size:N0} bytes; its mark of the web: {zoneLine}");
        if (!zone.Contains("ZoneId=3", StringComparison.Ordinal))
            throw Stopped.Driver($"the download carries no \"from the internet\" mark ({zoneLine}), so SmartScreen would not be exercised");
        Program.Shot("downloaded");
        CloseBrowser();
        return found;
    }

    private static bool IsBrowserWindow(SeenWindow window) =>
        window.Process.Equals("msedge", StringComparison.OrdinalIgnoreCase);

    private static string BrowserWords()
    {
        var words = new List<string>();
        foreach (var window in Program.Watch.New())
            if (IsBrowserWindow(window)) words.Add(WindowWatch.Words(window.Element));
        return words.Count == 0 ? "(no browser window)" : string.Join(" || ", words);
    }

    /// <summary>Closes the browser the way its close button does; ends it if it is still there ten seconds later.</summary>
    private static void CloseBrowser()
    {
        foreach (var window in Program.Watch.New())
        {
            if (!IsBrowserWindow(window)) continue;
            try { window.Element.Patterns.Window.PatternOrDefault?.Close(); } catch { }
        }
        Thread.Sleep(3000);
        var left = Process.GetProcessesByName("msedge");
        bool stillShowing = false;
        foreach (var window in Program.Watch.New())
            if (IsBrowserWindow(window)) stillShowing = true;
        if (stillShowing)
        {
            foreach (var process in left) { try { process.Kill(); } catch { } }
            Program.Note("the browser did not close from its window; ended it");
        }
        else Program.Note("closed the browser");
        // Its background processes may stay; they draw no window.
    }

    // ---- 2. Install ---------------------------------------------------------

    /// <summary>
    /// Starts the installer the way a double-click in File Explorer does
    /// (ShellExecute, which is where SmartScreen and the "Open File - Security
    /// Warning" question come from), then walks the wizard: Next, Install,
    /// Finish, with "Launch Plantoir" left as the installer sets it.
    /// Expected windows: the wizard; SmartScreen's "Windows protected your PC"
    /// (answered More info, Run anyway, and recorded as a finding); the
    /// security warning (answered Run, recorded). A Smart App Control block
    /// is a recorded stop: it has no "run anyway".
    /// </summary>
    public static void Install(string installer)
    {
        Process.Start(new ProcessStartInfo(installer) { UseShellExecute = true, WorkingDirectory = Downloads });
        Program.Note("started the installer from Downloads, as a double-click does");
        var pagesSeen = new List<string>();
        bool finished = false;
        DateTime lastProgress = DateTime.UtcNow;

        bool Expected(SeenWindow window)
        {
            // Finish with "Launch Plantoir" opens it; the next step looks at it.
            if (finished && IsPlantoirWindow(window)) return true;
            if (window.Process.StartsWith("PlantoirSetup", StringComparison.OrdinalIgnoreCase))
            {
                if (window.Class != "TWizardForm") return true;   // Inno's own hidden application window
                string page = InnoPageTitle(window.Element);
                if (page.Length == 0) return true;
                if (!pagesSeen.Contains(page))
                {
                    pagesSeen.Add(page);
                    lastProgress = DateTime.UtcNow;
                    Program.Note($"installer page: \"{page}\"");
                    Program.Shot("installer");
                }
                foreach (string button in new[] { "Finish", "Install", "Next" })
                {
                    if (InnoButton(window.Element, button) is { } found && found.IsEnabled)
                    {
                        if (button == "Finish") finished = true;
                        Program.Note($"installer: pressed {button} on \"{page}\"");
                        PostMessage(found.Properties.NativeWindowHandle.ValueOrDefault, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
                        Thread.Sleep(1500);
                        break;
                    }
                }
                return true;
            }
            if (window.Process.Equals("smartscreen", StringComparison.OrdinalIgnoreCase))
            {
                string words = WindowWatch.Words(window.Element);
                if (words.Contains("Smart App Control", StringComparison.OrdinalIgnoreCase))
                    throw Stopped.Product($"Smart App Control blocked the installer: \"{words}\" [screenshot {Program.Shot("smart-app-control")}]");
                Program.Note($"FINDING: SmartScreen asked before the installer ran: \"{words}\" [screenshot {Program.Shot("smartscreen")}]");
                if (FindByName(window.Element, "Run anyway") is { } run) Press(run, "Run anyway");
                else if (FindByName(window.Element, "More info") is { } more) Press(more, "More info");
                lastProgress = DateTime.UtcNow;
                return true;
            }
            if (window.Title.Contains("Security Warning", StringComparison.OrdinalIgnoreCase)
                && FindByName(window.Element, "Run") is { } runButton)
            {
                Program.Note($"FINDING: Windows asked \"{WindowWatch.Words(window.Element)}\"; pressed Run [screenshot {Program.Shot("security-warning")}]");
                Press(runButton, "Run");
                lastProgress = DateTime.UtcNow;
                return true;
            }
            return false;
        }

        bool done = Program.Watch.WaitFor(() =>
        {
            if (finished) return true;
            // Nothing new for three minutes and no wizard: a prompt the driver
            // cannot see (UAC draws on the secure desktop) or a silent refusal.
            if (DateTime.UtcNow - lastProgress > TimeSpan.FromMinutes(3) && pagesSeen.Count == 0)
                throw Stopped.Product("nothing appeared for three minutes after the installer was started (no wizard, no SmartScreen). "
                                      + "A UAC prompt would be on the secure desktop, out of this driver's sight: see the Mac-side captures"
                                      + $" [screenshot {Program.Shot("installer-silent")}]");
            return false;
        }, TimeSpan.FromMinutes(15), Expected);
        if (!done)
            throw Stopped.Product($"the installer did not reach its Finish page within fifteen minutes; pages seen: {string.Join(", ", pagesSeen)}"
                                  + $" [screenshot {Program.Shot("installer-stuck")}]");
        Program.Note($"installer finished; pages: {string.Join(" > ", pagesSeen)}");
        if (!File.Exists(InstalledApp))
            throw Stopped.Product($"the installer finished but there is no {InstalledApp}");
        var version = FileVersionInfo.GetVersionInfo(InstalledApp);
        Program.Note($"installed {InstalledApp}, version {version.ProductVersion}");
    }

    /// <summary>The heading of the wizard's current page (the first non-empty static text in its top panel).</summary>
    private static string InnoPageTitle(AutomationElement wizard)
    {
        try
        {
            foreach (var panel in wizard.FindAllDescendants(cf => cf.ByClassName("TPanel")))
                foreach (var text in panel.FindAllChildren(cf => cf.ByClassName("TNewStaticText")))
                {
                    string name = (text.Properties.Name.ValueOrDefault ?? "").Trim();
                    if (name.Length > 0) return name;
                }
            // The last page has no top panel: its heading is the first big static text.
            foreach (var text in wizard.FindAllDescendants(cf => cf.ByClassName("TNewStaticText")))
            {
                string name = (text.Properties.Name.ValueOrDefault ?? "").Trim();
                if (name.Length > 0) return name;
            }
        }
        catch { }
        return "";
    }

    private static AutomationElement? InnoButton(AutomationElement wizard, string name)
    {
        try
        {
            foreach (var button in wizard.FindAllDescendants(cf => cf.ByClassName("TNewButton")))
                if ((button.Properties.Name.ValueOrDefault ?? "") == name && !button.IsOffscreen) return button;
        }
        catch { }
        return null;
    }

    // ---- 3. Open Plantoir ----------------------------------------------------

    /// <summary>
    /// Finish with "Launch Plantoir" opens it. Passes at the first screen,
    /// "Choose Your Working Folder".
    /// </summary>
    public static AutomationElement WaitForPlantoir()
    {
        AutomationElement? window = null;
        bool shown = Program.Watch.WaitFor(() =>
        {
            window = PlantoirWindow();
            return window is not null && ById(window, "chooseFolderButton") is not null;
        }, TimeSpan.FromMinutes(5), IsPlantoirWindow);
        if (!shown || window is null)
        {
            string said = window is null ? "(no Plantoir window)" : WindowWatch.Words(window);
            throw Stopped.Product($"Plantoir's first screen did not appear within five minutes of Finish; it showed: \"{said}\" [screenshot {Program.Shot("no-first-screen")}]");
        }
        BringToFront(window);
        Program.Note("Plantoir opened at \"Choose Your Working Folder\"");
        Program.Shot("first-screen");
        return window;
    }

    private static bool IsPlantoirWindow(SeenWindow window) =>
        window.Process.Equals("Plantoir", StringComparison.OrdinalIgnoreCase)
        || window.Process.Equals("PickerHost", StringComparison.OrdinalIgnoreCase)
        // The installer's window is still closing during the first seconds.
        || window.Process.StartsWith("PlantoirSetup", StringComparison.OrdinalIgnoreCase);

    private static AutomationElement? PlantoirWindow()
    {
        foreach (var window in Program.Watch.New())
            if (window.Process.Equals("Plantoir", StringComparison.OrdinalIgnoreCase) && window.Class == "WinUIDesktopWin32WindowClass")
                return window.Element;
        return null;
    }

    private static void BringToFront(AutomationElement window)
    {
        IntPtr handle = window.Properties.NativeWindowHandle.ValueOrDefault;
        ShowWindow(handle, 3);   // SW_MAXIMIZE: nothing else on the desktop covers it
        SetForegroundWindow(handle);
    }

    // ---- 4. Working folder ----------------------------------------------------

    /// <summary>
    /// Makes an empty folder, Documents\Course Notes, then Choose Folder…,
    /// types its path into the picker's Folder box and presses Select Folder,
    /// then Set Up This Folder. Passes when the New Course or Club sheet opens
    /// (the app opens it itself after a set-up) and the folder holds its
    /// launchers. The folder is made by the driver, not in the picker (a
    /// teacher would use the picker's New folder button); what Plantoir does
    /// with an empty folder is the same.
    /// </summary>
    public static void SetUpWorkingFolder(AutomationElement window)
    {
        if (Directory.Exists(WorkingFolder) && Directory.EnumerateFileSystemEntries(WorkingFolder).Any())
            throw Stopped.Driver($"{WorkingFolder} already exists and is not empty; this machine is not clean");
        Directory.CreateDirectory(WorkingFolder);
        Program.Note($"made an empty folder, {WorkingFolder}");
        Press(ById(window, "chooseFolderButton")!, "Choose Folder…");

        AutomationElement? picker = null;
        if (!Program.Watch.WaitFor(() => (picker = FolderPicker(window)) is not null, TimeSpan.FromSeconds(60), IsPlantoirWindow) || picker is null)
            throw Stopped.Product($"Choose Folder… opened no folder picker within a minute [screenshot {Program.Shot("no-picker")}]");
        Thread.Sleep(1500);
        var folderBox = picker.FindFirstChild(cf => cf.ByAutomationId("1152"));
        var select = picker.FindFirstChild(cf => cf.ByAutomationId("1"));
        if (folderBox is null || select is null)
            throw Stopped.Driver("the folder picker has no Folder box or Select Folder button where expected: " + WindowWatch.Words(picker));
        SendMessage(folderBox.Properties.NativeWindowHandle.ValueOrDefault, WM_SETTEXT, IntPtr.Zero, WorkingFolder);
        Program.Note($"folder picker: typed {WorkingFolder} into Folder and pressed Select Folder");
        PostMessage(select.Properties.NativeWindowHandle.ValueOrDefault, BM_CLICK, IntPtr.Zero, IntPtr.Zero);

        AutomationElement? setUp = null;
        if (!Program.Watch.WaitFor(() => (setUp = ById(window, "initializeFolderButton")) is not null && FolderPicker(window) is null,
                                   TimeSpan.FromSeconds(60), IsPlantoirWindow) || setUp is null)
            throw Stopped.Product($"Plantoir did not offer to set up the empty folder; it showed: \"{WindowWatch.Words(window)}\" [screenshot {Program.Shot("no-set-up")}]");
        Program.Shot("set-up-offer");
        Press(setUp, "Set Up This Folder");

        bool sheet = Program.Watch.WaitFor(() =>
        {
            if (Readiness(window) == "failed")
                throw Stopped.Product($"Plantoir said it could not get the working folder ready: \"{WindowWatch.Words(window)}\" [screenshot {Program.Shot("not-ready")}]");
            return ById(window, "newCourseDialog") is not null;
        }, TimeSpan.FromMinutes(5), IsPlantoirWindow);
        if (!sheet)
            throw Stopped.Product($"the New Course or Club sheet did not open within five minutes of Set Up This Folder; the window showed: \"{WindowWatch.Words(window)}\" [screenshot {Program.Shot("no-new-course")}]");
        var holds = new List<string>();
        foreach (string entry in Directory.EnumerateFileSystemEntries(WorkingFolder)) holds.Add(Path.GetFileName(entry));
        holds.Sort(StringComparer.Ordinal);
        Program.Note($"the working folder holds: {string.Join(" ", holds)}");
        foreach (string expected in new[] { "courses", "preview.ps1", "deploy.ps1", ".toolchain" })
            if (!holds.Contains(expected))
                throw Stopped.Product($"the working folder is missing {expected} after Set Up This Folder");
        Program.Note("set up the working folder; Plantoir opened the New Course or Club sheet");
        Program.Shot("new-course-sheet");
    }

    /// <summary>The menu bar's ItemStatus: "copying", "ready" or "failed" (#473).</summary>
    private static string Readiness(AutomationElement window)
    {
        try { return ById(window, "appMenuBar")?.Properties.ItemStatus.ValueOrDefault ?? ""; }
        catch { return ""; }
    }

    private static AutomationElement? FolderPicker(AutomationElement window)
    {
        try
        {
            var inside = window.FindFirstChild(cf => cf.ByClassName("#32770"));
            if (inside is not null) return inside;
            foreach (var top in Program.Watch.New())
                if (top.Class == "#32770" && top.Process.Equals("PickerHost", StringComparison.OrdinalIgnoreCase)) return top.Element;
        }
        catch { }
        return null;
    }

    // ---- 5. Example course ----------------------------------------------------

    /// <summary>
    /// "Add Example Course" in the New Course or Club sheet. Passes when the
    /// sheet says Done, Close is pressed, and the course's section shows in
    /// the sidebar. Returns its course code.
    /// </summary>
    public static string AddExampleCourse(AutomationElement window)
    {
        var dialog = ById(window, "newCourseDialog")!;
        var add = FindByName(dialog, "Add Example Course")
                  ?? throw Stopped.Product("the New Course or Club sheet has no Add Example Course button");
        Press(add, "Add Example Course");
        string phase = "";
        bool done = Program.Watch.WaitFor(() =>
        {
            var sheet = ById(window, "newCourseDialog");
            if (sheet is null) return false;
            phase = ById(sheet, "taskPhaseLabel")?.Name ?? "";
            if (phase.Contains("went wrong", StringComparison.OrdinalIgnoreCase))
                throw Stopped.Product($"adding the example course stopped: \"{phase}\"; the sheet says \"{WindowWatch.Words(sheet, 80)}\" [screenshot {Program.Shot("example-failed")}]");
            var close = ById(sheet, "PrimaryButton");
            return phase == "Done" && close is not null && close.Name == "Close" && close.IsEnabled;
        }, TimeSpan.FromMinutes(10), IsPlantoirWindow);
        if (!done)
            throw Stopped.Product($"adding the example course did not finish within ten minutes (last phase \"{phase}\") [screenshot {Program.Shot("example-stuck")}]");
        Program.Shot("example-done");
        Press(ById(ById(window, "newCourseDialog")!, "PrimaryButton")!, "Close");

        string courses = Path.Combine(WorkingFolder, "courses");
        string? code = null;
        foreach (string folder in Directory.GetDirectories(courses))
        {
            string name = Path.GetFileName(folder);
            if (File.Exists(Path.Combine(folder, "course_config.json"))) code = name;
        }
        if (code is null)
            throw Stopped.Product("the example course was reported done, but no course folder with a course_config.json is in courses");
        string sectionId = $"sidebar-{code}-section1";
        if (!Program.Watch.WaitFor(() => ById(window, sectionId) is not null, TimeSpan.FromSeconds(60), IsPlantoirWindow))
            throw Stopped.Product($"the example course {code} was made but its section 1 does not show in the sidebar [screenshot {Program.Shot("no-sidebar")}]");
        Program.Note($"added the example course, {code}; its sections show in the sidebar");
        return code;
    }

    // ---- 6. Preview -------------------------------------------------------------

    /// <summary>
    /// Selects section 1 if it is not already open and presses Preview.
    /// Passes when the preview's address answers 200 and the window's own
    /// preview shows it; stops, with the progress view's words and the last
    /// lines of its details, at "Something went wrong". Plantoir's own
    /// questions during a preview (today's class, and the like) are answered
    /// with their Close button and recorded, as the UI suite does.
    /// </summary>
    public static void Preview(AutomationElement window, string code)
    {
        string title = $"{code}-S1";
        if (!(ById(window, "SectionTitle")?.Name ?? "").StartsWith(title, StringComparison.Ordinal))
        {
            var row = ById(window, $"sidebar-{code}-section1")!;
            BringToFront(window);
            row.Click();
            if (!Program.Watch.WaitFor(() => (ById(window, "SectionTitle")?.Name ?? "").StartsWith(title, StringComparison.Ordinal),
                                       TimeSpan.FromSeconds(20), IsPlantoirWindow))
                throw Stopped.Driver($"{code} section 1 did not open after a click on its sidebar row");
        }
        var started = DateTime.UtcNow;
        Press(ById(window, "previewButton")!, "Preview");
        string lastMilestone = "";
        string? address = null;
        bool served = Program.Watch.WaitFor(() =>
        {
            AnswerPlantoirQuestion(window);
            string phase = ById(window, "taskPhaseLabel")?.Name ?? "";
            string milestone = ById(window, "taskMilestoneLabel")?.Name ?? "";
            if (milestone.Length > 0 && milestone != lastMilestone)
            {
                lastMilestone = milestone;
                Program.Note($"preview: {phase} {milestone}".Trim());
            }
            if (phase.Contains("went wrong", StringComparison.OrdinalIgnoreCase))
                throw Stopped.Product($"the preview stopped: \"{ById(window, "TitleText")?.Name}: {phase}\"; the last lines of its details: "
                                      + DetailsTail(window) + $" [screenshot {Program.Shot("preview-failed")}]");
            address ??= PreviewAddress(window);
            return address is not null && Answers(address);
        }, TimeSpan.FromMinutes(20), IsPlantoirWindow);
        if (!served)
            throw Stopped.Product($"the preview did not answer within twenty minutes (last step \"{lastMilestone}\"); details: {DetailsTail(window)} [screenshot {Program.Shot("preview-stuck")}]");
        Program.Note($"the preview answers at {address}, {(DateTime.UtcNow - started).TotalSeconds:0} s after Preview");
        bool inWindow = Program.Watch.WaitFor(() => ById(window, "previewWebView") is { } view && !view.IsOffscreen,
                                              TimeSpan.FromSeconds(60), IsPlantoirWindow);
        Program.Shot("preview");
        if (!inWindow)
            throw Stopped.Product($"the preview answers at {address} but the window shows no preview [screenshot {Program.Shot("no-web-view")}]");
        Program.Note("the window shows the preview");
    }

    private static readonly Regex AddressLine = new(@"Preview will be available at:\s*(http://\S+)", RegexOptions.Compiled);

    /// <summary>The address the launcher printed, from the progress view's details.</summary>
    private static string? PreviewAddress(AutomationElement window)
    {
        try
        {
            foreach (var pane in window.FindAllDescendants(cf => cf.ByControlType(ControlType.Pane)))
            {
                string text = pane.Properties.Name.ValueOrDefault ?? "";
                var match = AddressLine.Match(text);
                if (match.Success) return match.Groups[1].Value;
            }
            // The details may be folded away; open them once to read the address.
            if (ById(window, "taskDetailsDisclosure") is { } disclosure
                && (ById(window, "DisclosureLabel")?.Name ?? "") == "Show details")
                Press(disclosure, "Show details");
        }
        catch { }
        return null;
    }

    private static string DetailsTail(AutomationElement window)
    {
        try
        {
            if ((ById(window, "DisclosureLabel")?.Name ?? "") == "Show details" && ById(window, "taskDetailsDisclosure") is { } disclosure)
            {
                Press(disclosure, "Show details");
                Thread.Sleep(1500);
            }
            string longest = "";
            foreach (var pane in window.FindAllDescendants(cf => cf.ByControlType(ControlType.Pane)))
            {
                string text = pane.Properties.Name.ValueOrDefault ?? "";
                if (text.Length > longest.Length) longest = text;
            }
            var lines = longest.Replace("\r", "").Split('\n', StringSplitOptions.RemoveEmptyEntries);
            var picked = new List<string>();
            foreach (string line in lines)
                if (line.Contains("ERR_", StringComparison.Ordinal) || line.Contains("could not be found", StringComparison.OrdinalIgnoreCase)
                    || line.Contains("Error", StringComparison.Ordinal) || line.Contains(".node", StringComparison.Ordinal))
                    if (!picked.Contains(line.Trim())) picked.Add(line.Trim());
            var tail = lines.Skip(Math.Max(0, lines.Length - 4)).Select(line => line.Trim());
            File.WriteAllText(Path.Combine(Program.Out, "details.txt"), longest);
            return "\"" + string.Join(" / ", picked.Take(8).Concat(tail)) + "\" (the whole of it is in details.txt)";
        }
        catch (Exception error) { return "(could not read the details: " + error.Message + ")"; }
    }

    private static readonly HttpClient Local = new() { Timeout = TimeSpan.FromSeconds(5) };

    private static bool Answers(string address)
    {
        try { return Local.GetAsync(address).GetAwaiter().GetResult().IsSuccessStatusCode; }
        catch { return false; }
    }

    /// <summary>
    /// A question Plantoir puts up as its own dialog while a preview starts
    /// (today's class, a folder finding). Answered with Close, the way
    /// DrivenApp.WaitAnsweringDialogs does, and recorded.
    /// </summary>
    private static void AnswerPlantoirQuestion(AutomationElement window)
    {
        try
        {
            foreach (var popup in window.FindAllDescendants(cf => cf.ByClassName("Popup").And(cf.ByControlType(ControlType.Window))))
            {
                if (popup.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton")) is { } close && close.IsEnabled)
                {
                    Program.Note($"FINDING: Plantoir asked \"{popup.Name}: {WindowWatch.Words(popup)}\"; answered with \"{close.Name}\" [screenshot {Program.Shot("question")}]");
                    Press(close, close.Name);
                }
            }
        }
        catch (Stopped) { throw; }
        catch { }
    }

    // ---- Shared -------------------------------------------------------------------

    private static AutomationElement? ById(AutomationElement root, string id)
    {
        try { return root.FindFirstDescendant(cf => cf.ByAutomationId(id)); }
        catch { return null; }
    }

    private static AutomationElement? FindByName(AutomationElement root, string name)
    {
        try { return root.FindFirstDescendant(cf => cf.ByName(name)); }
        catch { return null; }
    }

    /// <summary>Presses a control through UI Automation (Invoke), falling back to a Win32 click for a plain button.</summary>
    private static void Press(AutomationElement control, string describedAs)
    {
        if (control.Patterns.Invoke.TryGetPattern(out var invoke)) invoke.Invoke();
        else if (control.Patterns.Toggle.TryGetPattern(out var toggle)) toggle.Toggle();
        else PostMessage(control.Properties.NativeWindowHandle.ValueOrDefault, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
        Program.Note($"pressed {describedAs}");
        Thread.Sleep(500);
    }
}
