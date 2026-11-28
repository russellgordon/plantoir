using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// Restore from Backup…'s "Restore Section N" holds the Undo list across its
/// swap (#899 W8c-3b1, the mac's <c>UndoRestoreSetAside.swapHoldingTheList</c>
/// and the section cases of <c>UndoRestoreSetAsideRestoreTests</c>): the real
/// restore over a working folder with a live test list of its own. The lock
/// is taken just before the first move and held across the swap, its way
/// back and the per-section keys; once files were replaced, every step in
/// flight is set aside per file inside that lock; a swap that replaced
/// nothing sets nothing aside; a list still busy after the finish wait
/// refuses before anything moves. Each was seen to fail with its behaviour
/// taken out (vm-tools/guest/899-w8c-3b1-mustfail.json).
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoRestoreSetAsideSectionTests : IDisposable
{
    private const string Code = UndoScribe.ThisCourse;
    private const string DayOne = "courses/TST1O/section1/All Classes/Unit 1, Day 1.md";
    private const string DayTwo = "courses/TST1O/section1/All Classes/Unit 1, Day 2.md";
    private const string Syllabus = "courses/TST1O/Notes/Syllabus.md";
    private const string Timetable = "courses/TST1O/.internal/timetable/section1.json";
    private const string OtherOne = "courses/OTH1O/section1/All Classes/a.md";
    private const string OtherTwo = "courses/OTH1O/section1/All Classes/b.md";

    /// <summary>A finish wait for the tests (the door's own seam): a held lock outlasts it.</summary>
    private static readonly TimeSpan TestFinishWait = TimeSpan.FromMilliseconds(200);

    private readonly UndoScribe _scribe = new();
    private readonly string _trailPath;

    public UndoRestoreSetAsideSectionTests()
    {
        _trailPath = Path.Combine(_scribe.FullPath("A", ""), "trail", "activity.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(_trailPath)!);
        ActivityTrail.SetCustomLogPathForTesting(_trailPath);
        string courseDir = _scribe.FullPath("A", "courses/TST1O");
        Directory.CreateDirectory(courseDir);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"),
            """
            {
              "course_code": "TST1O",
              "course_name": "Testing",
              "num_sections": 2,
              "shared_folders": ["Notes"],
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1, 2],
              "unit_word": "Unit"
            }
            """);
        Directory.CreateDirectory(Path.Combine(courseDir, "section2", "All Classes"));
        foreach (string path in new[] { DayOne, DayTwo, Syllabus, Timetable, OtherOne, OtherTwo }) _scribe.WritePage("A", path, Old(path));
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { CourseRestorer.DeleteTree(BuildOutputLocation.BuildsRootFor(_scribe.FullPath("A", ""))); } catch { }
        _scribe.Dispose();
    }

    private static byte[] Old(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: false\n---\nThe lesson.\n");
    private static byte[] New(string path) => Encoding.UTF8.GetBytes($"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\npublish: true\n---\nThe lesson.\n");

    private string CoursesDir => _scribe.FullPath("A", "courses");
    private string CourseDir => _scribe.FullPath("A", "courses/TST1O");
    private string SectionOneDir => _scribe.FullPath("A", "courses/TST1O/section1");

    private UndoListForARestore TheList() =>
        new(_scribe.Journal, UndoMode.Live, line => { lock (_scribe.TrailLines) _scribe.TrailLines.Add(line); }, TestFinishWait);

    /// <summary>The same list as another process holds it: its own journal and memory over the same folder.</summary>
    private UndoJournal AnotherProcessesList() =>
        new(_scribe.JournalFolder, _scribe.Clock, process => true, step => true, isLive: true, memory: new UndoProcessMemory(),
            readRetry: TimeSpan.Zero);

    /// <summary>Whether another process could take the list's lock now, with no wait.</summary>
    private bool AnotherProcessCouldTakeTheLock()
    {
        try
        {
            AnotherProcessesList().WithLock(_ => { }, wait: TimeSpan.Zero);
            return true;
        }
        catch (UndoJournalException error) when (error.Failure == UndoJournalFailure.LockBusy)
        {
            return false;
        }
    }

    /// <summary>A backup of TST1O in which the section's two pages hold what the stopped change was writing (New), so a recovery that judged them would put them back.</summary>
    private BackupItem BackUpHoldingTheNewPages()
    {
        _scribe.WritePage("A", DayOne, New(DayOne));
        _scribe.WritePage("A", DayTwo, New(DayTwo));
        _scribe.WritePage("A", Timetable, New(Timetable));
        Course course = Workspace.DiscoverCourses(_scribe.FullPath("A", "")).First(found => found.Code == Code);
        string path = CourseArchiver.BackUpCourse(course, CoursesDir, new BackupMaker.Assistant(1));
        _scribe.WritePage("A", DayOne, Old(DayOne));
        _scribe.WritePage("A", DayTwo, Old(DayTwo));
        _scribe.WritePage("A", Timetable, Old(Timetable));
        return BackupItem.From(path, Code)!;
    }

    /// <summary>A step made by a process that is then gone, stopped before its swap of the file at <paramref name="stopBefore"/>.</summary>
    private long StopAStep(string[] paths, int stopBefore)
    {
        var changes = new List<(string, byte[]?)>();
        foreach (string path in paths) changes.Add((path, New(path)));
        UndoOutcome stopped = _scribe.Door(new UndoSeams { StopsHere = (at, where) => at == "beforeSwap" && where == stopBefore },
                                           UndoScribe.AProcessThatIsGone).Perform(_scribe.Draft("A", changes));
        Assert.Equal(UndoOutcomeKind.StoppedByATest, stopped.Kind);
        return _scribe.Fold().Steps.Keys.Max();
    }

    private int LinesOnDisk => _scribe.LinesOnDisk;

    private OneSectionRestore.Outcome Restore(BackupItem backup, CourseRestorer.SectionSwapHooks? hooks = null) =>
        CourseRestorer.RestoreSectionFromTheMenu(1, backup, CoursesDir, TheList, hooks);

    /// <summary>Hooks whose move throws at the given calls (1-based; the moves back counted on), real otherwise.</summary>
    private static CourseRestorer.SectionSwapHooks FailingAt(params int[] calls)
    {
        int count = 0;
        return new CourseRestorer.SectionSwapHooks
        {
            Move = (from, to) =>
            {
                count++;
                if (calls.Contains(count)) throw new IOException("a test refused move " + count);
                CourseRestorer.MoveEntry(from, to);
            },
            Reached = _ => { },
        };
    }

    private static bool Same(byte[]? a, byte[]? b) => a is null ? b is null : b is not null && a.AsSpan().SequenceEqual(b);

    private static List<string> Strings(JsonNode? array)
    {
        var found = new List<string>();
        foreach (JsonNode? item in array!.AsArray()) found.Add((string)item!);
        return found;
    }

    private List<JsonObject> LinesAfter(int count)
    {
        var lines = new List<JsonObject>();
        foreach (string text in File.ReadAllLines(_scribe.SegmentPath).Skip(count)) lines.Add(JsonNode.Parse(text)!.AsObject());
        return lines;
    }

    // ---- 1. A step stopped part way in the section ---------------------------

    [Fact]
    public void AStepStoppedInTheSectionIsSetAsideAndRecoveryNeverWritesTheRestoredSection()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        long seq = StopAStep([Syllabus, DayOne, DayTwo], stopBefore: 2);
        Assert.True(Same(New(Syllabus), _scribe.Page("A", Syllabus)));

        Restore(backup);

        UndoFoldedStep step = _scribe.Fold().Steps[seq];
        Assert.Contains(DayOne, step.SetAsidePaths);
        Assert.Contains(DayTwo, step.SetAsidePaths);
        var restored = SectionSwapFixture.Snapshot(SectionOneDir);

        UndoRecoveryRun run = _scribe.Door().Recover();

        Assert.Contains(run.Settled, result => result.Seq == seq);
        Assert.Equal(restored, SectionSwapFixture.Snapshot(SectionOneDir));
        Assert.True(Same(New(DayOne), _scribe.Page("A", DayOne)), "recovery wrote into the restored section");
        Assert.True(Same(Old(Syllabus), _scribe.Page("A", Syllabus)), "the step's file outside the section was not settled");
    }

    // ---- 2. A step partly inside ---------------------------------------------

    [Fact]
    public void AStepPartlyInsideGetsTheEventForTheSectionAndTheOutsideFilesItMoves()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        long seq = StopAStep([Syllabus, Timetable, DayOne], stopBefore: 1);
        int before = LinesOnDisk;

        Restore(backup);

        JsonObject line = Assert.Single(LinesAfter(before), written => (long?)written["seq"] == seq);
        Assert.Equal("filesReplacedByARestore", (string?)line["event"]);
        Assert.Equal(UndoRestoreSetAside.Reason, (string?)line["reason"]);
        List<string> named = Strings(line["paths"]);
        named.Sort(StringComparer.Ordinal);
        var expected = new List<string> { Timetable, DayOne };
        expected.Sort(StringComparer.Ordinal);
        Assert.Equal(expected, named);
        UndoFoldedStep step = _scribe.Fold().Steps[seq];
        Assert.True(step.IsInFlight, "the step stays in flight for its file outside the section");
        Assert.DoesNotContain(Syllabus, step.SetAsidePaths);
    }

    // ---- 3. Another course's step --------------------------------------------

    [Fact]
    public void AStepOfAnotherCourseSurvivesAndIsStillRecovered()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        long seq = StopAStep([OtherOne, OtherTwo], stopBefore: 1);
        Assert.True(Same(New(OtherOne), _scribe.Page("A", OtherOne)));

        Restore(backup);

        UndoFoldedStep step = _scribe.Fold().Steps[seq];
        Assert.True(step.IsInFlight);
        Assert.Empty(step.SetAsidePaths);
        UndoRecoveryRun run = _scribe.Door().Recover();
        Assert.Contains(run.Settled, result => result.Seq == seq);
        Assert.True(Same(Old(OtherOne), _scribe.Page("A", OtherOne)), "the other course's step was not recovered");
    }

    // ---- 4 and 5. Nothing replaced, nothing set aside ------------------------

    [Fact]
    public void AFirstMoveThatFailsSetsNothingAsideAndTheStepIsRecoveredByContent()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        long seq = StopAStep([DayOne, DayTwo], stopBefore: 1);
        int before = LinesOnDisk;

        var refused = Assert.Throws<CourseRestorer.RestoreException>(() => Restore(backup, FailingAt(1)));

        Assert.StartsWith(OneSectionRestoreWording.LeftAsItWas(1, "").TrimEnd(), refused.Message, StringComparison.Ordinal);
        Assert.Empty(LinesAfter(before));
        Assert.Empty(_scribe.Fold().Steps[seq].SetAsidePaths);
        UndoRecoveryRun run = _scribe.Door().Recover();
        Assert.Contains(run.Settled, result => result.Seq == seq);
        Assert.True(Same(Old(DayOne), _scribe.Page("A", DayOne)), "the step was not recovered by content");
    }

    [Fact]
    public void ASwapThatPutsEveryFileBackSetsNothingAsideAndTheStepIsRecoveredByContent()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        long seq = StopAStep([DayOne, DayTwo], stopBefore: 1);
        int before = LinesOnDisk;

        var refused = Assert.Throws<CourseRestorer.RestoreException>(() => Restore(backup, FailingAt(3)));

        Assert.StartsWith(OneSectionRestoreWording.LeftAsItWas(1, "").TrimEnd(), refused.Message, StringComparison.Ordinal);
        Assert.Empty(LinesAfter(before));
        Assert.Empty(_scribe.Fold().Steps[seq].SetAsidePaths);
        UndoRecoveryRun run = _scribe.Door().Recover();
        Assert.Contains(run.Settled, result => result.Seq == seq);
        Assert.True(Same(Old(DayOne), _scribe.Page("A", DayOne)), "the step was not recovered by content");
    }

    // ---- 6. Stopped part way with files moved and not put back ---------------

    [Fact]
    public void ASwapStoppedPartWayWithFilesNotPutBackSetsAside()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        long seq = StopAStep([Syllabus, DayOne, DayTwo], stopBefore: 2);

        Assert.Throws<CourseRestorer.SectionRestoreStoppedPartWay>(() => Restore(backup, FailingAt(3, 4)));

        UndoFoldedStep step = _scribe.Fold().Steps[seq];
        Assert.Contains(DayOne, step.SetAsidePaths);
        Assert.Contains(DayTwo, step.SetAsidePaths);
    }

    // ---- 7 and 9. The lock is held across the swap and the keys --------------

    [Fact]
    public void TheLockIsHeldForEveryMoveOfTheSwap()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        int moves = 0, refused = 0;
        var hooks = new CourseRestorer.SectionSwapHooks
        {
            Move = (from, to) =>
            {
                moves++;
                if (!AnotherProcessCouldTakeTheLock()) refused++;
                CourseRestorer.MoveEntry(from, to);
            },
            Reached = _ => { },
        };

        Restore(backup, hooks);

        Assert.True(moves > 0);
        Assert.Equal(moves, refused);
    }

    [Fact]
    public void ThePerSectionKeysAreWrittenInsideTheLock()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        bool reached = false, refused = false;
        var hooks = new CourseRestorer.SectionSwapHooks
        {
            Move = CourseRestorer.MoveEntry,
            Reached = point =>
            {
                if (point != CourseRestorer.SwapPoint.PerSectionKeysPutBack) return;
                reached = true;
                refused = !AnotherProcessCouldTakeTheLock();
            },
        };

        Restore(backup, hooks);

        Assert.True(reached, "the keys' point was never reached");
        Assert.True(refused, "the keys were written with the lock let go");
    }

    // ---- 8. A busy list refuses before anything moves ------------------------

    [Fact]
    public void ABusyListRefusesBeforeAnythingMoves()
    {
        BackupItem backup = BackUpHoldingTheNewPages();
        var courseBefore = SectionSwapFixture.Snapshot(CourseDir);
        int moves = 0;
        var hooks = new CourseRestorer.SectionSwapHooks
        {
            Move = (from, to) => { moves++; CourseRestorer.MoveEntry(from, to); },
            Reached = _ => { },
        };
        CourseRestorer.RestoreException? refused = null;

        AnotherProcessesList().WithLock(_ =>
        {
            refused = Assert.Throws<CourseRestorer.RestoreException>(() => Restore(backup, hooks));
        });

        Assert.NotNull(refused);
        Assert.Equal(OneSectionRestoreWording.LeftAsItWas(1, "another change in Plantoir was still being made"), refused!.Message);
        Assert.Equal(0, moves);
        Assert.Equal(courseBefore, SectionSwapFixture.Snapshot(CourseDir));
    }
}
