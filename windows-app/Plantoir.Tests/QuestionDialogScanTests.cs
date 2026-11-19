using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The question dialogs' keys (#979, the Windows half of the mac's #973 and
/// #987), held by source scan because the WinUI app cannot be loaded here.
/// Apple's HIG, Alerts (revised 2024-02-02): "Note that you don't want to make
/// a Cancel button the default button", and "If you want to encourage people
/// to read an alert and not just automatically press Return to dismiss it,
/// avoid making any button the default button." The keys themselves are
/// pressed for real in <c>QuestionDialogKeysUiTests</c>.
/// </summary>
/// <remarks>
/// A question with no default is asked through
/// <c>DialogButtons.AskWithNoDefault</c>, which also puts the focus on the
/// cancelling button: WinUI otherwise gives the first focus to the go-ahead
/// button, and a focused button takes Enter (measured on the Windows VM).
/// So a bare <c>ContentDialogButton.None</c> is refused outside the helper.
/// </remarks>
public class QuestionDialogScanTests
{
    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    private static IEnumerable<string> Sources() =>
        Directory.EnumerateFiles(AppFolder, "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"));

    private static string Relative(string file) => Path.GetRelativePath(AppFolder, file).Replace(Path.DirectorySeparatorChar, '/');

    /// <summary>
    /// Every ContentDialog initialiser in a file, as text: <c>new ContentDialog { … }</c>
    /// (with or without <c>()</c>), and a target-typed <c>new() { … }</c> where the type
    /// is ContentDialog, as UpdatePrompts' <c>Plain</c> builds one (the #979 review).
    /// </summary>
    internal static IEnumerable<string> Initialisers(string text) =>
        Regex.Matches(text,
                @"(new\s+ContentDialog\s*(\(\s*\))?|ContentDialog\??\s+\w+\s*(\([^)]*\))?\s*(=>|=)\s*new\s*\(\s*\))\s*\{.*?\n\s*\}",
                RegexOptions.Singleline)
            .Select(match => match.Value);

    [Fact]
    public void TheScanSeesEveryWayADialogIsBuilt()
    {
        const string Built =
            "var first = new ContentDialog\n{\n    Title = \"One\",\n};\n" +
            "var second = new ContentDialog()\n{\n    Title = \"Two\",\n};\n" +
            "private static ContentDialog Plain(string title, string text) => new()\n{\n    Title = title,\n};\n" +
            "ContentDialog fourth = new()\n{\n    Title = \"Four\",\n};\n" +
            "var notADialog = new TextBlock\n{\n    Text = \"Five\",\n};\n";
        var found = Initialisers(Built).ToList();
        Assert.Equal(4, found.Count);
        Assert.Contains(found, dialog => dialog.Contains("Title = title"));
        Assert.DoesNotContain(found, dialog => dialog.Contains("Five"));
        // And on the real file the review named.
        string prompts = File.ReadAllText(Path.Combine(AppFolder, "Services", "UpdatePrompts.cs"));
        Assert.Contains(Initialisers(prompts), dialog => dialog.Contains("CloseButtonText = UpdateWording.OkButton"));
    }

    /// <summary>A Close button that cancels: titled Cancel, or by a wording key that names it so.</summary>
    private static readonly Regex CancellingClose =
        new(@"CloseButtonText\s*=\s*(""Cancel""|[\w.]*(CancelButton|KeepWorking|MenuCancelButton)\b)");

    [Fact]
    public void NoCancelIsTheDefault()
    {
        var offenders = new List<string>();
        foreach (string file in Sources())
            foreach (string dialog in Initialisers(File.ReadAllText(file)))
                if (CancellingClose.IsMatch(dialog) && Regex.IsMatch(dialog, @"DefaultButton\s*=\s*ContentDialogButton\.Close\b"))
                    offenders.Add($"{Relative(file)}: {Regex.Match(dialog, @"Title\s*=\s*[^\n]*").Value.Trim()}");
        Assert.True(offenders.Count == 0,
            "A Cancel is the default here. Ask through DialogButtons.AskWithNoDefault, or make the go-ahead the " +
            "default where nothing can be lost:\n" + string.Join("\n", offenders));
    }

    /// <summary>
    /// The two dialogs allowed to set no default themselves: each opens with
    /// the cursor in a field of its own, so its first focus is never a button
    /// (the wizard's Course code; Class Dates' typed route, whose box needs
    /// Enter for a new line).
    /// </summary>
    private static readonly HashSet<string> FocusAField = new(StringComparer.Ordinal)
    {
        "Views/NewCourseDialog.cs",
        "Views/SectionScheduleDialog.cs",
    };

    [Fact]
    public void NoDefaultIsSetOnlyThroughTheHelper()
    {
        var bare = new Regex(@"=\s*ContentDialogButton\.None\b");
        var offenders = Sources()
            .Where(file => Relative(file) != "Views/DialogButtons.cs" && !FocusAField.Contains(Relative(file)))
            .SelectMany(file => File.ReadAllLines(file)
                .Select((line, index) => (line, index))
                .Where(pair => bare.IsMatch(pair.line) && !pair.line.TrimStart().StartsWith("//"))
                .Select(pair => $"{Relative(file)}:{pair.index + 1}: {pair.line.Trim()}"))
            .ToList();
        Assert.True(offenders.Count == 0,
            "A question with no default button opens with the focus on its go-ahead button, which Enter then presses. " +
            "Use DialogButtons.AskWithNoDefault(dialog):\n" + string.Join("\n", offenders));
    }

    /// <summary>
    /// The questions that have no default, as the mac has them (documentation
    /// 12, "The question dialogs' keys (#979)"), counted per file so one that
    /// loses the helper fails here.
    /// </summary>
    private static readonly Dictionary<string, int> AskedWithNoDefault = new()
    {
        ["MainWindow.xaml.cs"] = 2,                // the quit question; the synced folder
        ["Views/AssistantSettingsPane.cs"] = 1,    // Remove the downloaded assistant (D22)
        ["Views/AssistWindow.xaml.cs"] = 1,        // put a section back (D1)
        ["Views/FormBuilders.cs"] = 1,             // Remove a Course Settings list entry
        ["Views/SidebarPane.xaml.cs"] = 5,         // Remove; Delete a backup, an archive, the backups ticked; Remove the scheduled deploy
        ["Views/StartOfYearDialog.cs"] = 2,        // Get Ready's go-ahead (D39); its undo when nothing would go back
    };

    [Fact]
    public void EveryQuestionWithNoDefaultUsesTheHelper()
    {
        var found = Sources()
            .Select(file => (File: Relative(file),
                             Count: Regex.Matches(File.ReadAllText(file), @"DialogButtons\.AskWithNoDefault\(").Count))
            .Where(pair => pair.Count > 0 && pair.File != "Views/DialogButtons.cs")
            .ToDictionary(pair => pair.File, pair => pair.Count);
        var differences = found.Keys.Union(AskedWithNoDefault.Keys).OrderBy(file => file, StringComparer.Ordinal)
            .Where(file => found.GetValueOrDefault(file) != AskedWithNoDefault.GetValueOrDefault(file))
            .Select(file => $"{file}: expected {AskedWithNoDefault.GetValueOrDefault(file)}, found {found.GetValueOrDefault(file)}")
            .ToList();
        Assert.True(differences.Count == 0, "The questions with no default button changed:\n" + string.Join("\n", differences));
    }

    /// <summary>The helper sets no default AND moves the first focus to the Close button, the one Escape presses.</summary>
    [Fact]
    public void TheHelperPutsTheFocusOnCancel()
    {
        string helper = File.ReadAllText(Path.Combine(AppFolder, "Views", "DialogButtons.cs"));
        Assert.Contains("dialog.DefaultButton = ContentDialogButton.None;", helper);
        Assert.Contains("FocusTheCloseButton(sender);", helper);
        // The go-ahead is no tab stop until the dialog is open, so WinUI's own
        // first focus is Close and a queued Enter cannot press the go-ahead.
        Assert.Contains("untilOpen.Setters.Add(new Setter(Control.IsTabStopProperty, false));", helper);
        Assert.Contains("dialog.PrimaryButtonStyle = untilOpen;", helper);
        Assert.Contains("sender.PrimaryButtonStyle = goAheadStyle;", helper);
        Assert.Contains("TemplatePart(dialog, \"CloseButton\") is Control close", helper);
    }

    // ---- The New Course wizard (the mac's NewCourseWizardView rules) ----

    [Theory]
    [InlineData(true, false, true)]
    [InlineData(true, true, false)]    // the code list is drawn: Enter chooses there (the #987 review)
    [InlineData(false, false, false)]  // D32: only once the form is complete
    [InlineData(false, true, false)]
    public void CreateCourseIsTheDefaultOnceTheFormIsCompleteAndNoListIsDrawn(bool complete, bool listShown, bool expected) =>
        Assert.Equal(expected, QuestionKeys.CreateCourseIsTheDefault(complete, listShown));

    [Theory]
    [InlineData(false, false, true)]
    [InlineData(false, true, false)]   // Russell, 2026-11-18: Escape does nothing while the course is being made
    [InlineData(true, false, false)]   // the list's own Escape first (PickerEscape)
    public void WizardEscapeIsCancelExceptWhileMakingTheCourse(bool listShown, bool creating, bool expected) =>
        Assert.Equal(expected, QuestionKeys.WizardEscapeIsCancel(listShown, creating));

    [Fact]
    public void TheWizardUsesBothRules()
    {
        string wizard = File.ReadAllText(Path.Combine(AppFolder, "Views", "NewCourseDialog.cs"));
        Assert.Contains("QuestionKeys.CreateCourseIsTheDefault(", wizard);
        Assert.Contains("QuestionKeys.WizardEscapeIsCancel(", wizard);
        Assert.Contains("AutoSuggestBox.IsSuggestionListOpenProperty", wizard);
    }

    /// <summary>
    /// Escape is held back while the course is being made by no key catcher
    /// (the #979 review: one on the template's LayoutRoot was a hidden key
    /// catcher): Cancel is the Secondary button while the work runs, so its
    /// click is an answer, and Closing refuses a close with none, the
    /// Windows form of the mac's <c>.interactiveDismissDisabled(creator.isCreating)</c>.
    /// Pressed for real in <c>QuestionDialogKeysUiTests</c>.
    /// </summary>
    [Fact]
    public void TheWizardHoldsEscapeBackByRefusingTheCloseNotByCatchingTheKey()
    {
        string wizard = File.ReadAllText(Path.Combine(AppFolder, "Views", "NewCourseDialog.cs"));
        Assert.DoesNotContain("LayoutRoot", wizard);
        Assert.Matches(@"Closing \+= \(_, args\) =>\s*\{\s*if \(args\.Result == ContentDialogResult\.None\s*&& !QuestionKeys\.WizardEscapeIsCancel\(suggestionsAreShown: false, isCreating: _creator\.IsCreating\)\)\s*args\.Cancel = true;", wizard);
        Assert.Contains("SecondaryButtonClick += OnCancelWhileMaking;", wizard);
        Assert.Matches(@"CloseButtonText = """";\s*SecondaryButtonText = ""Cancel"";", wizard);
        // The only Escape the wizard reads is the code field's own (PickerEscape, the list first).
        Assert.Equal(1, Regex.Matches(wizard, @"\.PreviewKeyDown \+=").Count);
        Assert.Contains("_codeBox.PreviewKeyDown +=", wizard);
    }

    /// <summary>
    /// The important update offer has no Close button, and Escape still closes
    /// it with no key caught (#453; the #979 review deleted its catcher):
    /// WinUI closes a dialog with no answer on Escape anyway. Pressed for
    /// real in <c>UpdateOfferUiTests</c>.
    /// </summary>
    [Fact]
    public void TheUpdateOfferCatchesNoKey()
    {
        string prompts = File.ReadAllText(Path.Combine(AppFolder, "Services", "UpdatePrompts.cs"));
        Assert.DoesNotContain("KeyDown", prompts);
    }

    /// <summary>
    /// Undo Getting Ready cannot be pressed when nothing would go back, as on
    /// the mac (<c>.defaultButton(isEnabled: !putBack.isEmpty)</c>; the #979
    /// review), and its no-default question is asked after the enablement, so
    /// the helper keeps the style EnablePrimary chose.
    /// </summary>
    [Fact]
    public void UndoGettingReadyIsGreyedWhenNothingWouldGoBack()
    {
        string dialog = File.ReadAllText(Path.Combine(AppFolder, "Views", "StartOfYearDialog.cs"));
        Assert.Matches(@"DialogButtons\.EnablePrimary\(dialog, wouldPutBack\.Count > 0\);\s*if \(wouldPutBack\.Count == 0\) DialogButtons\.AskWithNoDefault\(dialog\);", dialog);
    }
}
