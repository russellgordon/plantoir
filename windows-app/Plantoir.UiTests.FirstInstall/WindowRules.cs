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
}

/// <summary>What the rules make of a new top-level window.</summary>
internal enum Verdict
{
    /// <summary>The desktop's own furniture (taskbar, Start, notification area, Parallels Tools).</summary>
    Desktop,
    /// <summary>A window this stage names; <see cref="Judgement.Kind"/> says which.</summary>
    Expected,
    /// <summary>No title and no words yet: a frame being drawn, looked at again next time.</summary>
    Empty,
    /// <summary>
    /// A window of Plantoir's whose class or title UI Automation cannot read
    /// yet (a window being created): judged again at the next look, and
    /// unexpected if it is still so after <see cref="WindowRules.SettlingLimit"/>.
    /// </summary>
    Settling,
    /// <summary>Not on this stage's list: the run ends, naming it.</summary>
    Unexpected,
    /// <summary>Windows says it blocked or warned about something: the run ends, naming it.</summary>
    Blocked,
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
    private string? _words;

    public WindowFacts(string title, string windowClass, string process, Func<string> readWords)
    {
        Title = title;
        Class = windowClass;
        Process = process;
        _readWords = readWords;
    }

    public string Title { get; }
    public string Class { get; }
    public string Process { get; }
    public string Words => _words ??= _readWords();

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
    /// say nothing about Plantoir, by process and (where given) class. A toast
    /// or flyout of these processes is still read for words that say Windows
    /// blocked or warned about something (<see cref="BlockWords"/>).
    /// </summary>
    private static readonly (string Process, string Class)[] DesktopWindows =
    {
        ("explorer", "Shell_TrayWnd"), ("explorer", "Shell_SecondaryTrayWnd"), ("explorer", "Progman"), ("explorer", "WorkerW"),
        ("explorer", "NotifyIconOverflowWindow"), ("explorer", "Xaml_WindowedPopupClass"), ("explorer", "TopLevelWindowForOverflowXamlIsland"),
        ("ShellExperienceHost", ""), ("StartMenuExperienceHost", ""), ("SearchHost", ""), ("SearchApp", ""), ("TextInputHost", ""),
        ("ShellHost", ""), ("LockApp", ""), ("prl_cc", ""), ("prl_tools", ""), ("prl_tools_service", ""),
        ("ApplicationFrameHost", "Windows.UI.Core.CoreWindow"),
    };

    /// <summary>
    /// Words that mean Windows itself stopped or questioned something, in a
    /// toast or any desktop window: Smart App Control's block notice comes
    /// through ShellExperienceHost, not the smartscreen process.
    /// </summary>
    /// <summary>How long a <see cref="Verdict.Settling"/> window may stay unreadable before it is unexpected.</summary>
    public static readonly TimeSpan SettlingLimit = TimeSpan.FromSeconds(20);

    public static readonly string[] BlockWords =
    {
        "Smart App Control", "SmartScreen", "Windows protected your PC", "blocked", "Controlled folder access",
        "Unauthorized changes", "Windows Security Alert", "Firewall",
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
    /// The User Account Control prompt. With PromptOnSecureDesktop 0 (as
    /// snapshot 00 has) it draws on the ordinary desktop, in consent.exe; on
    /// the secure desktop the driver cannot see it and the Mac's consent.exe
    /// probe reports it instead.
    /// </summary>
    private static bool IsUacPrompt(WindowFacts window) => Is(window.Process, "consent");

    private static bool IsDesktopFurniture(WindowFacts window)
    {
        // Parallels Tools updating itself in a terminal window: the virtual
        // machine's own plumbing, which a teacher's PC does not have.
        if (Is(window.Process, "WindowsTerminal") && window.Title.Contains(@"Parallels\Parallels Tools", StringComparison.OrdinalIgnoreCase))
            return true;
        foreach (var (process, windowClass) in DesktopWindows)
            if (Is(window.Process, process) && (windowClass.Length == 0 || window.Class == windowClass))
                return true;
        return false;
    }

    /// <summary>The first of <see cref="BlockWords"/> the text holds, or null.</summary>
    public static string? BlockWordIn(string text)
    {
        foreach (string word in BlockWords)
            if (text.Contains(word, StringComparison.OrdinalIgnoreCase)) return word;
        return null;
    }

    /// <summary>Judges one new top-level window at one stage.</summary>
    public static Judgement Judge(Stage stage, WindowFacts window)
    {
        // Asked first, whoever owns it: ShellExecute draws this question in
        // the CALLER's process, which is the driver itself.
        if (window.Title.Contains("Security Warning", StringComparison.OrdinalIgnoreCase))
            return stage == Stage.Install ? Judgement.Of(Verdict.Expected, "security warning") : Judgement.Of(Verdict.Unexpected);

        // Never expected: no step of a first install asks for elevation.
        if (IsUacPrompt(window)) return Judgement.Of(Verdict.Blocked, "a User Account Control prompt");

        if (IsDesktopFurniture(window))
        {
            // A toast is furniture unless it says Windows stopped something.
            if (Is(window.Process, "ShellExperienceHost") || Is(window.Process, "explorer") && window.Class == "Xaml_WindowedPopupClass")
                return BlockWordIn(window.Words) is null ? Judgement.Of(Verdict.Desktop) : Judgement.Of(Verdict.Blocked, "a notice from Windows");
            return Judgement.Of(Verdict.Desktop);
        }

        if (Is(window.Process, "smartscreen"))
            return stage == Stage.Install ? Judgement.Of(Verdict.Expected, "smartscreen") : Judgement.Of(Verdict.Unexpected);

        switch (stage)
        {
            case Stage.Download:
                if (Is(window.Process, "msedge")) return Judgement.Of(Verdict.Expected, "browser");
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
                if (window.Class == "#32770" && (Is(window.Process, "PickerHost") || Is(window.Process, "Plantoir")))
                    return Judgement.Of(Verdict.Expected, "folder picker");
                break;
            case Stage.ExampleCourse:
            case Stage.Preview:
                if (IsPlantoirMain(window)) return Judgement.Of(Verdict.Expected, "plantoir");
                if (IsPlantoirContent(window)) return Judgement.Of(Verdict.Expected, "plantoir content");
                if (IsPlantoirPopup(window)) return Judgement.Of(Verdict.Expected, "plantoir popup");
                break;
        }

        // Plantoir's own window while it is being created: rehearsal
        // 2026-11-18-102329 read its main window, a second after launch, with
        // no class and no title, showing only its caption buttons ("Minimize |
        // Maximize | Close"). Judged again until it reads as what it is.
        if (stage is Stage.InstallFinished or Stage.OpenPlantoir or Stage.WorkingFolder or Stage.ExampleCourse or Stage.Preview
            && Is(window.Process, "Plantoir")
            && (window.Class.Length == 0 || window.Class == "WinUIDesktopWin32WindowClass" && window.Title.Length == 0))
            return Judgement.Of(Verdict.Settling);

        // A window with no title and nothing in it is a frame being drawn;
        // it is judged again when it has something to show.
        if (window.Title.Length == 0 && window.Words.Length == 0) return Judgement.Of(Verdict.Empty);
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
        if (stage == Stage.Preview)
            foreach (var (pattern, kind) in PreviewQuestions)
                if (pattern.IsMatch(title)) return "question: " + kind;
        return null;
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
