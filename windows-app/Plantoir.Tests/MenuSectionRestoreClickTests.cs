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
        Assert.Contains("section restored", _fixture.Trail());
        Assert.Contains(ActivityTrail.RestoredOneSectionFromTheMenuLine(Path.GetFileName(backup.FilePath), Path.GetFileName(archive), 0, 0), _fixture.Trail());
        Assert.DoesNotContain("page settings left as they were", _fixture.Trail());
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
        Assert.Contains("page settings left as they were", _fixture.Trail());
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
        Assert.DoesNotContain("section restored", _fixture.Trail());
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
        Assert.DoesNotContain("section restored", _fixture.Trail());
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
        var block = Regex.Match(source, @"if \(offered is int section\)\s*\{(?<body>.*?)\n        \}\n", RegexOptions.Singleline);
        Assert.True(block.Success, "the offered dialog is not where the scan looks");
        string body = block.Groups["body"].Value;
        Assert.Contains("Title = OneSectionRestoreWording.Title(item.CourseCode)", body);
        Assert.Contains("Content = OneSectionRestoreWording.Message(section", body);
        Assert.Contains("PrimaryButtonText = OneSectionRestoreWording.RestoreSectionButton(section)", body);
        Assert.Contains("SecondaryButtonText = OneSectionRestoreWording.RestoreWholeCourseButton", body);
        Assert.Contains("CloseButtonText = \"Cancel\"", body);
        Assert.Contains("DefaultButton = ContentDialogButton.Primary", body);
        Assert.Matches(@"if \(answer == ContentDialogResult\.None\) return;\s*if \(TheFolderMovedUnderThisConfirmation\(askedIn\)\) return;", body);
        Assert.Contains("if (answer == ContentDialogResult.Primary) await RestoreOneSection(section", body);
    }
}
