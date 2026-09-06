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
        // Case-insensitively, because the filesystem is.
        Assert.Equal(SpecialNames.RenameProblemUnchanged,
            SpecialFolderRenamer.Problem("tasks", "Tasks", new[] { "Tasks" }));
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

    [Fact]
    public void TheTwoPlatformWordedSentencesSayThisPcRatherThanYourMac()
    {
        // Deliberate, and the same difference as "Setting up this Mac" against
        // "Setting up this PC". Asserted so that a future sync of the contract
        // cannot quietly put "your Mac" in front of a Windows teacher.
        Assert.Contains("on this PC", SpecialNames.RenameExplanation);
        Assert.DoesNotContain("your Mac", SpecialNames.RenameExplanation);
        Assert.Contains("on this PC", SpecialNames.RenameNothingWasThere);
        Assert.DoesNotContain("your Mac", SpecialNames.RenameNothingWasThere);

        // ...and otherwise word for word the contract's.
        var rename = ContractLoader.LoadJson("shared-rules.json")
            ["specialNames"]!["renameFolder"]!;
        Assert.Equal(rename["explanation"]!.ToString().Replace("on your Mac", "on this PC"),
                     SpecialNames.RenameExplanation);
        Assert.Equal(rename["doneNothingWasThere"]!.ToString().Replace("on your Mac", "on this PC"),
                     SpecialNames.RenameNothingWasThere);
    }

    [Fact]
    public void TheTwoTrailEventsAreTheOnesTheContractNames()
    {
        Assert.Equal("folder renamed", ActivityTrail.KeyFor(ActivityTrail.Event.FolderRenamed));
        Assert.Equal("folder created", ActivityTrail.KeyFor(ActivityTrail.Event.FolderCreated));
    }
}
