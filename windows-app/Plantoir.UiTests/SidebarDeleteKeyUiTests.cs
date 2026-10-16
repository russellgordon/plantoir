using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// Delete on a selected sidebar row (#491 item 5; <c>sidebarDeleteKey</c>):
/// it runs the menu item, so it ASKS — the same "Remove ICS3U?" the menu bar
/// and the − button ask — and where the item is greyed (a section of a course
/// kept for reference) it does nothing at all, and the − button is greyed
/// with it. Before #491, − on a reference section removed the whole course.
/// Delete is real input: see CopyAPageEscapeUiTests for why each press brings
/// the app to the front first.
/// </summary>
[Collection("drives the real app")]
public class SidebarDeleteKeyUiTests
{
    private static void PressDelete(DrivenApp app)
    {
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Press(VirtualKeyShort.DELETE);
    }

    [UiFact]
    public void DeleteOnACourseAsks_AndOnAReferenceSectionDoesNothing()
    {
        using var app = new DrivenApp(ReferenceCourseUiTests.WriteCourses);

        // A course row, clicked (a real click gives the row keyboard focus): Delete asks.
        app.SelectCourse("ICS3U");
        PressDelete(app);
        var asked = Retry.WhileNull(() => app.OpenDialog(), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(asked is not null, "Delete on a course row asked nothing");
        Assert.Equal("Remove ICS3U?", asked!.Name);
        asked.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton"))!.AsButton().Invoke();   // Cancel: nothing removed
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result);
        Assert.NotNull(app.FindOrNull("sidebar-ICS3U", TimeSpan.FromSeconds(2)));

        // A section of the course kept for reference: Remove Section… is
        // withheld there, so the key does nothing and − is greyed.
        app.SelectSection("ICS3U-2025", 1, shownCode: "ICS3U");
        Assert.True(Retry.WhileFalse(() => !app.Find("removeSelectedButton", "the − button").IsEnabled,
                                     TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result,
                    "− is offered on a section of a course kept for reference");
        PressDelete(app);
        Thread.Sleep(2000);
        Assert.True(app.OpenDialog() is null, $"Delete on a reference section opened \"{app.OpenDialog()?.Name}\"");
        Assert.NotNull(app.FindOrNull("sidebar-ICS3U-2025", TimeSpan.FromSeconds(2)));
    }
}
