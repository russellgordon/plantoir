using System.Text.RegularExpressions;

namespace Plantoir.FirstInstall;

/// <summary>Where the rehearsal is, for the purpose of which windows it expects.</summary>
internal enum Stage
{
    Starting,
    Download,
    Install,
    InstallFinished,
    OpenPlantoir,
    WorkingFolder,
    ExampleCourse,
    Preview,
    /// <summary>
    /// After the last step succeeded: the desktop is watched for
    /// <see cref="WindowRules.FinalWatchLength"/> before PASSED is written, with the
    /// preview's allow-list (a firewall alert raised when the preview server
    /// binds would otherwise come a second after the run said PASSED).
    /// </summary>
    FinalWatch,
}

/// <summary>What the rules make of a new top-level window.</summary>
internal enum Verdict
{
    /// <summary>The desktop's own furniture (taskbar, Start, notification area, Parallels Tools).</summary>
    Desktop,
    /// <summary>A window this stage names; <see cref="Judgement.Kind"/> says which.</summary>
    Expected,
    /// <summary>
    /// No title and no words yet: a frame being drawn, looked at again next
    /// time, and unexpected if it is still so after <see cref="WindowRules.EmptyLimit"/>
    /// (an elevated or custom-drawn prompt whose words UI Automation cannot read
    /// must not be tolerated for ever).
    /// </summary>
    Empty,
    /// <summary>
    /// A window of Plantoir's whose class or title UI Automation cannot read
    /// yet (a window being created), or a dialog at the working-folder step
    /// that does not yet hold the folder picker's controls: judged again at
    /// the next look, and unexpected if it is still so after
    /// <see cref="WindowRules.SettlingLimit"/>.
    /// </summary>
    Settling,
    /// <summary>Not on this stage's list: the run ends, naming it.</summary>
    Unexpected,
    /// <summary>Windows says it blocked or warned about something: the run ends, naming it.</summary>
    Blocked,
}

/// <summary>What <see cref="WindowRules.Settle"/> says a watch or a step may do at a look.</summary>
internal enum Settling
{
    /// <summary>No window is in a grace state: it may finish.</summary>
    Done,
    /// <summary>A window is still in a grace state: look again.</summary>
    KeepLooking,
    /// <summary>Windows were still in a grace state after <see cref="WindowRules.SettleLimit"/>: the run ends, not PASSED.</summary>
    OutOfTime,
    /// <summary>
    /// No successful look within <see cref="WindowRules.MaxLookAge"/> could be
    /// made in <see cref="WindowRules.SettleLimit"/>: nobody was looking, so the
    /// run ends as a DRIVER PROBLEM (cause "coverage"), never PASSED.
    /// </summary>
    NoRecentLook,
}

internal readonly record struct Judgement(Verdict Verdict, string Kind)
{
    public static Judgement Of(Verdict verdict, string kind = "") => new(verdict, kind);
}

/// <summary>
/// One top-level window as the rules see it: its title, class and process, and
/// a way to read the words it shows (read only when a rule needs them, because
/// walking a browser window's whole tree every second is slow).
/// </summary>
internal sealed class WindowFacts
{
    private readonly Func<string> _readWords;
    private readonly Func<string, string?> _controlName;
    private string? _words;

    public WindowFacts(string title, string windowClass, string process, Func<string> readWords,
                       Func<string, string?>? controlName = null)
    {
        Title = title;
        Class = windowClass;
        Process = process;
        _readWords = readWords;
        _controlName = controlName ?? (_ => null);
    }

    public string Title { get; }
    public string Class { get; }
    public string Process { get; }
    public string Words => _words ??= _readWords();

    /// <summary>The name of the control with this automation id inside the window, or null when it has none.</summary>
    public string? ControlName(string automationId) => _controlName(automationId);

    public override string ToString() => $"\"{Title}\" (class {Class}, process {Process})";
}

/// <summary>
/// The allow-list of the first-install rehearsal (#976), with no UI Automation
/// in it, so <c>Plantoir.UiTests.FirstInstall.Tests</c> can pin it on any
/// machine. Each stage NAMES the windows it expects; anything else ends the
/// run. The driver's steps decide how an expected window is answered; these
/// rules decide only whether it is expected.
///
/// The review of 2026-11-16 found the first version allowed every window of
/// Plantoir, PickerHost or PlantoirSetup from step 3 on, any non-wizard
/// window of the installer, every toast, and every window of the driver's own
/// process (where the "Open File - Security Warning" question appears, since
/// the driver is what calls ShellExecute). Those are the cases the tests hold.
/// </summary>
internal static class WindowRules
{
    /// <summary>
    /// Windows of the desktop itself that can come and go during any step and
    /// say nothing about Plantoir, by process and (where given) class. Those
    /// marked <c>Read</c> can carry a notice (a toast, a flyout, the search or
    /// lock screen, the touch keyboard's host) and are read for words that say
    /// Windows blocked or warned about something (<see cref="BlockWords"/>):
    /// the review of 2026-11-18 found SearchHost, ShellHost, LockApp and
    /// TextInputHost let through by process alone. The shell's fixed frames
    /// (taskbar, desktop) and Parallels' own tools are not read.
    /// </summary>
    private static readonly (string Process, string Class, bool Read)[] DesktopWindows =
    {
        ("explorer", "Shell_TrayWnd", false), ("explorer", "Shell_SecondaryTrayWnd", false), ("explorer", "Progman", false),
        ("explorer", "WorkerW", false), ("explorer", "NotifyIconOverflowWindow", true), ("explorer", "Xaml_WindowedPopupClass", true),
        ("explorer", "TopLevelWindowForOverflowXamlIsland", true),
        ("ShellExperienceHost", "", true), ("StartMenuExperienceHost", "", true), ("SearchHost", "", true), ("SearchApp", "", true),
        ("TextInputHost", "", true), ("ShellHost", "", true), ("LockApp", "", true),
        ("prl_cc", "", false), ("prl_tools", "", false), ("prl_tools_service", "", false),
        ("ApplicationFrameHost", "Windows.UI.Core.CoreWindow", true),
    };

    /// <summary>How long a <see cref="Verdict.Settling"/> window may stay unreadable before it is unexpected.</summary>
    public static readonly TimeSpan SettlingLimit = TimeSpan.FromSeconds(20);

    /// <summary>How long a <see cref="Verdict.Empty"/> window may stay without a title or words before it is unexpected.</summary>
    public static readonly TimeSpan EmptyLimit = TimeSpan.FromSeconds(20);

    /// <summary>
    /// How long a top-level window whose properties cannot be read at all may
    /// stay up before it ends the run (<see cref="UnreadableWindows{T}"/>). The
    /// same 20 s as <see cref="SettlingLimit"/>: a window being made or closed
    /// is unreadable for a look or two; one unreadable for longer is a window
    /// of a higher integrity level, which is exactly what the run must not miss
    /// (the uac self-test of 2026-11-18 noted one, handle 0x0, 2 s before the
    /// Mac saw consent.exe).
    /// </summary>
    public static readonly TimeSpan UnreadableLimit = TimeSpan.FromSeconds(20);

    /// <summary>
    /// How long the desktop is watched after the last step succeeded, before
    /// PASSED (the review of 2026-11-18: nothing was watched after the check
    /// that found the preview). Windows raises the Defender Firewall's
    /// "Windows Security Alert" on a program's first listen on a network
    /// address, within a second or two of the bind, but the preview brings up
    /// its web server and its live-reload server separately, the web view's
    /// first load makes the server do more work after the address first
    /// answers, and Windows' own notices (Defender, Smart App Control) arrive
    /// as toasts some seconds after the event. A minute covers all of those
    /// with room over, is about ten of the Mac's five-second looks (so its UAC
    /// watch sees the same minute), and costs one minute a run. This is a
    /// deliberate observation window, not a pause standing in for a condition.
    /// </summary>
    public static readonly TimeSpan FinalWatchLength = TimeSpan.FromSeconds(60);

    /// <summary>
    /// Words that mean Windows itself stopped or questioned something, in a
    /// toast or any desktop window: Smart App Control's block notice comes
    /// through ShellExperienceHost, not the smartscreen process.
    /// </summary>
    public static readonly string[] BlockWords =
    {
        "Smart App Control", "SmartScreen", "Windows protected your PC", "blocked", "Controlled folder access",
        "Unauthorized changes", "Windows Security Alert", "Firewall",
    };

    /// <summary>
    /// Words of Edge's own download warnings (Edge's SmartScreen is on in
    /// snapshot 00): "isn't commonly downloaded", "can harm your device", "was
    /// blocked", "might be harmful". Edge draws them inside its windows, so the
    /// browser being expected at the download step must not hide them; seen,
    /// they are a finding (<see cref="Judge"/>, kind "browser warning").
    /// </summary>
    public static readonly string[] EdgeWarningWords =
    {
        "isn't commonly downloaded", "isn\u2019t commonly downloaded", "can harm your device", "could harm your device",
        "was blocked", "might be harmful", "may be harmful", "Microsoft Defender SmartScreen", "unsafe to download", "Make sure you trust",
    };

    /// <summary>The questions Plantoir may ask while a preview starts, by the title its dialog shows.</summary>
    private static readonly (Regex Title, string Kind)[] PreviewQuestions =
    {
        // contracts/class-planning.json → todaysClassOnTheFrontPage.wording.question
        (new Regex(@"^Show .+ on the front page\?$"), "today's class"),
        // contracts/shared-rules.json → alertTitleOne / alertTitleSeveral
        (new Regex(@"^(A new problem|\d+ new problems) in .+ Section \d+$"), "a folder problem"),
        // Plantoir.Core AppUpdates.OfferTitle, when an older release is rehearsed
        (new Regex(@"^A new version of Plantoir is ready: .+\.$"), "an update offer"),
    };

    private static bool Is(string actual, string expected) =>
        string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase);

    private static bool IsInstaller(WindowFacts window) =>
        window.Process.StartsWith("PlantoirSetup", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Plantoir's main window, by its fixed title (MainWindow.xaml, Title="Plantoir").
    /// Its other windows (Settings, the assistant's "Revise …") share the class
    /// and are not part of a first install, so they are not let through by it.
    /// </summary>
    private static bool IsPlantoirMain(WindowFacts window) =>
        Is(window.Process, "Plantoir") && window.Class == "WinUIDesktopWin32WindowClass" && window.Title == "Plantoir";

    /// <summary>
    /// The input site of the main window's WinUI content (class
    /// InputSiteWindowClass, no title). Normally a child of the main window,
    /// two levels down (vm-tools/runs/win-explore, every UI tree read there);
    /// rehearsal 2026-11-16-134814 saw it once as a top-level window during the
    /// first seconds after launch, showing the first screen's own words. It is
    /// Plantoir's content, not a window of its own: the dialogs inside it are
    /// judged as the main window's are (<see cref="WindowWatch"/>).
    /// </summary>
    public static bool IsPlantoirContent(WindowFacts window) =>
        Is(window.Process, "Plantoir") && window.Class == "InputSiteWindowClass" && window.Title.Length == 0;

    /// <summary>
    /// A windowed popup of Plantoir's (WinUI draws a tooltip, a menu bar menu
    /// or a flyout in a window of this class so it can reach past the main
    /// window's edge). Not yet seen in a rehearsal; named because step 6 opens
    /// the section with a real click on a sidebar row that has a tooltip.
    /// Its words are recorded when it is allowed.
    /// </summary>
    private static bool IsPlantoirPopup(WindowFacts window) =>
        Is(window.Process, "Plantoir") && window.Class == "Microsoft.UI.Content.PopupWindowSiteBridge";

    /// <summary>
    /// The User Account Control prompt, by its process. Kept, but NOT relied
    /// on: in the uac self-test of 2026-11-18 (run
    /// win-rehearsal-2026-11-18-132158-selftest-uac, PromptOnSecureDesktop 0)
    /// the prompt was on the ordinary desktop and the Mac's capture, yet this
    /// driver went on for 20 s without UI Automation listing its window. The
    /// Mac's consent.exe probe, asked as SYSTEM, is the proven detection.
    /// </summary>
    private static bool IsUacPrompt(WindowFacts window) => Is(window.Process, "consent");

    /// <summary>Null when the window is not the desktop's furniture; otherwise whether its words are read for <see cref="BlockWords"/>.</summary>
    private static bool? DesktopFurniture(WindowFacts window)
    {
        // Parallels Tools updating itself in a terminal window: the virtual
        // machine's own plumbing, which a teacher's PC does not have.
        if (Is(window.Process, "WindowsTerminal") && window.Title.Contains(@"Parallels\Parallels Tools", StringComparison.OrdinalIgnoreCase))
            return false;
        foreach (var (process, windowClass, read) in DesktopWindows)
            if (Is(window.Process, process) && (windowClass.Length == 0 || window.Class == windowClass))
                return read;
        return null;
    }

    /// <summary>The first of <see cref="EdgeWarningWords"/> the text holds, or null.</summary>
    public static string? EdgeWarningIn(string text)
    {
        foreach (string word in EdgeWarningWords)
            if (text.Contains(word, StringComparison.OrdinalIgnoreCase)) return word;
        return null;
    }

    /// <summary>
    /// The folder picker (Windows.Storage.Pickers.FolderPicker, which
    /// Plantoir's Choose Folder… opens), known by what makes it the picker:
    /// its Folder box (id 1152) and its Select Folder button (id 1), the
    /// controls step 4 drives. A Win32 error box of the same class has neither.
    /// </summary>
    public static bool IsFolderPicker(WindowFacts window) =>
        window.Class == "#32770" && (Is(window.Process, "PickerHost") || Is(window.Process, "Plantoir"))
        && window.ControlName("1152") is not null && window.ControlName("1") is { } select
        && select.Replace("&", "").Equals("Select Folder", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The installer's Licence Agreement page (#1010), by its heading:
    /// installer.iss sets it to "Licence Agreement" (Russell, 2026-11-19,
    /// ruling 4); Inno's own "License Agreement" is recognised too, so an
    /// installer that lost the override still has its page answered, and the
    /// spelling is held by the source tests, not here. An older installer
    /// (1.9.3 and before) has no such page and nothing changes for it.
    /// </summary>
    public static bool IsLicencePage(string pageTitle) =>
        Is(pageTitle.Trim(), "Licence Agreement") || Is(pageTitle.Trim(), "License Agreement");

    /// <summary>The choice step 2 makes on the Licence Agreement page, by its UI Automation name.</summary>
    public const string LicenceAcceptName = "I accept the agreement";

    /// <summary>The other choice on the page, read only to say what the page opened with.</summary>
    public const string LicenceRefuseName = "I do not accept the agreement";

    /// <summary>
    /// Whether a control's UI Automation name is the named choice. Win32
    /// controls usually give their caption without its access-key ampersand
    /// ("I &amp;accept the agreement" reads "I accept the agreement"); it is
    /// taken out here too, so either reading matches, and nothing else does.
    /// </summary>
    public static bool IsChoiceNamed(string controlName, string choice) =>
        controlName.Replace("&", "").Trim().Equals(choice, StringComparison.Ordinal);

    /// <summary>
    /// How long after "I accept the agreement" was chosen Next may stay
    /// disabled before the run stops on it: Inno enables Next in the choice's
    /// own click handler, so on a working page it is enabled at the next look;
    /// thirty seconds is the same allowance the wizard's other pages get
    /// before a press is repeated.
    /// </summary>
    public static readonly TimeSpan LicenceNextLimit = TimeSpan.FromSeconds(30);

    /// <summary>
    /// What a Win32 button's BM_GETCHECK answer says about a choice: 1
    /// (BST_CHECKED) is chosen, 0 (BST_UNCHECKED) is not, and anything else
    /// (2 is BST_INDETERMINATE, which a radio button never is) is a state
    /// this driver cannot read, null. The #1010 review: a choice whose state
    /// could not be read is not "not chosen", or a page that opened with a
    /// choice made would pass unseen; the caller stops with DRIVER PROBLEM.
    /// </summary>
    public static bool? CheckStateMeans(long answer) => answer switch
    {
        1 => true,
        0 => false,
        _ => null,
    };

    /// <summary>
    /// The first Plantoir whose installer shows the Licence Agreement page
    /// (#1010, Russell's rulings of 2026-11-19). An installer of this version
    /// or later that never showed the page has lost it, and the run stops.
    /// </summary>
    public static readonly Version FirstVersionWithLicencePage = new(2, 0, 0);

    /// <summary>
    /// Whether the installer of the installed version must have shown the
    /// Licence Agreement page: true from <see
    /// cref="FirstVersionWithLicencePage"/> on, false before it (1.9.3 has
    /// none), and null when the version cannot be read, which the caller
    /// treats as a DRIVER PROBLEM rather than guess. The product version
    /// may carry a suffix ("2.0.0+1ba4ceaf6", "2.0.0-beta"); the numbers
    /// before it are read.
    /// </summary>
    public static bool? LicencePageRequiredFor(string? productVersion)
    {
        if (string.IsNullOrWhiteSpace(productVersion)) return null;
        var numbers = Regex.Match(productVersion.Trim(), @"^(\d+)\.(\d+)(?:\.(\d+))?");
        if (!numbers.Success) return null;
        int build = numbers.Groups[3].Success ? int.Parse(numbers.Groups[3].Value) : 0;
        var version = new Version(int.Parse(numbers.Groups[1].Value), int.Parse(numbers.Groups[2].Value), build);
        return version >= FirstVersionWithLicencePage;
    }

    /// <summary>Whether any page the installer showed was the Licence Agreement page.</summary>
    public static bool LicencePageWasSeen(IEnumerable<string> pagesSeen)
    {
        foreach (string page in pagesSeen)
            if (IsLicencePage(page)) return true;
        return false;
    }

    /// <summary>The first of <see cref="BlockWords"/> the text holds, or null.</summary>
    public static string? BlockWordIn(string text)
    {
        foreach (string word in BlockWords)
            if (text.Contains(word, StringComparison.OrdinalIgnoreCase)) return word;
        return null;
    }

    /// <summary>
    /// Judges one new top-level window at one stage. <paramref name="seenFor"/>
    /// is how long the watcher has seen this window: a window still settling
    /// or still empty past its limit is unexpected.
    /// </summary>
    public static Judgement Judge(Stage stage, WindowFacts window, TimeSpan seenFor = default)
    {
        // Asked first, whoever owns it: ShellExecute draws this question in
        // the CALLER's process, which is the driver itself.
        if (window.Title.Contains("Security Warning", StringComparison.OrdinalIgnoreCase))
            return stage == Stage.Install ? Judgement.Of(Verdict.Expected, "security warning") : Judgement.Of(Verdict.Unexpected);

        // Never expected: no step of a first install asks for elevation.
        if (IsUacPrompt(window)) return Judgement.Of(Verdict.Blocked, "a User Account Control prompt");

        if (DesktopFurniture(window) is { } read)
        {
            // A toast, flyout or shell surface is furniture unless it says
            // Windows stopped or questioned something.
            if (read && BlockWordIn(window.Words) is not null) return Judgement.Of(Verdict.Blocked, "a notice from Windows");
            return Judgement.Of(Verdict.Desktop);
        }

        if (Is(window.Process, "smartscreen"))
            return stage == Stage.Install ? Judgement.Of(Verdict.Expected, "smartscreen") : Judgement.Of(Verdict.Unexpected);

        switch (stage)
        {
            case Stage.Download:
                if (Is(window.Process, "msedge"))
                {
                    // Its untitled windows are its flyouts and bubbles, where
                    // Edge puts a download warning: read, and a warning is a
                    // finding. (Its titled windows are pages, searched for the
                    // same words by the step itself.)
                    if (window.Title.Length == 0 && EdgeWarningIn(window.Words) is not null)
                        return Judgement.Of(Verdict.Expected, "browser warning");
                    return Judgement.Of(Verdict.Expected, "browser");
                }
                break;
            case Stage.Install:
            case Stage.InstallFinished:
                if (IsInstaller(window) && window.Class == "TWizardForm") return Judgement.Of(Verdict.Expected, "wizard");
                // Inno Setup's application window: it carries the title only.
                if (IsInstaller(window) && window.Class == "TApplication") return Judgement.Of(Verdict.Expected, "installer application window");
                if (stage == Stage.InstallFinished && IsPlantoirMain(window)) return Judgement.Of(Verdict.Expected, "plantoir");
                if (stage == Stage.InstallFinished && IsPlantoirContent(window)) return Judgement.Of(Verdict.Expected, "plantoir content");
                break;
            case Stage.OpenPlantoir:
                if (IsPlantoirMain(window)) return Judgement.Of(Verdict.Expected, "plantoir");
                if (IsPlantoirContent(window)) return Judgement.Of(Verdict.Expected, "plantoir content");
                if (IsPlantoirPopup(window)) return Judgement.Of(Verdict.Expected, "plantoir popup");
                // The wizard is still closing during the first seconds.
                if (IsInstaller(window) && window.Class is "TWizardForm" or "TApplication") return Judgement.Of(Verdict.Expected, "installer closing");
                break;
            case Stage.WorkingFolder:
                if (IsPlantoirMain(window)) return Judgement.Of(Verdict.Expected, "plantoir");
                if (IsPlantoirContent(window)) return Judgement.Of(Verdict.Expected, "plantoir content");
                if (IsPlantoirPopup(window)) return Judgement.Of(Verdict.Expected, "plantoir popup");
                if (IsFolderPicker(window)) return Judgement.Of(Verdict.Expected, "folder picker");
                // The picker's window comes before its controls: judged again
                // until they are there, for at most SettlingLimit, so an error
                // box of the same class is not taken for it.
                if (window.Class == "#32770" && (Is(window.Process, "PickerHost") || Is(window.Process, "Plantoir")))
                    return seenFor < SettlingLimit ? Judgement.Of(Verdict.Settling)
                                                   : Judgement.Of(Verdict.Unexpected, $"not the folder picker after {SettlingLimit.TotalSeconds:0} s");
                break;
            case Stage.ExampleCourse:
            case Stage.Preview:
            case Stage.FinalWatch:
                if (IsPlantoirMain(window)) return Judgement.Of(Verdict.Expected, "plantoir");
                if (IsPlantoirContent(window)) return Judgement.Of(Verdict.Expected, "plantoir content");
                if (IsPlantoirPopup(window)) return Judgement.Of(Verdict.Expected, "plantoir popup");
                break;
        }

        // Plantoir's own window while it is being created: rehearsal
        // 2026-11-18-102329 read its main window, a second after launch, with
        // no class and no title, showing only its caption buttons ("Minimize |
        // Maximize | Close"). Judged again until it reads as what it is.
        if (stage is Stage.InstallFinished or Stage.OpenPlantoir or Stage.WorkingFolder or Stage.ExampleCourse or Stage.Preview or Stage.FinalWatch
            && Is(window.Process, "Plantoir")
            && (window.Class.Length == 0 || window.Class == "WinUIDesktopWin32WindowClass" && window.Title.Length == 0))
            return seenFor < SettlingLimit ? Judgement.Of(Verdict.Settling)
                                           : Judgement.Of(Verdict.Unexpected, $"still without a readable class or title after {SettlingLimit.TotalSeconds:0} s");

        // A window with no title and nothing in it is a frame being drawn;
        // it is judged again when it has something to show, for at most
        // EmptyLimit: one that stays so (an elevated or custom-drawn prompt
        // UI Automation cannot read) ends the run.
        if (window.Title.Length == 0 && window.Words.Length == 0)
            return seenFor < EmptyLimit ? Judgement.Of(Verdict.Empty)
                                        : Judgement.Of(Verdict.Unexpected, $"untitled, with no words UI Automation could read, for {EmptyLimit.TotalSeconds:0} s");
        return Judgement.Of(Verdict.Unexpected);
    }

    /// <summary>
    /// Judges a dialog inside Plantoir's window (a ContentDialog, which UI
    /// Automation shows as a Popup named by its title and holding a dialog's
    /// buttons). Returns what it is, "new course sheet" or "question: …", or
    /// null when this stage does not expect it.
    /// </summary>
    public static string? DialogKind(Stage stage, string title, bool isNewCourseSheet)
    {
        if (isNewCourseSheet && stage is Stage.WorkingFolder or Stage.ExampleCourse) return "new course sheet";
        if (stage is Stage.Preview or Stage.FinalWatch)
            foreach (var (pattern, kind) in PreviewQuestions)
                if (pattern.IsMatch(title)) return "question: " + kind;
        return null;
    }

    /// <summary>
    /// How long a watch or a step may go on looking, after it would otherwise
    /// have finished, for windows still in a grace period to be judged (the
    /// fourth review: the final watch could end, and PASSED be written, with an
    /// unreadable, empty or settling window still on screen). The final
    /// watch's own length: every grace is 20 s, so a window that reaches this
    /// is one that keeps coming back, and the run is not PASSED.
    /// </summary>
    public static readonly TimeSpan SettleLimit = TimeSpan.FromSeconds(60);

    /// <summary>
    /// The rule a watch or a step ends by: it may say it is finished only when
    /// no window is in a grace state (tolerated for now is not allowed).
    /// <paramref name="pending"/> is how many are, at the last look; <paramref name="waited"/>
    /// how long it has gone on looking past its own end.
    /// </summary>
    /// <remarks>
    /// <paramref name="freshLook"/> is whether the last look read the desktop
    /// AND was made within <see cref="MaxLookAge"/> (the fifth review: a look
    /// that cannot read the desktop keeps the previous look's pending set, so
    /// a watch whose last looks all failed decided on a stale, empty set and
    /// PASSED was written for a desktop nobody looked at). Without one, nothing
    /// is finished, whatever the pending count says.
    /// </remarks>
    public static Settling Settle(int pending, TimeSpan waited, bool freshLook)
    {
        if (freshLook && pending == 0) return Settling.Done;
        if (waited < SettleLimit) return Settling.KeepLooking;
        // Without a fresh look the pending count is an old look's, so running
        // out of time then says nobody was looking, not that a window stayed.
        return freshLook ? Settling.OutOfTime : Settling.NoRecentLook;
    }

    /// <summary>
    /// How recent the last successful look must be when a step or a watch is
    /// declared finished, or PASSED is written (the fifth review). Looks are a
    /// second apart and one takes about 0.3 s under emulation (a launch call
    /// of 22 s saw 17 looks, rehearsal 2026-11-18-184324), so 5 s is several
    /// looks' worth: a decision older than that is a decision about a desktop
    /// nobody has looked at lately.
    /// </summary>
    public static readonly TimeSpan MaxLookAge = TimeSpan.FromSeconds(5);

    /// <summary>
    /// The largest gap allowed between successful looks: inside the final
    /// watch the driver enforces it itself (DRIVER PROBLEM, cause "coverage"),
    /// and over the whole run it is recorded in result.txt
    /// (largest-look-gap-ms), and the Mac refuses a PASSED whose record is
    /// over it. Ten seconds: a window that comes and goes faster than that
    /// between two looks is not something a teacher could have read either,
    /// and slow work on the step's own thread (a screenshot, reading a
    /// browser's words) stays well inside it.
    /// </summary>
    public static readonly TimeSpan MaxLookGap = TimeSpan.FromSeconds(10);

    /// <summary>
    /// Whether the watcher looked enough during a stretch of time: at least
    /// one real look, and one for every three seconds (the installer's launch
    /// call, Steps.cs; the final watch, Program.cs). False means the stretch
    /// was not really watched and the run is a DRIVER PROBLEM. A count alone
    /// says nothing about spread: <see cref="LookRecord.LargestGap"/> does.
    /// </summary>
    public static bool LookedEnough(int realLooks, TimeSpan stretch, out int required)
    {
        required = Math.Max(1, (int)(stretch.TotalSeconds / 3));
        return realLooks >= required;
    }

    /// <summary>
    /// The middle of a box, for a real click, refused where it would land
    /// somewhere else — the rule of <c>DrivenApp.MiddleWithin</c> in the UI
    /// suite (documentation/12-windows-app.md: a bare <c>element.Click()</c>
    /// is ruled out). Returns null and the reason when refused.
    /// </summary>
    public static (int X, int Y)? MiddleWithin(int left, int top, int width, int height, bool offscreen,
                                               (int Left, int Top, int Width, int Height)? window, out string refusal)
    {
        refusal = "";
        if (offscreen) { refusal = "it is off screen"; return null; }
        if (width <= 0 || height <= 0) { refusal = $"its box is empty ({left},{top} {width}x{height})"; return null; }
        int x = left + width / 2, y = top + height / 2;
        if (window is { } w && (x < w.Left || y < w.Top || x >= w.Left + w.Width || y >= w.Top + w.Height))
        {
            refusal = $"its middle ({x},{y}) is outside Plantoir's window";
            return null;
        }
        return (x, y);
    }
}

/// <summary>What happened to an unreadable top-level window at one look.</summary>
internal enum UnreadableChange
{
    /// <summary>First seen unreadable at this look; recorded, and given <see cref="WindowRules.UnreadableLimit"/>.</summary>
    Appeared,
    /// <summary>Readable now, within the limit: from here it is judged by the ordinary rules.</summary>
    BecameReadable,
    /// <summary>No longer listed, within the limit (a window that closed).</summary>
    Gone,
    /// <summary>Still unreadable at the limit: the run ends, not PASSED.</summary>
    TooLong,
    /// <summary>
    /// At least one unreadable window has been on screen at every look for
    /// the limit, whichever windows they were: the run ends, not PASSED. Asked
    /// independently of identity, so a window whose comparison throws or never
    /// matches itself (and so gets a new number at each look) is still caught.
    /// </summary>
    PresentTooLong,
    /// <summary>Comparing two windows threw at this look; recorded, with how many times.</summary>
    ComparisonFailed,
}

/// <summary>One thing to record about an unreadable window. <see cref="Number"/> is its number in this run, from 1 (0 for the events about no one window).</summary>
internal readonly record struct UnreadableEvent(UnreadableChange Change, int Number, TimeSpan SeenFor, int Sightings, string Error);

/// <summary>
/// Judges the top-level windows UI Automation lists but cannot read (their
/// properties throw), which the review of 2026-11-18 found were noted once and
/// then never judged: one could stay up through the final watch and the run
/// still say PASSED. Each is told apart from the others by
/// <c>sameWindow</c> (UI Automation's own element comparison in the driver),
/// never by its handle, which reads 0x0 for every such window. Every window
/// is recorded when it appears and when it stops being unreadable; one still
/// unreadable after <see cref="WindowRules.UnreadableLimit"/> ends the run.
///
/// Two rules hold whatever the comparison says (the fourth review): a single
/// clock runs while at least one unreadable window is present at every look,
/// and it ends the run at the same limit; and a comparison that throws is
/// recorded, counted as "not the same window", never hidden.
/// No UI Automation in it, so the tests can drive it with plain values.
/// </summary>
internal sealed class UnreadableWindows<T>
{
    private sealed class Tracked
    {
        public required T Window { get; init; }
        public required int Number { get; init; }
        public required DateTime FirstSeen { get; init; }
        public int Sightings { get; set; }
        public string Error { get; set; } = "";
    }

    private readonly Func<T, T, bool> _sameWindow;
    private readonly List<Tracked> _tracked = new();
    private int _numbered;
    private DateTime? _presentSince;
    private int _presentLooks;
    private int _comparisonFailures;
    private string _lastComparisonError = "";

    public UnreadableWindows(Func<T, T, bool> sameWindow) => _sameWindow = sameWindow;

    /// <summary>How many different unreadable windows this run has seen.</summary>
    public int Seen => _numbered;

    /// <summary>How many comparisons threw in this run.</summary>
    public int ComparisonFailures => _comparisonFailures;

    /// <summary>
    /// Whether an unreadable window is still inside its grace: one is being
    /// tracked, or one was present at the last look. While true, no watch or
    /// step may be declared finished (<see cref="WindowRules.Settle"/>).
    /// </summary>
    public bool Pending => _tracked.Count > 0 || _presentSince is not null;

    private bool Same(T first, T second, ref int failures)
    {
        try { return _sameWindow(first, second); }
        catch (Exception error)
        {
            failures++;
            _comparisonFailures++;
            _lastComparisonError = error.GetType().Name + ": " + error.Message;
            return false;
        }
    }

    /// <summary>
    /// One look: the windows that could not be read at it (with the error),
    /// and the windows that could. Returns what to record, in order; a
    /// <see cref="UnreadableChange.TooLong"/> or <see cref="UnreadableChange.PresentTooLong"/>
    /// event means the run must end.
    /// </summary>
    public List<UnreadableEvent> Look(IReadOnlyList<(T Window, string Error)> unreadable, IReadOnlyList<T> readable, DateTime now)
    {
        var events = new List<UnreadableEvent>();
        var stillUnreadable = new List<Tracked>();
        int failures = 0;
        foreach (var (window, error) in unreadable)
        {
            Tracked? known = null;
            foreach (var tracked in _tracked)
                if (!stillUnreadable.Contains(tracked) && Same(tracked.Window, window, ref failures)) { known = tracked; break; }
            if (known is null)
            {
                known = new Tracked { Window = window, Number = ++_numbered, FirstSeen = now, Error = error };
                _tracked.Add(known);
                events.Add(new UnreadableEvent(UnreadableChange.Appeared, known.Number, TimeSpan.Zero, 1, error));
            }
            known.Sightings++;
            known.Error = error;
            stillUnreadable.Add(known);
        }
        foreach (var tracked in _tracked.ToList())
        {
            TimeSpan seenFor = now - tracked.FirstSeen;
            if (stillUnreadable.Contains(tracked))
            {
                if (seenFor >= WindowRules.UnreadableLimit)
                    events.Add(new UnreadableEvent(UnreadableChange.TooLong, tracked.Number, seenFor, tracked.Sightings, tracked.Error));
                continue;
            }
            bool nowReadable = false;
            foreach (var window in readable)
                if (Same(tracked.Window, window, ref failures)) { nowReadable = true; break; }
            events.Add(new UnreadableEvent(nowReadable ? UnreadableChange.BecameReadable : UnreadableChange.Gone,
                                           tracked.Number, seenFor, tracked.Sightings, tracked.Error));
            _tracked.Remove(tracked);
        }
        if (failures > 0)
            events.Add(new UnreadableEvent(UnreadableChange.ComparisonFailed, 0, TimeSpan.Zero, failures, _lastComparisonError));
        // The clock that does not depend on telling windows apart.
        if (unreadable.Count > 0)
        {
            _presentSince ??= now;
            _presentLooks++;
            TimeSpan present = now - _presentSince.Value;
            if (present >= WindowRules.UnreadableLimit)
                events.Add(new UnreadableEvent(UnreadableChange.PresentTooLong, 0, present, _presentLooks, unreadable[0].Error));
        }
        else
        {
            _presentSince = null;
            _presentLooks = 0;
        }
        return events;
    }
}

/// <summary>
/// The record of every look the watcher made: when each successful one read
/// the desktop, and how many failed (the fifth review: a look that could not
/// read the desktop returned early and was simply not counted, so a stretch of
/// failed looks was invisible). It answers the two questions every decision
/// needs, with no UI Automation in it so the tests can drive it: was the last
/// look successful and recent (<see cref="FreshAt"/>), and what was the
/// largest stretch with no successful look (<see cref="LargestGap"/>), over
/// the whole run or over one watch. A gap is measured from the record's start,
/// between successful looks, and on to the moment asked about, so a tail of
/// failed looks is a gap too.
/// </summary>
internal sealed class LookRecord
{
    private readonly DateTime _start;
    private readonly List<DateTime> _good = new();
    private bool _lastFailed;

    public LookRecord(DateTime start) => _start = start;

    /// <summary>Successful looks so far.</summary>
    public int Good => _good.Count;

    /// <summary>Looks that could not read the desktop.</summary>
    public int Failed { get; private set; }

    /// <summary>When the last successful look read the desktop, or null.</summary>
    public DateTime? LastGood => _good.Count == 0 ? null : _good[^1];

    /// <summary>A look that read the desktop at <paramref name="readAt"/>.</summary>
    public void Succeeded(DateTime readAt)
    {
        // Looks are made on one thread, in order; a clock step backwards is
        // recorded as a look at the last time rather than reordering the list.
        if (_good.Count > 0 && readAt < _good[^1]) readAt = _good[^1];
        _good.Add(readAt);
        _lastFailed = false;
    }

    /// <summary>A look that could not read the desktop.</summary>
    public void FailedLook()
    {
        Failed++;
        _lastFailed = true;
    }

    /// <summary>
    /// Whether a decision may be made at <paramref name="now"/>: the last look
    /// was successful, and made within <see cref="WindowRules.MaxLookAge"/>.
    /// </summary>
    public bool FreshAt(DateTime now) =>
        !_lastFailed && LastGood is { } last && now - last <= WindowRules.MaxLookAge;

    /// <summary>
    /// The largest stretch between <paramref name="from"/> and
    /// <paramref name="to"/> with no successful look in it: from
    /// <paramref name="from"/> to the first look after it, between looks, and
    /// from the last look to <paramref name="to"/>.
    /// </summary>
    public TimeSpan LargestGap(DateTime from, DateTime to)
    {
        DateTime previous = from;
        TimeSpan largest = TimeSpan.Zero;
        foreach (var look in _good)
        {
            if (look <= from) continue;
            if (look > to) break;
            if (look - previous > largest) largest = look - previous;
            previous = look;
        }
        if (to - previous > largest) largest = to - previous;
        return largest;
    }

    /// <summary>The largest gap from the record's start (the driver's first look) to <paramref name="now"/>.</summary>
    public TimeSpan LargestGap(DateTime now) => LargestGap(_start, now);
}
