using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The click on Restore from Backup…'s "Restore Section N" (#911 step 4,
/// <see cref="MenuSectionRestore.Run"/>, the mac's <c>restoreOneSection</c>):
/// a refused click archives nothing (the <c>Archived</c> listing before and
/// after); the whole course is archived first; the busy refusal is asked again
/// after the archive; <c>section restored</c> is written only once the section
/// is back; and the dialog that offers it has Restore Section N as its
/// default, Restore Whole Course beside it and Cancel as its close button.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class MenuSectionRestoreClickTests : IDisposable
{
    private readonly SectionSwapFixture _fixture = new();

    public MenuSectionRestoreClickTests()
    {
        ActivityTrail.SetCustomLogPathForTesting(_fixture.TrailPath);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { CourseRestorer.DeleteTree(BuildOutputLocation.BuildsRootFor(_fixture.Folder)); } catch { }
        _fixture.Dispose();
    }

    private static readonly BackupMaker MenuForSection2 = new BackupMaker.Menu(2, SubjectMenuLayout.Menu.Section);

    private List<string> Archived() => Workspace.FindArchivedItems(_fixture.Folder).Select(item => item.FilePath).OrderBy(path => path).ToList();

    private MenuSectionRestore.Result Click(BackupItem backup, Func<string?>? busy = null) =>
        MenuSectionRestore.Run(2, backup, _fixture.Course(), OneSectionRestore.ReadFacts(backup.FilePath), _fixture.CoursesDir, busy ?? (() => null));

    [Fact]
    public void ABackupMadeForTheSectionIsOfferedAndATeachersOwnIsNot()
    {
        _fixture.Write("a.md", "a");
        var menu = _fixture.BackUp(MenuForSection2);
        Assert.Equal(2, OneSectionRestore.OfferFor(menu, _fixture.Course(), OneSectionRestore.ReadFacts(menu.FilePath)));
        File.Delete(menu.FilePath);
        var teacher = _fixture.BackUp(BackupMaker.DefaultTeacher);
        Assert.Null(OneSectionRestore.OfferFor(teacher, _fixture.Course(), OneSectionRestore.ReadFacts(teacher.FilePath)));
    }

    [Fact]
    public void AFinishedRestoreArchivesTheCourseFirstSaysItIsBackAndLeavesItsLine()
    {
        _fixture.Write("a.md", "a, as backed up");
        var backup = _fixture.BackUp(MenuForSection2);
        _fixture.Write("a.md", "a, changed since");
        var before = Archived();

        var result = Click(backup);

        Assert.True(result.Finished, result.Message);
        Assert.Equal(OneSectionRestoreWording.DoneTitle(2, "ICS3U"), result.Title);
        Assert.Equal(OneSectionRestoreWording.Done(2, backup.WhenDescription, new OneSectionRestore.Outcome(0, 0, 0, false)), result.Message);
        string archive = Assert.Single(Archived().Except(before));
        Assert.Equal(archive, result.ArchivePath);
        Assert.Equal("a, as backed up", File.ReadAllText(Path.Combine(_fixture.Section2, "a.md")));
                Assert.Contains(ActivityTrail.RestoredOneSectionFromTheMenuLine(Path.GetFileName(backup.FilePath), Path.GetFileName(archive), 0, 0), _fixture.Trail());
        Assert.DoesNotContain("left the settings of", _fixture.Trail());
    }

    [Fact]
    public void APageThatCouldNotTakeAKeyIsCountedOnTheTrail()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp(MenuForSection2);
        string page = Path.Combine(_fixture.CourseDir, "Notes", "No room.md");
        File.WriteAllText(page, "---\n  title: No room\n---\nN.\n");

        var result = Click(backup);

        Assert.True(result.Finished, result.Message);
        Assert.Contains(ActivityTrail.PageSettingsLeftAsTheyWereLine("putting the section back from a backup", 1), _fixture.Trail());
    }

    // ---- a refused click archives nothing ------------------------------------

    [Fact]
    public void AClickRefusedAsBusyArchivesNothing()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp(MenuForSection2);
        var before = Archived();
        var sectionBefore = SectionSwapFixture.Snapshot(_fixture.Section2);

        var result = Click(backup, () => OneSectionRestoreWording.Busy(2, "ICS3U"));

        Assert.False(result.Finished);
        Assert.Equal(BackupProblemTitle.Restoring("ICS3U"), result.Title);
        Assert.Equal(OneSectionRestoreWording.Busy(2, "ICS3U"), result.Message);
        Assert.Equal(before, Archived());
        Assert.Equal(sectionBefore, SectionSwapFixture.Snapshot(_fixture.Section2));
        Assert.DoesNotContain("put the section back from", _fixture.Trail());
    }

    [Fact]
    public void AClickRefusedByTheOfferRuleAskedAgainArchivesNothing()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp(MenuForSection2);
        // Since the dialog opened, the course's word for a unit changed.
        string config = Path.Combine(_fixture.CourseDir, "course_config.json");
        File.WriteAllText(config, File.ReadAllText(config).Replace("\"Unit\"", "\"Module\""));
        var before = Archived();

        var result = Click(backup);

        Assert.False(result.Finished);
        Assert.Equal(OneSectionRestoreWording.NamingChanged(2, "ICS3U"), result.Message);
        Assert.Equal(before, Archived());
        Assert.Null(result.ArchivePath);
    }

    [Fact]
    public void AClickOnABackupNotMadeForTheSectionArchivesNothing()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp(BackupMaker.DefaultTeacher);
        var before = Archived();

        var result = Click(backup);

        Assert.Equal(OneSectionRestoreWording.NotMadeForThisSection(2), result.Message);
        Assert.Equal(before, Archived());
    }

    [Fact]
    public void BusyAfterTheArchiveRestoresNothingAndTheArchiveStays()
    {
        _fixture.Write("a.md", "a, as backed up");
        var backup = _fixture.BackUp(MenuForSection2);
        _fixture.Write("a.md", "a, changed since");
        var sectionBefore = SectionSwapFixture.Snapshot(_fixture.Section2);
        int asked = 0;

        var result = Click(backup, () => ++asked == 1 ? null : OneSectionRestoreWording.Busy(2, "ICS3U"));

        Assert.Equal(2, asked);
        Assert.False(result.Finished);
        Assert.Equal(OneSectionRestoreWording.Busy(2, "ICS3U"), result.Message);
        Assert.NotNull(result.ArchivePath);
        Assert.True(File.Exists(result.ArchivePath));
        Assert.Equal(sectionBefore, SectionSwapFixture.Snapshot(_fixture.Section2));
        Assert.DoesNotContain("put the section back from", _fixture.Trail());
    }

    // ---- the dialog, as the source builds it ---------------------------------

    /// <summary>
    /// The offered dialog in <c>SidebarPane.xaml.cs</c>: the contract's title
    /// and message, Restore Section N as the primary and DEFAULT button,
    /// Restore Whole Course as the secondary, Cancel as the close button
    /// (Escape), the folder guard after it, and the primary answer going to
    /// the one-section restore. The UI test reads the same buttons rendered.
    /// </summary>
    [Fact]
    public void TheOfferedDialogDefaultsToRestoreSectionN()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml.cs"));
        var block = Regex.Match(source, @"if \(offered is int section\)\s*\{(?<body>.*?)\r?\n        \}\r?\n", RegexOptions.Singleline);
        Assert.True(block.Success, "the offered dialog is not where the scan looks");
        string body = block.Groups["body"].Value;
        Assert.Contains("Title = OneSectionRestoreWording.Title(item.CourseCode)", body);
        Assert.Contains("Content = OneSectionRestoreWording.Message(section", body);
        Assert.Contains("PrimaryButtonText = OneSectionRestoreWording.RestoreSectionButton(section)", body);
        Assert.Contains("SecondaryButtonText = OneSectionRestoreWording.RestoreWholeCourseButton", body);
        Assert.Contains("CloseButtonText = \"Cancel\"", body);
        Assert.Contains("DefaultButton = ContentDialogButton.Primary", body);
        // Only the two explicit buttons choose (review 2's MEDIUM): a question
        // that could not be shown answers null, which must restore nothing.
        Assert.Contains("RestoreChoice chosen = RestoreChoice.Nothing;", body);
        Assert.Contains("if (answer == ContentDialogResult.Primary) chosen = RestoreChoice.OneSection;", body);
        Assert.Contains("if (answer == ContentDialogResult.Secondary) chosen = RestoreChoice.WholeCourse;", body);
        Assert.Matches(@"if \(chosen == RestoreChoice\.Nothing\) return nothing;\s*if \(TheFolderMovedUnderThisConfirmation\(askedIn\)\) return nothing;\s*return \(chosen, section, facts\);", body);
        Assert.DoesNotContain("else", body);
        Assert.DoesNotContain("RestoreWholeCourse(", body);
    }

    /// <summary>
    /// The restore is run only for an explicit choice: the switch names both,
    /// and nothing else in <c>ConfirmRestoreBackup</c> calls either restore,
    /// so no answer other than a button's can fall through to one.
    /// </summary>
    [Fact]
    public void OnlyAnExplicitChoiceRestores()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SidebarPane.xaml.cs"));
        var method = Regex.Match(source, @"public async void ConfirmRestoreBackup\(BackupItem item\)\s*\{(?<body>.*?)\r?\n    \}\r?\n", RegexOptions.Singleline);
        Assert.True(method.Success, "ConfirmRestoreBackup is not where the scan looks");
        string body = method.Groups["body"].Value;
        Assert.Matches(@"case RestoreChoice\.OneSection:\s*await RestoreOneSection\(section, item, facts!\);\s*break;", body);
        Assert.Matches(@"case RestoreChoice\.WholeCourse:\s*await RestoreWholeCourse\(item\);\s*break;", body);
        Assert.Matches(@"case RestoreChoice\.Nothing:\s*break;", body);
        Assert.DoesNotContain("default:", body);
        Assert.Equal(1, Regex.Matches(body, @"RestoreOneSection\(").Count);
        Assert.Equal(1, Regex.Matches(body, @"RestoreWholeCourse\(").Count);
        // The question is asked with every Restore… greyed, and ungreyed
        // whatever happens (a finally), before anything is restored.
        Assert.Matches(@"if \(IsAskingWhichRestore\) return;\s*SetAskingWhichRestore\(true\);", body);
        Assert.Matches(@"try\s*\{\s*\(choice, section, facts\) = await AskWhichRestore\(item\);\s*\}\s*finally\s*\{\s*SetAskingWhichRestore\(false\);\s*\}\s*//[^\n]*\n(\s*//[^\n]*\n)*\s*switch \(choice\)", body);
    }

    /// <summary>
    /// Every Restore… a teacher can press reads <c>IsAskingWhichRestore</c>
    /// and is greyed while it is true: the menu bar (the situation counts it
    /// as a dialog up), the backup row's context menu as it opens, and the
    /// backup pane's button, drawn again when the flag changes.
    /// </summary>
    [Fact]
    public void EveryRestoreIsGreyedWhileTheQuestionIsAsked()
    {
        string root = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");
        string sidebar = File.ReadAllText(Path.Combine(root, "Views", "SidebarPane.xaml.cs"));
        string menus = File.ReadAllText(Path.Combine(root, "MainWindow.Menus.cs"));
        string window = File.ReadAllText(Path.Combine(root, "MainWindow.xaml.cs"));
        Assert.Contains("SheetIsUp = DialogGate.IsOpen(Content?.XamlRoot) || Sidebar.IsAskingWhichRestore,", menus);
        Assert.Matches(@"var restoreItem = MenuItem\(""Restore…"", RestoreGlyph, Selecting\(row, \(\) => ConfirmRestoreBackup\(item\)\)\);\s*menu\.Items\.Add\(restoreItem\);\s*//[^\n]*\n\s*menu\.Opening \+= \(_, _\) => restoreItem\.IsEnabled = !IsAskingWhichRestore;", sidebar);
        Assert.Matches(@"""Restore…"", \(\) => Sidebar\.ConfirmRestoreBackup\(backup\),\s*""Delete Backup…"", \(\) => Sidebar\.ConfirmDeleteBackup\(backup\),\s*actionEnabled: !Sidebar\.IsAskingWhichRestore\);", window);
        Assert.Contains("IsEnabled = actionEnabled,", window);
        Assert.Matches(@"Sidebar\.AskingWhichRestoreChanged \+= \(_, _\) =>\s*\{\s*if \(IsClosed\) return;\s*if \(Workspace\.Selection is SidebarSelection\.BackupEntry\) ShowDetailForSelection\(\);\s*ApplyMenuEnablement\(\);", window);
    }
}
