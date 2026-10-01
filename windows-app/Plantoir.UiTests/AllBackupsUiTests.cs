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

        app.Find("backupsGroup", "the Backups group").RightClick();
        var open = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByName("All Backups…").And(cf.ByControlType(ControlType.MenuItem))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(open);
        open!.Click();

        var first = app.Find("allBackups-" + Names[0], "the first backup's line");
        var second = app.Find("allBackups-" + Names[1], "the second backup's line");
        first.Click();
        Keyboard.Pressing(VirtualKeyShort.CONTROL);
        second.Click();
        Keyboard.Release(VirtualKeyShort.CONTROL);

        var button = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByName("Delete 2 Backups…").And(cf.ByControlType(ControlType.Button))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(button);
        button!.Click();

        var confirm = Retry.WhileNull(
            () => desktop.FindFirstDescendant(cf => cf.ByName("Delete").And(cf.ByControlType(ControlType.Button))),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.NotNull(confirm);
        confirm!.Click();

        Assert.True(Retry.WhileTrue(
            () => app.FindOrNull("backup-" + Names[0], TimeSpan.FromMilliseconds(200)) is not null
                  || app.FindOrNull("backup-" + Names[1], TimeSpan.FromMilliseconds(200)) is not null,
            TimeSpan.FromSeconds(8), TimeSpan.FromMilliseconds(300)).Success,
            "The two deleted backups are still listed in the sidebar.");
        Assert.NotNull(app.FindOrNull("backup-" + Names[2], TimeSpan.FromSeconds(3)));
        string dir = Path.Combine(app.WorkspacePath, "courses", "_backups", "ICS3U");
        Assert.False(File.Exists(Path.Combine(dir, Names[0])));
        Assert.False(File.Exists(Path.Combine(dir, Names[1])));
        Assert.True(File.Exists(Path.Combine(dir, Names[2])));
    }
}
