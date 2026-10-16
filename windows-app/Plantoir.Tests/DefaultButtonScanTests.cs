using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// #491 item 2: a dialog's main button that cannot be pressed never looks like
/// the default. The rule is <c>PrimaryButtonLook</c> (unit-tested); this holds
/// every dialog to it by source scan — the WinUI app cannot be loaded here —
/// so a new dialog that greys its main button by hand, and leaves it wearing
/// the default's accent slab (measured: #BFBFBF in Light, #434343 in Dark),
/// fails here rather than in a teacher's eye.
/// </summary>
public class DefaultButtonScanTests
{
    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    private static IEnumerable<string> Sources(string pattern) =>
        Directory.EnumerateFiles(AppFolder, pattern, SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"));

    private static string Relative(string file) => Path.GetRelativePath(AppFolder, file).Replace(Path.DirectorySeparatorChar, '/');

    /// <summary>
    /// No <c>IsPrimaryButtonEnabled</c> write anywhere but <c>Views/DialogButtons.cs</c>
    /// — an assignment on a dialog, a bare one inside a ContentDialog subclass,
    /// or an object initialiser (All Backups' was one) all match, as does an
    /// attribute in XAML.
    /// </summary>
    [Fact]
    public void OnlyDialogButtons_EnablesAMainButton()
    {
        var write = new Regex(@"\bIsPrimaryButtonEnabled\s*=(?!=)");
        var offenders = Sources("*.cs").Concat(Sources("*.xaml"))
            .Where(file => Relative(file) != "Views/DialogButtons.cs")
            .SelectMany(file => File.ReadAllLines(file)
                .Select((line, index) => (line, index))
                .Where(pair => write.IsMatch(pair.line) && !pair.line.TrimStart().StartsWith("//"))
                .Select(pair => $"{Relative(file)}:{pair.index + 1}: {pair.line.Trim()}"))
            .ToList();
        Assert.True(offenders.Count == 0,
            "Enable a dialog's main button through DialogButtons.EnablePrimary, which also takes the default and " +
            "the accent away while it is greyed:\n" + string.Join("\n", offenders));
    }

    /// <summary>The helper itself applies the whole rule: enablement, the default and the accent style together.</summary>
    [Fact]
    public void DialogButtons_SetsTheDefaultAndTheStyleWithTheEnablement()
    {
        string helper = File.ReadAllText(Path.Combine(AppFolder, "Views", "DialogButtons.cs"));
        Assert.Contains("PrimaryButtonLook.For(", helper);
        Assert.Contains("dialog.IsPrimaryButtonEnabled = enabled;", helper);
        Assert.Contains("dialog.DefaultButton = ContentDialogButton.Primary", helper);
        Assert.Contains("dialog.DefaultButton = ContentDialogButton.None", helper);
        Assert.Contains("dialog.PrimaryButtonStyle", helper);
    }

    /// <summary>
    /// The wizard's Create Course never takes Enter: nothing in the wizard
    /// makes Primary its default, and its enablement goes through
    /// <c>NeverTakesEnter</c>. (Its closing button after the work is over is
    /// the one exception, and is enabled through the ordinary kind.)
    /// </summary>
    [Fact]
    public void CreateCourse_NeverTakesEnter()
    {
        string wizard = File.ReadAllText(Path.Combine(AppFolder, "Views", "NewCourseDialog.cs"));
        Assert.DoesNotContain("DefaultButton = ContentDialogButton.Primary", wizard);
        Assert.Contains("PrimaryKind.NeverTakesEnter", wizard);
    }

    /// <summary>Class Dates reads, then remembers: the main button is enabled by whether dates were read.</summary>
    [Fact]
    public void ClassDates_RemembersOnlyWhatWasRead()
    {
        string dialog = File.ReadAllText(Path.Combine(AppFolder, "Views", "SectionScheduleDialog.cs"));
        Assert.Contains("\"Remember These Dates\"", dialog);
        Assert.Contains("\"Read the Dates\"", dialog);
        Assert.Contains("DialogButtons.EnablePrimary(this, read)", dialog);
        Assert.Contains("_routePicker.SelectedIndex == 0 ? ContentDialogButton.None : ContentDialogButton.Secondary", dialog);
    }
}
