using Xunit;

namespace Plantoir.FirstInstall.Tests;

/// <summary>
/// The allow-list of the first-install rehearsal, held case by case. Each
/// review finding of 2026-11-16 about a window let through silently is a
/// test here, so loosening a rule fails a test rather than a rehearsal
/// nobody is watching.
/// </summary>
public class WindowRulesTests
{
    private static WindowFacts Window(string title, string windowClass, string process, string words = "",
                                      Dictionary<string, string>? controls = null) =>
        new(title, windowClass, process, () => words,
            id => controls is not null && controls.TryGetValue(id, out string? name) ? name : null);

    private static Verdict VerdictOf(Stage stage, WindowFacts window, double seenForSeconds = 0) =>
        WindowRules.Judge(stage, window, TimeSpan.FromSeconds(seenForSeconds)).Verdict;

    private static readonly Dictionary<string, string> PickerControls = new() { ["1152"] = "Course Notes", ["1"] = "Select Folder" };

    private static readonly WindowFacts PlantoirMain = Window("Plantoir", "WinUIDesktopWin32WindowClass", "Plantoir");
    private static readonly WindowFacts Wizard = Window("Setup - Plantoir version 1.9.3", "TWizardForm", "PlantoirSetup.tmp");
    private static readonly WindowFacts InnoErrorBox = Window("Setup", "#32770", "PlantoirSetup.tmp", "Setup | An error occurred while trying to replace the existing file");
    // vm-tools/runs/win-explore/up/pick3.txt: the picker's Folder box (id 1152) and Select Folder (id 1).
    private static readonly WindowFacts Picker = Window("Select Folder", "#32770", "PickerHost", "", PickerControls);
    private static readonly WindowFacts Notepad = Window("Untitled - Notepad", "Notepad", "Notepad");
    private static readonly WindowFacts Edge = Window("New tab - Microsoft Edge", "Chrome_WidgetWin_1", "msedge");

    [Fact]
    public void TheInstallersWizardIsExpectedWhileInstalling()
    {
        Assert.Equal(new Judgement(Verdict.Expected, "wizard"), WindowRules.Judge(Stage.Install, Wizard));
    }

    [Fact]
    public void AnyOtherWindowOfTheInstallerEndsTheRun()
    {
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, InnoErrorBox));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.InstallFinished, InnoErrorBox));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.OpenPlantoir, InnoErrorBox));
    }

    [Fact]
    public void TheInstallerIsNotExpectedOnceTheAppIsBeingSetUp()
    {
        Assert.Equal(Verdict.Expected, VerdictOf(Stage.OpenPlantoir, Wizard));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.WorkingFolder, Wizard));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Wizard));
    }

    [Fact]
    public void PlantoirsMainWindowIsExpectedFromFinishOn()
    {
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, PlantoirMain));
        foreach (var stage in new[] { Stage.InstallFinished, Stage.OpenPlantoir, Stage.WorkingFolder, Stage.ExampleCourse, Stage.Preview })
            Assert.Equal(Verdict.Expected, VerdictOf(stage, PlantoirMain));
    }

    [Fact]
    public void AnyOtherTopLevelWindowOfPlantoirEndsTheRun()
    {
        var other = Window("Plantoir", "#32770", "Plantoir", "Plantoir | Something went wrong | OK");
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.ExampleCourse, other));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, other));
    }

    [Fact]
    public void PlantoirsContentSeenOutsideItsWindowIsExpectedFromFinishOn()
    {
        // Rehearsal 2026-11-16-134814, step 3: the main window's WinUI input
        // site, seen once as a top-level window, showing the first screen.
        var content = Window("", "InputSiteWindowClass", "Plantoir",
                             "Choose Your Working Folder | Pick the folder where your course notes live | Choose Folder…");
        foreach (var stage in new[] { Stage.InstallFinished, Stage.OpenPlantoir, Stage.WorkingFolder, Stage.ExampleCourse, Stage.Preview })
            Assert.Equal(new Judgement(Verdict.Expected, "plantoir content"), WindowRules.Judge(stage, content));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, content));
        // Only that class, untitled, of Plantoir's own process.
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.OpenPlantoir, Window("Plantoir", "InputSiteWindowClass", "Plantoir", "words")));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.OpenPlantoir, Window("", "InputSiteWindowClass", "Notepad", "words")));
    }

    [Fact]
    public void PlantoirsWindowBeingMadeIsJudgedAgainNotPassed()
    {
        // Rehearsal 2026-11-18-102329, step 3: no class, no title, caption buttons only.
        var beingMade = Window("", "", "Plantoir", "Minimize | Maximize | Close");
        var untitledMain = Window("", "WinUIDesktopWin32WindowClass", "Plantoir", "Minimize | Maximize | Close");
        foreach (var stage in new[] { Stage.InstallFinished, Stage.OpenPlantoir, Stage.WorkingFolder, Stage.ExampleCourse, Stage.Preview })
        {
            Assert.Equal(Verdict.Settling, VerdictOf(stage, beingMade));
            Assert.Equal(Verdict.Settling, VerdictOf(stage, untitledMain));
        }
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, beingMade));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.OpenPlantoir, Window("", "", "Notepad", "Minimize | Maximize | Close")));
        // A titled window of another class is judged at once, not left settling.
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Window("Plantoir", "#32770", "Plantoir", "OK")));
    }

    [Fact]
    public void PlantoirsOtherWindowsAreNotTakenForItsMainWindow()
    {
        var settings = Window("Settings", "WinUIDesktopWin32WindowClass", "Plantoir", "Settings");
        var assistant = Window("Revise EXC2O Section 1", "WinUIDesktopWin32WindowClass", "Plantoir", "Revise");
        foreach (var stage in new[] { Stage.OpenPlantoir, Stage.WorkingFolder, Stage.ExampleCourse, Stage.Preview })
        {
            Assert.Equal(Verdict.Unexpected, VerdictOf(stage, settings));
            Assert.Equal(Verdict.Unexpected, VerdictOf(stage, assistant));
        }
    }

    [Fact]
    public void APopupOfPlantoirsIsExpectedOnlyOnceItIsOpen()
    {
        var tooltip = Window("", "Microsoft.UI.Content.PopupWindowSiteBridge", "Plantoir", "EXC2O Section 1");
        foreach (var stage in new[] { Stage.OpenPlantoir, Stage.WorkingFolder, Stage.ExampleCourse, Stage.Preview })
            Assert.Equal(new Judgement(Verdict.Expected, "plantoir popup"), WindowRules.Judge(stage, tooltip));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, tooltip));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Window("", "Microsoft.UI.Content.PopupWindowSiteBridge", "msedge", "words")));
    }

    [Fact]
    public void AUacPromptEndsTheRunAtEveryStageAndIsNamed()
    {
        var consent = Window("User Account Control", "Credential Dialog Xaml Host", "consent",
                             "User Account Control | Do you want to allow this app to make changes to your device? | Yes | No");
        foreach (Stage stage in Enum.GetValues<Stage>())
            Assert.Equal(new Judgement(Verdict.Blocked, "a User Account Control prompt"), WindowRules.Judge(stage, consent));
    }

    [Fact]
    public void TheFolderPickerIsExpectedOnlyWhileChoosingTheWorkingFolder()
    {
        Assert.Equal(new Judgement(Verdict.Expected, "folder picker"), WindowRules.Judge(Stage.WorkingFolder, Picker));
        Assert.Equal(new Judgement(Verdict.Expected, "folder picker"),
                     WindowRules.Judge(Stage.WorkingFolder, Window("Select Folder", "#32770", "Plantoir", "", PickerControls)));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.ExampleCourse, Picker));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Picker));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.WorkingFolder, Window("Something", "Chrome_WidgetWin_1", "PickerHost", "words")));
    }

    [Fact]
    public void ADialogOfThePickersClassIsNotThePickerWithoutItsControls()
    {
        // The review of 2026-11-18: any #32770 of Plantoir passed as the picker.
        // A Win32 error box, and the picker's own task dialog (pick7.txt: titled
        // "Select Folder", one OK button), are judged again while the picker's
        // controls may still be coming, then refused.
        var errorBox = Window("Plantoir", "#32770", "Plantoir", "Plantoir | The folder could not be opened | OK");
        var taskDialog = Window("Select Folder", "#32770", "PickerHost", "Select Folder | You can't use this folder | OK",
                                new Dictionary<string, string> { ["CommandButton_1"] = "OK" });
        foreach (var window in new[] { errorBox, taskDialog })
        {
            Assert.Equal(Verdict.Settling, VerdictOf(Stage.WorkingFolder, window));
            Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.WorkingFolder, window, WindowRules.SettlingLimit.TotalSeconds));
        }
        // Both controls are needed, and the button must be Select Folder.
        Assert.Equal(Verdict.Settling, VerdictOf(Stage.WorkingFolder, Window("Select Folder", "#32770", "PickerHost", "",
                                                  new Dictionary<string, string> { ["1152"] = "" })));
        Assert.Equal(Verdict.Settling, VerdictOf(Stage.WorkingFolder, Window("Select Folder", "#32770", "PickerHost", "",
                                                  new Dictionary<string, string> { ["1152"] = "", ["1"] = "OK" })));
        Assert.True(WindowRules.IsFolderPicker(Window("Select Folder", "#32770", "PickerHost", "",
                                               new Dictionary<string, string> { ["1152"] = "", ["1"] = "&Select Folder" })));
        Assert.False(WindowRules.IsFolderPicker(Window("Select Folder", "#32770", "Notepad", "", PickerControls)));
    }

    [Fact]
    public void AWindowNobodyNamedEndsTheRunAtEveryStage()
    {
        foreach (Stage stage in Enum.GetValues<Stage>())
            Assert.Equal(Verdict.Unexpected, VerdictOf(stage, Notepad));
    }

    [Fact]
    public void TheBrowserIsExpectedOnlyWhileDownloading()
    {
        Assert.Equal(new Judgement(Verdict.Expected, "browser"), WindowRules.Judge(Stage.Download, Edge));
        Assert.Equal(new Judgement(Verdict.Expected, "browser"), WindowRules.Judge(Stage.Download, Window("", "Chrome_WidgetWin_1", "msedge", "Downloads | PlantoirSetup.exe")));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, Edge));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Edge));
    }

    [Theory]
    [InlineData("PlantoirSetup.exe isn't commonly downloaded. Make sure you trust PlantoirSetup.exe before you open it. | Delete | Keep")]
    [InlineData("PlantoirSetup.exe isn\u2019t commonly downloaded | More actions")]
    [InlineData("PlantoirSetup.exe was blocked because it could harm your device | Delete")]
    [InlineData("Microsoft Defender SmartScreen couldn't verify if this file is safe")]
    public void EdgesOwnDownloadWarningIsAFinding(string words)
    {
        // The review of 2026-11-18: any msedge window was expected at Download,
        // so Edge's own warning (its SmartScreen is on in snapshot 00) was never recorded.
        Assert.Equal(new Judgement(Verdict.Expected, "browser warning"),
                     WindowRules.Judge(Stage.Download, Window("", "Chrome_WidgetWin_1", "msedge", words)));
        Assert.NotNull(WindowRules.EdgeWarningIn(words));
    }

    [Fact]
    public void AnOrdinaryBrowserFlyoutIsNoWarning()
    {
        Assert.Null(WindowRules.EdgeWarningIn("Downloads | PlantoirSetup.exe | 23.1 MB | Open file"));
        Assert.Null(WindowRules.EdgeWarningIn(""));
    }

    [Fact]
    public void TheSecurityWarningIsAnsweredWhileInstallingWhicheverProcessDrawsIt()
    {
        // ShellExecute draws it in the caller's process: the driver's own.
        var warning = Window("Open File - Security Warning", "#32770", "PlantoirFirstInstall", "Do you want to run this file? | Run | Cancel");
        Assert.Equal(new Judgement(Verdict.Expected, "security warning"), WindowRules.Judge(Stage.Install, warning));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, warning));
    }

    [Fact]
    public void TheDriversOwnProcessIsNotAllowedWholesale()
    {
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, Window("PlantoirFirstInstall", "#32770", "PlantoirFirstInstall", "Error")));
    }

    [Fact]
    public void SmartScreenIsExpectedOnlyWhileInstalling()
    {
        var smartScreen = Window("Windows protected your PC", "Windows.UI.Core.CoreWindow", "smartscreen", "Windows protected your PC | More info");
        Assert.Equal(new Judgement(Verdict.Expected, "smartscreen"), WindowRules.Judge(Stage.Install, smartScreen));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, smartScreen));
    }

    [Fact]
    public void AToastThatSaysWindowsBlockedSomethingEndsTheRun()
    {
        var smartAppControl = Window("New notification", "Windows.UI.Core.CoreWindow", "ShellExperienceHost",
                                     "Smart App Control blocked an app that may be unsafe");
        Assert.Equal(Verdict.Blocked, VerdictOf(Stage.Install, smartAppControl));
        var firewall = Window("New notification", "Windows.UI.Core.CoreWindow", "ShellExperienceHost", "Windows Security | Firewall");
        Assert.Equal(Verdict.Blocked, VerdictOf(Stage.Preview, firewall));
    }

    [Fact]
    public void AnOrdinaryToastIsDesktopFurniture()
    {
        var toast = Window("New notification", "Windows.UI.Core.CoreWindow", "ShellExperienceHost", "Parallels Tools | Updated");
        Assert.Equal(Verdict.Desktop, VerdictOf(Stage.Preview, toast));
        Assert.Equal(Verdict.Desktop, VerdictOf(Stage.Install, Window("Taskbar", "Shell_TrayWnd", "explorer")));
    }

    [Fact]
    public void AnExplorerWindowThatIsNotFurnitureEndsTheRun()
    {
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.WorkingFolder, Window("Documents", "CabinetWClass", "explorer", "Documents")));
    }

    [Fact]
    public void ParallelsToolsUpdatingInATerminalIsFurnitureButAnotherTerminalIsNot()
    {
        Assert.Equal(Verdict.Desktop, VerdictOf(Stage.Install, Window(@"C:\Program Files\Parallels\Parallels Tools\Services\prl_tools_service.exe", "CASCADIA_HOSTING_WINDOW_CLASS", "WindowsTerminal")));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, Window("Windows PowerShell", "CASCADIA_HOSTING_WINDOW_CLASS", "WindowsTerminal", "PS C:\\>")));
    }

    [Fact]
    public void AnEmptyUntitledWindowIsWatchedForAWhileThenRefused()
    {
        var empty = Window("", "Chrome_WidgetWin_1", "Notepad");
        Assert.Equal(Verdict.Empty, VerdictOf(Stage.Preview, empty));
        Assert.Equal(Verdict.Empty, VerdictOf(Stage.Preview, empty, WindowRules.EmptyLimit.TotalSeconds - 1));
        // The review of 2026-11-18: an untitled window whose words UI
        // Automation cannot read (an elevated or custom-drawn prompt) was
        // tolerated for ever. Past the limit it ends the run.
        foreach (Stage stage in Enum.GetValues<Stage>())
            Assert.Equal(Verdict.Unexpected, VerdictOf(stage, empty, WindowRules.EmptyLimit.TotalSeconds));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Window("", "Chrome_WidgetWin_1", "Notepad", "Save changes?")));
    }

    [Fact]
    public void PlantoirsWindowBeingMadeIsRefusedPastItsLimit()
    {
        var beingMade = Window("", "", "Plantoir", "Minimize | Maximize | Close");
        Assert.Equal(Verdict.Settling, VerdictOf(Stage.OpenPlantoir, beingMade, WindowRules.SettlingLimit.TotalSeconds - 1));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.OpenPlantoir, beingMade, WindowRules.SettlingLimit.TotalSeconds));
    }

    [Theory]
    [InlineData("SearchHost")]
    [InlineData("ShellHost")]
    [InlineData("LockApp")]
    [InlineData("TextInputHost")]
    [InlineData("StartMenuExperienceHost")]
    public void ShellSurfacesAreFurnitureUnlessTheySayWindowsBlockedSomething(string process)
    {
        // The review of 2026-11-18: these were allowed by process alone.
        Assert.Equal(Verdict.Desktop, VerdictOf(Stage.Preview, Window("", "Windows.UI.Core.CoreWindow", process, "Search | Apps")));
        Assert.Equal(Verdict.Blocked, VerdictOf(Stage.Preview, Window("", "Windows.UI.Core.CoreWindow", process,
                                                                        "Windows Security Alert | Windows Defender Firewall has blocked some features of this app")));
        Assert.Equal(Verdict.Blocked, VerdictOf(Stage.Install, Window("Notification", "Windows.UI.Core.CoreWindow", process, "Smart App Control blocked an app")));
    }

    [Fact]
    public void TheTaskbarIsNotReadForWords()
    {
        int reads = 0;
        var taskbar = new WindowFacts("", "Shell_TrayWnd", "explorer", () => { reads++; return "Firewall"; });
        Assert.Equal(Verdict.Desktop, WindowRules.Judge(Stage.Preview, taskbar).Verdict);
        Assert.Equal(0, reads);
    }

    [Fact]
    public void TheFinalWatchExpectsWhatThePreviewDoesAndNothingElse()
    {
        Assert.Equal(Verdict.Expected, VerdictOf(Stage.FinalWatch, PlantoirMain));
        Assert.Equal(Verdict.Expected, VerdictOf(Stage.FinalWatch, Window("", "Microsoft.UI.Content.PopupWindowSiteBridge", "Plantoir", "tip")));
        // A firewall alert a second after the preview server binds: the case the watch exists for.
        var firewallAlert = Window("Windows Security Alert", "#32770", "rundll32",
                                   "Windows Defender Firewall has blocked some features of this app | Allow | Cancel");
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, firewallAlert));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, Notepad));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, Edge));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, Picker));
        Assert.Equal("question: today's class", WindowRules.DialogKind(Stage.FinalWatch, "Show Day 3 on the front page?", isNewCourseSheet: false));
        Assert.Null(WindowRules.DialogKind(Stage.FinalWatch, "Something went wrong", isNewCourseSheet: false));
        Assert.True(WindowRules.FinalWatchLength >= TimeSpan.FromSeconds(30));
    }

    [Fact]
    public void WordsAreReadOnlyWhenARuleNeedsThem()
    {
        int reads = 0;
        var main = new WindowFacts("Plantoir", "WinUIDesktopWin32WindowClass", "Plantoir", () => { reads++; return "lots"; });
        WindowRules.Judge(Stage.Preview, main);
        Assert.Equal(0, reads);
    }

    [Theory]
    [InlineData("Show Day 3 on the front page?", "question: today's class")]
    [InlineData("A new problem in EXC2O Section 1", "question: a folder problem")]
    [InlineData("3 new problems in EXC2O Section 1", "question: a folder problem")]
    [InlineData("A new version of Plantoir is ready: 1.9.4.", "question: an update offer")]
    public void ThePreviewsNamedQuestionsAreAnswered(string title, string kind)
    {
        Assert.Equal(kind, WindowRules.DialogKind(Stage.Preview, title, isNewCourseSheet: false));
    }

    [Fact]
    public void AnyOtherDialogInThePreviewEndsTheRun()
    {
        Assert.Null(WindowRules.DialogKind(Stage.Preview, "Delete this course?", isNewCourseSheet: false));
        Assert.Null(WindowRules.DialogKind(Stage.Preview, "Something went wrong", isNewCourseSheet: false));
        Assert.Null(WindowRules.DialogKind(Stage.Preview, "New Course or Club", isNewCourseSheet: true));
    }

    [Fact]
    public void TheNewCourseSheetIsExpectedOnlyAroundTheExampleCourse()
    {
        Assert.Equal("new course sheet", WindowRules.DialogKind(Stage.WorkingFolder, "New Course or Club", isNewCourseSheet: true));
        Assert.Equal("new course sheet", WindowRules.DialogKind(Stage.ExampleCourse, "New Course or Club", isNewCourseSheet: true));
        Assert.Null(WindowRules.DialogKind(Stage.OpenPlantoir, "New Course or Club", isNewCourseSheet: true));
        Assert.Null(WindowRules.DialogKind(Stage.ExampleCourse, "Show Day 3 on the front page?", isNewCourseSheet: false));
    }

    [Fact]
    public void AClickIsRefusedWhereItWouldLandSomewhereElse()
    {
        var window = (0, 0, 1000, 800);
        Assert.Equal((150, 120), WindowRules.MiddleWithin(100, 100, 100, 40, false, window, out _));
        Assert.Null(WindowRules.MiddleWithin(100, 100, 100, 40, true, window, out string offscreen));
        Assert.Contains("off screen", offscreen);
        Assert.Null(WindowRules.MiddleWithin(0, 0, 0, 0, false, window, out string empty));
        Assert.Contains("empty", empty);
        Assert.Null(WindowRules.MiddleWithin(100, 900, 100, 40, false, window, out string outside));
        Assert.Contains("outside", outside);
    }

    // ---- Unreadable top-level windows (the review of 2026-11-18) -------------

    /// <summary>
    /// Stands for a window UI Automation cannot read: every one of them has
    /// handle 0x0, so the handle is the same in all of them on purpose and
    /// only the identity (UI Automation's element comparison) tells them apart.
    /// </summary>
    private sealed record Unreadable(string Identity)
    {
        public IntPtr Handle => IntPtr.Zero;
    }

    private static UnreadableWindows<Unreadable> Tracker() =>
        new((first, second) => first.Identity == second.Identity);

    private static readonly DateTime Start = new(2026, 11, 18, 12, 0, 0, DateTimeKind.Utc);
    private static readonly Unreadable[] NoneReadable = Array.Empty<Unreadable>();

    private static List<(Unreadable, string)> Listing(params Unreadable[] windows)
    {
        var listing = new List<(Unreadable, string)>();
        foreach (var window in windows) listing.Add((window, "COMException: access denied"));
        return listing;
    }

    [Fact]
    public void AnUnreadableWindowThatBecomesReadableWithinTheGraceIsToleratedThenJudgedByTheOrdinaryRules()
    {
        var tracker = Tracker();
        var prompt = new Unreadable("a");
        var first = tracker.Look(Listing(prompt), NoneReadable, Start);
        Assert.Equal(UnreadableChange.Appeared, Assert.Single(first).Change);
        Assert.Empty(tracker.Look(Listing(prompt), NoneReadable, Start + TimeSpan.FromSeconds(10)));
        var readable = tracker.Look(Listing(), new[] { prompt }, Start + TimeSpan.FromSeconds(12));
        var change = Assert.Single(readable);
        Assert.Equal(UnreadableChange.BecameReadable, change.Change);
        Assert.Equal(1, change.Number);
        Assert.Equal(2, change.Sightings);
        // From then on the ordinary rules judge it: Notepad, readable, is unexpected.
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, Notepad));
    }

    [Fact]
    public void AnUnreadableWindowPastTheGraceStopsTheRun()
    {
        var tracker = Tracker();
        var prompt = new Unreadable("a");
        tracker.Look(Listing(prompt), NoneReadable, Start);
        Assert.Empty(tracker.Look(Listing(prompt), NoneReadable, Start + WindowRules.UnreadableLimit - TimeSpan.FromSeconds(1)));
        var late = tracker.Look(Listing(prompt), NoneReadable, Start + WindowRules.UnreadableLimit);
        // Both clocks run out at the same look: this window's, and "an unreadable window was present".
        Assert.Contains(late, change => change.Change == UnreadableChange.PresentTooLong);
        var change = Assert.Single(late, change => change.Change == UnreadableChange.TooLong);
        Assert.Equal(3, change.Sightings);
        Assert.Contains("access denied", change.Error);
        Assert.Equal(TimeSpan.FromSeconds(20), WindowRules.UnreadableLimit);
    }

    [Fact]
    public void TwoUnreadableWindowsInOneRunAreBothRecordedThoughBothHaveHandleZero()
    {
        var tracker = Tracker();
        var first = new Unreadable("a");
        var second = new Unreadable("b");
        Assert.Equal(first.Handle, second.Handle);
        var atFirst = tracker.Look(Listing(first), NoneReadable, Start);
        Assert.Equal(UnreadableChange.Appeared, Assert.Single(atFirst).Change);
        var atSecond = tracker.Look(Listing(first, second), NoneReadable, Start + TimeSpan.FromSeconds(5));
        var appeared = Assert.Single(atSecond);
        Assert.Equal(UnreadableChange.Appeared, appeared.Change);
        Assert.Equal(2, appeared.Number);
        Assert.Equal(2, tracker.Seen);
        // The first one going does not hide the second, which still runs out its own time.
        var firstGone = tracker.Look(Listing(second), NoneReadable, Start + TimeSpan.FromSeconds(8));
        Assert.Equal(new[] { UnreadableChange.Gone }, firstGone.ConvertAll(change => change.Change).ToArray());
        Assert.Equal(1, firstGone[0].Number);
        var secondLate = tracker.Look(Listing(second), NoneReadable, Start + TimeSpan.FromSeconds(25));
        Assert.Equal(2, Assert.Single(secondLate, change => change.Change == UnreadableChange.TooLong).Number);
    }

    [Fact]
    public void AnUnreadableWindowThatComesBackIsRecordedAgain()
    {
        var tracker = Tracker();
        var prompt = new Unreadable("a");
        tracker.Look(Listing(prompt), NoneReadable, Start);
        Assert.Equal(UnreadableChange.Gone, Assert.Single(tracker.Look(Listing(), NoneReadable, Start + TimeSpan.FromSeconds(2))).Change);
        var back = tracker.Look(Listing(prompt), NoneReadable, Start + TimeSpan.FromSeconds(4));
        Assert.Equal(UnreadableChange.Appeared, Assert.Single(back).Change);
        Assert.Equal(2, back[0].Number);
    }

    // ---- Enough looks (Steps.cs, the installer's launch call; Program.cs, the final watch) ----

    [Fact]
    public void TooFewRealLooksDuringTheLaunchCallFailTheCheck()
    {
        Assert.False(WindowRules.LookedEnough(0, TimeSpan.FromSeconds(1), out int atLeastOne));
        Assert.Equal(1, atLeastOne);
        Assert.False(WindowRules.LookedEnough(3, TimeSpan.FromSeconds(12.2), out int forTwelve));
        Assert.Equal(4, forTwelve);
        Assert.True(WindowRules.LookedEnough(4, TimeSpan.FromSeconds(12.2), out _));
    }

    [Fact]
    public void TooFewRealLooksDuringTheFinalWatchFailTheCheck()
    {
        Assert.False(WindowRules.LookedEnough(19, WindowRules.FinalWatchLength, out int required));
        Assert.Equal(20, required);
        Assert.True(WindowRules.LookedEnough(20, WindowRules.FinalWatchLength, out _));
    }

    // ---- The presence clock and the comparison (the fourth review) -----------

    private static bool ThrowingCompare(Unreadable first, Unreadable second) =>
        throw new InvalidOperationException("CompareElements failed");

    [Fact]
    public void AComparerThatAlwaysThrowsStillStopsTheRunAfterTheGrace()
    {
        var tracker = new UnreadableWindows<Unreadable>(ThrowingCompare);
        var prompt = new Unreadable("a");
        var events = new List<UnreadableEvent>();
        for (int second = 0; second <= 20; second += 2)
            events.AddRange(tracker.Look(Listing(prompt), NoneReadable, Start + TimeSpan.FromSeconds(second)));
        // Each look it gets a new number (the comparison never answers), so no
        // single window reaches TooLong; the presence clock does.
        Assert.DoesNotContain(events, change => change.Change == UnreadableChange.TooLong);
        Assert.Contains(events, change => change.Change == UnreadableChange.ComparisonFailed && change.Error.Contains("CompareElements failed"));
        var stop = Assert.Single(events, change => change.Change == UnreadableChange.PresentTooLong);
        Assert.Equal(TimeSpan.FromSeconds(20), stop.SeenFor);
        Assert.True(tracker.ComparisonFailures > 0);
        Assert.True(tracker.Pending);
    }

    [Fact]
    public void AComparerThatNeverMatchesStillStopsTheRunAfterTheGrace()
    {
        var tracker = new UnreadableWindows<Unreadable>((first, second) => false);
        var prompt = new Unreadable("a");
        var events = new List<UnreadableEvent>();
        for (int second = 0; second < 20; second += 2)
            events.AddRange(tracker.Look(Listing(prompt), NoneReadable, Start + TimeSpan.FromSeconds(second)));
        Assert.DoesNotContain(events, change => change.Change is UnreadableChange.TooLong or UnreadableChange.PresentTooLong);
        var late = tracker.Look(Listing(prompt), NoneReadable, Start + TimeSpan.FromSeconds(20));
        Assert.Contains(late, change => change.Change == UnreadableChange.PresentTooLong);
    }

    [Fact]
    public void ThePresenceClockStartsAgainWhenNoUnreadableWindowIsPresent()
    {
        var tracker = new UnreadableWindows<Unreadable>((first, second) => false);
        var prompt = new Unreadable("a");
        tracker.Look(Listing(prompt), NoneReadable, Start);
        tracker.Look(Listing(), NoneReadable, Start + TimeSpan.FromSeconds(15));
        Assert.False(tracker.Pending);
        var events = tracker.Look(Listing(prompt), NoneReadable, Start + TimeSpan.FromSeconds(25));
        Assert.DoesNotContain(events, change => change.Change == UnreadableChange.PresentTooLong);
        Assert.True(tracker.Pending);
    }

    // ---- A watch or step may finish only when nothing is in a grace state ----

    [Fact]
    public void AWatchMayNotFinishWhileAWindowIsInAGraceState()
    {
        Assert.Equal(Settling.Done, WindowRules.Settle(0, TimeSpan.Zero, true));
        Assert.Equal(Settling.KeepLooking, WindowRules.Settle(1, TimeSpan.Zero, true));
        Assert.Equal(Settling.KeepLooking, WindowRules.Settle(2, WindowRules.SettleLimit - TimeSpan.FromSeconds(1), true));
        Assert.Equal(Settling.OutOfTime, WindowRules.Settle(1, WindowRules.SettleLimit, true));
        Assert.Equal(TimeSpan.FromSeconds(60), WindowRules.SettleLimit);
    }

    [Fact]
    public void AnUnreadableWindowSeenInTheLastLookOfAWatchIsPending()
    {
        var tracker = Tracker();
        tracker.Look(Listing(new Unreadable("late")), NoneReadable, Start);
        Assert.True(tracker.Pending);
        Assert.Equal(Settling.KeepLooking, WindowRules.Settle(tracker.Pending ? 1 : 0, TimeSpan.Zero, true));
        tracker.Look(Listing(), NoneReadable, Start + TimeSpan.FromSeconds(3));
        Assert.False(tracker.Pending);
    }

    [Fact]
    public void AnEmptyOrSettlingWindowIsAGraceStateNotAnAllowedOne()
    {
        var empty = Window("", "Window", "powershell");
        Assert.Equal(Verdict.Empty, VerdictOf(Stage.FinalWatch, empty, 5));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, empty, WindowRules.EmptyLimit.TotalSeconds));
        var making = Window("", "", "Plantoir");
        Assert.Equal(Verdict.Settling, VerdictOf(Stage.FinalWatch, making, 5));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.FinalWatch, making, WindowRules.SettlingLimit.TotalSeconds));
    }

    // ---- Proof of looking: every decision rests on a recent successful look (the fifth review) ----

    private static LookRecord Record() => new(Start);

    private static void LooksEverySecond(LookRecord record, int fromSecond, int toSecond)
    {
        for (int second = fromSecond; second <= toSecond; second++) record.Succeeded(Start + TimeSpan.FromSeconds(second));
    }

    [Fact]
    public void AWatchWhoseLastLooksAllFailedCannotFinishEvenWithNothingPending()
    {
        // Looks every second for 20 s, then 40 s of failed reads: the pending
        // set the last good look left is empty, and that must not be enough.
        var record = Record();
        LooksEverySecond(record, 0, 20);
        for (int second = 21; second <= 60; second++) record.FailedLook();
        var decisionAt = Start + TimeSpan.FromSeconds(60);
        Assert.False(record.FreshAt(decisionAt));
        Assert.Equal(Settling.KeepLooking, WindowRules.Settle(0, TimeSpan.Zero, record.FreshAt(decisionAt)));
        // Still no successful look when the settle time is up: nobody looked, a DRIVER PROBLEM.
        Assert.Equal(Settling.NoRecentLook, WindowRules.Settle(0, WindowRules.SettleLimit, record.FreshAt(decisionAt + WindowRules.SettleLimit)));
        Assert.Equal(40, record.Failed);
        Assert.Equal(TimeSpan.FromSeconds(40), record.LargestGap(Start, decisionAt));
        Assert.True(record.LargestGap(Start, decisionAt) > WindowRules.MaxLookGap);
    }

    [Fact]
    public void OneLongGapInTheMiddleOfAWatchIsFoundThoughTheCountIsEnough()
    {
        // 50 good looks in 60 s pass the count (20 required), but none from 20 s to 35 s.
        var record = Record();
        LooksEverySecond(record, 0, 20);
        LooksEverySecond(record, 35, 64);
        var end = Start + TimeSpan.FromSeconds(64);
        Assert.True(WindowRules.LookedEnough(record.Good, TimeSpan.FromSeconds(60), out _));
        Assert.Equal(TimeSpan.FromSeconds(15), record.LargestGap(Start, end));
        Assert.True(record.LargestGap(Start, end) > WindowRules.MaxLookGap);
        // Asked about the watch after the gap only, it is clean.
        Assert.Equal(TimeSpan.FromSeconds(1), record.LargestGap(Start + TimeSpan.FromSeconds(35), end));
    }

    [Fact]
    public void AFailedLookImmediatelyBeforeTheDecisionMeansLookAgain()
    {
        var record = Record();
        LooksEverySecond(record, 0, 30);
        var now = Start + TimeSpan.FromSeconds(30.5);
        Assert.True(record.FreshAt(now));
        record.FailedLook();
        Assert.False(record.FreshAt(now));
        Assert.Equal(Settling.KeepLooking, WindowRules.Settle(0, TimeSpan.Zero, record.FreshAt(now)));
        // The next successful look makes it fresh again.
        record.Succeeded(Start + TimeSpan.FromSeconds(31.5));
        Assert.True(record.FreshAt(Start + TimeSpan.FromSeconds(32)));
        Assert.Equal(Settling.Done, WindowRules.Settle(0, TimeSpan.Zero, record.FreshAt(Start + TimeSpan.FromSeconds(32))));
    }

    [Fact]
    public void ALookOlderThanTheBoundIsNotFresh()
    {
        var record = Record();
        record.Succeeded(Start);
        Assert.True(record.FreshAt(Start + WindowRules.MaxLookAge));
        Assert.False(record.FreshAt(Start + WindowRules.MaxLookAge + TimeSpan.FromMilliseconds(1)));
        Assert.False(Record().FreshAt(Start));   // no look at all
        Assert.Equal(TimeSpan.FromSeconds(5), WindowRules.MaxLookAge);
        Assert.Equal(TimeSpan.FromSeconds(10), WindowRules.MaxLookGap);
    }

    [Fact]
    public void TheGapRunsOnToTheMomentAskedAbout()
    {
        var record = Record();
        LooksEverySecond(record, 0, 10);
        Assert.Equal(TimeSpan.FromSeconds(30), record.LargestGap(Start + TimeSpan.FromSeconds(40)));
        // From a start with no look after it at all.
        Assert.Equal(TimeSpan.FromSeconds(20), record.LargestGap(Start + TimeSpan.FromSeconds(20), Start + TimeSpan.FromSeconds(40)));
    }

    [Fact]
    public void AStaleEmptySetWithAFreshLookIsTheOnlyWayToFinish()
    {
        Assert.Equal(Settling.Done, WindowRules.Settle(0, TimeSpan.FromSeconds(3), true));
        Assert.Equal(Settling.KeepLooking, WindowRules.Settle(0, TimeSpan.FromSeconds(3), false));
        Assert.Equal(Settling.NoRecentLook, WindowRules.Settle(2, WindowRules.SettleLimit, false));   // a stale pending set says nothing
    }

    // #1010: the installer's Licence Agreement page, answered by step 2.

    [Fact]
    public void TheLicencePageIsKnownByItsHeadingInEitherSpelling()
    {
        Assert.True(WindowRules.IsLicencePage("Licence Agreement"));
        Assert.True(WindowRules.IsLicencePage("License Agreement"));   // Inno's own, should the override be lost
        Assert.False(WindowRules.IsLicencePage("Select Destination Location"));
        Assert.False(WindowRules.IsLicencePage("Information"));   // a page to read is not an agreement to accept
        Assert.False(WindowRules.IsLicencePage(""));
    }

    [Fact]
    public void TheAcceptChoiceIsFoundByItsNameOnly()
    {
        Assert.Equal("I accept the agreement", WindowRules.LicenceAcceptName);
        Assert.True(WindowRules.IsChoiceNamed("I accept the agreement", WindowRules.LicenceAcceptName));
        Assert.True(WindowRules.IsChoiceNamed("I &accept the agreement", WindowRules.LicenceAcceptName));
        // The refusal is never taken for the acceptance, nor the acceptance for the refusal.
        Assert.False(WindowRules.IsChoiceNamed("I do not accept the agreement", WindowRules.LicenceAcceptName));
        Assert.False(WindowRules.IsChoiceNamed("I accept the agreement", WindowRules.LicenceRefuseName));
        Assert.True(WindowRules.IsChoiceNamed("I &do not accept the agreement", WindowRules.LicenceRefuseName));
        Assert.Equal(TimeSpan.FromSeconds(30), WindowRules.LicenceNextLimit);
    }
}
