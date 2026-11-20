using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace Plantoir.FirstInstall;

/// <summary>
/// The six steps. Each sets its <see cref="Stage"/>, whose allow-list in
/// <see cref="WindowRules"/> names the windows it expects, and answers those
/// here. Every wait goes through <see cref="WindowWatch.WaitFor"/>, so a
/// window or dialog nobody planned for ends the run in whichever step it
/// appears, named, with a screenshot.
/// </summary>
internal static class Steps_
{
    [DllImport("user32.dll")] private static extern IntPtr PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr w, string l);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")] private static extern IntPtr SendMessageNoText(IntPtr window, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);

    private const uint BM_CLICK = 0x00F5;
    private const uint BM_GETCHECK = 0x00F0;
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
        Program.Watch.Stage = Stage.Download;
        Program.Note($"opening {url} in the default browser");
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        string? found = null;
        // Edge's own download warnings (its SmartScreen is on in snapshot 00)
        // are a finding, not part of "the browser is expected here": in an
        // untitled flyout the rules name them ("browser warning"); in a page
        // window they are searched for every five seconds.
        var warned = new HashSet<string>();
        DateTime? firstWarning = null;
        DateTime lastPageSearch = DateTime.MinValue;
        void RecordWarning(SeenWindow window, string words)
        {
            if (!warned.Add($"{window.Handle}|{WindowRules.EdgeWarningIn(words)}")) return;
            firstWarning ??= DateTime.UtcNow;
            Program.Note($"FINDING: Edge warned about the download: {window}, saying \"{words}\" [screenshot {Program.Shot("edge-warning")}]");
        }
        void Answer(SeenWindow window, string kind)
        {
            if (kind == "browser warning") RecordWarning(window, WindowWatch.Words(window.Element, 80));
        }
        bool arrived = Program.Watch.WaitFor(() =>
        {
            if (DateTime.UtcNow - lastPageSearch > TimeSpan.FromSeconds(5))
            {
                lastPageSearch = DateTime.UtcNow;
                foreach (var window in Program.Watch.New())
                {
                    if (!IsBrowserWindow(window) || window.Title.Length == 0) continue;
                    string words = WindowWatch.Words(window.Element, 400);
                    if (WindowRules.EdgeWarningIn(words) is not null) RecordWarning(window, words);
                }
            }
            foreach (string file in Directory.GetFiles(Downloads, "PlantoirSetup*.exe"))
            {
                // Edge writes to a .crdownload (or a "Unconfirmed" name) and renames at the end.
                found = file;
                return true;
            }
            // A warning that holds the download back (Keep / Delete) leaves no
            // PlantoirSetup.exe: a minute after it, the run stops on it rather
            // than waiting out the ten minutes.
            if (firstWarning is { } since && DateTime.UtcNow - since > TimeSpan.FromMinutes(1))
                throw Stopped.Product("Edge warned about the download and PlantoirSetup.exe did not arrive in the minute after; the browser showed: "
                                      + BrowserWords() + $" [screenshot {Program.Shot("edge-held")}]");
            return false;
        }, TimeSpan.FromMinutes(10), Answer);
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
        }, TimeSpan.FromMinutes(2));
        // Edge writes the mark as the download completes, a moment after the
        // file has its name; asked again for up to half a minute.
        string zone = "";
        Program.Watch.WaitFor(() => (zone = ZoneOf(found, Answer)).Contains("ZoneId=", StringComparison.Ordinal),
                              TimeSpan.FromSeconds(30));
        string zoneLine = zone.Split('\n').FirstOrDefault(line => line.StartsWith("ZoneId", StringComparison.Ordinal))?.Trim() ?? zone.Trim();
        Program.Note($"downloaded {Path.GetFileName(found)}, {size:N0} bytes; its mark of the web: {zoneLine}");
        if (!zone.Contains("ZoneId=3", StringComparison.Ordinal))
            throw Stopped.Driver($"the download carries no \"from the internet\" mark ({zoneLine}), so SmartScreen would not be exercised");
        Program.Note("its signature: " + SignatureOf(found, Answer));
        Program.Shot("downloaded");
        CloseBrowser();
        return found;
    }

    /// <summary>
    /// The file's Zone.Identifier stream, the "from the internet" mark. Read
    /// directly, and through PowerShell's -Stream if the runtime refuses the
    /// stream path; the reason is kept when neither can read it.
    /// </summary>
    private static string ZoneOf(string file, Action<SeenWindow, string>? answer)
    {
        string why;
        try { return File.ReadAllText(file + ":Zone.Identifier"); }
        catch (Exception error) { why = error.GetType().Name + ": " + error.Message; }
        try
        {
            var start = new ProcessStartInfo("powershell.exe", $"-NoProfile -Command \"Get-Content -Raw -Stream Zone.Identifier -LiteralPath '{file}'\"")
            { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            var (text, errors) = RunWatched(start, TimeSpan.FromSeconds(30), answer);
            if (text.Contains("ZoneId=", StringComparison.Ordinal)) return text;
            why += "; PowerShell read: " + text.Trim() + errors.Trim();
        }
        catch (Stopped) { throw; }
        catch (Exception error) { why += "; PowerShell: " + error.Message; }
        return "(no mark read: " + why + ")";
    }

    /// <summary>
    /// The installer's Authenticode signature as PowerShell reports it (status
    /// and signer), recorded because SmartScreen's silence depends on it: a
    /// file signed by a publisher with reputation is let through without a
    /// question.
    /// </summary>
    private static string SignatureOf(string file, Action<SeenWindow, string>? answer)
    {
        try
        {
            var start = new ProcessStartInfo("powershell.exe",
                $"-NoProfile -Command \"$s = Get-AuthenticodeSignature -LiteralPath '{file}'; '' + $s.Status + '; ' + $s.SignerCertificate.Subject + '; issued by ' + $s.SignerCertificate.Issuer\"")
            { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            var (output, errors) = RunWatched(start, TimeSpan.FromSeconds(30), answer);
            string text = output.Trim();
            return text.Length > 0 ? text : "(none read) " + errors.Trim();
        }
        catch (Stopped) { throw; }
        catch (Exception error) { return "(could not read: " + error.Message + ")"; }
    }

    /// <summary>
    /// Runs a short command and returns what it printed, looking at the
    /// desktop once a second while it runs. Round six of #976: the signature
    /// check, a PowerShell call of about ten seconds under emulation, was made
    /// with no look at all, and every full run's record showed a gap of 10 to
    /// 15 s in Download, over <see cref="WindowRules.MaxLookGap"/> (runs
    /// win-rehearsal-2026-11-18-232648 and -233358). A command still running
    /// after <paramref name="within"/> is ended.
    /// </summary>
    private static (string Output, string Errors) RunWatched(ProcessStartInfo start, TimeSpan within, Action<SeenWindow, string>? answer)
    {
        using var process = Process.Start(start)!;
        Task<string> output = process.StandardOutput.ReadToEndAsync();
        Task<string> errors = process.StandardError.ReadToEndAsync();
        var until = DateTime.UtcNow + within;
        bool exited = false;
        while (!exited)
        {
            Program.Watch.Check(answer);
            exited = process.WaitForExit(1000);
            if (!exited && DateTime.UtcNow >= until) break;
        }
        if (!exited)
        {
            try { process.Kill(); } catch { }
        }
        string printed = output.Wait(TimeSpan.FromSeconds(5)) ? output.Result : "";
        string complaints = errors.Wait(TimeSpan.FromSeconds(5)) ? errors.Result : "";
        if (!exited) complaints += $" (still running after {within.TotalSeconds:0} s; ended)";
        return (printed, complaints);
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
        // Gone when no browser window is left; ended if one is still there ten seconds on.
        bool closed = Program.Watch.WaitFor(() =>
        {
            foreach (var window in Program.Watch.New())
                if (IsBrowserWindow(window)) return false;
            return true;
        }, TimeSpan.FromSeconds(10));
        if (!closed)
        {
            foreach (var process in Process.GetProcessesByName("msedge")) { try { process.Kill(); } catch { } }
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
        Program.Watch.Stage = Stage.Install;
        // The launch runs on a thread of its own. ShellExecute does not return
        // while Windows checks the file (SmartScreen) or asks about it (the
        // security warning), and those questions are what the watcher below
        // must see and answer; on the step's own thread it would be blind
        // until the call came back (the review of 2026-11-16: run 1 spent
        // 11 s inside the call).
        bool smartScreenBefore = Process.GetProcessesByName("smartscreen").Length > 0;
        DateTime launchStarted = DateTime.UtcNow;
        DateTime? launchReturned = null;
        Exception? launchError = null;
        int looksAtLaunch = Program.Watch.Looks;
        int looksAtReturn = -1;
        var launch = new Thread(() =>
        {
            try { Process.Start(new ProcessStartInfo(installer) { UseShellExecute = true, WorkingDirectory = Downloads }); }
            catch (Exception error) { launchError = error; }
            finally
            {
                // Read here, as the call returns, so the count is exactly the
                // real looks made while it was running.
                Volatile.Write(ref looksAtReturn, Program.Watch.Looks);
                launchReturned = DateTime.UtcNow;
            }
        }) { IsBackground = true, Name = "installer launch" };
        launch.SetApartmentState(ApartmentState.STA);
        launch.Start();
        Program.Note("starting the installer from Downloads, as a double-click does (ShellExecute, on its own thread)");

        var pagesSeen = new List<string>();
        bool finished = false;
        bool launchReported = false;
        bool smartScreenDuring = false;
        int looksDuringLaunch = 0;
        DateTime lastProgress = DateTime.UtcNow;
        string pressedOn = "";
        DateTime pressedAt = DateTime.MinValue;
        DateTime? licenceChosenAt = null;

        void Answer(SeenWindow window, string kind)
        {
            switch (kind)
            {
                case "wizard":
                {
                    string page = InnoPageTitle(window.Element);
                    if (page.Length == 0) return;
                    if (!pagesSeen.Contains(page))
                    {
                        pagesSeen.Add(page);
                        lastProgress = DateTime.UtcNow;
                        Program.Note($"installer page: \"{page}\"");
                        Program.Shot("installer");
                    }
                    // One press per page. Pressed again only if the page is
                    // still showing, its button still enabled, half a minute on.
                    bool again = page == pressedOn && DateTime.UtcNow - pressedAt > TimeSpan.FromSeconds(30);
                    if (page == pressedOn && !again) return;
                    // The Licence Agreement page (#1010): Next works only once
                    // "I accept the agreement" is chosen, so it is chosen first.
                    if (WindowRules.IsLicencePage(page) && page != pressedOn)
                        AnswerLicencePage(window.Element, page, ref licenceChosenAt);
                    foreach (string button in new[] { "Finish", "Install", "Next" })
                    {
                        if (InnoButton(window.Element, button) is { } found && found.IsEnabled)
                        {
                            if (button == "Finish") finished = true;
                            Program.Note($"installer: pressed {button} on \"{page}\"{(again ? " again, the page had not moved in 30 s" : "")}");
                            PostMessage(found.Properties.NativeWindowHandle.ValueOrDefault, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
                            pressedOn = page;
                            pressedAt = DateTime.UtcNow;
                            break;
                        }
                    }
                    return;
                }
                case "smartscreen":
                {
                    string words = WindowWatch.Words(window.Element);
                    if (words.Contains("Smart App Control", StringComparison.OrdinalIgnoreCase))
                        throw Stopped.Product($"Smart App Control blocked the installer: \"{words}\" [screenshot {Program.Shot("smart-app-control")}]");
                    Program.Note($"FINDING: SmartScreen asked before the installer ran: \"{words}\" [screenshot {Program.Shot("smartscreen")}]");
                    if (FindByName(window.Element, "Run anyway") is { } run) Press(run, "Run anyway");
                    else if (FindByName(window.Element, "More info") is { } more) Press(more, "More info");
                    lastProgress = DateTime.UtcNow;
                    return;
                }
                case "security warning":
                {
                    if (FindByName(window.Element, "Run") is not { } runButton)
                        throw Stopped.Product($"Windows asked \"{WindowWatch.Words(window.Element)}\" with no Run button [screenshot {Program.Shot("security-warning")}]");
                    Program.Note($"FINDING: Windows asked \"{WindowWatch.Words(window.Element)}\"; pressed Run [screenshot {Program.Shot("security-warning")}]");
                    Press(runButton, "Run");
                    lastProgress = DateTime.UtcNow;
                    return;
                }
            }
        }

        bool done = Program.Watch.WaitFor(() =>
        {
            if (launchReturned is null)
            {
                if (Process.GetProcessesByName("smartscreen").Length > 0) smartScreenDuring = true;
            }
            else if (!launchReported)
            {
                launchReported = true;
                double seconds = (launchReturned.Value - launchStarted).TotalSeconds;
                looksDuringLaunch = Volatile.Read(ref looksAtReturn) - looksAtLaunch;
                // Enforced, not only reported (the review of 2026-11-18): the
                // point of the launch thread is that the watcher keeps looking
                // while Windows checks the file. At least one real look, and
                // one for every three seconds of the call.
                bool enough = WindowRules.LookedEnough(looksDuringLaunch, launchReturned.Value - launchStarted, out int required);
                Program.Note($"the launch call returned after {seconds:0.0} s; "
                             + $"the watcher looked {looksDuringLaunch} times while it was inside the call (at least {required} required; "
                             + $"{Program.Watch.FailedLooks} looks so far could not read the desktop and are not counted); "
                             + $"smartscreen.exe running before the launch: {(smartScreenBefore ? "yes" : "no")}, during it: {(smartScreenDuring ? "yes" : "no")}");
                if (!enough)
                    throw Stopped.Driver($"the watcher made only {looksDuringLaunch} real looks in the {seconds:0.0} s the installer's launch call ran (at least {required} required), so a question Windows asked then could have gone unseen", "coverage");
                if (launchError is not null)
                    throw Stopped.Product($"Windows would not start the installer: {launchError.GetType().Name}: {launchError.Message} [screenshot {Program.Shot("no-launch")}]");
            }
            if (finished)
            {
                Program.Watch.Stage = Stage.InstallFinished;
                return true;
            }
            // Nothing new for three minutes and no wizard: a prompt the driver
            // cannot see (UAC draws on the secure desktop) or a silent refusal.
            if (DateTime.UtcNow - lastProgress > TimeSpan.FromMinutes(3) && pagesSeen.Count == 0)
                throw Stopped.Product("nothing appeared for three minutes after the installer was started (no wizard, no SmartScreen). "
                                      + "A UAC prompt would be on the secure desktop, out of this driver's sight: see the Mac's report"
                                      + $" [screenshot {Program.Shot("installer-silent")}]");
            return false;
        }, TimeSpan.FromMinutes(15), Answer);
        if (!done)
            throw Stopped.Product($"the installer did not reach its Finish page within fifteen minutes; pages seen: {string.Join(", ", pagesSeen)}"
                                  + $" [screenshot {Program.Shot("installer-stuck")}]");
        Program.Note($"installer finished; pages: {string.Join(" > ", pagesSeen)}");
        if (!File.Exists(InstalledApp))
            throw Stopped.Product($"the installer finished but there is no {InstalledApp}");
        var version = FileVersionInfo.GetVersionInfo(InstalledApp);
        Program.Note($"installed {InstalledApp}, version {version.ProductVersion}");
        // The #1010 review: from 2.0.0 the installer shows the Licence
        // Agreement page, so an install of 2.0.0 or later that never showed
        // it has lost the page, and that is the product's fault, not a pass.
        bool? licenceRequired = WindowRules.LicencePageRequiredFor(version.ProductVersion);
        if (licenceRequired is null)
            throw Stopped.Driver($"the installed {InstalledApp} has a version this driver cannot read (\"{version.ProductVersion}\"), so it could not tell whether the Licence Agreement page was owed");
        if (licenceRequired == true && !WindowRules.LicencePageWasSeen(pagesSeen))
            throw Stopped.Product($"the installer of Plantoir {version.ProductVersion} never showed the Licence Agreement page "
                                  + $"(every installer from {WindowRules.FirstVersionWithLicencePage} shows it first); pages seen: {string.Join(" > ", pagesSeen)}");
    }

    /// <summary>
    /// The Licence Agreement page (#1010): chooses "I accept the agreement"
    /// by its UI Automation name, once, so the button loop can press Next.
    /// Stops the run (PRODUCT STOPPED, never a silent pass) when the page is
    /// there and that choice cannot be found, when the page opened with a
    /// choice already made (the ruling: neither is chosen when it opens), or
    /// when Next is still disabled <see cref="WindowRules.LicenceNextLimit"/>
    /// after the choice.
    /// </summary>
    private static void AnswerLicencePage(AutomationElement wizard, string page, ref DateTime? chosenAt)
    {
        var accept = LicenceChoice(wizard, WindowRules.LicenceAcceptName);
        if (accept is null)
            throw Stopped.Product($"the installer's \"{page}\" page has no \"{WindowRules.LicenceAcceptName}\" choice this driver can find by name; "
                                  + $"it showed: \"{WindowWatch.Words(wizard)}\" [screenshot {Program.Shot("licence-no-accept")}]");
        if (chosenAt is null)
        {
            var refuse = LicenceChoice(wizard, WindowRules.LicenceRefuseName);
            bool? acceptChosen = IsChosen(accept);
            bool? refuseChosen = refuse is null ? false : IsChosen(refuse);
            Program.Note($"installer: \"{page}\" opened with \"{WindowRules.LicenceAcceptName}\" {ChoiceWords(acceptChosen)} "
                         + $"and \"{WindowRules.LicenceRefuseName}\" {(refuse is null ? "not found" : ChoiceWords(refuseChosen))}"
                         + $" [screenshot {Program.Shot("licence-page")}]");
            // The #1010 review: a state that cannot be read is not "not
            // chosen"; the driver did not look, so it says so.
            if (acceptChosen is null || refuseChosen is null)
                throw Stopped.Driver($"the driver could not read whether the choices on the installer's \"{page}\" page were made "
                                     + $"(\"{WindowRules.LicenceAcceptName}\" {ChoiceWords(acceptChosen)}, \"{WindowRules.LicenceRefuseName}\" {ChoiceWords(refuseChosen)}), "
                                     + "so it could not look whether the page opened with neither chosen");
            if (acceptChosen == true || refuseChosen == true)
                throw Stopped.Product($"the installer's \"{page}\" page opened with a choice already made; neither may be chosen when it opens");
            // A click, as a teacher's: Inno's own click handler is what enables Next.
            PostMessage(accept.Properties.NativeWindowHandle.ValueOrDefault, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
            chosenAt = DateTime.UtcNow;
            Program.Note($"installer: chose \"{WindowRules.LicenceAcceptName}\" on \"{page}\"");
            return;
        }
        if (DateTime.UtcNow - chosenAt.Value > WindowRules.LicenceNextLimit
            && !(InnoButton(wizard, "Next") is { } next && next.IsEnabled))
            throw Stopped.Product($"Next was still disabled on the installer's \"{page}\" page {WindowRules.LicenceNextLimit.TotalSeconds:0} s after "
                                  + $"\"{WindowRules.LicenceAcceptName}\" was chosen (the choice reads {ChoiceWords(IsChosen(accept))}) "
                                  + $"[screenshot {Program.Shot("licence-next-disabled")}]");
    }

    /// <summary>
    /// A choice on the page, by its name. Inno draws its choices as
    /// TNewRadioButton, which UI Automation reports as a Pane with no
    /// selection pattern (measured on the VM, 2026-11-19, Inno 6.7.3), so the
    /// class is matched as well as the RadioButton control type.
    /// </summary>
    private static AutomationElement? LicenceChoice(AutomationElement wizard, string choice)
    {
        try
        {
            foreach (var control in wizard.FindAllDescendants())
            {
                bool isChoice = control.Properties.ClassName.ValueOrDefault == "TNewRadioButton"
                                || control.Properties.ControlType.ValueOrDefault == ControlType.RadioButton;
                if (isChoice && WindowRules.IsChoiceNamed(control.Properties.Name.ValueOrDefault ?? "", choice) && !control.IsOffscreen)
                    return control;
            }
        }
        catch { }
        return null;
    }

    /// <summary>
    /// Whether a choice is checked, asked of the Win32 button itself
    /// (BM_GETCHECK): Inno's radios offer UI Automation no state. Null when
    /// the state cannot be read (no window handle, an answer that is neither
    /// checked nor clear, or UI Automation failing), never "not chosen".
    /// </summary>
    private static bool? IsChosen(AutomationElement radio)
    {
        try
        {
            if (radio.Patterns.SelectionItem.TryGetPattern(out var selection))
                return selection.IsSelected.TryGetValue(out bool selected) ? selected : null;
            IntPtr handle = radio.Properties.NativeWindowHandle.ValueOrDefault;
            if (handle == IntPtr.Zero) return null;
            return WindowRules.CheckStateMeans(SendMessageNoText(handle, BM_GETCHECK, IntPtr.Zero, IntPtr.Zero).ToInt64());
        }
        catch { return null; }
    }

    private static string ChoiceWords(bool? chosen) => chosen switch
    {
        true => "chosen",
        false => "not chosen",
        null => "unreadable",
    };

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
        Program.Watch.Stage = Stage.OpenPlantoir;
        AutomationElement? window = null;
        bool shown = Program.Watch.WaitFor(() =>
        {
            window = PlantoirWindow();
            return window is not null && ById(window, "chooseFolderButton") is not null;
        }, TimeSpan.FromMinutes(5));
        if (!shown || window is null)
        {
            string said = window is null ? "(no Plantoir window)" : WindowWatch.Words(window);
            throw Stopped.Product($"Plantoir's first screen did not appear within five minutes of Finish; it showed: \"{said}\" [screenshot {Program.Shot("no-first-screen")}]");
        }
        Program.Watch.PlantoirWindow = window;
        BringToFront(window);
        Program.Note("Plantoir opened at \"Choose Your Working Folder\"");
        Program.Shot("first-screen");
        return window;
    }

    private static AutomationElement? PlantoirWindow()
    {
        foreach (var window in Program.Watch.New())
            if (window.Process.Equals("Plantoir", StringComparison.OrdinalIgnoreCase) && window.Class == "WinUIDesktopWin32WindowClass"
                && window.Title == "Plantoir")
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
        Program.Watch.Stage = Stage.WorkingFolder;
        Directory.CreateDirectory(WorkingFolder);
        Program.Note($"made an empty folder, {WorkingFolder}");
        Press(ById(window, "chooseFolderButton")!, "Choose Folder…");

        AutomationElement? picker = null;
        if (!Program.Watch.WaitFor(() => (picker = FolderPicker(window)) is not null, TimeSpan.FromSeconds(60)) || picker is null)
            throw Stopped.Product($"Choose Folder… opened no folder picker within a minute [screenshot {Program.Shot("no-picker")}]");
        // The picker's window comes before its controls: waited for until both are there.
        AutomationElement? folderBox = null, select = null;
        Program.Watch.WaitFor(() =>
        {
            folderBox = picker.FindFirstChild(cf => cf.ByAutomationId("1152"));
            select = picker.FindFirstChild(cf => cf.ByAutomationId("1"));
            return folderBox is not null && select is not null;
        }, TimeSpan.FromSeconds(30));
        if (folderBox is null || select is null || !(select.Name ?? "").Replace("&", "").Equals("Select Folder", StringComparison.OrdinalIgnoreCase))
            // What opened is a dialog of the picker's class without the
            // picker's controls: an error box, say. That is the product's
            // answer to Choose Folder…, not the driver losing its way.
            throw Stopped.Product($"Choose Folder… opened a dialog that is not the folder picker (no Folder box and Select Folder button): \"{picker.Name}\", saying \"{WindowWatch.Words(picker)}\" [screenshot {Program.Shot("not-the-picker")}]");
        SendMessage(folderBox.Properties.NativeWindowHandle.ValueOrDefault, WM_SETTEXT, IntPtr.Zero, WorkingFolder);
        Program.Note($"folder picker: typed {WorkingFolder} into Folder and pressed Select Folder");
        PostMessage(select.Properties.NativeWindowHandle.ValueOrDefault, BM_CLICK, IntPtr.Zero, IntPtr.Zero);

        AutomationElement? setUp = null;
        if (!Program.Watch.WaitFor(() => (setUp = ById(window, "initializeFolderButton")) is not null && FolderPicker(window) is null,
                                   TimeSpan.FromSeconds(60)) || setUp is null)
            throw Stopped.Product($"Plantoir did not offer to set up the empty folder; it showed: \"{WindowWatch.Words(window)}\" [screenshot {Program.Shot("no-set-up")}]");
        Program.Shot("set-up-offer");
        Press(setUp, "Set Up This Folder");

        bool sheet = Program.Watch.WaitFor(() =>
        {
            if (Readiness(window) == "failed")
                throw Stopped.Product($"Plantoir said it could not get the working folder ready: \"{WindowWatch.Words(window)}\" [screenshot {Program.Shot("not-ready")}]");
            return ById(window, "newCourseDialog") is not null;
        }, TimeSpan.FromMinutes(5));
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
        Program.Watch.Stage = Stage.ExampleCourse;
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
        }, TimeSpan.FromMinutes(10));
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
        if (!Program.Watch.WaitFor(() => ById(window, sectionId) is not null, TimeSpan.FromSeconds(60)))
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
    /// questions during a preview are answered with their Close button and
    /// recorded, as the UI suite does, but only the ones
    /// <see cref="WindowRules.DialogKind"/> names (today's class, a folder
    /// problem, an update offer); any other dialog ends the run.
    /// </summary>
    public static void Preview(AutomationElement window, string code)
    {
        Program.Watch.Stage = Stage.Preview;
        string title = $"{code}-S1";
        if (!(ById(window, "SectionTitle")?.Name ?? "").StartsWith(title, StringComparison.Ordinal))
            OpenSection(window, code, title);
        var started = DateTime.UtcNow;
        Press(ById(window, "previewButton")!, "Preview");
        string lastMilestone = "";
        string? address = null;
        bool served = Program.Watch.WaitFor(() =>
        {
            string phase = ById(window, "taskPhaseLabel")?.Name ?? "";
            string milestone = ById(window, "taskMilestoneLabel")?.Name ?? "";
            // "Gathering your content… still working… (4s)" counts up every second; the step is what matters.
            int working = milestone.IndexOf(" still working", StringComparison.Ordinal);
            if (working > 0) milestone = milestone[..working];
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
        }, TimeSpan.FromMinutes(20));
        if (!served)
            throw Stopped.Product($"the preview did not answer within twenty minutes (last step \"{lastMilestone}\"); details: {DetailsTail(window)} [screenshot {Program.Shot("preview-stuck")}]");
        Program.Note($"the preview answers at {address}, {(DateTime.UtcNow - started).TotalSeconds:0} s after Preview");
        bool inWindow = Program.Watch.WaitFor(() => ById(window, "previewWebView") is { } view && !view.IsOffscreen,
                                              TimeSpan.FromSeconds(60));
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
            }
            // The details draw a moment after they are shown: read until they have text, for up to ten seconds.
            string longest = "";
            var until = DateTime.UtcNow + TimeSpan.FromSeconds(10);
            while (true)
            {
                foreach (var pane in window.FindAllDescendants(cf => cf.ByControlType(ControlType.Pane)))
                {
                    string text = pane.Properties.Name.ValueOrDefault ?? "";
                    if (text.Length > longest.Length) longest = text;
                }
                if (longest.Trim().Length > 0 || DateTime.UtcNow > until) break;
                Thread.Sleep(250);
            }
            var lines = longest.Replace("\r", "").Split('\n', StringSplitOptions.RemoveEmptyEntries);
            // The lines that say what failed: errors, and the module that would not load.
            var picked = new List<string>();
            foreach (string raw in lines)
            {
                string line = raw.Trim();
                bool telling = line.StartsWith("Error", StringComparison.Ordinal) || line.Contains("ERR_", StringComparison.Ordinal)
                               || line.EndsWith(".node", StringComparison.Ordinal) || line.StartsWith("subprocess.CalledProcessError", StringComparison.Ordinal);
                if (telling && !picked.Contains(line)) picked.Add(line.Length > 240 ? line[..240] + "…" : line);
            }
            if (picked.Count == 0)
                foreach (string line in lines.Skip(Math.Max(0, lines.Length - 3))) picked.Add(line.Trim());
            string path = Path.Combine(Program.Out, "details.txt");
            File.WriteAllText(path, longest);
            Program.Keep(path, "details.txt");
            return "\"" + string.Join(" / ", picked.Take(7)) + "\" (the whole of it is in details.txt)";
        }
        catch (Exception error) { return "(could not read the details: " + error.Message + ")"; }
    }

    private static readonly HttpClient Local = new() { Timeout = TimeSpan.FromSeconds(5) };

    private static bool Answers(string address)
    {
        try { return Local.GetAsync(address).GetAwaiter().GetResult().IsSuccessStatusCode; }
        catch { return false; }
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
        // No pause after: every caller waits for the condition the press should bring about.
        Program.Note($"pressed {describedAs}");
    }

    /// <summary>
    /// Opens a section by a real click on its sidebar row: the sidebar acts on
    /// TreeView.ItemInvoked, which SelectionItem.Select does not raise (the UI
    /// suite's DrivenApp.SelectSection says so). Not <c>element.Click()</c>,
    /// which documentation/12-windows-app.md rules out: the middle of the row
    /// is refused when it is off screen, has an empty box, or lies outside
    /// Plantoir's window, so the click cannot land on something else. Up to
    /// three clicks, each followed by a wait for the section's title.
    /// </summary>
    private static void OpenSection(AutomationElement window, string code, string title)
    {
        for (int attempt = 1; attempt <= 3; attempt++)
        {
            var row = ById(window, $"sidebar-{code}-section1")
                      ?? throw Stopped.Product($"the sidebar has no row for {code} section 1 [screenshot {Program.Shot("no-row")}]");
            BringToFront(window);
            var box = row.BoundingRectangle;
            var frame = window.BoundingRectangle;
            bool offscreen;
            try { offscreen = row.IsOffscreen; } catch { offscreen = false; }
            var middle = WindowRules.MiddleWithin(box.Left, box.Top, box.Width, box.Height, offscreen,
                                                  (frame.Left, frame.Top, frame.Width, frame.Height), out string refusal);
            if (middle is not { } point)
                throw Stopped.Driver($"a click on {code} section 1's sidebar row would land somewhere else: {refusal}");
            FlaUI.Core.Input.Mouse.Click(new System.Drawing.Point(point.X, point.Y));
            Program.Note($"clicked {code} section 1's sidebar row at {point.X},{point.Y}{(attempt > 1 ? $" (attempt {attempt})" : "")}");
            if (Program.Watch.WaitFor(() => (ById(window, "SectionTitle")?.Name ?? "").StartsWith(title, StringComparison.Ordinal),
                                      TimeSpan.FromSeconds(6)))
                return;
        }
        throw Stopped.Driver($"{code} section 1 did not open after three clicks on its sidebar row");
    }
}
