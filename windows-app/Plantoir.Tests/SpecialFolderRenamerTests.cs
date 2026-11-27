using System;
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

    // ------------------------------------------------------- the half failure

    [Fact]
    public void AHalfFinishedRenameNamesTheCountAndTheSectionThatStoppedIt()
    {
        string message = SpecialFolderRenamer.HalfFailureMessage(2, 4, "Tasks", 3, "the folder is in use");
        Assert.Contains("2 of 4", message);
        Assert.Contains("Tasks", message);
        Assert.Contains("section3", message);
        Assert.Contains("the folder is in use", message);
    }

    [Fact]
    public void ASharedFolderSaysWhereRatherThanNamingASection()
    {
        string message = SpecialFolderRenamer.HalfFailureMessage(0, 1, "Curriculum", null, "denied");
        Assert.DoesNotContain("section", message);
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
}
