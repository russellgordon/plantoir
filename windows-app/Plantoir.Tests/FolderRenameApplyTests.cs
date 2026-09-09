using System.Text;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Renaming a folder from inside the app: the folders move in every section,
/// the links that name it are rewritten, every key that mentioned it follows,
/// and a rename that stopped after the folders moved can be finished.
///
/// <para>The tests that matter most are the ones about NOT doing something:
/// nothing moves when one destination is taken; a phantom entry renamed onto
/// a real second folder is refused, not adopted; the config writer used by
/// Save is unchanged, so Revert still does what it says.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class FolderRenameApplyTests : IDisposable
{
    private readonly string _root;

    public FolderRenameApplyTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-rename-apply").FullName;
        // No line is written here, but the redirect keeps a stray one out of
        // the real trail; the collection is what makes that safe to set.
        ActivityTrail.SetCustomLogPathForTesting(Path.Combine(_root, "trail.txt"));
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string CoursesDir => Path.Combine(_root, "courses");
    private string CourseDir => Path.Combine(CoursesDir, "ICS3U");
    private static readonly int[] Sections = { 1, 2 };

    private string MakeCourse(string configJson)
    {
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "Tasks"));
        Directory.CreateDirectory(Path.Combine(CourseDir, "section2", "Tasks"));
        Directory.CreateDirectory(Path.Combine(CourseDir, "Curriculum"));
        File.WriteAllText(Path.Combine(CourseDir, "section1", "Tasks", "Quiz.md"), "---\ntitle: Quiz\n---\nA quiz.\n");
        File.WriteAllText(Path.Combine(CourseDir, "section1", "index.md"), "---\ntitle: Home\n---\nSee [the quiz](Tasks/Quiz.md) and [[Tasks/Quiz]].\n");
        File.WriteAllText(Path.Combine(CourseDir, "Curriculum", "A1.md"), "---\ntitle: A1\n---\n");
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), configJson);
        return CourseDir;
    }

    private const string Config = """
        {
          "course_code": "ICS3U",
          "section_numbers": [1, 2],
          "shared_folders": ["Notes", "Curriculum"],
          "per_section_folders": ["Tasks", "All Classes"],
          "graded_folders": ["Tasks"],
          "hidden": ["Curriculum", "Tasks"],
          "expandable": ["Tasks"],
          "excluded_items": { "shared": ["Tasks"], "per_section": ["Tasks"] }
        }
        """;

    // ---- The moves and the links ---------------------------------------------

    [Fact]
    public void ARenameMovesEverySectionsFolderAndRewritesTheLinksThatNameIt()
    {
        MakeCourse(Config);

        var outcome = SpecialFolderRenamer.Rename("Tasks", "Assignments", FolderScope.PerSection, CourseDir, Sections);

        Assert.True(outcome.Succeeded);
        Assert.Equal(2, outcome.FoldersMoved);
        Assert.Equal(1, outcome.PagesRelinked);
        Assert.False(Directory.Exists(Path.Combine(CourseDir, "section1", "Tasks")));
        Assert.True(File.Exists(Path.Combine(CourseDir, "section1", "Assignments", "Quiz.md")));
        Assert.True(Directory.Exists(Path.Combine(CourseDir, "section2", "Assignments")));
        string index = File.ReadAllText(Path.Combine(CourseDir, "section1", "index.md"));
        Assert.Contains("(Assignments/Quiz.md)", index);
        Assert.Contains("[[Assignments/Quiz]]", index);
        Assert.Equal(SpecialFolderRenamer.DoneMessage("Tasks", "Assignments", 1), outcome.Message);
        // The record is written before the move and is the caller's to clear
        // once the configuration is written.
        Assert.True(File.Exists(SpecialFolderRenamer.RenameRecordPath(CourseDir)));
    }

    [Fact]
    public void NothingMovesWhenAnyDestinationIsTaken()
    {
        MakeCourse(Config);
        Directory.CreateDirectory(Path.Combine(CourseDir, "section2", "Assignments"));

        var refusal = Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => SpecialFolderRenamer.Rename("Tasks", "Assignments", FolderScope.PerSection, CourseDir, Sections));

        Assert.Equal(SpecialNames.RenameProblemDestinationExists.Replace("{name}", "Assignments"), refusal.Message);
        Assert.True(Directory.Exists(Path.Combine(CourseDir, "section1", "Tasks")), "section 1 was not moved");
        Assert.False(File.Exists(SpecialFolderRenamer.RenameRecordPath(CourseDir)), "nothing started, nothing recorded");
    }

    [Fact]
    public void AFolderThatIsNotOnDiskStillRenamesTheLinksAndSaysBothThings()
    {
        MakeCourse(Config);
        File.WriteAllText(Path.Combine(CourseDir, "section1", "index.md"), "See [notes](Notes/Week%201.md).\n");
        var outcome = SpecialFolderRenamer.Rename("Notes", "Handouts", FolderScope.Shared, CourseDir, Sections);
        Assert.True(outcome.NothingWasThere);
        Assert.Equal(0, outcome.FoldersMoved);
        // The configuration is about to name the new folder, so a page that
        // links into the old name would otherwise be left pointing nowhere.
        Assert.Equal(1, outcome.PagesRelinked);
        Assert.Contains("(Handouts/Week%201.md)", File.ReadAllText(Path.Combine(CourseDir, "section1", "index.md")));
        Assert.StartsWith(SpecialNames.RenameDone.Replace("{old}", "Notes").Replace("{new}", "Handouts"), outcome.Message);
        Assert.EndsWith(SpecialNames.RenameNothingWasThere, outcome.Message);
    }

    [Fact]
    public void ACapitalisationOnlyRenameIsARename()
    {
        MakeCourse(Config);
        Assert.Null(SpecialFolderRenamer.Problem("TASKS", "Tasks", new[] { "Tasks", "All Classes" }));
        var outcome = SpecialFolderRenamer.Rename("Tasks", "TASKS", FolderScope.PerSection, CourseDir, Sections);
        Assert.Equal(2, outcome.FoldersMoved);
        Assert.Equal("TASKS", Path.GetFileName(Directory.GetDirectories(Path.Combine(CourseDir, "section1"), "T*").Single()));
    }

    [Fact]
    public void AddingANameCreatesTheFolderInEverySection()
    {
        MakeCourse(Config);
        Assert.True(SpecialFolderRenamer.CreateFoldersOnDisk("Labs", FolderScope.PerSection, CourseDir, Sections));
        Assert.True(Directory.Exists(Path.Combine(CourseDir, "section1", "Labs")));
        Assert.True(Directory.Exists(Path.Combine(CourseDir, "section2", "Labs")));
        // Already there: nothing made, and nothing said.
        Assert.False(SpecialFolderRenamer.CreateFoldersOnDisk("Labs", FolderScope.PerSection, CourseDir, Sections));
    }

    // ---- The keys that carry across --------------------------------------------

    [Fact]
    public void EveryKeyTheContractSaysCarriesAcrossIsRewritten()
    {
        var values = JObject.Parse(Config);
        var updated = SpecialFolderRenamer.Renaming(values, "Tasks", "Assignments", FolderScope.PerSection);

        Assert.Equal(new[] { "Assignments", "All Classes" }, updated["per_section_folders"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "Assignments" }, updated["graded_folders"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "Curriculum", "Assignments" }, updated["hidden"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "Assignments" }, updated["expandable"]!.Select(t => t.ToString()));
        // This scope's exclusions only: the shared "Tasks" is a different folder.
        Assert.Equal(new[] { "Assignments" }, updated["excluded_items"]!["per_section"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "Tasks" }, updated["excluded_items"]!["shared"]!.Select(t => t.ToString()));
        // Nothing the contract lists is left naming the old folder — except
        // the OTHER scope's exclusion, which names a different folder.
        foreach (string key in SpecialFolderRenamer.KeysThatCarryAcross)
        {
            var token = key == "excluded_items" ? updated[key]?["per_section"] : updated[key];
            Assert.DoesNotContain("\"Tasks\"", token?.ToString(Newtonsoft.Json.Formatting.None) ?? "");
        }
    }

    [Fact]
    public void TheClassFolderAndTheCurriculumFolderAreMaterialisedByARename()
    {
        // A course made from scratch: no class_folder, curriculum_folder null.
        var values = JObject.Parse("""
            {"shared_folders": ["Curriculum", "Notes"], "per_section_folders": ["All Classes", "Tasks"], "curriculum_folder": null}
            """);

        var classRenamed = SpecialFolderRenamer.Renaming(values, "All Classes", "All Days", FolderScope.PerSection);
        Assert.Equal("All Days", classRenamed["class_folder"]!.ToString());

        var curriculumRenamed = SpecialFolderRenamer.Renaming(values, "Curriculum", "Expectations", FolderScope.Shared);
        Assert.Equal("Expectations", curriculumRenamed["curriculum_folder"]!.ToString());

        // Renaming a folder that is NEITHER writes neither key.
        var other = SpecialFolderRenamer.Renaming(values, "Tasks", "Assignments", FolderScope.PerSection);
        Assert.Null(other["class_folder"]);
        Assert.Equal(JTokenType.Null, other["curriculum_folder"]!.Type);

        // A GUESS is never frozen: with nothing recorded and no folder
        // containing "class", the resolver falls back to the first folder,
        // and writing that into class_folder would stop a real "All Classes"
        // added later from ever taking over (the mac's wasSurelyTheClassFolder).
        var guessed = JObject.Parse(@"{""per_section_folders"": [""Lessons"", ""Homework""]}");
        Assert.Null(SpecialFolderRenamer.Renaming(guessed, "Lessons", "Notes", FolderScope.PerSection)["class_folder"]);
        // A recorded key that names a real folder is the answer, "class" or not.
        var recorded = JObject.Parse(@"{""per_section_folders"": [""Lessons"", ""Homework""], ""class_folder"": ""Lessons""}");
        Assert.Equal("Notes", SpecialFolderRenamer.Renaming(recorded, "Lessons", "Notes", FolderScope.PerSection)["class_folder"]!.ToString());
    }

    [Fact]
    public void AScopedKeyIsCarriedOnlyByARenameInItsOwnScope()
    {
        // The mac's contract test, ported: both keys set, the same bare name in
        // both scopes, and a rename in one scope leaves the other's key alone.
        var values = JObject.Parse(@"{""shared_folders"": [""Tasks"", ""Curriculum""], ""per_section_folders"": [""Tasks"", ""All Classes""], ""curriculum_folder"": ""Curriculum"", ""class_folder"": ""Tasks"", ""excluded_items"": {""shared"": [""Tasks""], ""per_section"": [""Tasks""]}}");
        var sharedRenamed = SpecialFolderRenamer.Renaming(values, "Tasks", "Handouts", FolderScope.Shared);
        Assert.Equal("Tasks", sharedRenamed["class_folder"]!.ToString());
        Assert.Equal(new[] { "Tasks", "All Classes" }, sharedRenamed["per_section_folders"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "Tasks" }, sharedRenamed["excluded_items"]!["per_section"]!.Select(t => t.ToString()));
        Assert.Equal(new[] { "Handouts" }, sharedRenamed["excluded_items"]!["shared"]!.Select(t => t.ToString()));

        var curriculumRenamed = SpecialFolderRenamer.Renaming(values, "Curriculum", "Expectations", FolderScope.Shared);
        Assert.Equal("Expectations", curriculumRenamed["curriculum_folder"]!.ToString());
        var perSectionRenamed = SpecialFolderRenamer.Renaming(values, "Tasks", "Assignments", FolderScope.PerSection);
        Assert.Equal("Assignments", perSectionRenamed["class_folder"]!.ToString());
        Assert.Equal("Curriculum", perSectionRenamed["curriculum_folder"]!.ToString());
        Assert.Equal(new[] { "Tasks", "Curriculum" }, perSectionRenamed["shared_folders"]!.Select(t => t.ToString()));
    }

    [Fact]
    public void AListHoldingBothNamesIsLeftWithOne()
    {
        // The starting state of an interrupted rename, by definition.
        Assert.Equal(new[] { "Assignments", "Notes" },
            SpecialFolderRenamer.RenamingInList(new[] { "Tasks", "Assignments", "Notes" }, "Tasks", "Assignments"));
    }

    // ---- The record, and finishing an interrupted rename -------------------------

    [Fact]
    public void AnInterruptedRenameIsRecognisedOnlyWhenTheRecordAndTheDiskAgree()
    {
        MakeCourse(Config);
        // The folders moved; the configuration write never happened.
        SpecialFolderRenamer.Rename("Tasks", "Assignments", FolderScope.PerSection, CourseDir, Sections);

        Assert.Equal("Assignments",
            SpecialFolderRenamer.InterruptedRenameTarget("Tasks", FolderScope.PerSection, CourseDir, Sections));
        // A different scope, or a different folder, is not this rename.
        Assert.Null(SpecialFolderRenamer.InterruptedRenameTarget("Tasks", FolderScope.Shared, CourseDir, Sections));
        Assert.Null(SpecialFolderRenamer.InterruptedRenameTarget("Notes", FolderScope.PerSection, CourseDir, Sections));

        // The clash the record exists to see through: a build has appended the
        // moved folder, so the list names both.
        var namesInUse = new[] { "Tasks", "All Classes", "Assignments" };
        Assert.Equal(SpecialNames.RenameProblemAlreadyUsed.Replace("{name}", "Assignments"),
            SpecialFolderRenamer.Problem("Assignments", "Tasks", namesInUse));
        Assert.Null(SpecialFolderRenamer.Problem("Assignments", "Tasks", namesInUse, isFinishingAnInterruptedRename: true));
        // The waiver is the SHEET's to grant, for the recorded target only:
        // it passes true only when the typed name equals that target, so any
        // other name is checked the ordinary way.
        Assert.NotNull(SpecialFolderRenamer.Problem("All Classes", "Tasks", namesInUse, isFinishingAnInterruptedRename: false));

        // A section still holding the old folder means something else happened.
        Directory.CreateDirectory(Path.Combine(CourseDir, "section2", "Tasks"));
        Assert.Null(SpecialFolderRenamer.InterruptedRenameTarget("Tasks", FolderScope.PerSection, CourseDir, Sections));
    }

    [Fact]
    public void APhantomEntryRenamedOntoARealSecondFolderIsNotAnInterruptedRename()
    {
        // No record: "Tasks" gone, "Assignments" present looks the same on
        // disk, and bypassing would hand the real folder the phantom's
        // attributes — hidden among them.
        MakeCourse(Config);
        Directory.Delete(Path.Combine(CourseDir, "section1", "Tasks"), recursive: true);
        Directory.Delete(Path.Combine(CourseDir, "section2", "Tasks"), recursive: true);
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "Assignments"));

        Assert.Null(SpecialFolderRenamer.InterruptedRenameTarget("Tasks", FolderScope.PerSection, CourseDir, Sections));
        Assert.False(SpecialFolderRenamer.LooksLikeAnInterruptedRename("Tasks", "Assignments", FolderScope.PerSection, CourseDir, Sections));
    }

    [Fact]
    public void TheRecordLivesUnderTheCoursesInternalFolderAndGoesWhenCleared()
    {
        MakeCourse(Config);
        string record = SpecialFolderRenamer.RenameRecordPath(CourseDir);
        Assert.Equal(Path.Combine(CoursesDir, ".internal", "renames", "ICS3U.json"), record);
        SpecialFolderRenamer.RecordRenameStarting("Tasks", "Assignments", FolderScope.PerSection, CourseDir);
        Assert.True(File.Exists(record));
        SpecialFolderRenamer.ClearRenameRecord(CourseDir);
        Assert.False(File.Exists(record));
    }

    // ---- The fresh-read recorder, and the writer Save uses -----------------------

    [Fact]
    public void RecordOnDiskWritesFromAFreshReadAndLeavesOtherUnsavedEditsUnsaved()
    {
        MakeCourse(Config);
        string path = Path.Combine(CourseDir, "course_config.json");
        var config = CourseConfiguration.Load(path);

        // An unsaved edit in the form, and another writer's change on disk.
        config.CourseName = "Computer Science";
        var onDisk = JObject.Parse(File.ReadAllText(path));
        onDisk["unit_word"] = "Module";
        File.WriteAllText(path, onDisk.ToString());

        config.RecordOnDisk(values => SpecialFolderRenamer.Renaming(values, "Tasks", "Assignments", FolderScope.PerSection), path);

        var written = JObject.Parse(File.ReadAllText(path));
        Assert.Equal("Module", written["unit_word"]!.ToString());                 // the other writer's key survives
        Assert.Contains("Assignments", written["per_section_folders"]!.Select(t => t.ToString()));
        Assert.Null(written["course_name"]);                                        // the unsaved edit stayed unsaved
        Assert.Contains("Assignments", config.PerSectionFolders);                   // and the object knows the rename
        // Still dirty — the unsaved name, and ALSO the other writer's key, which
        // the last-saved bytes now carry and the object does not: the same
        // dirtiness the mac's recordOnDisk produces, and Save would then
        // write the object's view over that key. A shared limit, recorded.
        Assert.True(config.HasUnsavedChanges);
        config.DiscardChanges();                                                    // Revert keeps the rename, drops the name
        Assert.Contains("Assignments", config.PerSectionFolders);
        Assert.False(config.HasUnsavedChanges);
    }

    [Fact]
    public void WriteIsUnchangedAndRevertStillDoesWhatItSays()
    {
        MakeCourse(Config);
        string path = Path.Combine(CourseDir, "course_config.json");
        var config = CourseConfiguration.Load(path);
        config.CourseName = "Computer Science";
        config.Write(path);
        Assert.False(config.HasUnsavedChanges);

        // Write does NOT read-compare-write: what is on disk is what this
        // object serialised, whatever another writer put there meanwhile.
        var onDisk = JObject.Parse(File.ReadAllText(path));
        onDisk["unit_word"] = "Module";
        File.WriteAllText(path, onDisk.ToString());
        config.CourseName = "Computing";
        config.Write(path);
        Assert.Null(JObject.Parse(File.ReadAllText(path))["unit_word"]);

        config.CourseName = "Never saved";
        Assert.True(config.HasUnsavedChanges);
        config.DiscardChanges();
        Assert.Equal("Computing", config.CourseName);
    }

    // ---- The sentences -------------------------------------------------------------

    [Fact]
    public void TheFootGunSentencesAndTheInterruptedLineAreTheContractsOwn()
    {
        var names = ContractLoader.LoadJson("shared-rules.json")["specialNames"]!;
        Assert.Equal(names["addCreatesTheFolder"]!["message"]!.ToString(), SpecialNames.AddCreatesTheFolder);
        Assert.Equal(names["removeLeavesTheFolderOnDisk"]!["message"]!.ToString().Replace("on your Mac", "on this PC"),
                     SpecialNames.RemoveLeavesTheFolderOnDisk);
        Assert.Equal(names["renameFolder"]!["interruptedRename"]!["message"]!.ToString(), SpecialNames.RenameInterrupted);
        foreach (string word in new[] { "record", "transaction", "config", "json", "script" })
            Assert.DoesNotContain(word, SpecialNames.RenameInterrupted.ToLowerInvariant());
    }
}
