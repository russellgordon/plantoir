using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// Escape is never trapped (#491 item 1). Measured before the fix: WinUI's
/// AutoSuggestBox swallows every Escape inside a ContentDialog, list open or
/// not, so Copy a Page — which opens with the cursor in that field — could
/// not be closed from the keyboard at all. Now the first Escape closes the
/// list and leaves the dialog up; the next closes the dialog.
/// </summary>
/// <remarks>
/// Escape is REAL input and goes to whatever holds the foreground, which a
/// test machine cannot promise (SpecialFoldersHelpUiTests explains the flake
/// that once cost): each press is preceded by <see cref="DrivenApp.BringToFront"/>,
/// and a failure to get the foreground says so rather than blaming the app.
/// </remarks>
[Collection("drives the real app")]
public class CopyAPageEscapeUiTests
{
    internal static void Front(DrivenApp app)
    {
        try { app.BringToFront(); }
        catch (InvalidOperationException error)
        {
            throw new Xunit.Sdk.XunitException($"the app did not hold the foreground, so Escape would have gone elsewhere: {error.Message}");
        }
    }

    /// <summary>The AutoSuggestBox's drop-down (its template's <c>SuggestionsList</c>), when it is drawn.</summary>
    internal static bool ListIsDrawn(DrivenApp app)
    {
        try
        {
            return app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("SuggestionsList")) is { } list && !list.IsOffscreen;
        }
        catch { return false; }
    }

    internal static void PressEscape(DrivenApp app)
    {
        Front(app);
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        Thread.Sleep(600);
    }

    [UiFact]
    public void EscapeClosesTheListThenTheDialog()
    {
        using var app = new DrivenApp(CopyAPageDialogUiTests.WriteCourses);
        app.PressRowMenuItem("sidebar-" + CopyAPageDialogUiTests.Source, "Copy a Page from This Course…");

        var picker = app.Find("copyPagePicker", "the page picker");
        app.ClickMiddleOf(picker);
        Keyboard.Type("Big");
        Assert.True(Retry.WhileFalse(() => ListIsDrawn(app), TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result,
                    "typing in the page picker drew no list");

        PressEscape(app);
        Assert.False(ListIsDrawn(app), "the first Escape left the list drawn");
        Assert.True(app.OpenDialog() is not null, "the first Escape closed Copy a Page — it should only have closed the list");

        PressEscape(app);
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200)).Result,
                    "Escape with no list drawn did not close Copy a Page (the picker trapped it)");
    }
}
