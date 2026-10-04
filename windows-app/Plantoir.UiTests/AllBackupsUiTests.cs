using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// All Backups through the real window (#283): select two backups, the one
/// button reads "Delete 2 Backups…", confirm, and both are gone from the
/// sidebar's Backups group. The backups are written by the fixture as tiny
/// zips with names the readers parse; nothing of the teacher's is touched.
///
/// <para>UNPROVEN as of 2026-10-01: written while the desktop was locked, so
/// it has compiled but never run (bundle 8).</para>
/// </summary>
[Collection("drives the real app")]
public class AllBackupsUiTests
{
    private static readonly string[] Names =
    {
        "ICS3U_backup_2026-09-01_120000.zip",
        "ICS3U_backup_2026-09-02_120000.zip",
        "ICS3U_backup_2026-09-03_120000.zip",
    };

    private static void WriteCoursesAndBackups(string coursesDir)
    {
        CourseFixtures.WriteBoth(coursesDir);
        string backups = Path.Combine(coursesDir, "_backups", "ICS3U");
        Directory.CreateDirectory(backups);
        foreach (string name in Names)
            File.WriteAllBytes(Path.Combine(backups, name), new byte[2048]);
    }

    [UiFact]
    public void TwoBackupsAreDeletedTogetherAndLeaveTheList()
    {
        using var app = new DrivenApp(WriteCoursesAndBackups);
        var desktop = app.Window.Automation.GetDesktop();

        app.RightClickMiddleOf(app.Find("backupsGroup", "the Backups group"));
        var open = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByName("All Backups…").And(cf.ByControlType(ControlType.MenuItem))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(open);
        DrivenApp.PressMenuItem(open!);

        // Nothing chosen yet: the button is greyed and offers no count — never
        // "Delete 0 Backups…" (bundle 11, ruling U9).
        var none = app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"));
        Assert.True(Retry.WhileNull(() => none = app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")),
                                    TimeSpan.FromSeconds(10)).Result is not null, "All Backups opened no dialog");
        Assert.Equal("Delete Backups…", none!.Name);
        Assert.False(none.IsEnabled, "Delete was offered with nothing chosen");

        var first = app.Find("allBackups-" + Names[0], "the first backup's line");
        var second = app.Find("allBackups-" + Names[1], "the second backup's line");
        app.ClickMiddleOf(first);
        Keyboard.Press(VirtualKeyShort.CONTROL);
        try { app.ClickMiddleOf(second); }
        finally { Keyboard.Release(VirtualKeyShort.CONTROL); }

        var button = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByName("Delete 2 Backups…").And(cf.ByControlType(ControlType.Button))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(button);
        button!.AsButton().Invoke();

        // The CONFIRMATION's own button, found inside the dialog titled for it
        // and pressed by Invoke: a mouse click while the dialog was still
        // animating in landed nowhere and nothing was deleted (run 3).
        var confirm = Retry.WhileNull(
            () => app.OpenDialog() is { Name: "Delete 2 backups?" } d ? d.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")) : null,
            TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(confirm);
        Assert.Equal("Delete", confirm!.Name);
        confirm.AsButton().Invoke();

        // The sidebar's Backups group starts FOLDED, and a folded TreeView
        // item's children are not in the tree at all — so before bundle 11
        // the "gone" check below passed vacuously and the "still there" one
        // could never pass (measured on the first unlocked run). Unfold it.
        // The files first, so a failure below is about the SIDEBAR, not the delete.
        string dir = Path.Combine(app.WorkspacePath, "courses", "_backups", "ICS3U");
        Assert.True(Retry.WhileFalse(() => !File.Exists(Path.Combine(dir, Names[0])) && !File.Exists(Path.Combine(dir, Names[1])),
                                     TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(300)).Result,
                    "the two backups were not deleted from disk");
        Assert.True(File.Exists(Path.Combine(dir, Names[2])));
        // All Backups closes with Done (never the confirmation's Cancel).
        Retry.WhileTrue(() => app.OpenDialog()?.Name == "Delete 2 backups?", TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200));
        if (app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton")) is { Name: "Done" } done) done.AsButton().Invoke();
        Thread.Sleep(1500);
        var group = app.Find("backupsGroup", "the Backups group");
        if (group.Patterns.ExpandCollapse.IsSupported
            && group.Patterns.ExpandCollapse.Pattern.ExpandCollapseState.Value != ExpandCollapseState.Expanded)
            group.Patterns.ExpandCollapse.Pattern.Expand();
        Assert.NotNull(app.FindOrNull("backup-" + Names[2], TimeSpan.FromSeconds(8)));
        app.AssertAbsent("backup-" + Names[0], "the first deleted backup's sidebar row", TimeSpan.FromSeconds(15));
        app.AssertAbsent("backup-" + Names[1], "the second deleted backup's sidebar row", TimeSpan.FromSeconds(15));
        Assert.NotNull(app.FindOrNull("backup-" + Names[2], TimeSpan.FromSeconds(3)));
    }
}
