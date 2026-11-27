using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8c-2a (the mac's <c>StartOfYearRestoreOfferTests</c>): Go stopped
/// part way is its own outcome (<see cref="StartOfYearOutcome.StoppedPartWay"/>),
/// told from a stop that changed nothing by the door's exception alone, with
/// the backup Go made as a <see cref="BackupItem"/>, the kept count and the
/// true trail line. <c>startOfYear.stoppedPartWayCases</c> run from the JSON
/// as <c>howToRunAStoppedPartWayCase</c> says, laid out on
/// <c>startOfYear.cases[0]</c>.
/// </summary>
public partial class StartOfYearTests
{
    // ---- Stored properties ---------------------------------------------------------

    /// <summary>Every key of a stopped-part-way case this replay knows; any other fails it.</summary>
    private static readonly HashSet<string> StoppedPartWayKeysChecked = ["name", "door", "expect", "expectInDraft", "then", "why"];

    /// <summary>Every key of a case's <c>door</c> this replay knows.</summary>
    private static readonly HashSet<string> DoorKeysChecked = ["fileInUseAtSwap", "putBackFailsAt"];

    // ---- Functions -------------------------------------------------------------------

    /// <summary>A maker whose backup name <see cref="BackupItem.From"/> cannot read, so no item can be made.</summary>
    private sealed record UnreadableMaker : BackupMaker
    {
        public override string DescriptionFor(ClassNoun noun) => "made by a test";
        public override string NameSuffix => "_not_a_maker_name";
    }

    /// <summary>The trail this test writes, read back; the shared scratch trail is put back after.</summary>
    private static string TrailWhile(Action act)
    {
        string trail = Path.Combine(Path.GetTempPath(), "plantoir-tests", "soy-trail-" + Guid.NewGuid().ToString("N") + ".txt");
        Directory.CreateDirectory(Path.GetDirectoryName(trail)!);
        ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            act();
            return File.Exists(trail) ? File.ReadAllText(trail) : "";
        }
        finally
        {
            ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
            try { File.Delete(trail); } catch { }
        }
    }

    /// <summary>
    /// The app's Go on the plain year, with the door made to fail as the
    /// case's <c>door</c> says: a real holder at <c>fileInUseAtSwap</c> (it
    /// shares reading and writing but not delete, so the rename is refused)
    /// and <c>putBackFailsAt</c>'s put-back refused.
    /// </summary>
    private StartOfYearOutcome GoWithTheDoor(int? fileInUseAtSwap, int? putBackFailsAt, BackupMaker maker)
    {
        string listFolder = Path.Combine(_folder, "state", "undo");
        Directory.CreateDirectory(listFolder);
        FileStream? holder = null;
        var seams = new UndoSeams
        {
            BeforeEachSwap = (index, fullPath) =>
            {
                if (index == fileInUseAtSwap) holder ??= new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            },
            PutBackFailsAt = index => index == putBackFailsAt,
        };
        var workspace = new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory())
        {
            Surface = AssistSurface.Menu,
            UndoList = new UndoForThisProcess(listFolder, UndoMode.Shadow, null),
            UndoSeams = seams,
        };
        try
        {
            return workspace.PrepareForStartOfYear(Code, 1, workspace.PlanStartOfYear(Code, 1).Code,
                StartOfYearAskedFrom.TheApp, maker);
        }
        finally
        {
            holder?.Dispose();
        }
    }

    private static JsonNode ThePlainYear =>
        StartOfYearRule["cases"]!.AsArray().First(x => x!["name"]!.ToString() == "the plain year")!;

    /// <summary>Of the plan's pages that were visible before Go, how many read HIDDEN for section 1 now.</summary>
    private static int InDraftNow(List<string> visibleBefore)
    {
        int inDraft = 0;
        foreach (string full in visibleBefore)
            if (PageFrontmatter.IsDraft(File.ReadAllText(full), 1)) inDraft++;
        return inDraft;
    }

    private List<string> PlannedPagesVisibleNow()
    {
        var visible = new List<string>();
        foreach (var draft in Workspace().PlanStartOfYear(Code, 1).Plan.Drafts)
            if (!PageFrontmatter.IsDraft(File.ReadAllText(draft.Page.Id), 1)) visible.Add(draft.Page.Id);
        return visible;
    }

    [Fact]
    public void StoppedPartWayCasesAsTheContractSays()
    {
        var cases = StartOfYearRule["stoppedPartWayCases"]!.AsArray();
        Assert.Equal(3, cases.Count);
        Assert.Contains("fileInUseAtSwap", StartOfYearRule["howToRunAStoppedPartWayCase"]!.ToString(), StringComparison.Ordinal);
        foreach (JsonNode? node in cases)
        {
            JsonObject stopCase = node!.AsObject();
            string name = stopCase["name"]!.ToString();
            foreach (var (key, _) in stopCase) Assert.True(StoppedPartWayKeysChecked.Contains(key), $"{name}: a key this replay does not check: {key}");
            JsonObject door = stopCase["door"]!.AsObject();
            foreach (var (key, _) in door) Assert.True(DoorKeysChecked.Contains(key), $"{name}: a door key this replay does not check: {key}");
            int? inUseAt = door["fileInUseAtSwap"]?.GetValue<int>();
            int? putBackFailsAt = door["putBackFailsAt"]?.GetValue<int>();

            LayOut(ThePlainYear);
            var visibleBefore = PlannedPagesVisibleNow();
            Assert.Equal(2, visibleBefore.Count);
            StartOfYearOutcome outcome = null!;
            string trail = TrailWhile(() => outcome = GoWithTheDoor(inUseAt, putBackFailsAt, new BackupMaker.Teacher()));

            Assert.True(InDraftNow(visibleBefore) == stopCase["expectInDraft"]!.GetValue<int>(), $"{name}: pages in draft");
            Assert.False(outcome.Changed, name);
            switch (stopCase["expect"]!.ToString())
            {
                case "stoppedPartWay":
                    StartOfYearStoppedPartWay stop = outcome.StoppedPartWay ?? throw new Xunit.Sdk.XunitException($"{name}: not its own outcome: {outcome.Message}");
                    Assert.Equal(1, stop.Section);
                    Assert.Equal(Code, stop.CourseCode);
                    Assert.Equal(1, stop.KeptCount);
                    // The backup item names the zip Go made, and only it.
                    Assert.Equal(outcome.BackupPath, stop.Backup.FilePath);
                    Assert.True(File.Exists(stop.Backup.FilePath), name);
                    Assert.Equal(Code, stop.Backup.CourseCode);
                    Assert.Contains(ActivityTrail.StartOfYearStoppedPartWayLine("from the app", 1, Path.GetFileName(outcome.BackupPath!)), trail, StringComparison.Ordinal);
                    Assert.DoesNotContain("(writeFailed)", trail, StringComparison.Ordinal);
                    Assert.DoesNotContain("nothing was changed", trail, StringComparison.Ordinal);
                    // TODO(W8c-2b): the answer half. `leaveAsItIs`: the sheet's
                    // Leave As It Is changes no file of the course and keeps the
                    // backup, byte for byte; `restoreCourse`: the sheet's
                    // Restore Course hands stop.Backup, and only it, to the
                    // whole-course restore with no second confirmation.
                    Assert.Contains(stopCase["then"]!.ToString(), new[] { "leaveAsItIs", "restoreCourse" });
                    break;
                case "writeFailed":
                    Assert.Null(outcome.StoppedPartWay);
                    Assert.StartsWith("Nothing was changed", outcome.Message, StringComparison.Ordinal);
                    Assert.Contains("did not get ready for the start of the year from the app — nothing was changed (writeFailed)", trail, StringComparison.Ordinal);
                    Assert.DoesNotContain("stopped part way", trail, StringComparison.Ordinal);
                    Assert.Null(stopCase["then"]);
                    break;
                default:
                    Assert.Fail($"{name}: an expect this replay does not know");
                    break;
            }
        }
    }

    /// <summary>The mac's <c>testTheStoppedPartWayLineCountsWhatWasKept</c>: no count, one file, several files.</summary>
    [Fact]
    public void TheStoppedPartWayLineCountsWhatWasKept()
    {
        Assert.Equal("stopped part way getting ready for the start of the year from the app — some pages went into draft; offered the backup TEST_backup_x.zip",
            ActivityTrail.StartOfYearStoppedPartWayLine("from the app", 0, "TEST_backup_x.zip"));
        Assert.Equal("stopped part way getting ready for the start of the year from the app — some pages went into draft, 1 file kept beside its page; offered the backup TEST_backup_x.zip",
            ActivityTrail.StartOfYearStoppedPartWayLine("from the app", 1, "TEST_backup_x.zip"));
        Assert.Equal("stopped part way getting ready for the start of the year from an outside assistant — some pages went into draft, 3 files kept beside their pages; offered the backup TEST_backup_x.zip",
            ActivityTrail.StartOfYearStoppedPartWayLine("from an outside assistant", 3, "TEST_backup_x.zip"));
    }

    /// <summary>
    /// Review 1 of the mac's piece, LOW 1: when no <see cref="BackupItem"/>
    /// can be made of Go's backup, no offer is made and the sheet's
    /// <c>writeFailed</c> words are said, which are true (the backup holds the
    /// course as it was); the trail still says part way, which is true too.
    /// </summary>
    [Fact]
    public void NoOfferWhenNoBackupItemCanBeMade()
    {
        LayOut(ThePlainYear);
        StartOfYearOutcome outcome = null!;
        string trail = TrailWhile(() => outcome = GoWithTheDoor(1, 0, new UnreadableMaker()));

        Assert.Null(outcome.StoppedPartWay);
        Assert.NotNull(outcome.BackupPath);
        Assert.Null(BackupItem.From(outcome.BackupPath!, Code));
        Assert.Equal(StartOfYearWording.Fill(StartOfYearWording.WriteFailed, ("backup", Path.GetFileName(outcome.BackupPath!))), outcome.Message);
        Assert.Contains(ActivityTrail.StartOfYearStoppedPartWayLine("from the app", 1, Path.GetFileName(outcome.BackupPath!)), trail, StringComparison.Ordinal);
    }

    /// <summary>The four restore-offer keys are Windows' own, equal to the contract's, read by key.</summary>
    [Fact]
    public void TheRestoreOfferWordsAreTheContracts()
    {
        var wording = StartOfYearRule["wording"]!.AsObject();
        foreach (string key in new[] { "stoppedPartWay", "restoreOffer", "leaveAsItIsButton", "restoreCourseButton" })
            Assert.True(StartOfYearWording.ByKey.TryGetValue(key, out string? said) && said == wording[key]!.ToString(), $"startOfYear.wording.{key}");
    }
}
