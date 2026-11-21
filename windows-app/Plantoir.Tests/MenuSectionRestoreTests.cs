using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Restore from Backup…'s "Restore Section N" (#911 step 3, the mac's
/// <c>restoreSectionFromTheMenu</c>): the assistant route's staged swap over
/// the section folder AND the section's files outside it, each treated as
/// <c>course-management.json</c> → <c>backups.restoreOneSection.filesOutsideTheSection</c>
/// says (read from the JSON here, never retyped); a shared page made since
/// the backup hidden from the section; the naming asked again of the
/// unpacked backup; the legacy website marker kept across the discarded
/// build; and the <see cref="OneSectionRestore.Outcome"/> counts. Faults have
/// REAL causes (a file held open without delete sharing); only the sweep
/// throws from the move seam, the mac's own shape for it. Content is judged
/// by SHA-256.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class MenuSectionRestoreTests : IDisposable
{
    private readonly SectionSwapFixture _fixture = new();
    public MenuSectionRestoreTests()
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

    private static JsonArray ContractList =>
        ContractLoader.LoadJson("course-management.json")["backups"]!["restoreOneSection"]!["filesOutsideTheSection"]!.AsArray();

    private string InCourse(string relative) => Path.Combine(_fixture.CourseDir, relative.Replace('/', Path.DirectorySeparatorChar));

    private void WriteInCourse(string relative, string text)
    {
        string path = InCourse(relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    /// <summary>Every path the contract lists, for Section 2 and for Section 1, written with <paramref name="state"/> in its bytes.</summary>
    private void PlantEveryListedPath(string state, int section)
    {
        foreach (var entry in ContractList)
        {
            string relative = entry!["path"]!.GetValue<string>().Replace("{N}", section.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (entry["folder"]!.GetValue<bool>()) WriteInCourse(relative + "/Unit 1, Day 1.md", relative + ", " + state);
            else WriteInCourse(relative, "{\"path\": \"" + relative + "\", \"state\": \"" + state + "\"}");
        }
    }

    private BackupItem BackupThenChange()
    {
        _fixture.Write("a.md", "a, as backed up");
        _fixture.Write(Path.Combine("zz notes", "held.md"), "held, as backed up");
        var backup = _fixture.BackUp();
        _fixture.Write("a.md", "a, changed since");
        _fixture.Write(Path.Combine("zz notes", "held.md"), "held, changed since");
        _fixture.Write("made since.md", "made since");
        return backup;
    }

    // ---- the files outside the section, case for case from the JSON -------

    [Fact]
    public void EveryFileOutsideTheSectionIsTreatedAsTheContractSays()
    {
        PlantEveryListedPath("as backed up", 2);
        PlantEveryListedPath("section one", 1);
        _fixture.Write("a.md", "a, as backed up");
        var backup = _fixture.BackUp();
        var section1Before = SectionSwapFixture.Snapshot(_fixture.CourseDir);
        PlantEveryListedPath("changed since", 2);
        var live = new Dictionary<string, string>();
        foreach (var entry in ContractList)
        {
            string relative = entry!["path"]!.GetValue<string>().Replace("{N}", "2");
            string file = entry["folder"]!.GetValue<bool>() ? relative + "/Unit 1, Day 1.md" : relative;
            live[relative] = SectionSwapFixture.Hash(InCourse(file));
        }

        var outcome = CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir);

        int checkedCases = 0;
        foreach (var entry in ContractList)
        {
            string relative = entry!["path"]!.GetValue<string>().Replace("{N}", "2");
            bool folder = entry["folder"]!.GetValue<bool>();
            string file = folder ? relative + "/Unit 1, Day 1.md" : relative;
            string treatment = entry["treatment"]!.GetValue<string>();
            switch (treatment)
            {
                case "fromTheBackup":
                    Assert.True(File.ReadAllText(InCourse(file)).Contains("as backed up", StringComparison.Ordinal), relative + " comes back from the backup");
                    break;
                case "discarded":
                    Assert.False(File.Exists(InCourse(file)) || Directory.Exists(InCourse(relative)), relative + " is discarded");
                    break;
                case "leftAsItIs":
                    Assert.Equal(live[relative], SectionSwapFixture.Hash(InCourse(file)));
                    break;
                default:
                    throw new InvalidOperationException("a treatment called " + treatment + " is not known here");
            }
            checkedCases++;
        }
        Assert.Equal(9, checkedCases);
        // Section 1's files outside its folder, and its folder, are byte for byte as they were.
        var section1Now = SectionSwapFixture.Snapshot(_fixture.CourseDir);
        foreach (var (path, hash) in section1Before)
            if (path.Contains("section1", StringComparison.Ordinal)) Assert.Equal(hash, section1Now[path]);
        // The live markers differ from the backup's, so the finished line says the address is kept.
        Assert.True(outcome.WebsiteRecordDiffers);
        Assert.False(Directory.Exists(_fixture.RestoringDir), "no staging left behind");
    }

    [Fact]
    public void AFileTheBackupLacksIsRemovedWhenItComesFromTheBackupAndKeptAsideUntilTheSwapIsGood()
    {
        _fixture.Write("a.md", "a, as backed up");
        var backup = _fixture.BackUp();
        WriteInCourse(".internal/timetable/section2.json", "{\"made\": \"since\"}");
        string? seenAside = null;

        CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir,
            keepingWhatWasReplaced: aside =>
            {
                seenAside = File.ReadAllText(Path.Combine(aside, "outside", ".internal", "timetable", "section2.json"));
            });

        Assert.False(File.Exists(InCourse(".internal/timetable/section2.json")), "the backup has no class dates for Section 2, so none are left");
        Assert.Equal("{\"made\": \"since\"}", seenAside);   // the Undo seam is handed the aside folder before it goes
        Assert.False(Directory.Exists(_fixture.RestoringDir));
    }

    [Fact]
    public void TheSameWebsiteRecordIsNotADifference()
    {
        WriteInCourse(".netlify_sites/section2.json", "{\"site_id\": \"abc\", \"url\": \"https://x\"}");
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp();
        WriteInCourse(".netlify_sites/section2.json", "{\n    \"url\": \"https://x\",\n    \"site_id\": \"abc\"\n}");

        Assert.False(CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir).WebsiteRecordDiffers);
    }

    // ---- shared pages: keys put back, a page made since hidden -------------

    [Fact]
    public void ASharedPageMadeSinceTheBackupIsHiddenFromTheSectionAndTheFinishedLineSaysSo()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp();
        WriteInCourse("Notes/New page.md", "---\ntitle: New page\npublish: true\n---\nNew.\n");
        WriteInCourse("Notes/Hidden already.md", "---\ntitle: Hidden\npublishForSection2: false\n---\nH.\n");
        WriteInCourse("templates/Class.md", "---\ntitle: Template\n---\nT.\n");
        WriteInCourse(".obsidian/notes.md", "---\ntitle: obsidian\n---\n");
        string hiddenBefore = SectionSwapFixture.Hash(InCourse("Notes/Hidden already.md"));
        string templateBefore = SectionSwapFixture.Hash(InCourse("templates/Class.md"));

        var outcome = CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir);

        string page = File.ReadAllText(InCourse("Notes/New page.md"));
        Assert.True(PageFrontmatter.IsDraft(page, 2), "the page made since is hidden from Section 2");
        Assert.False(PageFrontmatter.IsDraft(page, 1), "and only from Section 2");
        Assert.Equal(hiddenBefore, SectionSwapFixture.Hash(InCourse("Notes/Hidden already.md")));
        Assert.Equal(templateBefore, SectionSwapFixture.Hash(InCourse("templates/Class.md")));
        Assert.Equal(new OneSectionRestore.Outcome(0, 0, 1, false), outcome);
    }

    [Fact]
    public void APageMadeSinceWithNoRoomForAKeyIsCountedAndLeftAsItIs()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp();
        // #186's shape: the block's first line indented, so no column-0 place for a key.
        WriteInCourse("Notes/No room.md", "---\n  title: No room\n---\nN.\n");
        string before = SectionSwapFixture.Hash(InCourse("Notes/No room.md"));

        var outcome = CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir);

        Assert.Equal(1, outcome.PagesNotPutBack);
        Assert.Equal(before, SectionSwapFixture.Hash(InCourse("Notes/No room.md")));
    }

    [Fact]
    public void ThisSectionsKeyOnASharedPageGoesBackToTheBackups()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp();       // Syllabus: publishForSection2: false
        WriteInCourse("Notes/Syllabus.md", "---\ntitle: Syllabus\npublishForSection2: true\npublishForSection1: false\n---\nThe syllabus.\n");

        CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir);

        string page = File.ReadAllText(InCourse("Notes/Syllabus.md"));
        Assert.True(PageFrontmatter.IsDraft(page, 2));
        Assert.True(PageFrontmatter.IsDraft(page, 1), "Section 1's key is not the restore's");
    }

    // ---- refusals of the unpacked backup: nothing moves --------------------

    [Fact]
    public void ANamingChangedSinceTheBackupIsRefusedOfTheUnpackedBackupBeforeAnythingMoves()
    {
        var backup = BackupThenChange();
        string config = InCourse("course_config.json");
        File.WriteAllText(config, File.ReadAllText(config).Replace("\"Unit\"", "\"Module\""));
        var before = SectionSwapFixture.Snapshot(_fixture.CourseDir);

        var error = Assert.Throws<CourseRestorer.RestoreException>(() => CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir));

        Assert.Equal(OneSectionRestoreWording.NamingChanged(2, "ICS3U"), error.Message);
        Assert.Equal(before, SectionSwapFixture.Snapshot(_fixture.CourseDir));
        Assert.False(Directory.Exists(Path.Combine(_fixture.CoursesDir, ".internal")), "nothing left in .internal\\restoring");
    }

    [Fact]
    public void AFolderRemovedSinceTheBackupIsRefused()
    {
        var backup = BackupThenChange();
        string config = InCourse("course_config.json");
        File.WriteAllText(config, File.ReadAllText(config).Replace("\"shared_folders\": [\"Notes\"]", "\"shared_folders\": []"));

        var error = Assert.Throws<CourseRestorer.RestoreException>(() => CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir));

        Assert.Equal(OneSectionRestoreWording.FoldersChanged(2, "ICS3U"), error.Message);
    }

    [Fact]
    public void ASectionNotInTheCourseIsRefused()
    {
        var backup = BackupThenChange();
        var error = Assert.Throws<CourseRestorer.RestoreException>(() => CourseRestorer.RestoreSectionFromTheMenu(3, backup, _fixture.CoursesDir));
        Assert.Equal(OneSectionRestoreWording.SectionNotInCourse(3, "ICS3U"), error.Message);
    }

    // ---- a real fault, and a way back that does not finish -----------------

    [Fact]
    public void AFolderHoldingAnOpenFileLeavesTheSectionAndItsOutsideFilesAsTheyWere()
    {
        PlantEveryListedPath("as backed up", 2);
        var backup = BackupThenChange();
        PlantEveryListedPath("changed since", 2);
        var courseBefore = SectionSwapFixture.Snapshot(_fixture.CourseDir);

        string message;
        using (Hold(Path.Combine(_fixture.Section2, "zz notes", "held.md")))
        {
            message = Assert.Throws<CourseRestorer.RestoreException>(() =>
                CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir)).Message;
        }

        Assert.StartsWith(OneSectionRestoreWording.LeftAsItWas(2, ""), message);
        Assert.Equal(courseBefore, SectionSwapFixture.Snapshot(_fixture.CourseDir));
        Assert.False(Directory.Exists(Path.Combine(_fixture.CoursesDir, ".internal")), "nothing left in .internal\\restoring");
        Assert.DoesNotContain("section restored", _fixture.Trail());
    }

    [Fact]
    public void AWayBackThatDoesNotFinishOnTheMenusRouteSaysTheArchiveIsInArchived()
    {
        var backup = BackupThenChange();
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(_fixture.Section2));
        var handles = new List<FileStream>();
        string? heldAt = null;
        var hooks = new CourseRestorer.SectionSwapHooks
        {
            // The first entry moved aside is held at its new place, so the way
            // back cannot move it; let go once it has failed, so the keep can.
            Move = (source, destination) =>
            {
                try { CourseRestorer.MoveEntry(source, destination); }
                catch when (heldAt is not null && string.Equals(source, heldAt, StringComparison.OrdinalIgnoreCase))
                {
                    foreach (var handle in handles) handle.Dispose();
                    throw;
                }
                if (heldAt is null)
                {
                    heldAt = destination;
                    string file = File.Exists(destination) ? destination : Directory.EnumerateFiles(destination, "*", SearchOption.AllDirectories).First();
                    handles.Add(new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read));
                }
            },
            Reached = _ => { },
        };

        string message;
        using (Hold(Path.Combine(_fixture.Section2, "zz notes", "held.md")))
        {
            message = Assert.Throws<CourseRestorer.SectionRestoreStoppedPartWay>(() =>
                CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir, hooks)).Message;
        }
        foreach (var handle in handles) handle.Dispose();

        string kept = Assert.Single(_fixture.KeptFoldersInBackups());
        Assert.Equal(OneSectionRestoreWording.StoppedPartWay(2, Path.GetRelativePath(_fixture.Folder, kept)) + " " + OneSectionRestoreWording.StoppedPartWayArchived, message);
        Assert.Empty(_fixture.OriginalsMissing(originals, new[] { kept }));
        Assert.Contains("section restore stopped part way", _fixture.Trail());
    }

    // ---- what backups leave out stays; the website marker stays -----------

    [Fact]
    public void AGitFolderAndNodeModulesInTheSectionStayWhereTheyAre()
    {
        _fixture.Write("a.md", "a, as backed up");
        var backup = _fixture.BackUp();
        _fixture.Write("a.md", "a, changed since");
        _fixture.Write(Path.Combine(".git", "objects", "pack", "pack-1.idx"), "a pack file");
        string pack = Path.Combine(_fixture.Section2, ".git", "objects", "pack", "pack-1.idx");
        File.SetAttributes(pack, FileAttributes.ReadOnly);
        _fixture.Write(Path.Combine("node_modules", "x", "index.js"), "module");
        var gitBefore = SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, ".git"));
        var modulesBefore = SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, "node_modules"));

        CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir);

        Assert.Equal(gitBefore, SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, ".git")));
        Assert.Equal(modulesBefore, SectionSwapFixture.Snapshot(Path.Combine(_fixture.Section2, "node_modules")));
        Assert.Equal("a, as backed up", File.ReadAllText(Path.Combine(_fixture.Section2, "a.md")));
        File.SetAttributes(pack, FileAttributes.Normal);
    }

    [Fact]
    public void TheBuiltSiteGoesAndTheLegacyWebsiteMarkerAndTheKeptCopiesStay()
    {
        _fixture.Write("a.md", "a");
        var backup = _fixture.BackUp();
        string buildsRoot = BuildOutputLocation.BuildsRootFor(_fixture.Folder);
        string site = BuildOutputLocation.ForSection(buildsRoot, "ICS3U", 2);
        Directory.CreateDirectory(Path.Combine(site, "public"));
        File.WriteAllText(Path.Combine(site, "public", "index.html"), "<html>built</html>");
        File.WriteAllText(Path.Combine(site, ".netlify_site.json"), "{\"site_id\": \"legacy\"}");
        string keptCopy = Path.Combine(BuildOutputLocation.ForCourse(buildsRoot, "ICS3U"), BuildOutputLocation.KeptCopiesFolderName, "sketch.json");
        Directory.CreateDirectory(Path.GetDirectoryName(keptCopy)!);
        File.WriteAllText(keptCopy, "a kept sketch");

        CourseRestorer.RestoreSectionFromTheMenu(2, backup, _fixture.CoursesDir);

        Assert.False(File.Exists(Path.Combine(site, "public", "index.html")), "the built page is discarded");
        Assert.Equal("{\"site_id\": \"legacy\"}", File.ReadAllText(Path.Combine(site, ".netlify_site.json")));
        Assert.Equal("a kept sketch", File.ReadAllText(keptCopy));
    }

    // ---- the double-failure sweep on the menu's route (the mac's 12 of 91) ---

    /// <summary>
    /// The mac's measured shape on its own route: four section files and six
    /// outside files, a failure at forward move k and way-back move j, for
    /// every k from 2 and j below k. Every original, in the section and
    /// outside it, is kept in every case; the cases that leave the section a
    /// mix are counted and printed for the notes, never held to a number.
    /// </summary>
    [Fact]
    public void EveryDoubleFailureOnTheMenusRouteKeepsEveryOriginalAndTheMixesAreCounted()
    {
        int cases = 0, mixes = 0;
        for (int k = 2; ; k++)
        {
            if (!SweepOne(k, j: 0, out _)) break;
            for (int j = 1; j < k; j++)
            {
                SweepOne(k, j, out bool mix);
                cases++;
                if (mix) mixes++;
            }
        }
        Assert.True(cases > 0);
        Console.WriteLine($"DOUBLE-FAILURE SWEEP (menu): {mixes} of {cases} cases left section2 a mix");
        File.AppendAllText(Path.Combine(Path.GetTempPath(), "plantoir-911-sweep.txt"), $"{DateTime.Now:s} menu route: {mixes} of {cases}\n");
    }

    private static readonly string[] SweepOutside =
    {
        ".internal/timetable/section2.json",
        ".publish_state/section2.published-pages/Unit 1, Day 1.md",
        ".publish_state/section2.links-checklist-answered.json",
        ".publish_state/section2.later-classes-kept.json",
        ".publish_state/section2.front-page-not-today.json",
        ".publish_state/section2.links-checklist.json",
    };

    private static bool SweepOne(int k, int j, out bool mix)
    {
        using var fixture = new SectionSwapFixture();
        void Outside(string relative, string text)
        {
            string path = Path.Combine(fixture.CourseDir, relative.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, text);
        }
        fixture.Write("a.md", "a, backup");
        fixture.Write(".hidden", "hidden, backup");
        fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, backup");
        fixture.Write(Path.Combine("All Classes", "deeper", "x.md"), "x, backup");
        foreach (string relative in SweepOutside) Outside(relative, relative + ", backup");
        var backup = fixture.BackUp();
        var backupFiles = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(fixture.Section2));
        fixture.Write("a.md", "a, live");
        fixture.Write(".hidden", "hidden, live");
        fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, live");
        fixture.Write("made since.md", "made since, live");
        foreach (string relative in SweepOutside) Outside(relative, relative + ", live");
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(fixture.Section2));
        var outsideOriginals = new Dictionary<string, string>();
        foreach (string relative in SweepOutside)
        {
            string native = relative.Replace('/', Path.DirectorySeparatorChar);
            outsideOriginals[native] = SectionSwapFixture.Hash(Path.Combine(fixture.CourseDir, native));
        }

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
        try { CourseRestorer.RestoreSectionFromTheMenu(2, backup, fixture.CoursesDir, hooks); }
        catch (CourseRestorer.RestoreException) { }
        if (!failed) return false;
        if (j == 0) return true;

        var kept = fixture.KeptFoldersInBackups().Concat(fixture.AsideFoldersInStaging()).ToList();
        var missing = fixture.OriginalsMissing(originals, kept);
        foreach (var (relative, hash) in outsideOriginals)
        {
            string live = Path.Combine(fixture.CourseDir, relative);
            if (File.Exists(live) && SectionSwapFixture.Hash(live) == hash) continue;
            bool found = false;
            foreach (string folder in kept)
            {
                string aside = Path.Combine(folder, "outside", relative);
                if (File.Exists(aside) && SectionSwapFixture.Hash(aside) == hash) { found = true; break; }
            }
            if (!found) missing.Add(relative);
        }
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
