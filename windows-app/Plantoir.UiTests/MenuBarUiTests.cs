using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>Shared by the menu bar's tests (#488): opening a menu and reading its items as UI Automation sees them.</summary>
internal static class MenuBar
{
    /// <summary>Open one of the menu bar's menus and return its items, by AutomationId, once they are on screen.</summary>
    public static Dictionary<string, AutomationElement> Open(DrivenApp app, string menu, string anyItemId)
    {
        var top = app.Window.FindFirstDescendant(cf => cf.ByName(menu).And(cf.ByControlType(ControlType.MenuItem)))
                  ?? throw new Xunit.Sdk.XunitException($"the menu bar has no {menu} menu");
        if (top.Patterns.ExpandCollapse.IsSupported) top.Patterns.ExpandCollapse.Pattern.Expand();
        else app.ClickMiddleOf(top);
        var first = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(anyItemId)),
                                    TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result
                    ?? throw new Xunit.Sdk.XunitException($"the {menu} menu never showed {anyItemId}");
        Thread.Sleep(300);   // the enablement the flyout's opening re-reads
        var parent = first.Parent;
        var items = new Dictionary<string, AutomationElement>();
        foreach (var item in parent.FindAllChildren(cf => cf.ByControlType(ControlType.MenuItem)))
        {
            string id;
            try { id = item.AutomationId; } catch { continue; }
            if (!string.IsNullOrEmpty(id)) items[id] = item;
        }
        return items;
    }

    /// <summary>Close whatever menu is open.</summary>
    public static void Close()
    {
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Thread.Sleep(300);
    }

    /// <summary>The trail this run's app writes (its state folder's Logs\activity.txt).</summary>
    public static string Trail(DrivenApp app)
    {
        string path = Path.Combine(app.StateDirectory, "Logs", "activity.txt");
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd();
        }
        catch (IOException) { return ""; }
    }

    /// <summary>Wait for the one open ContentDialog, or fail saying what was expected.</summary>
    public static AutomationElement Dialog(DrivenApp app, string what) =>
        Retry.WhileNull(() => app.OpenDialog(), TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result
        ?? throw new Xunit.Sdk.XunitException($"{what} never opened a dialog");

    /// <summary>Close the open dialog by its Close button and wait for it to go.</summary>
    public static void CloseDialog(DrivenApp app)
    {
        var dialog = app.OpenDialog() ?? throw new Xunit.Sdk.XunitException("there was no dialog to close");
        dialog.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10)).Result, "the dialog would not close");
    }
}

/// <summary>
/// #488 through the real window: the Course, Section and Help menus REACH
/// what their context-menu and toolbar twins reach — each item opens its own
/// dialog, which is then cancelled, so nothing is changed or scheduled.
/// </summary>
[Collection("drives the real app")]
public class MenuBarReachUiTests
{
    [UiFact]
    public void CourseSectionAndHelpItemsOpenWhatTheirOtherRoutesOpen()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);

        // Course ▸ Add Section… on a selected course.
        app.ClickMiddleOf(app.Find("sidebar-ICS3U", "the ICS3U row"));
        EndToEnd.PressMenuBarItem(app, "Course", "courseAddSection");
        var addSection = MenuBar.Dialog(app, "Course > Add Section…");
        Assert.Equal("Add a Section to ICS3U", addSection.Name);
        MenuBar.CloseDialog(app);

        // Course ▸ Copy a Page from This Course…
        EndToEnd.PressMenuBarItem(app, "Course", "courseCopyAPage");
        Assert.NotNull(MenuBar.Dialog(app, "Course > Copy a Page…"));
        EndToEnd.CloseCopyAPage(app);

        // Section ▸ Schedule Deploy… on a selected section: the sheet, then Cancel.
        app.SelectSection("ICS3U", 1);
        EndToEnd.PressMenuBarItem(app, "Section", "sectionScheduleDeploy");
        var schedule = MenuBar.Dialog(app, "Section > Schedule Deploy…");
        Assert.Equal("Schedule a deploy", schedule.Name);
        MenuBar.CloseDialog(app);

        // Help ▸ Publishing and Deploying…, in the contract's words.
        var wording = EndToEnd.Contract("assist-wording.json")["wording"]!;
        EndToEnd.PressMenuBarItem(app, "Help", "helpPublishingAndDeploying");
        var explained = MenuBar.Dialog(app, "Help > Publishing and Deploying…");
        Assert.Equal(wording["publishingAndDeployingTitle"]!.ToString(), explained.Name);
        Assert.Contains(wording["publishingAndDeployingExplained"]!.ToString(), DrivenApp.TextsUnder(explained));
        MenuBar.CloseDialog(app);
    }
}

/// <summary>
/// #488: with a dialog up, every Course and Section item is greyed
/// (<c>subjectMenus</c> → <c>sheetIsUp</c>), and a menu key pressed under it
/// runs nothing. The key's positive control is the #191 arrival record: the
/// same Ctrl+Shift+D, pressed with no dialog up, is recorded as "passed" —
/// so its absence under the dialog means the key was kept from the item, not
/// that the keystroke went somewhere else.
/// </summary>
[Collection("drives the real app")]
public class MenuGreysUnderADialogUiTests
{
    private const string Code = "UIMENU";

    private static List<string> Arrivals(DrivenApp app)
    {
        string record = Path.Combine(app.StateDirectory, "accelerators-arrived.txt");
        return File.Exists(record) ? File.ReadAllLines(record).Where(l => l.Length > 0).ToList() : new List<string>();
    }

    [UiFact]
    public void EveryCourseAndSectionItemIsGreyedUnderADialog_AndDeploysKeyRunsNothing()
    {
        string missing = Path.Combine(Path.GetTempPath(), "plantoir-ui-no-such-folder-" + Guid.NewGuid().ToString("N")[..8]);
        using var app = new DrivenApp(courses =>
            EndToEnd.WriteCourse(courses, Code, "Menu Course", new[] { "Concepts" }, EndToEnd.PublishesTo(missing)));
        app.SelectSection(Code, 1);

        // With no dialog: Section ▸ Deploy… is live (the control for the greying).
        var live = MenuBar.Open(app, "Section", "sectionDeploy");
        Assert.True(live["sectionDeploy"].IsEnabled, "Section > Deploy… was greyed with nothing in the way");
        MenuBar.Close();

        // The key's control: Ctrl+Shift+D with no dialog arrives, and the
        // deploy refuses (its folder does not exist) in a dialog of its own.
        app.Window.Focus();
        int before = Arrivals(app).Count;
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.KEY_D);
        Assert.True(Retry.WhileFalse(() => Arrivals(app).Skip(before).Contains("Ctrl+Shift+D passed"),
                                     TimeSpan.FromSeconds(8), TimeSpan.FromMilliseconds(200)).Result,
                    $"Ctrl+Shift+D, pressed with no dialog up, never reached Section > Deploy… Recorded: {string.Join(", ", Arrivals(app))}");
        var refusal = MenuBar.Dialog(app, "Ctrl+Shift+D");
        string refusalTitle = refusal.Name;

        // Under that dialog: the key again, and nothing passes.
        int under = Arrivals(app).Count;
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.KEY_D);
        Thread.Sleep(1200);
        Assert.DoesNotContain(Arrivals(app).Skip(under), line => line.EndsWith(" passed", StringComparison.Ordinal));
        Assert.Equal(refusalTitle, app.OpenDialog()?.Name);   // the same one dialog, not a second deploy's

        // And every Course and Section item greyed while it is up.
        foreach (var (menu, anyId) in new[] { ("Course", "courseAddSection"), ("Section", "sectionDeploy") })
        {
            var items = MenuBar.Open(app, menu, anyId);
            var live2 = items.Where(pair => pair.Value.IsEnabled).Select(pair => pair.Key)
                             .Where(id => id is not ("courseReviseWith" or "sectionReviseWith")).ToList();
            MenuBar.Close();
            Assert.True(live2.Count == 0, $"{menu} items live under a dialog: {string.Join(", ", live2)}");
        }
        MenuBar.CloseDialog(app);
    }
}

/// <summary>
/// #488: File ▸ Open Recent through the real window — the folders opened,
/// newest first; choosing one switches the window; a folder that has gone
/// says why and the window keeps its folder; Clear Menu empties it and says
/// so on the trail.
/// </summary>
[Collection("drives the real app")]
public class OpenRecentUiTests
{
    [UiFact]
    public void TheFoldersOpenedAreOfferedNewestFirst_AndAGoneOneSaysWhy()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        string second = app.Scratch("RecentB");
        Plantoir.Core.Models.ToolchainMirror.InitializeWorkspace(
            second, Path.Combine(Path.GetDirectoryName(DrivenApp.ExecutablePath)!, "Toolchain"));
        EndToEnd.WriteCourse(Path.Combine(second, "courses"), "RECENTB", "Second Folder's Course", new[] { "Concepts" });

        // Open the second folder the ordinary way.
        EndToEnd.PressMenuBarItem(app, "File", "fileOpenWorkingFolder");
        EndToEnd.ChooseInFolderPicker(app, second);
        Assert.NotNull(app.FindOrNull("sidebar-RECENTB", TimeSpan.FromSeconds(20)));

        // Open Recent lists it first, then the folder the window started on.
        var file = MenuBar.Open(app, "File", "fileOpenWorkingFolder");
        var recent = file["fileOpenRecent"];
        recent.Patterns.ExpandCollapse.Pattern.Expand();
        var first = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("openRecentFolder0")),
                                    TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result!;
        var then = app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("openRecentFolder1"))!;
        Assert.Equal("RecentB", first.Name);
        Assert.Equal(Path.GetFileName(app.WorkspacePath), then.Name);

        // Choosing the older one switches the window back to it.
        DrivenApp.PressMenuItem(then);
        Assert.NotNull(app.FindOrNull("sidebar-ICS3U", TimeSpan.FromSeconds(20)));
        Assert.Contains("from File ▸ Open Recent", MenuBar.Trail(app));

        // A folder that has gone: it says why, and the window keeps its folder.
        Directory.Delete(second, recursive: true);
        file = MenuBar.Open(app, "File", "fileOpenWorkingFolder");
        file["fileOpenRecent"].Patterns.ExpandCollapse.Pattern.Expand();
        var gone = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByName("RecentB").And(cf.ByControlType(ControlType.MenuItem))),
                                   TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result!;
        DrivenApp.PressMenuItem(gone);
        var wording = EndToEnd.Contract()["openRecent"]!["wording"]!;
        var dialog = MenuBar.Dialog(app, "a gone folder from Open Recent");
        Assert.Equal(wording["title"]!.ToString().Replace("{folder}", "RecentB"), dialog.Name);
        Assert.Contains(wording["gone"]!.ToString(), DrivenApp.TextsUnder(dialog));
        MenuBar.CloseDialog(app);
        Assert.NotNull(app.FindOrNull("sidebar-ICS3U", TimeSpan.FromSeconds(5)));
        Assert.Contains("working folder not reopened (gone) — a folder chosen from Open Recent", MenuBar.Trail(app));

        // Clear Menu.
        file = MenuBar.Open(app, "File", "fileOpenWorkingFolder");
        file["fileOpenRecent"].Patterns.ExpandCollapse.Pattern.Expand();
        var clear = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("openRecentClearMenu")),
                                    TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result!;
        DrivenApp.PressMenuItem(clear);
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains("recent working folders cleared — 2 folders"),
                                     TimeSpan.FromSeconds(5)).Result, "Clear Menu wrote no line on the trail");
        file = MenuBar.Open(app, "File", "fileOpenWorkingFolder");
        file["fileOpenRecent"].Patterns.ExpandCollapse.Pattern.Expand();
        Thread.Sleep(500);
        Assert.Null(app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("openRecentFolder0")));
        MenuBar.Close();
        MenuBar.Close();
    }
}
