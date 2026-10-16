using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>#491 item 1: a picker takes Escape only while its list is drawn.</summary>
public class PickerEscapeTests
{
    [Fact]
    public void AnOpenList_TakesTheEscape() =>
        Assert.Equal(PickerEscape.Result.CloseTheList, PickerEscape.For(listWasOpen: true));

    [Fact]
    public void WithNoList_TheDialogHasIt() =>
        Assert.Equal(PickerEscape.Result.LetTheDialogHaveIt, PickerEscape.For(listWasOpen: false));

    /// <summary>
    /// Both AutoSuggestBoxes route their Escape through the rule — read from
    /// the source, since the views cannot be loaded here — and the dialogs are
    /// closed, not merely left to WinUI (measured: it swallows the press).
    /// </summary>
    [Theory]
    [InlineData("CopyAPageDialog.cs", "_picker")]
    [InlineData("NewCourseDialog.cs", "_codeBox")]
    public void BothPickers_AskTheRule(string file, string field)
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", file));
        Assert.Contains($"{field}.PreviewKeyDown +=", source);
        Assert.Contains($"PickerEscape.For({field}.IsSuggestionListOpen)", source);
    }
}
