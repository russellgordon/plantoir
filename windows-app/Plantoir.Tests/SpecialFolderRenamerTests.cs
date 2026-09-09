using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Renaming a course folder: the refusals, the moves, and the rule that
/// nothing moves until every destination has been checked.
/// </summary>
public class SpecialFolderRenamerTests : IDisposable
{
    private readonly string _root;

    public SpecialFolderRenamerTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-rename-tests").FullName;
    }

    public void Dispose()
    {
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
    /// contract, and nothing may be in the contract without an entry here.</b>
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
}
