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
/// <para>Written while the desktop was locked (bundle 8); first run on
/// bundle 11's unlocked runs, and fixed again on the v1.4.3 cut.</para>
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

        // The harness's own row-menu helper, not a whole-desktop query of
        // its own: that query is the one that times out (bundle 11 run 5),
        // and it failed this test at "All Backups…" on the v1.4.3 cut.
        app.PressRowMenuItem("backupsGroup", "All Backups…");

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
        // Ctrl is given time to land before the click and after it. Pressed
        // and clicked back to back, the click arrived as a PLAIN one and
        // replaced the first choice (v1.4.3 cut, 2026-10-07: only the second
        // row selected, the button "Delete 1 Backup…", in both runs that got
        // that far); with the pauses it was a Ctrl-click in every run since. WinUI 3 takes the pointer in
        // through its own input-site window, so the key and the click are not
        // guaranteed to be read in the order they were sent.
        Keyboard.Press(VirtualKeyShort.CONTROL);
        try
        {
            Thread.Sleep(150);
            app.ClickMiddleOf(second);
            Thread.Sleep(150);
        }
        finally { Keyboard.Release(VirtualKeyShort.CONTROL); }

        // Read in the dialog itself, not a whole-desktop query by name.
        var button = Retry.WhileNull(
            () => app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")) is { Name: "Delete 2 Backups…" } b ? b : null,
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(button is not null, "two backups were not chosen together; the dialog's button reads \"" +
            (app.OpenDialog()?.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Properties.Name.ValueOrDefault ?? "(no dialog)") + "\"");
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
