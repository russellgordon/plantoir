using System.Text.RegularExpressions;

namespace Plantoir.Tests;

/// <summary>
/// One dialog title shape (#491 item 3; the mac's <c>SheetTitleScanTests</c>).
/// Every ContentDialog's title is a plain string in WinUI's own title style —
/// no <c>TitleTemplate</c>, no element as a title — so size and weight cannot
/// differ. The five dialogs with an explanation under the title draw it with
/// <c>FormBuilders.DialogExplanation</c>, first in their content. Titles stay
/// in sentence case (Russell, on the mac's half).
/// </summary>
/// <remarks>
/// The census counts every place a dialog is made, per file, so a NEW dialog
/// arrives having been looked at: when it fails, check the new dialog's title
/// is a plain string and whether it carries an explanation (then use the
/// helper), and update the count. Read from source: the WinUI app cannot be
/// loaded here.
/// </remarks>
public class DialogTitleScanTests
{
    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    private static IEnumerable<string> Sources(string pattern) =>
        Directory.EnumerateFiles(AppFolder, pattern, SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"));

    private static string Relative(string file) => Path.GetRelativePath(AppFolder, file).Replace(Path.DirectorySeparatorChar, '/');

    /// <summary>Where dialogs are made, and how many, on 2026-10-15 (batch 3B of the catch-up to mac 1.7.1).</summary>
    private static readonly Dictionary<string, int> Census = new()
    {
        ["MainWindow.Menus.cs"] = 2,
        ["MainWindow.xaml.cs"] = 6,
        ["Services/UpdatePrompts.cs"] = 1,
        ["Views/AboutDialog.cs"] = 1,
        ["Views/AddSectionDialog.cs"] = 1,
        ["Views/AssistWindow.xaml.cs"] = 2,
        ["Views/CopyAPageDialog.cs"] = 1,
        ["Views/CourseSettingsView.xaml.cs"] = 2,
        ["Views/FolderProblemsDialog.cs"] = 2,
        ["Views/FormBuilders.cs"] = 1,
        ["Views/LinksChecklistDialog.cs"] = 1,
        ["Views/NewCourseDialog.cs"] = 1,
        ["Views/SectionDetailView.xaml.cs"] = 14,
        ["Views/SectionScheduleDialog.cs"] = 1,
        ["Views/SectionVerbDialog.cs"] = 1,
        ["Views/SidebarPane.Reference.cs"] = 6,
        ["Views/SidebarPane.xaml.cs"] = 16,
        ["Views/SpecialFoldersHelpDialog.cs"] = 1,
        ["Views/StartOfYearDialog.cs"] = 2,
        ["Views/TaskProgressView.xaml.cs"] = 2,
    };

    [Fact]
    public void EveryDialogIsCounted()
    {
        var made = new Regex(@"new\s+ContentDialog\b|:\s*ContentDialog\b|ContentDialog\s+\w+\s*=\s*new\s*\(");
        var found = Sources("*.cs")
            .Select(file => (File: Relative(file), Count: File.ReadAllLines(file).Count(line => made.IsMatch(line))))
            .Where(pair => pair.Count > 0)
            .ToDictionary(pair => pair.File, pair => pair.Count);
        var differences = found.Keys.Union(Census.Keys).OrderBy(file => file, StringComparer.Ordinal)
            .Where(file => found.GetValueOrDefault(file) != Census.GetValueOrDefault(file))
            .Select(file => $"{file}: counted {Census.GetValueOrDefault(file)}, found {found.GetValueOrDefault(file)}")
            .ToList();
        Assert.True(differences.Count == 0,
            "A dialog was added or removed. Check its title is a plain string, and if it explains itself under the title, " +
            "use FormBuilders.DialogExplanation first in its content; then update the census:\n" + string.Join("\n", differences));
    }

    [Fact]
    public void NoTitleIsATemplateOrAnElement()
    {
        var shaped = new Regex(@"\bTitleTemplate\b|\bTitle\s*=\s*new\b");
        var offenders = Sources("*.cs").Concat(Sources("*.xaml"))
            .SelectMany(file => File.ReadAllLines(file).Select((line, index) => (file, line, index)))
            .Where(entry => shaped.IsMatch(entry.line))
            .Select(entry => $"{Relative(entry.file)}:{entry.index + 1}: {entry.line.Trim()}")
            .ToList();
        Assert.True(offenders.Count == 0, "A dialog title must be a plain string:\n" + string.Join("\n", offenders));
    }

    [Theory]
    [InlineData("Views/AddSectionDialog.cs")]
    [InlineData("Views/SidebarPane.Reference.cs")]   // Keep a Copy for Reference
    [InlineData("Views/SectionScheduleDialog.cs")]   // Class Dates
    [InlineData("Views/SpecialFoldersHelpDialog.cs")]
    [InlineData("Views/CredentialRequestPanel.cs")]  // every credential request
    public void TheFiveWithAnExplanation_UseTheOneShape(string file) =>
        Assert.Contains("FormBuilders.DialogExplanation(", File.ReadAllText(Path.Combine(AppFolder, file)));
}
