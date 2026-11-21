using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// The one-section restore is staged, then swapped, with a way back (#911,
/// the mac's #897 C), on the assistant window's route. Every fault here has a
/// REAL cause: a file held open by a second handle without delete sharing
/// (Windows refuses to rename a folder holding an open file, measured on the
/// old #873 branch), released or not. Only the double-failure sweep throws
/// from the move seam, which is the mac's own test shape for that sweep.
/// Content is judged by SHA-256, never a file time.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class SectionSwapTests : IDisposable
{
    private readonly SectionSwapFixture _fixture = new();

    public SectionSwapTests()
    {
        ActivityTrail.SetCustomLogPathForTesting(_fixture.TrailPath);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { CourseRestorer.DeleteTree(BuildOutputLocation.BuildsRootFor(_fixture.Folder)); } catch { }
        _fixture.Dispose();
    }

    private static FileStream Hold(string path) =>
        new(path, FileMode.Open, FileAccess.Read, FileShare.Read);      // no FileShare.Delete: no rename past it

    /// <summary>Section 2 as the backup has it, then changed, so every file differs from the backup's.</summary>
    private BackupItem BackupThenChange()
    {
        _fixture.Write("a.md", "a, as backed up");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day one, as backed up");
        _fixture.Write(Path.Combine("zz notes", "held.md"), "held, as backed up");
        var backup = _fixture.BackUp();
        _fixture.Write("a.md", "a, changed since");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day one, changed since");
        _fixture.Write(Path.Combine("zz notes", "held.md"), "held, changed since");
        _fixture.Write("made since.md", "made since");
        return backup;
    }

    // ---- a move that fails part way: refused, the section as it was --------

    [Fact]
    public void AFolderHoldingAnOpenFileLeavesTheSectionAsItWasAndSaysSo()
    {
        var backup = BackupThenChange();
        var courseBefore = SectionSwapFixture.Snapshot(_fixture.CourseDir);

        string message;
        using (Hold(Path.Combine(_fixture.Section2, "zz notes", "held.md")))
        {
            // Exactly a Problem, so the window puts "Nothing was put back:" in front, which is true.
            var error = Assert.Throws<AssistSectionRestore.Problem>(() =>
                AssistSectionRestore.Restore(backup.FilePath, "ICS3U", 2, _fixture.CoursesDir));
            message = error.Message;
        }

        Assert.StartsWith(OneSectionRestoreWording.LeftAsItWas(2, ""), message);
        Assert.Equal(courseBefore, SectionSwapFixture.Snapshot(_fixture.CourseDir));
        Assert.False(Directory.Exists(Path.Combine(_fixture.CoursesDir, ".internal")), "nothing is left in courses\\.internal");
        Assert.DoesNotContain("section restore stopped part way", _fixture.Trail());
        Assert.DoesNotContain("section restored", _fixture.Trail());
        Assert.Empty(_fixture.KeptFoldersInBackups());
    }

    [Fact]
    public void ABackupWithoutTheSectionIsRefusedBeforeAnythingMoves()
    {
        _fixture.Write("a.md", "a");
        var course = Workspace.DiscoverCourses(_fixture.Folder).First(found => found.Code == "ICS3U");
        var backup = BackupItem.From(CourseArchiver.BackUpCourse(course, _fixture.CoursesDir, new BackupMaker.Assistant(3)), "ICS3U")!;
        var before = SectionSwapFixture.Snapshot(_fixture.CourseDir);

        Assert.Throws<CourseRestorer.RestoreException>(() => CourseRestorer.RestoreSection(3, backup, _fixture.CoursesDir));

        Assert.Equal(before, SectionSwapFixture.Snapshot(_fixture.CourseDir));
        Assert.False(Directory.Exists(Path.Combine(_fixture.CoursesDir, ".internal")));
    }

    [Fact]
    public void ARestoreThatFinishesPutsTheSectionBackAndLeavesNoStaging()
    {
        _fixture.Write("a.md", "a, as backed up");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day one, as backed up");
        var backup = _fixture.BackUp();
        var sectionAsBackedUp = SectionSwapFixture.Snapshot(_fixture.Section2);
        _fixture.Write("a.md", "a, changed since");
        _fixture.Write("made since.md", "made since");
        string builds = BuildOutputLocation.BuildsRootFor(_fixture.Folder);
        string keptCopy = Path.Combine(BuildOutputLocation.ForCourse(builds, "ICS3U"), BuildOutputLocation.KeptCopiesFolderName, "k1", "sketch.ggb");
        string builtPage = Path.Combine(BuildOutputLocation.ForSection(builds, "ICS3U", 2), "public", "index.html");
        Directory.CreateDirectory(Path.GetDirectoryName(keptCopy)!);
        File.WriteAllText(keptCopy, "a kept copy");
        Directory.CreateDirectory(Path.GetDirectoryName(builtPage)!);
        File.WriteAllText(builtPage, "built");

        CourseRestorer.RestoreSection(2, backup, _fixture.CoursesDir);

        Assert.Equal(sectionAsBackedUp, SectionSwapFixture.Snapshot(_fixture.Section2));
        Assert.False(Directory.Exists(Path.Combine(_fixture.CoursesDir, ".internal")));
        // #805: the section's discard takes its built site and never the course's kept copies.
        Assert.False(File.Exists(builtPage));
        Assert.Equal("a kept copy", File.ReadAllText(keptCopy));
    }

    // ---- a way back that does not finish -----------------------------------

    /// <summary>
    /// Holds the first entry the swap moves aside, at its new place, from the
    /// moment it lands there: the way back must move it and cannot.
    /// <paramref name="releaseAfterTheWayBack"/> lets go once the way back has
    /// failed on it, so the keep can move the folder; otherwise it is let go
    /// at the end of the test.
    /// </summary>
    private sealed class FirstMoveHeld(bool releaseAfterTheWayBack) : IDisposable
    {
        private readonly List<FileStream> _handles = new();
        private string? _heldAt;

        public CourseRestorer.SectionSwapHooks Hooks => new()
        {
            Move = (source, destination) =>
            {
                try { CourseRestorer.MoveEntry(source, destination); }
                catch when (_heldAt is not null && string.Equals(source, _heldAt, StringComparison.OrdinalIgnoreCase) && releaseAfterTheWayBack)
                {
                    Dispose();
                    throw;
                }
                if (_heldAt is null)
                {
                    _heldAt = destination;
                    string file = File.Exists(destination) ? destination : Directory.EnumerateFiles(destination, "*", SearchOption.AllDirectories).First();
                    _handles.Add(new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read));
                }
            },
            Reached = _ => { },
        };

        public void Dispose()
        {
            foreach (var handle in _handles) handle.Dispose();
            _handles.Clear();
        }
    }

    [Fact]
    public void AWayBackThatDoesNotFinishKeepsTheSetAsideFilesBesideTheBackupsAndSaysWhere()
    {
        var backup = BackupThenChange();
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(_fixture.Section2));

        string message;
        using (Hold(Path.Combine(_fixture.Section2, "zz notes", "held.md")))
        using (var held = new FirstMoveHeld(releaseAfterTheWayBack: true))
        {
            var error = Assert.Throws<AssistSectionRestore.StoppedPartWay>(() =>
                AssistSectionRestore.Restore(backup.FilePath, "ICS3U", 2, _fixture.CoursesDir, held.Hooks));
            message = error.Message;
        }

        string kept = Assert.Single(_fixture.KeptFoldersInBackups());
        string keptAt = Path.GetRelativePath(_fixture.Folder, kept);
        Assert.Equal(OneSectionRestoreWording.StoppedPartWay(2, keptAt), message);
        Assert.Empty(_fixture.OriginalsMissing(originals, new[] { kept }));
        Assert.True(File.Exists(Path.Combine(kept, "section2", "a.md")), "the file the way back could not move is kept");
        Assert.Contains("section restore stopped part way", _fixture.Trail());
        Assert.Contains(ActivityTrail.SectionRestoreStoppedPartWayLine(keptAt), _fixture.Trail());
        Assert.False(Directory.Exists(_fixture.RestoringDir), "nothing is left in courses\\.internal\\restoring once the files are kept");
    }

    [Fact]
    public void WithOnlyHiddenFilesLeftAsideTheTeacherIsNotSentToAnEmptyLookingFolder()
    {
        _fixture.Write(".a-hidden", "hidden, as backed up");
        _fixture.Write(Path.Combine("zz notes", "held.md"), "held, as backed up");
        var backup = _fixture.BackUp();
        _fixture.Write(".a-hidden", "hidden, changed since");
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(_fixture.Section2));

        string message;
        using (Hold(Path.Combine(_fixture.Section2, "zz notes", "held.md")))
        using (var held = new FirstMoveHeld(releaseAfterTheWayBack: true))
        {
            message = Assert.Throws<CourseRestorer.SectionRestoreStoppedPartWay>(() =>
                CourseRestorer.RestoreSection(2, backup, _fixture.CoursesDir, held.Hooks)).Message;
        }

        Assert.Equal(OneSectionRestoreWording.StoppedPartWayNothingToOpen(2), message);
        string kept = Assert.Single(_fixture.KeptFoldersInBackups());
        Assert.Empty(_fixture.OriginalsMissing(originals, new[] { kept }));
        Assert.Contains(ActivityTrail.SectionRestoreStoppedPartWayLine(Path.GetRelativePath(_fixture.Folder, kept)), _fixture.Trail());
    }

    [Fact]
    public void WhenEvenTheKeepCannotMoveTheFilesStayInStagingAndThatPathIsSaid()
    {
        var backup = BackupThenChange();
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(_fixture.Section2));

        string message;
        List<string> asides;
        using (Hold(Path.Combine(_fixture.Section2, "zz notes", "held.md")))
        using (var held = new FirstMoveHeld(releaseAfterTheWayBack: false))
        {
            message = Assert.Throws<CourseRestorer.SectionRestoreStoppedPartWay>(() =>
                CourseRestorer.RestoreSection(2, backup, _fixture.CoursesDir, held.Hooks)).Message;
            asides = _fixture.AsideFoldersInStaging().ToList();
        }

        string aside = Assert.Single(asides);
        Assert.Empty(_fixture.KeptFoldersInBackups());
        Assert.Equal(OneSectionRestoreWording.StoppedPartWay(2, Path.GetRelativePath(_fixture.Folder, aside)), message);
        Assert.Empty(_fixture.OriginalsMissing(originals, new[] { aside }));
        Assert.False(Directory.Exists(Path.Combine(Path.GetDirectoryName(aside)!, "backup")), "the unpacked backup still goes");
    }

    // ---- what backups leave out is never moved aside or deleted -------------

    [Fact]
    public void AGitFolderAndNodeModulesInTheSectionStayWhereTheyAre()
    {
        _fixture.Write("a.md", "a, as backed up");
        var backup = _fixture.BackUp();
        _fixture.Write("a.md", "a, changed since");
        _fixture.Write(Path.Combine(".git", "objects", "pack", "pack-1.idx"), "a pack file");
        File.SetAttributes(Path.Combine(_fixture.Section2, ".git", "objects", "pack", "pack-1.idx"), FileAttributes.ReadOnly);
        _fixture.Write(Path.Combine("node_modules", "x", "index.js"), "module");
        var gitBefore = SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, ".git"));
        var modulesBefore = SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, "node_modules"));

        CourseRestorer.RestoreSection(2, backup, _fixture.CoursesDir);

        Assert.Equal(gitBefore, SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, ".git")));
        Assert.Equal(modulesBefore, SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, "node_modules")));
        Assert.Equal("a, as backed up", File.ReadAllText(Path.Combine(_fixture.Section2, "a.md")));
        Assert.False(Directory.Exists(Path.Combine(_fixture.CoursesDir, ".internal")), "nothing went aside to keep");
        File.SetAttributes(Path.Combine(_fixture.Section2, ".git", "objects", "pack", "pack-1.idx"), FileAttributes.Normal);
    }

    [Fact]
    public void ADeeperGitFolderThatWentAsideWithItsFolderIsKeptNotDeleted()
    {
        _fixture.Write(Path.Combine("project", "main.md"), "as backed up");
        var backup = _fixture.BackUp();
        _fixture.Write(Path.Combine("project", ".git", "HEAD"), "ref: refs/heads/main");

        CourseRestorer.RestoreSection(2, backup, _fixture.CoursesDir);

        string aside = Assert.Single(_fixture.AsideFoldersInStaging());
        Assert.Equal("ref: refs/heads/main", File.ReadAllText(Path.Combine(aside, "section2", "project", ".git", "HEAD")));
    }

    // ---- the double-failure sweep (the mac's 12 of 91) ---------------------

    /// <summary>
    /// A failure at forward move k and at way-back move j, for every k from 2
    /// and every j below k, on Windows' own fixture: every original is kept,
    /// in the section or the kept folder, in every case. How many cases leave
    /// the section a MIX of original and backup files is counted and printed
    /// for the notes; it is the limit the stopped sentence admits, not a
    /// number this test holds to.
    /// </summary>
    [Fact]
    public void EveryDoubleFailureKeepsEveryOriginalAndTheMixesAreCounted()
    {
        int cases = 0, mixes = 0;
        for (int k = 2; ; k++)
        {
            bool reachedK = SweepOne(k, j: 0, out _);
            if (!reachedK) break;
            for (int j = 1; j < k; j++)
            {
                SweepOne(k, j, out bool mix);
                cases++;
                if (mix) mixes++;
            }
        }
        Assert.True(cases > 0);
        Console.WriteLine($"DOUBLE-FAILURE SWEEP: {mixes} of {cases} cases left section2 a mix");
        File.AppendAllText(Path.Combine(Path.GetTempPath(), "plantoir-911-sweep.txt"), $"{DateTime.Now:s} assistant route: {mixes} of {cases}\n");
    }

    /// <summary>One case on a fresh course; j 0 only asks whether there is a forward move k at all.</summary>
    private static bool SweepOne(int k, int j, out bool mix)
    {
        using var fixture = new SectionSwapFixture();
        fixture.Write("a.md", "a, backup");
        fixture.Write(".hidden", "hidden, backup");
        fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, backup");
        fixture.Write(Path.Combine("All Classes", "deeper", "x.md"), "x, backup");
        var backup = fixture.BackUp();
        var backupFiles = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(fixture.Section2));
        fixture.Write("a.md", "a, live");
        fixture.Write(".hidden", "hidden, live");
        fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, live");
        fixture.Write("made since.md", "made since, live");
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(fixture.Section2));

        int forward = 0, back = 0;
        bool failed = false;
        var hooks = new CourseRestorer.SectionSwapHooks
        {
            Move = (source, destination) =>
            {
                if (!failed)
                {
                    forward++;
                    if (forward == k) { failed = true; throw new IOException("injected forward failure " + k); }
                }
                else
                {
                    back++;
                    if (back == j) throw new IOException("injected way-back failure " + j);
                }
                CourseRestorer.MoveEntry(source, destination);
            },
            Reached = _ => { },
        };
        mix = false;
        try { CourseRestorer.RestoreSection(2, backup, fixture.CoursesDir, hooks); }
        catch (CourseRestorer.RestoreException) { }
        if (!failed) return false;
        if (j == 0) return true;

        var kept = fixture.KeptFoldersInBackups().Concat(fixture.AsideFoldersInStaging()).ToList();
        var missing = fixture.OriginalsMissing(originals, kept);
        Assert.True(missing.Count == 0, $"k {k}, j {j}: lost {string.Join(", ", missing)}");

        var now = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(fixture.Section2));
        bool holdsAnOriginal = false, holdsABackupFile = false;
        foreach (var (path, hash) in now)
        {
            if (originals.TryGetValue(path, out var original) && original == hash) holdsAnOriginal = true;
            else if (backupFiles.TryGetValue(path, out var backedUp) && backedUp == hash) holdsABackupFile = true;
        }
        mix = holdsAnOriginal && holdsABackupFile;
        return true;
    }
}
