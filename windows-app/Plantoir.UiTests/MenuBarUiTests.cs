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
        Keyboard.Type(VirtualKeyShort.ESCAPE);
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
        // #547: the battery line is RENDERED, as its own text under the opening.
        Assert.Contains(Plantoir.Core.Assist.ScheduledDeploy.OnBatterySleepsSooner, DrivenApp.TextsUnder(schedule));
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

/// <summary>
/// #990 (Russell's ruling of 2026-11-20, grouping A) through the real window:
/// the menu bar reads File · Course · Section · Classes · View · Help, and the
/// Section and Classes menus draw <c>SubjectMenuLayout</c> (the contract's
/// <c>subjectMenus.layout</c>) line for line, a separator between groups and
/// nowhere else; every item is DRAWN and dimmed where the rule greys it,
/// never hidden; and Copy a Page answers its ruled key, Ctrl+Shift+K.
/// </summary>
[Collection("drives the real app")]
public class SectionAndClassesUiTests
{
    private const string Separator = "----";

    /// <summary>The gaps between items, in pixels, of the menu last read.</summary>
    private static string LastGaps = "";

    /// <summary>What a menu should read, by AutomationId, from the layout.</summary>
    private static List<string> Expected(Plantoir.Core.Models.SubjectMenuLayout.Menu menu)
    {
        var lines = new List<string>();
        bool first = true;
        foreach (var group in Plantoir.Core.Models.SubjectMenuLayout.Groups(menu))
        {
            if (!first) lines.Add(Separator);
            first = false;
            foreach (var entry in group)
            {
                switch (entry)
                {
                    case Plantoir.Core.Models.SubjectMenuLayout.Entry.OfSubmenu:
                        lines.Add("sectionReviseWith");
                        break;
                    case Plantoir.Core.Models.SubjectMenuLayout.Entry.OfItem(var item):
                        lines.Add(Plantoir.Core.Models.SubjectMenuLayout.AutomationIdHere(menu, item));
                        // #514's second visible Preview item, drawn under it while no preview runs.
                        if (item == Plantoir.Core.Models.SubjectMenuRules.Item.Preview) lines.Add("sectionPreviewAlternate");
                        break;
                }
            }
        }
        return lines;
    }

    /// <summary>
    /// Open a menu and read its lines in order: each item's AutomationId, and
    /// a separator as "----". A <c>MenuFlyoutSeparator</c> has no UI Automation
    /// element at all, so the separator cannot be read as an element: measured
    /// in the VM on 2026-11-20 (#990 review), the RAW view under the open
    /// flyout's <c>MenuFlyout</c> and its <c>Popup</c> holds the
    /// <c>MenuFlyoutItem</c>s and their text and nothing else (WinUI gives the
    /// separator no automation peer). So it is read where it is drawn, from
    /// the gaps between items compared with EACH OTHER, never with a number of
    /// pixels (<see cref="SeparatorGaps"/>): at any scaling every gap inside a
    /// group is the same drawn spacing and every gap across a separator is that
    /// spacing plus the separator, so the gaps fall into two sets. The groups
    /// themselves are pinned without pixels by
    /// <c>SubjectMenuLayoutContractTests</c>, against the lists the window
    /// draws from.
    /// </summary>
    private static List<(string Line, AutomationElement? Element)> Read(DrivenApp app, string menu, string anyItemId)
    {
        MenuBar.Open(app, menu, anyItemId);
        var first = app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId(anyItemId))!;
        var items = new List<(string Id, AutomationElement Element, System.Drawing.Rectangle Box)>();
        foreach (var child in first.Parent.FindAllChildren(cf => cf.ByControlType(ControlType.MenuItem)))
        {
            string id;
            try { id = child.AutomationId; } catch { continue; }
            items.Add((id, child, child.BoundingRectangle));
        }
        items.Sort((one, other) => one.Box.Top.CompareTo(other.Box.Top));
        var gaps = new List<int>();
        for (int index = 1; index < items.Count; index++) gaps.Add(items[index].Box.Top - items[index - 1].Box.Bottom);
        LastGaps = string.Join(", ", gaps);
        var across = SeparatorGaps(gaps);
        var lines = new List<(string, AutomationElement?)>();
        for (int index = 0; index < items.Count; index++)
        {
            if (index > 0 && across.Contains(index - 1)) lines.Add((Separator, null));
            lines.Add((items[index].Id, items[index].Element));
        }
        return lines;
    }

    /// <summary>
    /// Which gaps hold a separator, read from the gaps alone, at any scaling.
    /// Sorted, the gaps are split where two neighbouring values differ the
    /// most: below that jump are the gaps inside a group, above it the gaps
    /// across a separator. The split counts only when it is unambiguous: the
    /// jump must be wider than the spread inside either set (the spread being
    /// the device-pixel rounding of one drawn spacing), or the test fails
    /// saying it cannot tell the two apart, rather than guess. All gaps equal:
    /// no separator. A missing or extra separator then shows as a line out of
    /// place against the layout, which is the assertion that fails.
    /// </summary>
    internal static HashSet<int> SeparatorGaps(IReadOnlyList<int> gaps)
    {
        var across = new HashSet<int>();
        var sorted = gaps.Distinct().OrderBy(gap => gap).ToList();
        if (sorted.Count < 2) return across;
        int widest = 0, splitAbove = 0;
        for (int index = 1; index < sorted.Count; index++)
            if (sorted[index] - sorted[index - 1] > widest) { widest = sorted[index] - sorted[index - 1]; splitAbove = sorted[index - 1]; }
        var inside = gaps.Where(gap => gap <= splitAbove).ToList();
        var between = gaps.Where(gap => gap > splitAbove).ToList();
        int spread = Math.Max(inside.Max() - inside.Min(), between.Max() - between.Min());
        if (widest <= spread)
            throw new Xunit.Sdk.XunitException(
                $"the menu's gaps do not fall into two clear sets, so its separators cannot be read: {string.Join(", ", gaps)}");
        for (int index = 0; index < gaps.Count; index++)
            if (gaps[index] > splitAbove) across.Add(index);
        return across;
    }

    /// <summary>
    /// With <c>PLANTOIR_UI_CAPTURE_DIR</c> set, a picture of the screen with the
    /// menu open, for the hand-back (#990's captures); otherwise nothing.
    /// </summary>
    private static void CaptureIfAsked(DrivenApp app, string menu, string anyItemId, string fileName)
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_CAPTURE_DIR") is not { Length: > 0 } folder) return;
        Directory.CreateDirectory(folder);
        MenuBar.Open(app, menu, anyItemId);
        FlaUI.Core.Capturing.Capture.Screen().ToFile(Path.Combine(folder, fileName));
        MenuBar.Close();
    }

    /// <summary>The app's own menu bar's titles, in order (not the title bar's System menu).</summary>
    private static string MenuBarTitles(DrivenApp app) =>
        string.Join(", ", app.Window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem))
            .Where(e => e.Parent?.ControlType == ControlType.MenuBar && e.Name != "System").Select(e => e.Name));

    /// <summary>Whether the menu bar comes to read <paramref name="expected"/>, waited for as every element here is.</summary>
    private static bool MenuBarComesToRead(DrivenApp app, string expected) =>
        Retry.WhileFalse(() => MenuBarTitles(app) == expected, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result;

    /// <summary>
    /// Russell's ruling on #990 (2026-11-20 evening): "in a club the menu
    /// itself is titled Meetings, on both platforms, so no sentence a club's
    /// teacher reads says 'class'." The title follows the selected course
    /// live (<c>subjectMenus.layout.titleForAMeeting</c>): a course reads
    /// Classes, a club (its pages called meetings) reads Meetings with the
    /// same items, and back. MUST FAIL with the title set once when the menu
    /// is built.
    /// </summary>
    [UiFact]
    public void TheClassesMenuIsTitledMeetingsWhileAClubIsSelected()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBothAndAClub);
        const string ForACourse = "File, Course, Section, Classes, View, Help";
        const string ForAClub = "File, Course, Section, Meetings, View, Help";

        app.ClickMiddleOf(app.Find("sidebar-ICS3U", "the ICS3U row"));
        Assert.True(MenuBarComesToRead(app, ForACourse), $"a course's menu bar reads {MenuBarTitles(app)}");

        app.ClickMiddleOf(app.Find("sidebar-" + CourseFixtures.Club, "the club's row"));
        Assert.True(MenuBarComesToRead(app, ForAClub), $"a club's menu bar reads {MenuBarTitles(app)}");
        var meetings = MenuBar.Open(app, "Meetings", "classesClassDates");
        Assert.Equal(Expected(Plantoir.Core.Models.SubjectMenuLayout.Menu.Classes).Where(line => line != Separator).OrderBy(id => id),
                     meetings.Keys.OrderBy(id => id));
        MenuBar.Close();

        app.ClickMiddleOf(app.Find("sidebar-ICS3U", "the ICS3U row"));
        Assert.True(MenuBarComesToRead(app, ForACourse), $"back on a course the menu bar reads {MenuBarTitles(app)}");
    }

    [UiFact]
    public void TheMenusDrawTheLayout_EveryItemDrawnAndDimmedWhereTheRuleGreysIt()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);

        // The menu bar's order, Classes after Section: the app's own bar, not
        // the window's title-bar System menu, which UI Automation also shows
        // as a menu bar.
        var titles = app.Window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem))
            .Where(e => e.Parent?.ControlType == ControlType.MenuBar && e.Name != "System").Select(e => e.Name).ToList();
        Assert.Equal(new[] { "File", "Course", "Section", "Classes", "View", "Help" }, titles);

        // A COURSE row selected: the rule greys every Section and Classes item,
        // and every one is still drawn, in the layout's order and groups.
        app.ClickMiddleOf(app.Find("sidebar-ICS3U", "the ICS3U row"));
        foreach (var (menu, title, anyId) in new[]
                 {
                     (Plantoir.Core.Models.SubjectMenuLayout.Menu.Section, "Section", "sectionPublishPages"),
                     (Plantoir.Core.Models.SubjectMenuLayout.Menu.Classes, "Classes", "classesClassDates"),
                 })
        {
            var lines = Read(app, title, anyId);
            var drawn = lines.Select(l => l.Line).ToList();
            Assert.True(Expected(menu).SequenceEqual(drawn),
                $"{title}: expected {string.Join(", ", Expected(menu))}\n drawn {string.Join(", ", drawn)}\n gaps {LastGaps}");
            var live = lines.Where(l => l.Element is not null && l.Line != "sectionReviseWith" && l.Element.IsEnabled)
                            .Select(l => l.Line).ToList();
            Assert.True(live.Count == 0, $"{title} items live on a course row: {string.Join(", ", live)}");
            foreach (var (line, element) in lines)
            {
                if (element is null || line is "sectionReviseWith" or "sectionPreview" or "sectionPreviewAlternate") continue;
                var item = Enum.GetValues<Plantoir.Core.Models.SubjectMenuRules.Item>()
                    .Single(i => Plantoir.Core.Models.SubjectMenuLayout.MenuContaining(i) == menu
                                 && Plantoir.Core.Models.SubjectMenuLayout.AutomationIdHere(menu, i) == line);
                Assert.Equal(Plantoir.Core.Models.SubjectMenuLayout.TitleHere(item), element.Name);
            }
            MenuBar.Close();
        }

        // A SECTION row selected: the Classes items come live, and Remove
        // Section reads without an ellipsis.
        app.SelectSection("ICS3U", 1);
        CaptureIfAsked(app, "Section", "sectionPublishPages", "windows-section-menu.png");
        CaptureIfAsked(app, "Classes", "classesClassDates", "windows-classes-menu.png");
        var classes = MenuBar.Open(app, "Classes", "classesClassDates");
        Assert.True(classes["classesClassDates"].IsEnabled, "Classes > Class Dates… was greyed on a live section");
        Assert.True(classes["classesReDateClasses"].IsEnabled, "Classes > Re-date Classes… was greyed on a live section");
        MenuBar.Close();
        var section = MenuBar.Open(app, "Section", "sectionRemoveSection");
        Assert.Equal("Remove Section", section["sectionRemoveSection"].Name);
        Assert.Equal("Remove Scheduled Deploy", section["sectionCancelScheduledDeploy"].Name);
        MenuBar.Close();

        // Classes > Class Dates… opens the section's class dates, as the row's menu does.
        EndToEnd.PressMenuBarItem(app, "Classes", "classesClassDates");
        Assert.NotNull(MenuBar.Dialog(app, "Classes > Class Dates…"));
        MenuBar.CloseDialog(app);
        Assert.Contains("Classes ▸ Class Dates…", MenuBar.Trail(app));
    }

    /// <summary>#990: Copy a Page from This Course… answers Ctrl+Shift+K (the mac's Shift-Command-K).</summary>
    [UiFact]
    public void CopyAPageAnswersCtrlShiftK()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.ClickMiddleOf(app.Find("sidebar-ICS3U", "the ICS3U row"));
        app.Window.Focus();
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.KEY_K);
        Assert.NotNull(MenuBar.Dialog(app, "Ctrl+Shift+K"));
        EndToEnd.CloseCopyAPage(app);
    }
}
