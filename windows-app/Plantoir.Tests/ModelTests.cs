using System.Text;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Preview leases and the publish registry are process-wide statics, so the
/// classes that touch them must not run at the same time. xUnit runs test
/// CLASSES in parallel by default, and PreviewLeaseTests resets the lease
/// list around every one of its methods — which would yank the lease
/// CourseActivityTests is in the middle of asserting on, roughly one run in
/// three. Sharing a collection serializes them.
/// </summary>
[CollectionDefinition(SharedActivityState.Name, DisableParallelization = true)]
public class SharedActivityStateCollection { }

public static class SharedActivityState { public const string Name = "Process-wide preview and publish state"; }

[Collection(SharedActivityState.Name)]
public class PreviewLeaseTests : IDisposable
{
    public PreviewLeaseTests() => PreviewLeases.Reset();
    public void Dispose() => PreviewLeases.Reset();

    [Fact]
    public void SameSectionSameFolderIsRefused()
    {
        PreviewLeases.Take(@"C:\folder", "ICS3U", 1);
        var refusal = Assert.Throws<PreviewLeases.LeaseRefusedException>(
            () => PreviewLeases.Take(@"C:\folder", "ICS3U", 1));
        Assert.Equal("Section 1 of ICS3U is already being previewed in another window. Stop that preview first, or work with it there.",
            refusal.Message);
    }

    [Fact]
    public void SameSectionDifferentFolderIsAllowed()
    {
        PreviewLeases.Take(@"C:\folderA", "ICS3U", 1);
        var lease = PreviewLeases.Take(@"C:\folderB", "ICS3U", 1);
        Assert.Equal(8081, lease.Port);   // ports contend per folder only
    }

    [Fact]
    public void FifthPreviewOfAFolderIsRefusedPolitely()
    {
        for (int i = 1; i <= 4; i++) PreviewLeases.Take(@"C:\folder", "ICS3U", i);
        var refusal = Assert.Throws<PreviewLeases.LeaseRefusedException>(
            () => PreviewLeases.Take(@"C:\folder", "ICS3U", 5));
        Assert.Equal("Four previews of this folder are already running, which is the most that can run at once. Stop one, then try again.",
            refusal.Message);
    }

    [Fact]
    public void ReleaseFreesThePort()
    {
        var lease = PreviewLeases.Take(@"C:\folder", "ICS3U", 1);
        PreviewLeases.Release(lease);
        var again = PreviewLeases.Take(@"C:\folder", "ICS3U", 1);
        Assert.Equal(8081, again.Port);
    }
}

public class ArchivedItemTests
{
    [Fact]
    public void CourseArchiveParses()
    {
        var item = ArchivedItem.From(@"C:\b\ICS3U_2026-08-09_141530.zip", "ICS3U")!;
        Assert.Null(item.SectionNumber);
        Assert.Equal("ICS3U", item.Title);
        Assert.Equal(new DateTime(2026, 8, 9, 14, 15, 30), item.ArchivedAt);
    }

    [Fact]
    public void SectionArchiveParses()
    {
        var item = ArchivedItem.From(@"C:\b\ICS3U-section3_2026-08-09_141530.zip", "ICS3U")!;
        Assert.Equal(3, item.SectionNumber);
        Assert.Equal("ICS3U — Section 3", item.Title);
    }

    [Fact]
    public void WizardTimestampBackupsAreNotArchives() =>
        Assert.Null(ArchivedItem.From(@"C:\b\2026-08-09_141530.zip", "ICS3U"));

    [Fact]
    public void ForeignAndMalformedNamesAreIgnored()
    {
        Assert.Null(ArchivedItem.From(@"C:\b\OTHER_2026-08-09_141530.zip", "ICS3U"));
        Assert.Null(ArchivedItem.From(@"C:\b\ICS3U_notadate.zip", "ICS3U"));
        Assert.Null(ArchivedItem.From(@"C:\b\ICS3U-section3_2026-08-09_141530.txt", "ICS3U"));
        Assert.Null(ArchivedItem.From(@"C:\b\noseparator.zip", "ICS3U"));
    }
}

public class SectionAdderTests
{
    [Theory]
    [InlineData("ICS3U", "Grade 11")]
    [InlineData("SNC1W", "Grade 9")]
    [InlineData("MHF4U", "Grade 12")]
    [InlineData("ABC5X", "Grade ?")]
    [InlineData("CODING", "")]
    [InlineData("ART", "")]
    public void GradeLabelsComeFromTheFourthCharacter(string code, string label) =>
        Assert.Equal(label, SectionAdder.GradeLabel(code));

    [Fact]
    public void SuggestedNumberIsTheSmallestGap()
    {
        Assert.Equal(2, SectionAdder.SuggestedNumber(new[] { 1, 3 }));
        Assert.Equal(1, SectionAdder.SuggestedNumber(Array.Empty<int>()));
        Assert.Equal(4, SectionAdder.SuggestedNumber(new[] { 1, 2, 3 }));
    }

    [Fact]
    public void EntryProblemsMatchTheHouseWording()
    {
        Assert.Null(SectionAdder.EntryProblem("", new[] { 1 }, "ICS3U"));
        Assert.Equal("“2a” isn’t a section number — sections are 1 or higher.",
            SectionAdder.EntryProblem("2a", new[] { 1 }, "ICS3U"));
        Assert.Equal("“0” isn’t a section number — sections are 1 or higher.",
            SectionAdder.EntryProblem("0", new[] { 1 }, "ICS3U"));
        Assert.Equal("Section 1 of ICS3U already exists.",
            SectionAdder.EntryProblem("1", new[] { 1 }, "ICS3U"));
        Assert.Null(SectionAdder.EntryProblem("2", new[] { 1 }, "ICS3U"));
    }

    [Fact]
    public void TimestampUsesColonFreeOffset()
    {
        string stamp = SectionAdder.Timestamp(new DateTimeOffset(2026, 8, 10, 14, 30, 0, TimeSpan.FromHours(-4)));
        Assert.Equal("2026-08-10T14:30:00.000-0400", stamp);
    }

    [Fact]
    public void ScaffoldingMirrorsTheLowestSibling()
    {
        string root = Path.Combine(Path.GetTempPath(), "adder-" + Guid.NewGuid());
        try
        {
            var course = MakeCourse(root, "ICS3U", """
                {"course_code":"ICS3U","course_name":"Computer Science","section_numbers":[2],
                 "per_section_folders":["All Classes"],"per_section_files":["Private Notes.md","Key Links.md"]}
                """);
            string section2 = Path.Combine(course.DirectoryPath, "section2");
            Directory.CreateDirectory(Path.Combine(section2, "All Classes"));
            File.WriteAllText(Path.Combine(section2, "index.md"),
                "---\ntitle: My Special Wording, Section 2\ncreated: 2025-01-01T00:00:00.000-0500\nenableToc: false\n---");
            File.WriteAllText(Path.Combine(section2, "Private Notes.md"),
                "---\ntitle: Private Notes\ncreated: 2025-01-01T00:00:00.000-0500\ndraft: true\n---\nbody");
            File.WriteAllText(Path.Combine(section2, "All Classes", "index.md"),
                "---\ntitle: All Classes\ncreated: 2025-01-01T00:00:00.000-0500\n---\nbody");

            SectionAdder.AddSection(1, course);

            string index = File.ReadAllText(Path.Combine(course.DirectoryPath, "section1", "index.md"));
            Assert.Contains("title: My Special Wording, Section 1", index);   // teacher's wording kept, renumbered
            Assert.Contains("enableToc: false", index);                        // flags carried over
            Assert.DoesNotContain("2025-01-01", index);                        // created freshened

            string notes = File.ReadAllText(Path.Combine(course.DirectoryPath, "section1", "Private Notes.md"));
            Assert.Contains("draft: true", notes);                             // sibling's draft flag carried

            Assert.Equal(new[] { 1, 2 }, CourseConfiguration.Load(course.ConfigFilePath).SectionNumbers);
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void FallbackTemplateMakesTeacherPagesDrafts()
    {
        string root = Path.Combine(Path.GetTempPath(), "adder-" + Guid.NewGuid());
        try
        {
            var course = MakeCourse(root, "SNC1W", """
                {"course_code":"SNC1W","course_name":"Science","section_numbers":[],
                 "per_section_files":["Private Notes.md","Key Links.md"]}
                """);
            SectionAdder.AddSection(1, course);
            // publish:, and inverted — a teacher-eyes-only page is publish: false.
            Assert.Contains("publish: false", File.ReadAllText(Path.Combine(course.DirectoryPath, "section1", "Private Notes.md")));
            Assert.Contains("publish: true", File.ReadAllText(Path.Combine(course.DirectoryPath, "section1", "Key Links.md")));
            Assert.Contains("title: Grade 9 Science, Section 1",
                File.ReadAllText(Path.Combine(course.DirectoryPath, "section1", "index.md")));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void RefusalsProtectExistingWork()
    {
        string root = Path.Combine(Path.GetTempPath(), "adder-" + Guid.NewGuid());
        try
        {
            var course = MakeCourse(root, "ICS3U", """{"course_code":"ICS3U","section_numbers":[1]}""");
            var listed = Assert.Throws<SectionAdder.SectionAddException>(() => SectionAdder.AddSection(1, course));
            Assert.Equal("Section 1 of ICS3U already exists.", listed.Message);

            Directory.CreateDirectory(Path.Combine(course.DirectoryPath, "section3"));
            var inTheWay = Assert.Throws<SectionAdder.SectionAddException>(() => SectionAdder.AddSection(3, course));
            Assert.Contains("Move it aside first — it may hold work you want to keep.", inTheWay.Message);
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    internal static Course MakeCourse(string root, string code, string configJson)
    {
        string courseDir = Path.Combine(root, "courses", code);
        Directory.CreateDirectory(courseDir);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"), configJson);
        var config = CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(configJson));
        return new Course(code, courseDir, config);
    }
}

public class ArchiveRoundTripTests
{
    [Fact]
    public void RemovingACourseSurvivesAGitRepoInTheBuildOutput()
    {
        // The Quartz project copied into .merged_output carries a .git whose
        // pack files are READONLY — git marks them so — and removing a course
        // died on the first one ("Access to the path 'pack-….idx' is
        // denied"), half-deleted, behind an archive that had already
        // succeeded. The delete must strip attributes as it goes.
        string root = Path.Combine(Path.GetTempPath(), "arch-" + Guid.NewGuid());
        string pack = "";
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = SectionAdderTests.MakeCourse(root, "ADA1O",
                """{"course_code":"ADA1O","course_name":"Drama","section_numbers":[1]}""");
            string packDir = Path.Combine(course.DirectoryPath,
                ".merged_output", "section1", ".git", "objects", "pack");
            Directory.CreateDirectory(packDir);
            pack = Path.Combine(packDir, "pack-ace7b.idx");
            File.WriteAllText(pack, "git made me");
            File.SetAttributes(pack, FileAttributes.ReadOnly);
            File.WriteAllText(Path.Combine(course.DirectoryPath, "index.md"), "---\ntitle: T\n---");

            string archivePath = CourseArchiver.ArchiveAndRemoveCourse(course, coursesDir);

            Assert.False(Directory.Exists(course.DirectoryPath));
            Assert.True(File.Exists(archivePath));
        }
        finally
        {
            // If the delete under test failed, the readonly pack would trip
            // this cleanup too — clear it so the temp folder never leaks.
            try { if (File.Exists(pack)) File.SetAttributes(pack, FileAttributes.Normal); } catch { }
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }

    [Fact]
    public void SectionArchiveRoundTripsAndKeepsBookkeeping()
    {
        string root = Path.Combine(Path.GetTempPath(), "arch-" + Guid.NewGuid());
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = SectionAdderTests.MakeCourse(root, "ICS3U",
                """{"course_code":"ICS3U","course_name":"CS","section_numbers":[1,2]}""");
            string section2 = Path.Combine(course.DirectoryPath, "section2");
            Directory.CreateDirectory(Path.Combine(section2, ".merged_output", "junk"));
            File.WriteAllText(Path.Combine(section2, ".merged_output", "junk", "big.html"), "generated");
            File.WriteAllText(Path.Combine(section2, "index.md"), "---\ntitle: T\n---");

            string archivePath = CourseArchiver.ArchiveAndRemoveSection(course, 2, coursesDir);

            Assert.False(Directory.Exists(section2));
            Assert.Equal(new[] { 1 }, CourseConfiguration.Load(course.ConfigFilePath).SectionNumbers);
            var item = ArchivedItem.From(archivePath, "ICS3U")!;
            Assert.Equal(2, item.SectionNumber);

            // Restore refuses while the course is missing from the list, then succeeds.
            var missing = Assert.Throws<CourseRestorer.RestoreException>(
                () => CourseRestorer.Restore(item, coursesDir, Array.Empty<Course>()));
            Assert.Contains("Restore the course first", missing.Message);

            CourseRestorer.Restore(item, coursesDir, new[] { course });
            Assert.True(File.Exists(Path.Combine(section2, "index.md")));
            Assert.False(Directory.Exists(Path.Combine(section2, ".merged_output")));   // excluded from the zip
            Assert.Equal(new[] { 1, 2 }, CourseConfiguration.Load(course.ConfigFilePath).SectionNumbers);
            Assert.False(File.Exists(archivePath));   // restored = no longer archived
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void RestoreNeverOverwrites()
    {
        string root = Path.Combine(Path.GetTempPath(), "arch-" + Guid.NewGuid());
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = SectionAdderTests.MakeCourse(root, "ICS3U",
                """{"course_code":"ICS3U","section_numbers":[1]}""");
            string section1 = Path.Combine(course.DirectoryPath, "section1");
            Directory.CreateDirectory(section1);
            File.WriteAllText(Path.Combine(section1, "index.md"), "---\ntitle: T\n---");

            string zipPath = Path.Combine(CourseArchiver.BackupsDirectory(coursesDir, "ICS3U"),
                CourseArchiver.TimestampedName("ICS3U-section1", DateTime.Now));
            Directory.CreateDirectory(Path.GetDirectoryName(zipPath)!);
            CourseArchiver.ZipFolder(section1, zipPath);
            var item = ArchivedItem.From(zipPath, "ICS3U")!;

            var refusal = Assert.Throws<CourseRestorer.RestoreException>(
                () => CourseRestorer.Restore(item, coursesDir, new[] { course }));
            Assert.Equal("Section 1 of ICS3U already exists. Remove it first if you want the archived copy back.", refusal.Message);
            Assert.True(File.Exists(zipPath));   // refusal leaves the archive alone
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }
}

/// <summary>
/// Whole-course backups (row 106): the three zip name forms stay strangers,
/// backing up touches nothing, and a restore replaces the course folder's
/// CONTENTS — never the folder itself, which is Obsidian's vault anchor.
/// </summary>
public class CourseBackupTests
{
    private static string Temp()
    {
        string root = Path.Combine(Path.GetTempPath(), "backup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

    private static Course MakeCourse(string coursesDir, string code)
    {
        string dir = Path.Combine(coursesDir, code);
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "course_config.json"),
            $$"""{"course_code":"{{code}}","section_numbers":[1]}""");
        File.WriteAllText(Path.Combine(dir, "Learning Goals.md"), "original goals");
        Directory.CreateDirectory(Path.Combine(dir, ".merged_output"));
        File.WriteAllText(Path.Combine(dir, ".merged_output", "huge.txt"), "rebuildable");
        return Workspace.DiscoverCourses(Path.GetDirectoryName(coursesDir)!).First(c => c.Code == code);
    }

    [Fact]
    public void TheThreeZipNameFormsNeverCrossMatch()
    {
        const string backup = @"C:\x\ICS3U_backup_2026-08-12_101500.zip";
        const string archive = @"C:\x\ICS3U_2026-08-12_101500.zip";
        const string wizard = @"C:\x\2026-08-12_101500.zip";

        Assert.NotNull(BackupItem.From(backup, "ICS3U"));
        Assert.Null(ArchivedItem.From(backup, "ICS3U"));

        Assert.NotNull(ArchivedItem.From(archive, "ICS3U"));
        Assert.Null(BackupItem.From(archive, "ICS3U"));

        Assert.Null(BackupItem.From(wizard, "ICS3U"));
        Assert.Null(ArchivedItem.From(wizard, "ICS3U"));
    }

    [Fact]
    public void BackingUpTouchesNothingAndSkipsTheRebuildableBulk()
    {
        string root = Temp();
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = MakeCourse(coursesDir, "ICS3U");

            string zipPath = CourseArchiver.BackUpCourse(course, coursesDir);

            Assert.True(File.Exists(Path.Combine(course.DirectoryPath, "Learning Goals.md")));
            Assert.NotNull(BackupItem.From(zipPath, "ICS3U"));
            using var zip = System.IO.Compression.ZipFile.OpenRead(zipPath);
            Assert.Contains(zip.Entries, e => e.FullName.EndsWith("Learning Goals.md"));
            Assert.DoesNotContain(zip.Entries, e => e.FullName.Contains(".merged_output"));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void RestoreReplacesContentsInPlaceKeepsTheFolderAndTheZip()
    {
        string root = Temp();
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = MakeCourse(coursesDir, "ICS3U");
            string zipPath = CourseArchiver.BackUpCourse(course, coursesDir);
            var backup = BackupItem.From(zipPath, "ICS3U")!;

            // The mess an LLM might make: a page rewritten, a stray added.
            File.WriteAllText(Path.Combine(course.DirectoryPath, "Learning Goals.md"), "MANGLED");
            File.WriteAllText(Path.Combine(course.DirectoryPath, "Rogue.md"), "should vanish");
            DateTime folderCreated = Directory.GetCreationTimeUtc(course.DirectoryPath);

            CourseRestorer.RestoreBackup(backup, coursesDir);

            Assert.Equal("original goals", File.ReadAllText(Path.Combine(course.DirectoryPath, "Learning Goals.md")));
            Assert.False(File.Exists(Path.Combine(course.DirectoryPath, "Rogue.md")));
            // The folder itself never left: same file-system identity for
            // Obsidian's watcher (a recreated folder gets a new creation time).
            Assert.Equal(folderCreated, Directory.GetCreationTimeUtc(course.DirectoryPath));
            Assert.True(File.Exists(zipPath));   // the backup STAYS after restoring
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void RestoreSurvivesReadonlyFilesAndUntraversableLinks()
    {
        // What a course folder REALLY holds after container builds: readonly
        // droppings and links Directory.Delete(recursive) cannot traverse —
        // the failure seen live before the delete learned to cope.
        string root = Temp();
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = MakeCourse(coursesDir, "ICS3U");
            string zipPath = CourseArchiver.BackUpCourse(course, coursesDir);
            var backup = BackupItem.From(zipPath, "ICS3U")!;

            File.WriteAllText(Path.Combine(course.DirectoryPath, "Learning Goals.md"), "MANGLED");
            string stubborn = Path.Combine(course.DirectoryPath, ".merged_output", "locked.txt");
            File.WriteAllText(stubborn, "readonly dropping");
            File.SetAttributes(stubborn, FileAttributes.ReadOnly);
            try
            {
                // A link like the container's content\Media, when this
                // machine permits creating one (Developer Mode / admin).
                Directory.CreateSymbolicLink(
                    Path.Combine(course.DirectoryPath, ".merged_output", "Media"),
                    Path.Combine(root, "no-such-target"));
            }
            catch { /* the readonly file still exercises the robust delete */ }

            CourseRestorer.RestoreBackup(backup, coursesDir);

            Assert.Equal("original goals", File.ReadAllText(Path.Combine(course.DirectoryPath, "Learning Goals.md")));
            Assert.False(Directory.Exists(Path.Combine(course.DirectoryPath, ".merged_output")));
        }
        finally
        {
            // The readonly dropping would also stop the cleanup.
            foreach (string file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
                try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void DeletingRemovesOnlyTheZip()
    {
        string root = Temp();
        try
        {
            string coursesDir = Path.Combine(root, "courses");
            var course = MakeCourse(coursesDir, "ICS3U");
            string zipPath = CourseArchiver.BackUpCourse(course, coursesDir);
            var backup = BackupItem.From(zipPath, "ICS3U")!;

            CourseRestorer.DeleteBackup(backup);
            Assert.False(File.Exists(zipPath));
            Assert.True(Directory.Exists(course.DirectoryPath));
            Assert.Empty(Workspace.FindBackups(root));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }
}

/// <summary>
/// The per-window sidebar memory's string forms (row 99): selection and
/// expansion round-trips, unrecognized forms restoring nothing, and the
/// deliberate Windows divergence — no stored state means all-open.
/// </summary>
public class WindowMemoryCodecTests
{
    [Theory]
    [InlineData("course|ICS3U", "course", "ICS3U", 0, "")]
    [InlineData("section|MCV4U|3", "section", "MCV4U", 3, "")]
    [InlineData("archived|abc-123", "archived", "", 0, "abc-123")]
    public void SelectionsRoundTrip(string stored, string kind, string code, int section, string id)
    {
        var decoded = WindowMemoryCodec.ParseSelection(stored)!;
        Assert.Equal(kind, decoded.Kind);
        Assert.Equal(code, decoded.Code);
        Assert.Equal(section, decoded.Section);
        Assert.Equal(id, decoded.Id);
    }

    [Fact]
    public void EncodersProduceWhatTheParserReads()
    {
        Assert.Equal("course|ICS3U", WindowMemoryCodec.EncodeCourse("ICS3U"));
        Assert.Equal("section|MCV4U|3", WindowMemoryCodec.EncodeSection("MCV4U", 3));
        Assert.Equal("archived|x", WindowMemoryCodec.EncodeArchived("x"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("course|")]
    [InlineData("section|ICS3U|zero")]
    [InlineData("section|ICS3U|0")]
    [InlineData("bookmark|whatever")]
    public void UnrecognizedSelectionsRestoreNothing(string? stored) =>
        Assert.Null(WindowMemoryCodec.ParseSelection(stored));

    [Fact]
    public void ExpansionRoundTripsAndNullMeansEverythingOpen()
    {
        Assert.Null(WindowMemoryCodec.EncodeExpandedCourses(null));
        Assert.Null(WindowMemoryCodec.ParseExpandedCourses(null));   // legacy entry: all open

        Assert.Equal("ICS3U,MCV4U", WindowMemoryCodec.EncodeExpandedCourses(new[] { "MCV4U", "ICS3U" }));
        Assert.Equal(new[] { "ICS3U", "MCV4U" },
            WindowMemoryCodec.ParseExpandedCourses("ICS3U,MCV4U")!.OrderBy(c => c));

        // An explicit empty string is "the teacher collapsed everything".
        Assert.Equal("", WindowMemoryCodec.EncodeExpandedCourses(Array.Empty<string>()));
        Assert.Empty(WindowMemoryCodec.ParseExpandedCourses("")!);
    }
}

/// <summary>
/// The cross-window busy registry gating Add Section (row 104). Folder paths
/// are unique per test so the static registry never crosses wires with the
/// lease tests.
/// </summary>
[Collection(SharedActivityState.Name)]
public class CourseActivityTests
{
    private static string Folder() => @"C:\activity-" + Guid.NewGuid().ToString("N");

    [Fact]
    public void PublishesAreScopedToTheirCourseAndFolder()
    {
        string folder = Folder(), other = Folder();
        using var publish = CourseActivity.BeginPublish(folder, "ICS3U", 1);
        Assert.True(CourseActivity.IsPublishing(folder, "ICS3U"));
        Assert.False(CourseActivity.IsPublishing(folder, "ICS4U"));
        Assert.False(CourseActivity.IsPublishing(other, "ICS3U"));   // same code, other folder = other course
    }

    [Fact]
    public void TwoPublishesOfOneCourseEndIndependently()
    {
        string folder = Folder();
        var first = CourseActivity.BeginPublish(folder, "ICS3U", 1);
        var second = CourseActivity.BeginPublish(folder, "ICS3U", 3);
        first.Dispose();
        Assert.True(CourseActivity.IsPublishing(folder, "ICS3U"));   // section 3 still going
        second.Dispose();
        Assert.False(CourseActivity.IsPublishing(folder, "ICS3U"));
        second.Dispose();   // double-dispose is harmless
        Assert.False(CourseActivity.IsPublishing(folder, "ICS3U"));
    }

    [Fact]
    public void BusyReasonNamesWhatStandsInTheWay()
    {
        string folder = Folder();
        Assert.Null(CourseActivity.BusyReason(folder, "ICS3U"));

        var publish = CourseActivity.BeginPublish(folder, "ICS3U", 1);
        Assert.Equal("Available once deploy completed", CourseActivity.BusyReason(folder, "ICS3U"));

        var lease = PreviewLeases.Take(folder, "ICS3U", 2);
        Assert.Equal("Available once preview and deploy complete", CourseActivity.BusyReason(folder, "ICS3U"));

        publish.Dispose();
        Assert.Equal("Available once preview completed", CourseActivity.BusyReason(folder, "ICS3U"));

        PreviewLeases.Release(lease);
        Assert.Null(CourseActivity.BusyReason(folder, "ICS3U"));
    }

    [Fact]
    public void PreviewsCountThroughTheirLeases()
    {
        string folder = Folder();
        var lease = PreviewLeases.Take(folder, "MCV4U", 1);
        Assert.True(CourseActivity.IsPreviewing(folder, "MCV4U"));
        Assert.False(CourseActivity.IsPreviewing(folder, "ICS3U"));
        PreviewLeases.Release(lease);
        Assert.False(CourseActivity.IsPreviewing(folder, "MCV4U"));
    }
}

public class BuildFreshnessTests
{
    [Fact]
    public void NeverBuiltNeedsRebuild()
    {
        string root = Path.Combine(Path.GetTempPath(), "fresh-" + Guid.NewGuid());
        try
        {
            var course = SectionAdderTests.MakeCourse(root, "ICS3U", """{"course_code":"ICS3U"}""");
            Assert.True(BuildFreshness.NeedsRebuild(course, 1));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void FreshBuildDoesNotRebuildUntilContentChanges()
    {
        string root = Path.Combine(Path.GetTempPath(), "fresh-" + Guid.NewGuid());
        try
        {
            var course = SectionAdderTests.MakeCourse(root, "ICS3U", """{"course_code":"ICS3U"}""");
            string publicDir = Path.Combine(course.DirectoryPath, ".merged_output", "section1", "public");
            Directory.CreateDirectory(publicDir);
            string content = Path.Combine(course.DirectoryPath, "section1");
            Directory.CreateDirectory(content);
            File.WriteAllText(Path.Combine(content, "index.md"), "x");
            File.WriteAllText(Path.Combine(publicDir, "index.html"), "built");
            File.SetLastWriteTimeUtc(Path.Combine(publicDir, "index.html"), DateTime.UtcNow.AddMinutes(5));
            Assert.False(BuildFreshness.NeedsRebuild(course, 1));

            File.SetLastWriteTimeUtc(Path.Combine(content, "index.md"), DateTime.UtcNow.AddMinutes(10));
            Assert.True(BuildFreshness.NeedsRebuild(course, 1));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void HiddenEntriesNeverTriggerRebuilds()
    {
        string root = Path.Combine(Path.GetTempPath(), "fresh-" + Guid.NewGuid());
        try
        {
            var course = SectionAdderTests.MakeCourse(root, "ICS3U", """{"course_code":"ICS3U"}""");
            string publicDir = Path.Combine(course.DirectoryPath, ".merged_output", "section1", "public");
            Directory.CreateDirectory(publicDir);
            File.WriteAllText(Path.Combine(publicDir, "index.html"), "built");
            File.SetLastWriteTimeUtc(Path.Combine(publicDir, "index.html"), DateTime.UtcNow.AddMinutes(5));

            string obsidian = Path.Combine(course.DirectoryPath, ".obsidian");
            Directory.CreateDirectory(obsidian);
            File.WriteAllText(Path.Combine(obsidian, "workspace.json"), "{}");
            File.SetLastWriteTimeUtc(Path.Combine(obsidian, "workspace.json"), DateTime.UtcNow.AddMinutes(30));

            Assert.False(BuildFreshness.NeedsRebuild(course, 1));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }

    [Fact]
    public void APreviewBuildIsNeverDeployFresh()
    {
        // Serve mode bakes a live-reload client into every page; deploying it
        // makes the public site knock on ws://localhost and browsers prompt.
        string root = Path.Combine(Path.GetTempPath(), "fresh-" + Guid.NewGuid());
        try
        {
            var course = SectionAdderTests.MakeCourse(root, "ICS3U", """{"course_code":"ICS3U"}""");
            string publicDir = Path.Combine(course.DirectoryPath, ".merged_output", "section1", "public");
            Directory.CreateDirectory(publicDir);
            string index = Path.Combine(publicDir, "index.html");
            File.WriteAllText(index,
                "<script>const socket = new WebSocket('ws://localhost:9081')</script>");
            File.SetLastWriteTimeUtc(index, DateTime.UtcNow.AddMinutes(5));

            Assert.True(BuildFreshness.BuiltForPreview(index));
            Assert.True(BuildFreshness.NeedsRebuild(course, 1));

            File.WriteAllText(index, "a clean production page");
            File.SetLastWriteTimeUtc(index, DateTime.UtcNow.AddMinutes(5));
            Assert.False(BuildFreshness.BuiltForPreview(index));
            Assert.False(BuildFreshness.NeedsRebuild(course, 1));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }
}

public class FolderContainerTests
{
    [Fact]
    public void ContainerNameMatchesTheLauncherDerivation()
    {
        // The launcher hashes the physical path (true casing) + "\n"; the app
        // must agree even when handed a differently-cased path.
        string dir = Path.Combine(Path.GetTempPath(), "MixedCase-" + Guid.NewGuid());
        Directory.CreateDirectory(dir);
        try
        {
            string physical = FolderContainers.PhysicalPath(dir.ToLowerInvariant());
            byte[] hash = System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(physical + "\n"));
            string expected = "teaching-quartz-" + Convert.ToHexString(hash).ToLowerInvariant()[..8];

            Assert.Equal(expected, FolderContainers.ContainerName(dir.ToLowerInvariant()));
            Assert.Equal(expected, FolderContainers.ContainerName(dir.ToUpperInvariant()));
            Assert.Equal(expected, FolderContainers.ContainerName(dir));
            Assert.StartsWith("teaching-quartz-", expected);
            Assert.Equal("teaching-quartz-".Length + 8, expected.Length);
        }
        finally { try { Directory.Delete(dir); } catch { } }
    }

    [Fact]
    public void QuitReleaseStopsContainersThenChecksForIdle()
    {
        var recorded = new List<string[]>();
        FolderContainers.CommandRunnerOverride = recorded.Add;
        try
        {
            FolderContainers.ReleaseEverythingAtQuit(new[] { @"C:\Windows", @"C:\Windows" });
            var command = Assert.Single(recorded);
            string joined = string.Join(" ", command);
            Assert.Contains("docker stop -t 2 teaching-quartz-", joined);
            Assert.Contains("docker ps -q", joined);          // the emptiness check
            Assert.Contains("wsl --terminate", joined);       // only fires when idle
            // De-duplicated: one container name, mentioned once.
            int count = joined.Split("teaching-quartz-").Length - 1;
            Assert.Equal(1, count);
        }
        finally { FolderContainers.CommandRunnerOverride = null; }
    }
}

public class CourseRenamerTests
{
    [Fact]
    public void QuietOutcomeYieldsNoNotice()
    {
        var outcome = new CourseRenamer.Outcome("ICS4U", Array.Empty<int>(), Array.Empty<int>());
        Assert.True(outcome.IsQuiet);
        Assert.Null(CourseRenamer.NoticeAfterRenaming(outcome));
    }

    [Fact]
    public void StoppedSectionsYieldNotice()
    {
        var outcome = new CourseRenamer.Outcome("ICS4U", new[] { 1, 2 }, Array.Empty<int>());
        Assert.False(outcome.IsQuiet);
        var notice = CourseRenamer.NoticeAfterRenaming(outcome);
        Assert.NotNull(notice);
        Assert.Equal("Scheduled publishing turned off", notice.Title);
        Assert.Contains("Section 1, Section 2", notice.Message);
    }

    [Fact]
    public void UnstoppedSectionsYieldErrorNotice()
    {
        var outcome = new CourseRenamer.Outcome("ICS4U", Array.Empty<int>(), new[] { 3 });
        Assert.False(outcome.IsQuiet);
        var notice = CourseRenamer.NoticeAfterRenaming(outcome);
        Assert.NotNull(notice);
        Assert.Equal("Scheduled publishing could not be cancelled", notice.Title);
        Assert.Contains("Section 3", notice.Message);
    }

    [Fact]
    public void RenameUpdatesConfigAndMovesDirectory()
    {
        string tempDir = Path.Combine(Path.GetTempPath(), "PlantoirRenameTest-" + Guid.NewGuid());
        Directory.CreateDirectory(tempDir);
        try
        {
            string courseDir = Path.Combine(tempDir, "ICS3U");
            Directory.CreateDirectory(courseDir);
            string configPath = Path.Combine(courseDir, "course_config.json");
            File.WriteAllText(configPath, "{\n  \"course_code\": \"ICS3U\",\n  \"sections\": [1]\n}\n");

            var config = CourseConfiguration.Load(configPath);
            var course = new Course("ICS3U", courseDir, config);

            var outcome = CourseRenamer.Rename(course, "ICS4U", tempDir, new[] { "ICS3U" });
            Assert.Equal("ICS4U", outcome.NewCode);
            Assert.False(Directory.Exists(courseDir));

            string newDir = Path.Combine(tempDir, "ICS4U");
            Assert.True(Directory.Exists(newDir));
            var newConfig = CourseConfiguration.Load(Path.Combine(newDir, "course_config.json"));
            Assert.Equal("ICS4U", newConfig.CourseCode);
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }
}

public class UnitDayAndSectionIndexTests
{
    [Fact]
    public void UnitDay_ComparesUnitThenDayCorrectly()
    {
        var u1d2 = UnitDay.Parse("Unit 1, Day 2");
        var u1d10 = UnitDay.Parse("Unit 1, Day 10");
        var u2d1 = UnitDay.Parse("Unit 2, Day 1");

        Assert.NotNull(u1d2);
        Assert.NotNull(u1d10);
        Assert.NotNull(u2d1);

        Assert.True(u1d2.Value.CompareTo(u1d10.Value) < 0);
        Assert.True(u1d10.Value.CompareTo(u1d2.Value) > 0);
        Assert.True(u1d10.Value.CompareTo(u2d1.Value) < 0);
        Assert.True(u2d1.Value.CompareTo(u1d10.Value) > 0);
    }

    [Fact]
    public void SectionIndex_TieBreaksSameDateClassesByUnitDay()
    {
        string tempDir = Path.Combine(Path.GetTempPath(), "PlantoirSectionIndexTest-" + Guid.NewGuid());
        Directory.CreateDirectory(tempDir);
        try
        {
            string page1 = Path.Combine(tempDir, "Unit 1, Day 1.md");
            string page2 = Path.Combine(tempDir, "Unit 1, Day 2.md");
            File.WriteAllText(page1, "---\ncreated: 2026-09-08\npublish: true\n---\n# Lesson 1");
            File.WriteAllText(page2, "---\ncreated: 2026-09-08\npublish: true\n---\n# Lesson 2");

            string configPath = Path.Combine(tempDir, "course_config.json");
            File.WriteAllText(configPath, "{\n  \"course_code\": \"ICS3U\",\n  \"sections\": [1]\n}\n");
            var config = CourseConfiguration.Load(configPath);
            var course = new Course("ICS3U", tempDir, config);

            string? best = SectionIndex.MostRecentPublished(course, 1, new[] { page1, page2 });
            Assert.Equal(page2, best);

            string? bestReversed = SectionIndex.MostRecentPublished(course, 1, new[] { page2, page1 });
            Assert.Equal(page2, bestReversed);
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }
}

public class ProblemReportEnvironmentTests
{
    [Fact]
    public void EnvironmentDescriptions_ArePopulated()
    {
        string app = Plantoir.Core.Scripting.ProblemReportEnvironment.AppDescription;
        string sys = Plantoir.Core.Scripting.ProblemReportEnvironment.SystemDescription;
        string helpers = Plantoir.Core.Scripting.ProblemReportEnvironment.HelperDescription;

        Assert.StartsWith("Plantoir", app);
        Assert.Contains("pid", app);
        Assert.StartsWith("Windows", sys);
        Assert.Contains("cores", sys);
        Assert.Contains("llama.cpp b10435", helpers);
        Assert.Contains(".NET", helpers);
    }
}
