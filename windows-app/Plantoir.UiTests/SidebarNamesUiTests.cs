using FlaUI.Core.Definitions;

namespace Plantoir.UiTests;

/// <summary>
/// What a screen reader says for each sidebar row is what the row SHOWS (ruling
/// U9, bundle 11). Before this every row's automation name was the class name,
/// "Plantoir.Views.SidebarRow" — measured on bundle 11's first unlocked run —
/// because the TreeView's items are SidebarRow objects and nothing named them.
/// </summary>
[Collection("drives the real app")]
public class SidebarNamesUiTests
{
    [UiFact]
    public void EveryRowIsNamedAsItIsShown()
    {
        using var app = new DrivenApp(courses =>
        {
            CourseFixtures.WriteBoth(courses);
            string backups = Path.Combine(courses, "_backups", "ICS3U");
            Directory.CreateDirectory(backups);
            File.WriteAllBytes(Path.Combine(backups, "ICS3U_backup_2026-09-01_120000.zip"), new byte[64]);
        });

        Assert.Equal(CourseFixtures.Renamed, app.Find("sidebar-" + CourseFixtures.Renamed, "the course row").Name);
        Assert.Equal("Section 1", app.Find($"sidebar-{CourseFixtures.Renamed}-section1", "its section row").Name);
        Assert.Equal("Backups", app.Find("backupsGroup", "the Backups group").Name);

        var rows = app.Window.FindAllDescendants(cf => cf.ByControlType(ControlType.TreeItem));
        Assert.NotEmpty(rows);
        var unnamed = rows.Select(r => r.Name ?? "").Where(n => n.Length == 0 || n.StartsWith("Plantoir.", StringComparison.Ordinal)).ToList();
        Assert.True(unnamed.Count == 0, "rows a screen reader would read as: " + string.Join(", ", unnamed));
    }
}
