using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// The folder/file lists as tables (#269, mac #266): + asks for a name, Delete
/// removes the selected row through the same path as −, and Hide and
/// Expandable share one table whose checkboxes have names of their own.
/// Written 2026-10-01 with the desktop LOCKED: UNPROVEN until its first run.
/// </summary>
[Collection("drives the real app")]
public class ListTablesUiTests
{
    private const string Shared = "Shared folders (all sections)";

    [UiFact]
    public void PlusAddsAFolderAndDeleteRemovesTheSelectedRow()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.NeverAsked);

        app.Find("add:" + Shared, "+ under the shared folders").AsButton().Invoke();
        var field = app.Find("addField:" + Shared, "the new folder's name").AsTextBox();
        field.Text = "Projects";
        Keyboard.Press(VirtualKeyShort.RETURN);
        var added = app.Find("row:" + Shared + ":Projects", "the new row");

        added.AsListBoxItem().Select();
        added.Focus();
        Keyboard.Press(VirtualKeyShort.DELETE);
        app.AssertAbsent("row:" + Shared + ":Projects", "the deleted row", TimeSpan.FromSeconds(5));
    }

    [UiFact]
    public void HideAndExpandableShareARowWithTheirOwnNames()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.NeverAsked);

        Assert.Equal("Hide Tasks", app.Find("hide:Tasks", "Hide for Tasks").Name);
        Assert.Equal("Expandable: Tasks", app.Find("expandable:Tasks", "Expandable for Tasks").Name);
    }
}
