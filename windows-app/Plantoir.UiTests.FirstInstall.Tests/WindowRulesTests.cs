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
    private static WindowFacts Window(string title, string windowClass, string process, string words = "") =>
        new(title, windowClass, process, () => words);

    private static Verdict VerdictOf(Stage stage, WindowFacts window) => WindowRules.Judge(stage, window).Verdict;

    private static readonly WindowFacts PlantoirMain = Window("Plantoir", "WinUIDesktopWin32WindowClass", "Plantoir");
    private static readonly WindowFacts Wizard = Window("Setup - Plantoir version 1.9.3", "TWizardForm", "PlantoirSetup.tmp");
    private static readonly WindowFacts InnoErrorBox = Window("Setup", "#32770", "PlantoirSetup.tmp", "Setup | An error occurred while trying to replace the existing file");
    private static readonly WindowFacts Picker = Window("Choose your working folder", "#32770", "PickerHost");
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
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.ExampleCourse, Picker));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Picker));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.WorkingFolder, Window("Something", "Chrome_WidgetWin_1", "PickerHost", "words")));
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
        Assert.Equal(Verdict.Expected, VerdictOf(Stage.Download, Edge));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Install, Edge));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Edge));
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
    public void AnEmptyUntitledWindowIsWatchedNotJudged()
    {
        Assert.Equal(Verdict.Empty, VerdictOf(Stage.Preview, Window("", "Chrome_WidgetWin_1", "Notepad")));
        Assert.Equal(Verdict.Unexpected, VerdictOf(Stage.Preview, Window("", "Chrome_WidgetWin_1", "Notepad", "Save changes?")));
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
}
