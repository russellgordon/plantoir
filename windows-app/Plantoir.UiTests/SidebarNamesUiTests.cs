using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;

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

    /// <summary>
    /// #426: no Button in the main window is announced as just "button". The
    /// icon-only ones (the sidebar's Add and Remove, the section toolbar's
    /// back/forward/reload/Obsidian/Open in Browser, Course Settings' Obsidian,
    /// a list row's rename) carry their tooltip's words as their Name. Asked on
    /// three screens, because each shows different buttons: the sidebar alone,
    /// a course's settings, and a section.
    /// </summary>
    [UiFact]
    public void NoButtonInTheMainWindowHasAnEmptyName()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);

        void NoneUnnamed(string screen)
        {
            var buttons = app.Window.FindAllDescendants(cf => cf.ByControlType(ControlType.Button));
            Assert.NotEmpty(buttons);
            var unnamed = buttons.Where(b => string.IsNullOrWhiteSpace(b.Name))
                .Select(b => string.IsNullOrEmpty(b.AutomationId) ? b.ClassName : b.AutomationId).ToList();
            Assert.True(unnamed.Count == 0, $"{screen}: buttons announced with no name: " + string.Join(", ", unnamed));
        }

        NoneUnnamed("the sidebar");
        Assert.Equal("Add a course or club", app.Find("addCourseButton", "the sidebar's Add button").Name);
        Assert.Equal("Remove the selected course or section", app.Find("removeSelectedButton", "the sidebar's Remove button").Name);

        app.SelectCourse(CourseFixtures.Renamed);
        NoneUnnamed("Course Settings");

        app.SelectSection(CourseFixtures.Renamed, 1);
        NoneUnnamed("a section");
        Assert.Equal("Go back a page", app.Find("previewBackButton", "the toolbar's back button").Name);
    }

    /// <summary>
    /// #426, the smaller half: a reference course's row SHOWS its code, the
    /// same code as the live course's row, so a screen reader is told which
    /// one it is ("ICS3U, kept for reference, 2025–26"). The live row stays
    /// named as it is shown.
    /// </summary>
    [UiFact]
    public void AReferenceRowSaysItIsKeptForReference()
    {
        using var app = new DrivenApp(courses =>
        {
            foreach (var (folder, extra) in new[] { ("ICS3U", ""), ("ICS3U-2025", ", \"kept_for_reference\": true, \"reference_school_year\": 2025") })
            {
                string dir = Path.Combine(courses, folder);
                Directory.CreateDirectory(Path.Combine(dir, "section1"));
                File.WriteAllText(Path.Combine(dir, "section1", "index.md"), "# Section 1\n");
                File.WriteAllText(Path.Combine(dir, "course_config.json"),
                    "{\"course_code\": \"ICS3U\", \"course_name\": \"Computer Science\", \"num_sections\": 1, \"section_numbers\": [1], " +
                    "\"shared_folders\": [], \"per_section_folders\": [], \"shared_files\": [], \"per_section_files\": []" + extra + "}");
            }
        });

        Assert.Equal("ICS3U", app.Find("sidebar-ICS3U", "the live course's row").Name);
        var reference = Retry.WhileNull(() => app.FindOrNull("sidebar-ICS3U-2025", TimeSpan.FromSeconds(1)),
            TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result;
        if (reference is null)
        {
            // The reference group and its year start folded on a fresh state
            // folder; open both, then look again.
            app.Find("referenceGroup", "the reference group").Patterns.ExpandCollapse.Pattern.Expand();
            app.Find("referenceYear-2025", "the 2025–26 group").Patterns.ExpandCollapse.Pattern.Expand();
            reference = app.Find("sidebar-ICS3U-2025", "the reference course's row");
        }
        Assert.Equal(Plantoir.Core.Models.ReferenceCourse.SpokenRowName("ICS3U", 2025), reference.Name);
        Assert.Equal("ICS3U, kept for reference, 2025–26", reference.Name);
    }
}
