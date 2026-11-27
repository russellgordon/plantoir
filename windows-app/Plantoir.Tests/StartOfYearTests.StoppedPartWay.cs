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
            _visibleBeforeGo = visibleBefore;
            Assert.NotEmpty(visibleBefore);
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
                    AnswerAsTheCaseSays(name, stopCase["then"]!.ToString(), stop);
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

    /// <summary>
    /// The answer half of a <c>stoppedPartWay</c> case (#899 W8c-2b), as
    /// <c>howToRunAStoppedPartWayCase</c> says: <c>leaveAsItIs</c> changes
    /// nothing (every file of the course and the backup byte for byte as
    /// after Go) and restores nothing; <c>restoreCourse</c> hands the backup
    /// Go made, and only it, to the whole-course restore Restore from Backup…
    /// runs, with no second confirmation.
    /// </summary>
    private void AnswerAsTheCaseSays(string name, string then, StartOfYearStoppedPartWay stop)
    {
        var recorder = new AnswersRecorder(this);
        var offer = new StartOfYearRestoreOffer(stop, () => false);
        switch (then)
        {
            case "leaveAsItIs":
                var before = EveryFileOf(Path.Combine(_folder, "courses", Code), stop.Backup.FilePath);
                Assert.True(offer.LeaveAsItIs(), name);
                // Restore Course after it: answered once, nothing happens.
                Assert.Equal(RestoreCoursePress.AlreadyAnswered, offer.RestoreCourseIsPressed());
                offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
                Assert.Empty(recorder.Restored);
                Assert.Equal(before, EveryFileOf(Path.Combine(_folder, "courses", Code), stop.Backup.FilePath));
                break;
            case "restoreCourse":
                // No second question: the press itself closes the offer.
                Assert.Equal(RestoreCoursePress.Closes, offer.RestoreCourseIsPressed());
                offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
                Assert.Equal(new[] { stop.Backup }, recorder.Restored);
                Assert.Equal(0, InDraftNow(recorder.VisibleBeforeGo));
                break;
            default:
                Assert.Fail($"{name}: a then this replay does not know: {then}");
                break;
        }
    }

    /// <summary>Every file under the course folder, and the backup, with its bytes (hidden files included).</summary>
    private static SortedDictionary<string, string> EveryFileOf(string courseFolder, string backup)
    {
        var files = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (string file in Directory.EnumerateFiles(courseFolder, "*", SearchOption.AllDirectories))
            files[file] = Convert.ToBase64String(File.ReadAllBytes(file));
        files[backup] = Convert.ToBase64String(File.ReadAllBytes(backup));
        return files;
    }

    /// <summary>
    /// The app's answers, recorded: the restore is the REAL whole-course
    /// restore (<see cref="CourseRestorer.RestoreWholeCourse"/>); the previews
    /// are the test's, previewing the sections it is told.
    /// </summary>
    private sealed class AnswersRecorder
    {
        public readonly List<BackupItem> Restored = [];
        public readonly List<string> Calls = [];
        public readonly HashSet<int> Previewing = [];
        public readonly List<string> VisibleBeforeGo;
        public StartOfYearRestoreAnswers Answers { get; }

        public AnswersRecorder(StartOfYearTests test, IReadOnlyCollection<int>? sectionsAfter = null)
        {
            VisibleBeforeGo = test._visibleBeforeGo;
            string folder = test._folder;
            Answers = new StartOfYearRestoreAnswers(
                StopEveryPreviewOfTheCourse: () =>
                {
                    var stopped = Previewing.OrderBy(section => section).ToList();
                    foreach (int section in stopped) Calls.Add("stop " + section);
                    Previewing.Clear();
                    return Task.FromResult<IReadOnlyList<int>>(stopped);
                },
                RestoreWholeCourse: item =>
                {
                    Calls.Add("restore");
                    Restored.Add(item);
                    var workspace = new AssistWorkspace(folder, new FakeLauncher(), undo: new UndoHistory());
                    CourseRestorer.RestoreWholeCourse(item, workspace.Course(item.CourseCode), Workspace.CoursesDirectory(folder));
                    return Task.CompletedTask;
                },
                SectionsOfTheCourseNow: () => sectionsAfter ?? new AssistWorkspace(folder, new FakeLauncher(), undo: new UndoHistory()).Course(Code).Configuration.SectionNumbers,
                IsPreviewing: section => Previewing.Contains(section),
                StartPreview: section =>
                {
                    Calls.Add("start " + section);
                    Previewing.Add(section);
                });
        }
    }

    private List<string> _visibleBeforeGo = [];

    /// <summary>The plain year stopped part way, as the contract's first case, with the pages visible before Go remembered.</summary>
    private StartOfYearStoppedPartWay StopPartWay()
    {
        LayOut(ThePlainYear);
        _visibleBeforeGo = PlannedPagesVisibleNow();
        var outcome = GoWithTheDoor(1, 0, new BackupMaker.Teacher());
        return outcome.StoppedPartWay ?? throw new Xunit.Sdk.XunitException("Go did not stop part way: " + outcome.Message);
    }

    [Fact]
    public void TheOfferSaysTheTwoSentencesInOrderAndNamesNoHiddenFile()
    {
        var stop = StopPartWay();
        var offer = new StartOfYearRestoreOffer(stop, () => false);
        Assert.Equal(new[]
        {
            StartOfYearWording.Fill(StartOfYearWording.StoppedPartWay, ("section", "1"), ("course", Code)),
            StartOfYearWording.Fill(StartOfYearWording.RestoreOffer, ("course", Code), ("backup", Path.GetFileName(stop.Backup.FilePath))),
        }, offer.Sentences);
        foreach (string sentence in offer.Sentences) Assert.DoesNotContain(".plantoir-undo", sentence, StringComparison.Ordinal);
    }

    [Fact]
    public void RestoreCourseRestoresTheBackupGoMadeWithNoSecondQuestion()
    {
        var stop = StopPartWay();
        var recorder = new AnswersRecorder(this);
        var offer = new StartOfYearRestoreOffer(stop, () => false);
        int zipsBefore = Directory.EnumerateFiles(Path.Combine(_folder, "courses"), "*.zip", SearchOption.AllDirectories).Count();
        string trail = TrailWhile(() =>
        {
            Assert.Equal(RestoreCoursePress.Closes, offer.RestoreCourseIsPressed());
            offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
        });
        Assert.Equal(new[] { stop.Backup }, recorder.Restored);
        Assert.Equal(0, InDraftNow(_visibleBeforeGo));
        Assert.Contains("restored", trail, StringComparison.OrdinalIgnoreCase);
        // Archived first, so the course as it was after Go is kept; the backup stays.
        Assert.True(File.Exists(stop.Backup.FilePath));
        Assert.True(Directory.EnumerateFiles(Path.Combine(_folder, "courses"), "*.zip", SearchOption.AllDirectories).Count() > zipsBefore,
            "the course as it was after Go was not archived before the restore");
    }

    [Fact]
    public void ADeployHoldsRestoreCourseBackAndTheOfferStillWorksAfter()
    {
        var stop = StopPartWay();
        var recorder = new AnswersRecorder(this);
        recorder.Previewing.Add(1);
        bool deploying = true;
        var offer = new StartOfYearRestoreOffer(stop, () => deploying);

        Assert.Equal(RestoreCoursePress.HeldBackByADeploy, offer.RestoreCourseIsPressed());
        Assert.False(offer.IsAnswered);
        Assert.Equal(CourseRestorer.BusyTitle(Code) + "\n" + CourseRestorer.BusyMessage, offer.HeldBackSentence);
        // Held back: nothing stopped, nothing restored, even if the restore were asked.
        offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
        Assert.Empty(recorder.Calls);

        deploying = false;
        Assert.Equal(RestoreCoursePress.Closes, offer.RestoreCourseIsPressed());
        offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
        Assert.Equal(new[] { "stop 1", "restore", "start 1" }, recorder.Calls);
    }

    [Fact]
    public void LeaveAsItIsWritesNothingAndKeepsTheBackup()
    {
        var stop = StopPartWay();
        var before = EveryFileOf(Path.Combine(_folder, "courses", Code), stop.Backup.FilePath);
        var recorder = new AnswersRecorder(this);
        var offer = new StartOfYearRestoreOffer(stop, () => false);
        string trail = TrailWhile(() => Assert.True(offer.LeaveAsItIs()));
        Assert.Equal("", trail);
        Assert.Equal(before, EveryFileOf(Path.Combine(_folder, "courses", Code), stop.Backup.FilePath));
        Assert.Empty(recorder.Calls);
    }

    [Fact]
    public void TheOfferIsAnsweredOnceAndAPreviewIsStartedAgainOnce()
    {
        var stop = StopPartWay();
        var recorder = new AnswersRecorder(this);
        recorder.Previewing.Add(1);
        recorder.Previewing.Add(2);
        var offer = new StartOfYearRestoreOffer(stop, () => false);

        Assert.Equal(RestoreCoursePress.Closes, offer.RestoreCourseIsPressed());
        Assert.Equal(RestoreCoursePress.AlreadyAnswered, offer.RestoreCourseIsPressed());
        Assert.False(offer.LeaveAsItIs());
        offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
        offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
        Assert.Equal(new[] { "stop 1", "stop 2", "restore", "start 1", "start 2" }, recorder.Calls);
        Assert.Single(recorder.Restored);
    }

    [Fact]
    public void APreviewOfASectionTheRestoredCourseNoLongerHasIsNotStartedAgain()
    {
        var stop = StopPartWay();
        var recorder = new AnswersRecorder(this, sectionsAfter: [1]);
        recorder.Previewing.Add(1);
        recorder.Previewing.Add(3);
        var offer = new StartOfYearRestoreOffer(stop, () => false);
        Assert.Equal(RestoreCoursePress.Closes, offer.RestoreCourseIsPressed());
        offer.RestoreCourseAsync(recorder.Answers).GetAwaiter().GetResult();
        Assert.Equal(new[] { "stop 1", "stop 3", "restore", "start 1" }, recorder.Calls);
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
