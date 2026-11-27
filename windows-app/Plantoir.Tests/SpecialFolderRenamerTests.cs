using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Renaming a course folder: the refusals, the moves, and the rule that
/// nothing moves until every destination has been checked; and the
/// interrupted-rename record, which lives only while its own rename is
/// unfinished (#899 W8b-17). In the shared collection because the record's
/// tests read their own trail.
/// </summary>
[Collection(SharedActivityState.Name)]
public class SpecialFolderRenamerTests : IDisposable
{
    private readonly string _root;

    public SpecialFolderRenamerTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-rename-tests").FullName;
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        // A test's read-only file is made writable again, so the folder goes.
        try
        {
            foreach (string file in Directory.EnumerateFiles(_root, "*", SearchOption.AllDirectories))
                File.SetAttributes(file, FileAttributes.Normal);
        }
        catch { }
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Course(params string[] relativeFolders)
    {
        string course = Path.Combine(_root, "ADA1O");
        foreach (string folder in relativeFolders)
            Directory.CreateDirectory(Path.Combine(course, folder));
        Directory.CreateDirectory(course);
        return course;
    }

    // ------------------------------------------------------------- refusals

    [Fact]
    public void AnEmptyNameIsRefused()
    {
        Assert.Equal(SpecialNames.RenameProblemEmpty,
            SpecialFolderRenamer.Problem("", "Tasks", new[] { "Tasks" }));
        Assert.Equal(SpecialNames.RenameProblemEmpty,
            SpecialFolderRenamer.Problem("   ", "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void TheNameItAlreadyHasIsRefused()
    {
        Assert.Equal(SpecialNames.RenameProblemUnchanged,
            SpecialFolderRenamer.Problem("Tasks", "Tasks", new[] { "Tasks" }));
        // A change of capitalisation only is a rename, as on the mac (until
        // 2026-09-07 this side refused it; the filesystem lets it through).
        Assert.Null(SpecialFolderRenamer.Problem("tasks", "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void APathSeparatorIsRefused()
    {
        // The backslash is Windows' own addition to the two the contract names.
        foreach (string bad in new[] { "A/B", "A:B", @"A\B" })
            Assert.Equal(SpecialNames.RenameProblemHasSeparator,
                SpecialFolderRenamer.Problem(bad, "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void ALeadingDotIsRefusedBecauseItWouldHideTheFolder()
    {
        Assert.Equal(SpecialNames.RenameProblemIsHidden,
            SpecialFolderRenamer.Problem(".Tasks", "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void MediaIsPlantoirsOwn()
    {
        Assert.Equal(SpecialNames.RenameProblemIsMedia,
            SpecialFolderRenamer.Problem("Media", "Tasks", new[] { "Tasks" }));
        Assert.Equal(SpecialNames.RenameProblemIsMedia,
            SpecialFolderRenamer.Problem("media", "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void ANameAlreadyInUseIsRefusedAndSaysWhich()
    {
        string? problem = SpecialFolderRenamer.Problem("Handouts", "Tasks", new[] { "Tasks", "Handouts" });
        Assert.NotNull(problem);
        Assert.Contains("Handouts", problem!);
        Assert.DoesNotContain("{name}", problem!);
    }

    [Fact]
    public void ASectionFolderNameIsRefused()
    {
        // "section3" is what Plantoir calls a section's own folder.
        string? problem = SpecialFolderRenamer.Problem("section3", "Tasks", new[] { "Tasks" });
        Assert.NotNull(problem);
        Assert.Contains("section3", problem!);
    }

    [Fact]
    public void AnOrdinaryNameThatMerelyStartsWithSectionIsFine()
    {
        // "Sections" and "section notes" are not what Plantoir calls a section
        // folder, and refusing them would be Plantoir's vocabulary imposed on a
        // teacher's.
        Assert.Null(SpecialFolderRenamer.Problem("Sections", "Tasks", new[] { "Tasks" }));
        Assert.Null(SpecialFolderRenamer.Problem("Section Notes", "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void AnOrdinaryRenameIsAllowed()
    {
        Assert.Null(SpecialFolderRenamer.Problem("Assignments", "Tasks", new[] { "Tasks", "Handouts" }));
    }

    [Fact]
    public void TheClassFolderNeedNotKeepTheWordClass()
    {
        // A refusal to that effect shipped on the mac for a few hours and was
        // reversed the same day: it was Plantoir's vocabulary imposed on a
        // teacher's, and somebody whose units are Threads and whose classes are
        // Days calls the folder "All Days".
        Assert.Null(SpecialFolderRenamer.Problem("All Days", "All Classes", new[] { "All Classes" }));
    }

    // ---------------------------------------------------------------- moves

    [Fact]
    public void ASharedFolderIsOneMoveAtTheCourseRoot()
    {
        string course = Course("Tasks");
        var moves = SpecialFolderRenamer.Moves(course, "Tasks", "Assignments",
                                               FolderScope.Shared, new[] { 1, 2 });
        Assert.Single(moves);
        Assert.Null(moves[0].Section);
        Assert.Equal(Path.Combine(course, "Assignments"), moves[0].To);
    }

    [Fact]
    public void APerSectionFolderMovesInEverySectionThatHasOne()
    {
        string course = Course(@"section1\All Classes", @"section2\All Classes", "section3");
        var moves = SpecialFolderRenamer.Moves(course, "All Classes", "All Days",
                                               FolderScope.PerSection, new[] { 1, 2, 3 });
        // Section 3 has no such folder, and that is not an error: a course can
        // have three sections and the folder in two.
        Assert.Equal(2, moves.Count);
        Assert.Equal(new[] { 1, 2 }, moves.Select(m => m.Section!.Value).ToArray());
    }

    [Fact]
    public void AFolderThatIsNotThereIsNoMoveAtAll()
    {
        string course = Course();
        Assert.Empty(SpecialFolderRenamer.Moves(course, "Tasks", "Assignments",
                                                FolderScope.Shared, new[] { 1 }));
    }

    [Fact]
    public void EveryDestinationIsCheckedBeforeAnythingMoves()
    {
        // The rule that matters most here: Directory.Move refuses a folder with
        // an open handle, and a rename that got half way through four sections
        // would leave a course nobody could reason about.
        string course = Course(@"section1\Tasks", @"section2\Tasks", @"section2\Assignments");
        var moves = SpecialFolderRenamer.Moves(course, "Tasks", "Assignments",
                                               FolderScope.PerSection, new[] { 1, 2 });
        string? why = SpecialFolderRenamer.WhyTheMovesCannotBeMade(moves);
        Assert.NotNull(why);
        Assert.Contains("Assignments", why!);

        // And nothing was moved by asking.
        Assert.True(Directory.Exists(Path.Combine(course, "section1", "Tasks")));
        Assert.True(Directory.Exists(Path.Combine(course, "section2", "Tasks")));
    }

    [Fact]
    public void ClearDestinationsAreAllowed()
    {
        string course = Course(@"section1\Tasks", @"section2\Tasks");
        var moves = SpecialFolderRenamer.Moves(course, "Tasks", "Assignments",
                                               FolderScope.PerSection, new[] { 1, 2 });
        Assert.Null(SpecialFolderRenamer.WhyTheMovesCannotBeMade(moves));
    }

    // ------------------------------------------------------------ the contract

    [Fact]
    public void TheKeysThatCarryAcrossAreTheContractsOwn()
    {
        // The test the handoff says to copy, and the one that catches the
        // failure this feature exists to prevent: a configuration naming a
        // folder that is not there. It FAILS if a key is added to the contract
        // and not to the code.
        var contract = ContractLoader.LoadJson("shared-rules.json")
            ["specialNames"]!["renameFolder"]!["carriesAcross"]!.AsArray()
            .Select(x => x!.ToString()).ToList();

        Assert.Equal(contract, SpecialFolderRenamer.KeysThatCarryAcross.ToList());
        // `hidden` is the dangerous one: a rename that does not carry it
        // silently UN-HIDES the folder, and the next publish puts pages the
        // teacher deliberately hid in front of students.
        Assert.Contains("hidden", SpecialFolderRenamer.KeysThatCarryAcross);
    }

    [Fact]
    public void TheRefusalsAreTheContractsOwnSentences()
    {
        var problems = ContractLoader.LoadJson("shared-rules.json")
            ["specialNames"]!["renameFolder"]!["problems"]!;

        Assert.Equal(problems["empty"]!.ToString(), SpecialNames.RenameProblemEmpty);
        Assert.Equal(problems["unchanged"]!.ToString(), SpecialNames.RenameProblemUnchanged);
        Assert.Equal(problems["hasSeparator"]!.ToString(), SpecialNames.RenameProblemHasSeparator);
        Assert.Equal(problems["isHidden"]!.ToString(), SpecialNames.RenameProblemIsHidden);
        Assert.Equal(problems["isMedia"]!.ToString(), SpecialNames.RenameProblemIsMedia);
        Assert.Equal(problems["alreadyUsed"]!.ToString(), SpecialNames.RenameProblemAlreadyUsed);
        Assert.Equal(problems["looksLikeASection"]!.ToString(), SpecialNames.RenameProblemLooksLikeASection);
        Assert.Equal(problems["destinationExists"]!.ToString(), SpecialNames.RenameProblemDestinationExists);
    }

    [Fact]
    public void TheOutcomeSentencesAreTheContractsOwn()
    {
        var rename = ContractLoader.LoadJson("shared-rules.json")
            ["specialNames"]!["renameFolder"]!;

        Assert.Equal(rename["sheetTitle"]!.ToString(), SpecialNames.RenameSheetTitle);
        Assert.Equal(rename["done"]!.ToString(), SpecialNames.RenameDone);
        Assert.Equal(rename["doneRelinkedOne"]!.ToString(), SpecialNames.RenameRelinkedOne);
        Assert.Equal(rename["doneRelinkedMany"]!.ToString(), SpecialNames.RenameRelinkedMany);
        Assert.Equal(rename["doneRelinkedNone"]!.ToString(), SpecialNames.RenameRelinkedNone);
    }

    /// <summary>
    /// Which sentences name the machine, read from the contract rather than
    /// listed here.
    /// </summary>
    /// <remarks>
    /// <para><b>Nothing may be added to this map without a matching key in the
    /// contract, and nothing may be in the contract without an entry here —
    /// with ONE exception, which is itself checked.</b> A key whose sentence
    /// belongs to a feature this app has not built yet may be held open as a
    /// NAMED GAP in <see cref="NamedGapLedger"/>, and
    /// <c>renameUnitWord.explanation</c> is (GitHub issue #158, v1.3.0). That
    /// is not a hole in the pairing: the ledger fails the moment the key
    /// appears in this map, and fails if the contract stops naming it, so the
    /// exception cannot outlive either half. See the ledger for when one is
    /// allowed.
    /// That pairing is the whole point of driving the test off
    /// <c>platformWording.keys</c>: the mac already fails if a fourth
    /// <c>specialNames</c> sentence contains its platform word and is not
    /// recorded, which pins the RECORD — but until this map existed nothing on
    /// this side READ the list, so a fourth sentence turned the mac red and
    /// still left a Windows test to be written by hand (GitHub issue #118).
    /// </para>
    /// </remarks>
    private static readonly Dictionary<string, string> PlatformWordedSentences = new()
    {
        ["renameFolder.explanation"] = SpecialNames.RenameExplanation,
        ["renameFolder.doneNothingWasThere"] = SpecialNames.RenameNothingWasThere,
        ["removeLeavesTheFolderOnDisk.message"] = SpecialNames.RemoveLeavesTheFolderOnDisk,
        ["renameUnitWord.explanation"] = Plantoir.Core.Models.UnitWordRenameWording.Explanation,
    };

    /// <summary>
    /// Every sentence the contract records as platform-worded says "on this
    /// PC" here, and is otherwise word for word the contract's.
    /// </summary>
    /// <remarks>
    /// <para>Deliberate, and the same difference as "Setting up this Mac"
    /// against "Setting up this PC" — recorded in
    /// <c>shared-rules.json</c> → <c>specialNames.platformWording</c>, shaped
    /// after <c>app-rules.json</c> → <c>markerOrigins.knownDivergence</c>,
    /// which <c>MilestoneContractTests</c> already reads the same way.</para>
    ///
    /// <para>A contract-driven test asserting the stored sentence VERBATIM
    /// would put the word Mac in front of a Windows teacher — a test enforcing
    /// a bug. So it compares everything except the platform word, and asserts
    /// this platform's spelling separately.</para>
    ///
    /// <para><b>Driven off the list, not off three names typed here.</b> Both
    /// directions are checked: a key added to the contract with no sentence on
    /// this side fails by name, and a sentence left in this map after the
    /// contract stopped recording it fails too — so the map cannot become a
    /// record of what once differed.</para>
    /// </remarks>
    [Fact]
    public void EverySentenceTheContractCallsPlatformWordedSaysThisPc()
    {
        var names = ContractLoader.LoadJson("shared-rules.json")["specialNames"]!;
        var wording = names["platformWording"]!;
        string macWord = wording["mac"]!.ToString();
        string windowsWord = wording["windows"]!.ToString();

        var recorded = wording["keys"]!.AsArray()
            .Select(key => key!.ToString()).ToList();
        Assert.NotEmpty(recorded);

        // A key whose sentence belongs to a feature this app has not built yet
        // is NAMED in the ledger with the issue and milestone that own it,
        // rather than quietly dropped here. Every other key is still compared
        // both ways, and the ledger fails if its key starts being worded here
        // or stops being in the contract.
        var deferred = NamedGapLedger.GapsIn(
            NamedGapLedger.PlatformWordedKeys, recorded, PlatformWordedSentences.Keys);
        recorded = recorded.Where(key => !deferred.Contains(key)).ToList();

        Assert.Equal(
            recorded.OrderBy(k => k, StringComparer.Ordinal).ToList(),
            PlatformWordedSentences.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList());

        foreach (string key in recorded)
        {
            // "renameFolder.explanation" walks two steps into specialNames;
            // "removeLeavesTheFolderOnDisk.message" walks two as well. Walked
            // rather than special-cased, so a three-part key added later needs
            // no change here.
            JsonNode? node = names;
            foreach (string step in key.Split('.')) node = node![step];
            string macSentence = node!.ToString();

            string here = PlatformWordedSentences[key];

            Assert.Contains(windowsWord, here);
            Assert.DoesNotContain(macWord, here);
            Assert.Equal(macSentence.Replace(macWord, windowsWord), here);
        }
    }

    [Fact]
    public void TheTwoTrailEventsAreTheOnesTheContractNames()
    {
        Assert.Equal("folder renamed", ActivityTrail.KeyFor(ActivityTrail.Event.FolderRenamed));
        Assert.Equal("folder created", ActivityTrail.KeyFor(ActivityTrail.Event.FolderCreated));
    }

    // ------------------------------ names Windows itself refuses (2026-09-06)

    [Theory]
    [InlineData("CON")]
    [InlineData("con")]
    [InlineData("NUL")]
    [InlineData("COM1")]
    [InlineData("LPT9")]
    [InlineData("PRN.md")]
    public void AReservedWindowsDeviceNameIsRefused(string name)
    {
        // These pass every other check and then fail at the move with whatever
        // the operating system says. Told plainly instead.
        string? problem = SpecialFolderRenamer.Problem(name, "Tasks", new[] { "Tasks" });
        Assert.NotNull(problem);
        Assert.Contains(name, problem!);
    }

    [Theory]
    [InlineData("Tasks.")]
    [InlineData("Tasks ")]
    public void ATrailingDotOrSpaceIsRefused(string name)
    {
        // The trailing dot is the one worth knowing about: Windows strips it,
        // so "Tasks." resolves to "Tasks" and the destination check would have
        // reported "there is already something called Tasks. beside it" about
        // the very folder being renamed.
        Assert.NotNull(SpecialFolderRenamer.Problem(name, "Handouts", new[] { "Tasks", "Handouts" }));
    }

    [Theory]
    [InlineData("a<b")]
    [InlineData("a>b")]
    [InlineData("a|b")]
    [InlineData("a?b")]
    [InlineData("a*b")]
    [InlineData("a\"b")]
    public void ACharacterWindowsForbidsIsRefused(string name)
    {
        Assert.NotNull(SpecialFolderRenamer.Problem(name, "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void AnOrdinaryNameContainingAReservedWordIsStillFine()
    {
        // "CONTENTS" is not "CON". The check is on the whole stem.
        Assert.Null(SpecialFolderRenamer.Problem("Contents", "Tasks", new[] { "Tasks" }));
        Assert.Null(SpecialFolderRenamer.Problem("Console Games", "Tasks", new[] { "Tasks" }));
    }

    [Fact]
    public void ARootedNameCannotMoveTheFolderOutOfTheCourse()
    {
        // Path.Combine with a rooted second argument DISCARDS the first, so
        // this would otherwise move the folder to the root of the drive.
        // Problem() refuses such a name and every caller is meant to ask first,
        // but a move list is not the place to depend on that.
        string course = Course("Tasks");
        Assert.Empty(SpecialFolderRenamer.Moves(course, "Tasks", @"C:\Windows",
                                                FolderScope.Shared, new[] { 1 }));
        Assert.Empty(SpecialFolderRenamer.Moves(course, "Tasks", @"sub\folder",
                                                FolderScope.Shared, new[] { 1 }));
    }

    // ------------------------------------------- the interrupted-rename record (#899 W8b-17)

    /// <summary>The settings, as Course Settings would find them: Tasks per section, Concepts shared and never made on disk.</summary>
    private const string RecordSettings =
        "{\"course_code\":\"ICS3U\",\"section_numbers\":[1,2],\"per_section_folders\":[\"All Classes\",\"Tasks\"],"
        + "\"shared_folders\":[\"Concepts\"],\"hidden\":[\"Tasks\"],\"expandable\":[\"Tasks\"]}";

    /// <summary>An earlier record spelled as no writer here spells it (CRLF, its own spacing), so a put-back that rewrites it shows.</summary>
    private static readonly byte[] AnotherFoldersRecord =
        System.Text.Encoding.UTF8.GetBytes("{\r\n    \"from\": \"Notes\",  \"to\": \"Handouts\",\r\n    \"scope\": \"shared\"\r\n}\r\n");

    private string WorkingFolder => Path.Combine(_root, "wf");
    private string RecordCourse => Path.Combine(WorkingFolder, "courses", "ICS3U");
    private string RecordPath => SpecialFolderRenamer.RenameRecordPath(RecordCourse);
    private string TrailPath => Path.Combine(_root, "trail.txt");

    /// <summary>Two sections with Tasks, section 1's index linking into it: a rename of Tasks moves two folders and relinks two pages.</summary>
    private void TheRecordCourse()
    {
        Directory.CreateDirectory(RecordCourse);
        File.WriteAllText(Path.Combine(WorkingFolder, Workspace.MarkerLauncher), "");
        File.WriteAllText(Path.Combine(RecordCourse, "course_config.json"), RecordSettings);
        WriteInCourse("section1/Tasks/Quiz 1.md", "See [[Tasks/Quiz 2]].\n");
        WriteInCourse("section1/index.md", "Start with [[Tasks/Quiz 1]].\n");
        WriteInCourse("section2/Tasks/Quiz 2.md", "Quiz two.\n");
        ActivityTrail.SetCustomLogPathForTesting(TrailPath);
    }

    private void WriteInCourse(string relative, string text)
    {
        string full = Path.Combine(RecordCourse, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, text);
    }

    private void LayTheRecord(byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(RecordPath)!);
        File.WriteAllBytes(RecordPath, bytes);
    }

    private static byte[] RecordOf(string from, string to, string scope) =>
        System.Text.Encoding.UTF8.GetBytes("{\n  \"from\": \"" + from + "\",\n  \"to\": \"" + to + "\",\n  \"scope\": \"" + scope + "\"\n}\n");

    /// <summary>Rename folder as the sheet makes it: through a door of the test's own, with the settings' change in the step.</summary>
    private RenameOutcome RenameAsTheSheetDoes(string oldName = "Tasks", string newName = "Assessments", FolderScope scope = FolderScope.PerSection,
                                               bool finishing = false, UndoSeams? seams = null)
    {
        var list = new UndoForThisProcess(Path.Combine(_root, "state", "undo"), UndoMode.Shadow, null);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams, trail: list.Trail);
        string configPath = Path.Combine(RecordCourse, "course_config.json");
        var configuration = CourseConfiguration.Load(configPath);
        var settings = SpecialFolderRenamer.RenamingTheSettings(configuration, configPath, oldName, newName, scope, RecordCourse);
        return SpecialFolderRenamer.Rename(oldName, newName, scope, RecordCourse, new[] { 1, 2 }, settings, finishing, list, door);
    }

    private string Trail() => File.Exists(TrailPath) ? File.ReadAllText(TrailPath) : "";

    [Fact]
    public void AnotherFoldersUnfinishedRecordSurvivesAWholeRenameOfThisOneByteForByte()
    {
        TheRecordCourse();
        LayTheRecord(AnotherFoldersRecord);

        var outcome = RenameAsTheSheetDoes();

        Assert.Equal(2, outcome.FoldersMoved);
        Assert.True(File.Exists(RecordPath), "another folder's unfinished rename is not this rename's to clear");
        Assert.Equal(AnotherFoldersRecord, File.ReadAllBytes(RecordPath));
    }

    [Fact]
    public void AWholeRenameWithNoEarlierRecordLeavesNone()
    {
        TheRecordCourse();

        RenameAsTheSheetDoes();

        Assert.False(File.Exists(RecordPath));
        Assert.False(OneSectionRestore.RenameIsUnfinished(RecordCourse));
    }

    [Fact]
    public void TheSameRenamesRecordIsClearedWhenTheRenameIsFinished()
    {
        TheRecordCourse();
        // Interrupted: the folders moved, the settings and links not.
        Directory.Move(Path.Combine(RecordCourse, "section1", "Tasks"), Path.Combine(RecordCourse, "section1", "Assessments"));
        Directory.Move(Path.Combine(RecordCourse, "section2", "Tasks"), Path.Combine(RecordCourse, "section2", "Assessments"));
        LayTheRecord(RecordOf("Tasks", "Assessments", "per_section"));

        var outcome = RenameAsTheSheetDoes(finishing: true);

        Assert.Equal(0, outcome.FoldersMoved);
        Assert.False(File.Exists(RecordPath), "the rename the record names is whole");
    }

    [Fact]
    public void ThisFoldersEarlierRenameToAnotherNameIsClearedOnceTheSettingsNoLongerNameIt()
    {
        TheRecordCourse();
        LayTheRecord(RecordOf("tasks", "Homework", "per_section"));

        RenameAsTheSheetDoes();

        Assert.False(File.Exists(RecordPath), "the settings no longer name Tasks, so its sheet never opens again");
    }

    [Fact]
    public void ARenameThatMovesNoFolderLeavesAnotherFoldersRecordUntouched()
    {
        TheRecordCourse();
        LayTheRecord(AnotherFoldersRecord);
        var written = new DateTime(2026, 1, 2, 3, 4, 5, DateTimeKind.Utc);
        File.SetLastWriteTimeUtc(RecordPath, written);

        // Concepts is in the settings and nowhere on disk.
        var outcome = RenameAsTheSheetDoes("Concepts", "Ideas", FolderScope.Shared);

        Assert.True(outcome.NothingWasThere);
        Assert.Equal(AnotherFoldersRecord, File.ReadAllBytes(RecordPath));
        Assert.Equal(written, File.GetLastWriteTimeUtc(RecordPath));
    }

    [Fact]
    public void ARefusalThatChangedNothingPutsTheEarlierRecordBackByteForByte()
    {
        TheRecordCourse();
        LayTheRecord(AnotherFoldersRecord);

        // The second staged file fails as it is written, as a full disk does: nothing moved.
        Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { StagingWriteFailsAt = index => index == 1 }));

        Assert.True(Directory.Exists(Path.Combine(RecordCourse, "section1", "Tasks")), "nothing moved");
        Assert.Equal(AnotherFoldersRecord, File.ReadAllBytes(RecordPath));
        Assert.DoesNotContain("could not tidy", Trail());
    }

    [Fact]
    public void ARefusalThatChangedNothingLeavesNoRecordWhenThereWasNoneSoTheOneSectionRestoreIsNotGreyed()
    {
        TheRecordCourse();

        Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { StagingWriteFailsAt = index => index == 1 }));

        Assert.True(Directory.Exists(Path.Combine(RecordCourse, "section1", "Tasks")), "nothing moved");
        Assert.False(File.Exists(RecordPath), "a rename that never happened leaves no record");
        Assert.False(OneSectionRestore.RenameIsUnfinished(RecordCourse));
    }

    [Fact]
    public void ARenameThatStoppedPartWayKeepsThisRunsRecord()
    {
        TheRecordCourse();
        LayTheRecord(AnotherFoldersRecord);
        // Section 1's index will not take its relink, and no page can be put
        // back: the step stops part way, the folders' moves left as they are.
        File.SetAttributes(Path.Combine(RecordCourse, "section1", "index.md"), FileAttributes.ReadOnly);

        Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { PutBackFailsAt = _ => true }));

        var note = Newtonsoft.Json.Linq.JObject.Parse(File.ReadAllText(RecordPath));
        Assert.Equal("Tasks", note["from"]?.ToString());
        Assert.Equal("Assessments", note["to"]?.ToString());
        Assert.Equal("per_section", note["scope"]?.ToString());
        Assert.DoesNotContain("could not tidy", Trail());
    }

    /// <summary>The kept record says what this run moves, as the contract's array (#899 W8b-18a).</summary>
    [Fact]
    public void ARenameThatStoppedPartWayKeepsARecordThatSaysWhatItMoves()
    {
        TheRecordCourse();
        File.SetAttributes(Path.Combine(RecordCourse, "section1", "index.md"), FileAttributes.ReadOnly);

        Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { PutBackFailsAt = _ => true }));

        var note = Newtonsoft.Json.Linq.JObject.Parse(File.ReadAllText(RecordPath));
        var moved = note["moved"] as Newtonsoft.Json.Linq.JArray;
        Assert.NotNull(moved);
        Assert.Equal(new[] { "section1/Assessments", "section2/Assessments" }, moved!.Select(place => place.ToString()).ToArray());
        Assert.Null(note["mayHaveMoved"]);
    }

    [Fact]
    public void APutBackThatFailsAfterARefusalSaysDidNotRenameOnTheTrail()
    {
        TheRecordCourse();
        LayTheRecord(AnotherFoldersRecord);
        // The record will take no write: neither this run's nor the put-back.
        File.SetAttributes(RecordPath, FileAttributes.ReadOnly);

        Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { StagingWriteFailsAt = index => index == 1 }));

        string trail = Trail();
        Assert.Contains("did not rename the folder Tasks to Assessments in ICS3U, and could not tidy the note kept while a folder rename is unfinished (", trail);
        Assert.DoesNotContain("renamed the folder Tasks", trail);
    }

    [Fact]
    public void APutBackThatFailsOnceTheRenameIsWholeSaysRenamedOnTheTrail()
    {
        TheRecordCourse();
        LayTheRecord(AnotherFoldersRecord);
        File.SetAttributes(RecordPath, FileAttributes.ReadOnly);

        RenameAsTheSheetDoes();

        string trail = Trail();
        Assert.Contains("renamed the folder Tasks to Assessments in ICS3U, but could not tidy the note kept while a folder rename is unfinished (", trail);
        Assert.DoesNotContain("did not rename", trail);
    }

    // ------------------------------- a rename stopped part way says what the disk shows (#899 W8b-18b)

    /// <summary><c>shared-rules.json</c> → <c>undo.wording.&lt;key&gt;</c>, read by key.</summary>
    private static string Wording(string key) =>
        ContractLoader.LoadJson("shared-rules.json")["undo"]!["wording"]![key]!.ToString();

    /// <summary>The contract's sentence with its places filled and <c>{said}</c> left off: what a sentence must start with.</summary>
    private static string Before(string sentence) => sentence.Substring(0, sentence.IndexOf("{said}", StringComparison.Ordinal));

    /// <summary>The renames a swap tried, as a failing assertion names them.</summary>
    private List<string> Seen { get; } = new();

    private string InCourse(string relative) => Path.Combine(RecordCourse, relative.Replace('/', Path.DirectorySeparatorChar));

    [Fact]
    public void TheRenameSentencesAreTheContractsOwnByKey()
    {
        Assert.Equal(Wording("renameFolderNothingWasChanged"), SpecialNames.RenameFolderNothingWasChanged);
        Assert.Equal(Wording("renameFolderStoppedPartWay"), SpecialNames.RenameFolderStoppedPartWay);
        Assert.Equal(Wording("renameFolderRenamedOnlyInPart"), SpecialNames.RenameFolderRenamedOnlyInPart);
        Assert.Equal(Wording("renameFolderMayBeRenamedInPart"), SpecialNames.RenameFolderMayBeRenamedInPart);
    }

    [Fact]
    public void EachSentenceIsTheContractsWithItsPlaceholdersFilled()
    {
        Assert.Equal(Wording("renameFolderNothingWasChanged").Replace("{old}", "Tasks").Replace("{said}", "S."),
                     SpecialFolderRenamer.NothingWasChanged("Tasks", "S."));

        var none = new SpecialFolderRenamer.LeftAtTheNewName();
        var stopped = SpecialFolderRenamer.PartWayEnding("Tasks", "Assessments", "ICS3U", FolderScope.PerSection, none, 1, "S.");
        Assert.Equal(Wording("renameFolderStoppedPartWay").Replace("{old}", "Tasks").Replace("{said}", "S."), stopped.Sentence);
        Assert.Equal("did not rename the folder Tasks to Assessments in ICS3U, and could not put everything back (per_section_folders, 1 file kept beside its page)",
                     stopped.Line);

        var some = new SpecialFolderRenamer.LeftAtTheNewName();
        some.Places.Add("section1/Assessments");
        some.Places.Add("section2/Assessments");
        some.Unreadable.Add("section3/Assessments (Access is denied.)");
        some.CannotTell.Add("section3/Assessments");
        some.CannotTellWhose.Add("section4/Assessments");
        some.CannotTell.Add("section4/Assessments");
        var part = SpecialFolderRenamer.PartWayEnding("Tasks", "Assessments", "ICS3U", FolderScope.PerSection, some, 2, "S.");
        Assert.Equal(Wording("renameFolderRenamedOnlyInPart").Replace("{old}", "Tasks").Replace("{new}", "Assessments")
                         .Replace("{places}", "“section1/Assessments”, “section2/Assessments”").Replace("{said}", "S."),
                     part.Sentence);
        Assert.Equal("renamed the folder Tasks to Assessments in ICS3U only in part, and could not put everything back (per_section_folders, "
                     + "still called Assessments: section1/Assessments, section2/Assessments; 2 files kept beside their pages"
                     + "; could not tell whether these are at the new name: section3/Assessments (Access is denied.)"
                     + "; could not tell whether this rename moved these: section4/Assessments)",
                     part.Line);

        var maybe = new SpecialFolderRenamer.LeftAtTheNewName();
        maybe.Unreadable.Add("section3/Assessments (Access is denied.)");
        maybe.CannotTell.Add("section3/Assessments");
        maybe.CannotTellWhose.Add("section4/Assessments");
        maybe.CannotTell.Add("section4/Assessments");
        var may = SpecialFolderRenamer.PartWayEnding("Tasks", "Assessments", "ICS3U", FolderScope.Shared, maybe, 0, "S.");
        Assert.Equal(Wording("renameFolderMayBeRenamedInPart").Replace("{old}", "Tasks").Replace("{new}", "Assessments")
                         .Replace("{places}", "“section3/Assessments”, “section4/Assessments”").Replace("{said}", "S."),
                     may.Sentence);
        Assert.Equal("may have renamed the folder Tasks to Assessments in ICS3U only in part, and could not put everything back (shared_folders, "
                     + "0 files kept beside their pages; could not tell whether these are at the new name: section3/Assessments (Access is denied.)"
                     + "; could not tell whether this rename moved these: section4/Assessments)",
                     may.Line);
    }

    /// <summary>A refusal that changed nothing is said in the contract's words around the door's reason.</summary>
    [Fact]
    public void ARefusalThatChangedNothingSaysRenameFolderNothingWasChanged()
    {
        TheRecordCourse();

        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { StagingWriteFailsAt = index => index == 1 }));

        string lead = Before(Wording("renameFolderNothingWasChanged").Replace("{old}", "Tasks"));
        Assert.StartsWith(lead, refused.Message, StringComparison.Ordinal);
        Assert.True(refused.Message.Length > lead.Length, "the door's reason follows");
    }

    /// <summary>
    /// Section 2's old place is taken just as its move is put back (a file
    /// made there), so the move back fails and it stays at the new name;
    /// section 1 goes back. Only section 2 is named, on the sheet and the
    /// trail.
    /// </summary>
    [Fact]
    public void AFolderLeftAtTheNewNameIsNamedAndTheRenameSaysOnlyInPart()
    {
        TheRecordCourse();
        File.SetAttributes(InCourse("section1/index.md"), FileAttributes.ReadOnly);
        string sectionTwosOldPlace = Path.GetFullPath(InCourse("section2/Tasks"));
        var seams = new UndoSeams
        {
            EachRename = (from, onto) =>
            {
                // Compared by their last two parts: the swap names them from the
                // working folder as it reads it, which may be spelled otherwise.
                bool puttingSectionTwoBack = from.Replace('/', '\\').EndsWith(@"\section2\Assessments", StringComparison.OrdinalIgnoreCase)
                    && onto.Replace('/', '\\').EndsWith(@"\section2\Tasks", StringComparison.OrdinalIgnoreCase);
                Seen.Add(from + " -> " + onto);
                if (puttingSectionTwoBack) File.WriteAllText(sectionTwosOldPlace, "made meanwhile");
            },
        };

        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(() => RenameAsTheSheetDoes(seams: seams));

        Assert.True(Directory.Exists(InCourse("section2/Assessments")), "section 2 stayed at the new name; renames: " + string.Join(" | ", Seen) + "; said: " + refused.Message);
        Assert.False(Directory.Exists(InCourse("section1/Assessments")), "section 1 went back");
        Assert.StartsWith(Before(Wording("renameFolderRenamedOnlyInPart").Replace("{old}", "Tasks").Replace("{new}", "Assessments")
                                     .Replace("{places}", "“section2/Assessments”")),
                          refused.Message, StringComparison.Ordinal);
        Assert.Contains("renamed the folder Tasks to Assessments in ICS3U only in part, and could not put everything back (per_section_folders, "
                        + "still called Assessments: section2/Assessments; ", Trail());
        Assert.True(File.Exists(RecordPath), "a part-way rename keeps its record");
    }

    /// <summary>Every folder back at its old name, a page's put-back failed: "did not rename", the kept file counted.</summary>
    [Fact]
    public void EveryFolderBackButAPageKeptSaysDidNotRename()
    {
        TheRecordCourse();
        File.SetAttributes(InCourse("section1/index.md"), FileAttributes.ReadOnly);

        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(seams: new UndoSeams { PutBackFailsAt = _ => true }));

        Assert.True(Directory.Exists(InCourse("section1/Tasks")));
        Assert.True(Directory.Exists(InCourse("section2/Tasks")));
        Assert.StartsWith(Before(Wording("renameFolderStoppedPartWay").Replace("{old}", "Tasks")), refused.Message, StringComparison.Ordinal);
        Assert.Contains("did not rename the folder Tasks to Assessments in ICS3U, and could not put everything back (per_section_folders, ", Trail());
        Assert.Contains(" kept beside ", Trail());
    }

    /// <summary>
    /// A finish of a rename whose record (as a released Windows wrote it)
    /// does not say what it moved: the folders at the new name may be its,
    /// never named, and the sheet says "may have been renamed only in part".
    /// </summary>
    [Fact]
    public void AFinishWhoseRecordDoesNotSayWhatItMovedSaysMayHaveBeenRenamedInPart()
    {
        TheRecordCourse();
        Directory.Move(InCourse("section1/Tasks"), InCourse("section1/Assessments"));
        Directory.Move(InCourse("section2/Tasks"), InCourse("section2/Assessments"));
        byte[] earlier = RecordOf("Tasks", "Assessments", "per_section");
        LayTheRecord(earlier);
        File.SetAttributes(InCourse("section1/index.md"), FileAttributes.ReadOnly);

        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(finishing: true, seams: new UndoSeams { PutBackFailsAt = _ => true }));

        Assert.StartsWith(Before(Wording("renameFolderMayBeRenamedInPart").Replace("{old}", "Tasks").Replace("{new}", "Assessments")
                                     .Replace("{places}", "“section1/Assessments”, “section2/Assessments”")),
                          refused.Message, StringComparison.Ordinal);
        string trail = Trail();
        Assert.Contains("may have renamed the folder Tasks to Assessments in ICS3U only in part, and could not put everything back (per_section_folders, ", trail);
        Assert.Contains("; could not tell whether this rename moved these: section1/Assessments, section2/Assessments)", trail);
        Assert.DoesNotContain("still called", trail);
        Assert.Equal(earlier, File.ReadAllBytes(RecordPath));
    }

    /// <summary>A finish refused with nothing changed keeps the record it was finishing, byte for byte (17's owner).</summary>
    [Fact]
    public void ARefusedFinishKeepsItsRecord()
    {
        TheRecordCourse();
        Directory.Move(InCourse("section1/Tasks"), InCourse("section1/Assessments"));
        Directory.Move(InCourse("section2/Tasks"), InCourse("section2/Assessments"));
        byte[] earlier = RecordOf("Tasks", "Assessments", "per_section");
        LayTheRecord(earlier);

        var refused = Assert.Throws<SpecialFolderRenamer.RenameException>(
            () => RenameAsTheSheetDoes(finishing: true, seams: new UndoSeams { StagingWriteFailsAt = index => index == 1 }));

        Assert.StartsWith(Before(Wording("renameFolderNothingWasChanged").Replace("{old}", "Tasks")), refused.Message, StringComparison.Ordinal);
        Assert.Equal(earlier, File.ReadAllBytes(RecordPath));
    }

    private static SpecialFolderRenamer.RenameRecordNote NoteOf(params string[] moved) =>
        new("Tasks", "Assessments", "per_section", moved, new List<string>());

    /// <summary>A folder at the new name that no move of this run and no record names is never counted: the disk alone does not make it this rename's.</summary>
    [Fact]
    public void AFolderAtTheNewNameThatDoesNotBelongIsNeverNamed()
    {
        Directory.CreateDirectory(InCourse("section1/Assessments"));
        Directory.CreateDirectory(InCourse("section2/Assessments"));

        var left = SpecialFolderRenamer.FoldersAtTheirNewName("Tasks", "Assessments", FolderScope.PerSection, RecordCourse, new[] { 1, 2 },
                                                              new[] { (InCourse("section2/Assessments"), false) }, null);

        Assert.Equal(new[] { "section2/Assessments" }, left.Places);
        Assert.Empty(left.CannotTell);
    }

    /// <summary>A place the earlier record of this rename says it moved belongs, and shows as a folder.</summary>
    [Fact]
    public void APlaceTheEarlierRecordMovedIsNamed()
    {
        Directory.CreateDirectory(InCourse("section1/Assessments"));
        Directory.CreateDirectory(InCourse("section2/Assessments"));

        var left = SpecialFolderRenamer.FoldersAtTheirNewName("Tasks", "Assessments", FolderScope.PerSection, RecordCourse, new[] { 1, 2 },
                                                              Array.Empty<(string, bool)>(), NoteOf("section1/Assessments"));

        Assert.Equal(new[] { "section1/Assessments" }, left.Places);
        Assert.Empty(left.CannotTell);
    }

    /// <summary>A link at the new name is named only where this run moved a link there; any other is cannot-tell, never named.</summary>
    [Fact]
    public void ALinkThisRunDidNotMoveIsCannotTellNeverNamed()
    {
        string library = Path.Combine(_root, "library");
        Directory.CreateDirectory(library);
        UndoKindsForTheCases.MakeAJunction(InCourse("section1/Assessments"), library);
        Directory.CreateDirectory(InCourse("section2/Assessments"));

        var left = SpecialFolderRenamer.FoldersAtTheirNewName("Tasks", "Assessments", FolderScope.PerSection, RecordCourse, new[] { 1, 2 },
                                                              new[] { (InCourse("section1/Assessments"), false) },
                                                              NoteOf("section1/Assessments", "section2/Assessments"));
        Assert.Equal(new[] { "section2/Assessments" }, left.Places);
        Assert.Equal(new[] { "section1/Assessments" }, left.CannotTellWhose);
        Assert.Equal(new[] { "section1/Assessments" }, left.CannotTell);

        var moved = SpecialFolderRenamer.FoldersAtTheirNewName("Tasks", "Assessments", FolderScope.PerSection, RecordCourse, new[] { 1, 2 },
                                                               new[] { (InCourse("section1/Assessments"), true) }, null);
        Assert.Equal(new[] { "section1/Assessments" }, moved.Places);
        Assert.Empty(moved.CannotTell);
    }

    /// <summary>A capitalisation-only rename counts a place only when the folder's listing shows the new spelling.</summary>
    [Fact]
    public void ACapitalisationOnlyRenameIsNamedOnlyWhereTheListingShowsTheNewSpelling()
    {
        Directory.CreateDirectory(InCourse("section1/tasks"));
        Directory.CreateDirectory(InCourse("section2/Tasks"));

        var left = SpecialFolderRenamer.FoldersAtTheirNewName("tasks", "Tasks", FolderScope.PerSection, RecordCourse, new[] { 1, 2 },
                                                              new[] { (InCourse("section1/Tasks"), false), (InCourse("section2/Tasks"), false) }, null);

        Assert.Equal(new[] { "section2/Tasks" }, left.Places);
        Assert.Empty(left.CannotTell);
    }

    /// <summary>A check that fails for any reason but "no such file" is told with the system's reason, never read as absent.</summary>
    [Fact]
    public void AnUnreadableCheckIsToldWithItsReasonNeverReadAsAbsent()
    {
        Directory.CreateDirectory(InCourse("section1/Assessments"));
        Directory.CreateDirectory(InCourse("section2/Assessments"));
        string refused = InCourse("section1/Assessments");
        SpecialFolderRenamer.LookingAtAPlaceFails = path =>
            string.Equals(Path.GetFullPath(path), Path.GetFullPath(refused), StringComparison.OrdinalIgnoreCase) ? "Access to the path is denied." : null;
        try
        {
            var left = SpecialFolderRenamer.FoldersAtTheirNewName("Tasks", "Assessments", FolderScope.PerSection, RecordCourse, new[] { 1, 2 },
                                                                  new[] { (InCourse("section1/Assessments"), false), (InCourse("section2/Assessments"), false) }, null);

            Assert.Equal(new[] { "section2/Assessments" }, left.Places);
            Assert.Equal(new[] { "section1/Assessments (Access to the path is denied.)" }, left.Unreadable);
            Assert.Equal(new[] { "section1/Assessments" }, left.CannotTell);
            Assert.Empty(left.CannotTellWhose);
        }
        finally { SpecialFolderRenamer.LookingAtAPlaceFails = null; }
    }
}
