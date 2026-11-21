using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #1024, review 2's L4 and L5: Class Dates moves only its own first placement
/// of the focus to the dates box, never the person's own first click or key,
/// and listens to the app-wide FocusManager event only while it is shown. The
/// rule is <see cref="DialogFirstFocus"/>; the source facts pin how the dialog
/// reads WinUI's focus event into it and when it listens, since a dialog
/// cannot be built outside a WinUI window here.
/// <c>PlaceholderFieldNamesUiTests</c> proves the placement itself.
/// </summary>
public class DialogFirstFocusTests
{
    private static bool IsThePlacement(bool arrived = false, bool lands = true, bool fromInside = false,
                                       bool onTheRoutePicker = true, bool pointer = false, bool directionKey = false) =>
        DialogFirstFocus.IsTheDialogsOwnFirstPlacement(arrived, lands, fromInside, onTheRoutePicker, pointer, directionKey);

    [Fact]
    public void TheDialogsOwnFirstPlacementIsMoved()
    {
        Assert.True(IsThePlacement());
    }

    [Fact]
    public void ThePersonsFirstClickIntoTheDialogIsLeftWhereTheySentIt()
    {
        Assert.False(IsThePlacement(pointer: true));
        Assert.False(IsThePlacement(pointer: true, onTheRoutePicker: false));
    }

    [Fact]
    public void ThePersonsFirstKeyIntoTheDialogIsLeftWhereTheySentIt()
    {
        Assert.False(IsThePlacement(directionKey: true));
        Assert.False(IsThePlacement(directionKey: true, onTheRoutePicker: false));
    }

    [Fact]
    public void AFirstMoveThatLandsElsewhereThanTheDialogsFirstPlaceIsLeftAlone()
    {
        Assert.False(IsThePlacement(onTheRoutePicker: false));
    }

    [Fact]
    public void EveryLaterMoveIsLeftAloneWhoeverMakesIt()
    {
        Assert.False(IsThePlacement(arrived: true));
        Assert.False(IsThePlacement(fromInside: true));
        Assert.False(IsThePlacement(lands: false));
    }

    [Fact]
    public void ThePersonsFirstMoveStillCountsAsTheFirstFocusArriving()
    {
        Assert.True(DialogFirstFocus.IsTheFirstMoveIntoTheDialog(false, true, false));
        Assert.False(DialogFirstFocus.IsTheFirstMoveIntoTheDialog(true, true, false));
        Assert.False(DialogFirstFocus.IsTheFirstMoveIntoTheDialog(false, true, true));
        Assert.False(DialogFirstFocus.IsTheFirstMoveIntoTheDialog(false, false, false));
    }

    private static string Dialog() => File.ReadAllText(Path.Combine(
        ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionScheduleDialog.cs")).Replace("\r\n", "\n");

    /// <summary>The method whose declaration holds <paramref name="signature"/>, to its closing brace.</summary>
    private static string Method(string source, string signature)
    {
        int start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"the dialog no longer holds: {signature}");
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        Assert.True(end >= 0, $"the dialog's {signature} has no closing brace");
        return source[start..end];
    }

    [Fact]
    public void TheDialogReadsThePointerAndDirectionKeysIntoTheRule()
    {
        string handler = Method(Dialog(), "private void SendTheFirstFocusToTheBox(");
        Assert.Contains("DialogFirstFocus.IsTheDialogsOwnFirstPlacement(", handler);
        Assert.Contains("madeByThePersonsPointer: args.FocusState == FocusState.Pointer", handler);
        Assert.Contains("madeByAKeyThatMovesFocus: args.Direction != FocusNavigationDirection.None", handler);
        Assert.Contains("landsWhereTheDialogPlacesItsFirstFocus: IsInside(_routePicker, args.NewFocusedElement)", handler);
        Assert.Contains("if (isThePlacement", handler);
    }

    /// <summary>
    /// L5: the static event is joined only inside the dialog's own show
    /// method and left in its finally, so a ShowAsync that throws leaves
    /// nothing joined to it; both callers show it that way.
    /// </summary>
    [Fact]
    public void TheDialogListensToTheAppWideFocusEventOnlyWhileItIsShown()
    {
        string source = Dialog();
        Assert.DoesNotContain("FocusManager.GettingFocus +=", Method(source, "public SectionScheduleDialog("));
        int joins = 0;
        for (int at = source.IndexOf("FocusManager.GettingFocus +=", StringComparison.Ordinal); at >= 0;
             at = source.IndexOf("FocusManager.GettingFocus +=", at + 1, StringComparison.Ordinal))
            joins++;
        Assert.Equal(1, joins);
        Assert.Contains("FocusManager.GettingFocus +=", Method(source, "private void StartListeningForTheFirstFocus("));
        Assert.Contains("FocusManager.GettingFocus -=", Method(source, "private void StopListeningForTheFirstFocus("));

        string show = Method(source, "public async Task<ContentDialogResult> ShowWithTheFirstFocusInTheBoxAsync(");
        int listen = show.IndexOf("StartListeningForTheFirstFocus();", StringComparison.Ordinal);
        int tryAt = show.IndexOf("try", StringComparison.Ordinal);
        int finallyAt = show.IndexOf("finally", StringComparison.Ordinal);
        int stop = show.IndexOf("StopListeningForTheFirstFocus();", StringComparison.Ordinal);
        Assert.True(listen >= 0 && tryAt > listen && show.IndexOf("await ShowAsync()", StringComparison.Ordinal) > tryAt
                    && finallyAt > tryAt && stop > finallyAt,
                    "the show method does not join, show inside a try, and leave in its finally");

        foreach (string caller in new[] { Path.Combine("Plantoir", "MainWindow.Verbs.cs"), Path.Combine("Plantoir", "Views", "AssistWindow.xaml.cs") })
        {
            string text = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", caller)).Replace("\r\n", "\n");
            int made = text.IndexOf("new SectionScheduleDialog(", StringComparison.Ordinal);
            Assert.True(made >= 0, $"{caller} no longer opens Class Dates");
            int shown = text.IndexOf("await dialog.", made, StringComparison.Ordinal);
            Assert.True(shown >= 0 && text.IndexOf("await dialog.ShowWithTheFirstFocusInTheBoxAsync()", made, StringComparison.Ordinal) == shown,
                        $"{caller} shows Class Dates some other way than ShowWithTheFirstFocusInTheBoxAsync");
        }
    }
}
