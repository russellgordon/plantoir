using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8c-1a (the mac's <c>UndoStoppedStepTests</c>; Russell's ruling of
/// 2026-11-26): a one-file settings step whose swap comes back part way is
/// judged AT ONCE by content, with recovery's own settle, and closed: the
/// file holding the new value closes it as made, the old value as put back,
/// neither value by the rule for a file changed by hand; a file the settle
/// cannot read, or a lock not had, leaves it in flight and the door answers
/// "could not finish" with its number, for the caller to offer Put It Back
/// (<see cref="UndoDoor.PutBackAtOnce"/>). Every test runs a LIVE door
/// unless it says shadow.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed partial class UndoStoppedStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-stopped-");
    private static readonly DateOnly Today = new(2026, 11, 20);

    /// <summary>The handles a test holds on the settings file (it cannot be read while one is open).</summary>
    private readonly List<IDisposable> _held = [];

    /// <summary>Each case its own course and list.</summary>
    private string _case = "first";

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, _case, "wf");
    private string ListFolder => Path.Combine(_root, _case, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string ConfigPath => Path.Combine(CourseFolder, "course_config.json");

    // ---- Initializer ---------------------------------------------------------------

    public UndoStoppedStepTests() => LayOutTheCourse();

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        LetGoOfTheFile();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private void LayOutTheCourse()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
        File.WriteAllBytes(ConfigPath, new UTF8Encoding(false).GetBytes(
            "{\n  \"course_code\" : \"ICS3U\",\n  \"course_name\" : \"Introduction to Computer Science\",\n  \"num_sections\" : 1\n}"));
    }

    /// <summary>A fresh course and list, for a test that runs several cases.</summary>
    private void FreshFolders(string name)
    {
        LetGoOfTheFile();
        _case = name;
        LayOutTheCourse();
    }

    private UndoForThisProcess List(UndoMode mode = UndoMode.Live, Action<UndoTrailLine>? trail = null) => new(ListFolder, mode, trail);

    private static UndoDoor Door(UndoForThisProcess list, UndoSeams? seams = null, TimeSpan? finishWait = null) =>
        new(list.Journal, list.Mode, list.Maintainers, seams: seams, finishWait: finishWait, trail: list.Trail);

    private Course TheCourse() => new("ICS3U", CourseFolder, CourseConfiguration.Load(ConfigPath));

    /// <summary>The course filed under 2026–2027 first, a step of its own, so the step under test is the second.</summary>
    private Course CourseIn2026(UndoForThisProcess list)
    {
        Course course = TheCourse();
        Assert.Null(ReferenceCourseUpkeep.WriteSchoolYear(course, 2026, Today, list, Door(list)));
        Assert.Equal(2026, YearOnDisk());
        return TheCourse();
    }

    private int? YearOnDisk()
    {
        JsonNode? year = JsonNode.Parse(File.ReadAllText(ConfigPath))!["reference_school_year"];
        return year is null ? null : (int)year;
    }

    private static int InFlightCount(UndoForThisProcess list)
    {
        int count = 0;
        foreach (UndoFoldedStep step in list.Journal.Read().Folded.Steps.Values)
        {
            if (step.IsInFlight) count++;
        }
        return count;
    }

    private static int StepCount(UndoForThisProcess list) => list.Journal.Read().Folded.Steps.Count;

    private static long NewestSeq(UndoForThisProcess list) => list.Journal.Read().Folded.Highest;

    private static UndoStepState StateOf(UndoForThisProcess list, long seq) => list.Journal.Read().Folded.Steps[seq].State;

    private bool AnythingStagedBeside()
    {
        foreach (string path in Directory.GetFiles(CourseFolder))
        {
            if (Path.GetFileName(path).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    /// <summary>The settings file held open with no sharing: nothing can read it until <see cref="LetGoOfTheFile"/>.</summary>
    private void HoldTheFile() => _held.Add(new FileStream(ConfigPath, FileMode.Open, FileAccess.Read, FileShare.None));

    private void LetGoOfTheFile()
    {
        foreach (IDisposable handle in _held) handle.Dispose();
        _held.Clear();
    }

    /// <summary>What the file holds once a stopped swap has put its new content in (the contract's <c>fileHolds</c>).</summary>
    private enum StoppedWith { TheNewValue, TheOldValue, AThirdValue, HalfWritten, Unreadable }

    private static StoppedWith FileHolds(string word) => Enum.Parse<StoppedWith>(word, ignoreCase: true);

    /// <summary>
    /// Makes the swap of the settings file stop part way while this process
    /// runs on (the mac's <c>stopTheSwapPartWay</c>): another program edits
    /// the file in place as the new content goes in, and the put-back fails,
    /// so the door's swap comes back <c>LeftPartWay</c>. What goes in is the
    /// whole new value, or the old one, a third another program wrote, half
    /// the bytes, or (<see cref="StoppedWith.Unreadable"/>) the new value with
    /// the file then held so that nothing can read it (the settle's read
    /// fails: cannot be read now).
    /// </summary>
    private UndoSeams StopTheSwapPartWay(StoppedWith holding, string oldText = "2026", string newText = "2027", string thirdText = "2030") => new()
    {
        BetweenKeepingAndRenaming = (_, fullPath) =>
        {
            using (var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            {
                inPlace.Seek(0, SeekOrigin.End);
                inPlace.WriteByte((byte)' ');
            }
            string pattern = "." + Path.GetFileName(fullPath) + UndoSwap.StagedMarker + "*-new";
            foreach (string staged in Directory.GetFiles(Path.GetDirectoryName(fullPath)!, pattern))
            {
                string text = File.ReadAllText(staged);
                byte[] bytes = Encoding.UTF8.GetBytes(text);
                byte[]? replacement = holding switch
                {
                    StoppedWith.TheOldValue => Encoding.UTF8.GetBytes(text.Replace(newText, oldText, StringComparison.Ordinal)),
                    StoppedWith.AThirdValue => Encoding.UTF8.GetBytes(text.Replace(newText, thirdText, StringComparison.Ordinal)),
                    StoppedWith.HalfWritten => bytes[..(bytes.Length / 2)],
                    _ => null,
                };
                if (replacement is null) continue;
                using var write = new FileStream(staged, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                write.Write(replacement);
                write.SetLength(replacement.Length);
            }
        },
        PutBackFailsAt = _ =>
        {
            // The new content is in: held now, nothing reads it until the test lets go.
            if (holding == StoppedWith.Unreadable) HoldTheFile();
            return true;
        },
    };

    private UndoActionStep NewStep(UndoForThisProcess list, UndoDoor door) =>
        new(new UndoStepMaker("sheet", "setSchoolYear"), Folder, "ICS3U", section: null, holds: "course", undo: list, door: door);

    /// <summary>Set School Year's own write (<see cref="CourseConfiguration.WriteMemberAsOneStep"/>), the exception it ends with, if any.</summary>
    private Exception? WriteTheYear(Course course, int year, UndoForThisProcess list, UndoDoor door)
    {
        course.Configuration.SetReferenceSchoolYear(year);
        try
        {
            course.Configuration.WriteMemberAsOneStep(ConfigPath, "reference_school_year", () => NewStep(list, door));
            return null;
        }
        catch (Exception error)
        {
            return error;
        }
    }

    /// <summary>Stops the second step at a kill point (a test's), leaving it in flight as a process that died there would.</summary>
    private static UndoSeams StopAt(string point, int index = -1) => new()
    {
        StopsHere = (at, atIndex) => at == point && (index < 0 || atIndex == index),
    };

    // ---- The door's judgement, at every stop point --------------------------------

    /// <summary>
    /// Stopped at each stop point a one-file <c>editJSON</c> step has, then
    /// judged at once: the file holding the new value is closed as made, the
    /// old value as put back; nothing in flight either way, nothing staged
    /// left beside the file, and the next change is not refused. MUST FAIL
    /// without the judgement.
    /// </summary>
    [Theory]
    [InlineData("afterBegin", -1, false)]
    [InlineData("beforeSwap", 0, false)]
    [InlineData("beforeApplied", -1, true)]
    public void AStepStoppedAtEveryPointIsJudgedAtOnceByContent(string point, int index, bool holdsNew)
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        Assert.IsType<UndoStepStoppedByATestException>(WriteTheYear(course, 2027, list, Door(list, StopAt(point, index))));
        long seq = NewestSeq(list);
        Assert.Equal(1, InFlightCount(list));

        UndoStoppedStepVerdict verdict = Door(list).JudgeAtOnce(seq);

        Assert.Equal(0, InFlightCount(list));
        Assert.False(AnythingStagedBeside(), "a staged copy stayed beside the file");
        if (holdsNew)
        {
            Assert.Equal(UndoStoppedStepVerdict.Finished, verdict);
            Assert.Equal(2027, YearOnDisk());
            Assert.Equal(UndoStepState.Done, StateOf(list, seq));
        }
        else
        {
            Assert.Equal(UndoStoppedStepVerdict.PutBack, verdict);
            Assert.Equal(2026, YearOnDisk());
            Assert.NotEqual(UndoStepState.Done, StateOf(list, seq));
        }
        Assert.Null(ReferenceCourseUpkeep.WriteSchoolYear(TheCourse(), 2025, Today, list, Door(list)));
        Assert.Equal(2025, YearOnDisk());
    }

    /// <summary>A file the settle cannot read is left in flight: the judgement says so, for the offer.</summary>
    [Fact]
    public void AStepWhoseFileCannotBeReadIsLeftInFlightForTheOffer()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        Assert.IsType<UndoStepStoppedByATestException>(WriteTheYear(course, 2027, list, Door(list, StopAt("beforeApplied"))));
        HoldTheFile();

        UndoStoppedStepVerdict verdict = Door(list).JudgeAtOnce(NewestSeq(list));

        LetGoOfTheFile();
        Assert.Equal(UndoStoppedStepVerdict.CouldNotFinish, verdict);
        Assert.Equal(1, InFlightCount(list));
    }

    // ---- Set School Year through the door -----------------------------------------

    /// <summary>
    /// Stopped part way with the file holding 2027–2028 whole: saved, nothing
    /// said, nothing in flight, and Undo puts 2026–2027 back as one step.
    /// MUST FAIL before W8c-1a (the step stayed in flight, said as part way).
    /// </summary>
    [Fact]
    public void SetSchoolYearStoppedWithTheNewYearSavesAndSaysNothing()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);

        string? said = ReferenceCourseUpkeep.WriteSchoolYear(course, 2027, Today, list, Door(list, StopTheSwapPartWay(StoppedWith.TheNewValue)));

        Assert.Null(said);
        Assert.Equal(2027, YearOnDisk());
        Assert.Equal(0, InFlightCount(list));
        UndoOutcome undo = Door(list).Undo();
        Assert.Equal(UndoOutcomeKind.Undone, undo.Kind);
        Assert.Equal(2, undo.Seq);
        Assert.Equal(2026, YearOnDisk());
    }

    /// <summary>
    /// Stopped part way with the file unreadable: the step's own exception
    /// for "could not finish", carrying the step's number, never the part-way
    /// one; left in flight. Put It Back then writes 2026–2027 back, closes the
    /// step as put back with recovery's trail line, and the next change is
    /// not refused. MUST FAIL before W8c-1a.
    /// </summary>
    [Fact]
    public void ACouldNotFinishCarriesTheSeqAndPutItBackPutsTheOldYearBack()
    {
        var lines = new List<UndoTrailLine>();
        UndoForThisProcess list = List(trail: lines.Add);
        Course course = CourseIn2026(list);

        Exception? thrown = WriteTheYear(course, 2027, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable)));

        LetGoOfTheFile();
        UndoStepCouldNotFinishException couldNotFinish = Assert.IsType<UndoStepCouldNotFinishException>(thrown);
        Assert.Equal(2, couldNotFinish.Seq);
        Assert.Equal(1, InFlightCount(list));
        Assert.Equal(2027, YearOnDisk());

        Assert.Equal(UndoPutBackVerdict.PutBack, Door(list).PutBackAtOnce(couldNotFinish.Seq));

        Assert.Equal(2026, YearOnDisk());
        Assert.Equal(0, InFlightCount(list));
        Assert.Equal(UndoStepState.RolledBack, StateOf(list, 2));
        Assert.Contains(lines, line => line.Event == ActivityTrail.Event.UndoRolledBack);
        // Only the kept original of what the other program wrote stays (an only copy); nothing staged by the step.
        foreach (string path in Directory.GetFiles(CourseFolder))
        {
            string name = Path.GetFileName(path);
            if (name.Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)) Assert.EndsWith("-orig", name, StringComparison.Ordinal);
        }
        Assert.Null(ReferenceCourseUpkeep.WriteSchoolYear(TheCourse(), 2025, Today, list, Door(list)));
        Assert.Equal(2025, YearOnDisk());
    }

    /// <summary>
    /// A file holding neither value (a third year another program wrote, or
    /// half the bytes): closed by the rule for a file changed by hand, the
    /// list cleared, nothing written over what the file holds, and the step
    /// NEVER retried (one step made, not four). MUST FAIL with "not made"
    /// answered as a changedSince refusal, or as "could not finish".
    /// </summary>
    [Theory]
    [InlineData("aThirdValue")]
    [InlineData("halfWritten")]
    public void AStepWhoseFileHoldsNeitherValueIsNotMadeAndNeverRetried(string word)
    {
        StoppedWith holding = FileHolds(word);
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);

        Exception? thrown = WriteTheYear(course, 2027, list, Door(list, StopTheSwapPartWay(holding)));

        Assert.IsType<UndoStepNotMadeException>(thrown);
        byte[] onDisk = File.ReadAllBytes(ConfigPath);
        Assert.Equal(2, StepCount(list));
        Assert.Equal(0, InFlightCount(list));
        Assert.Equal(UndoStepState.Interrupted, StateOf(list, 2));
        Assert.Equal(UndoOutcomeKind.NothingToUndo, Door(list).Undo().Kind);
        Assert.Equal(onDisk, File.ReadAllBytes(ConfigPath));
        if (holding == StoppedWith.AThirdValue) Assert.Equal(2030, YearOnDisk());
    }

    /// <summary>Save Course Settings retries only a changedSince too: a "not made" is never retried (one step, not four).</summary>
    [Fact]
    public void SaveCourseSettingsNeverRetriesANotMade()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        course.Configuration.Values["course_name"] = "Computer Studies";
        UndoSeams seams = StopTheSwapPartWay(StoppedWith.AThirdValue, oldText: "Introduction to Computer Science",
                                             newText: "Computer Studies", thirdText: "Workshop");

        Assert.Throws<UndoStepNotMadeException>(() => CourseConfiguration.SaveCourseSettings(course, list, Door(list, seams)));

        Assert.Equal(2, StepCount(list));
        Assert.Equal(0, InFlightCount(list));
        Assert.Equal("Workshop", (string?)JsonNode.Parse(File.ReadAllText(ConfigPath))!["course_name"]);
    }

    /// <summary>The same judged directly: a third value is not made, never an offer, and nothing is written over it.</summary>
    [Fact]
    public void JudgedDirectlyAThirdValueIsNotMade()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        Assert.IsType<UndoStepStoppedByATestException>(WriteTheYear(course, 2027, list, Door(list, StopAt("beforeApplied"))));
        File.WriteAllText(ConfigPath, File.ReadAllText(ConfigPath).Replace("2027", "2030", StringComparison.Ordinal));

        Assert.Equal(UndoStoppedStepVerdict.NotMade, Door(list).JudgeAtOnce(NewestSeq(list)));

        Assert.Equal(0, InFlightCount(list));
        Assert.Equal(2030, YearOnDisk());
    }

    // ---- A step already closed, a lock not had -----------------------------------

    /// <summary>A step already closed without the change (put back by an earlier judgement) is not made: never offered, nothing written.</summary>
    [Fact]
    public void AStepAlreadyClosedIsNotOffered()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        Assert.IsType<UndoStepStoppedByATestException>(WriteTheYear(course, 2027, list, Door(list, StopAt("afterBegin"))));
        long seq = NewestSeq(list);
        Assert.Equal(UndoStoppedStepVerdict.PutBack, Door(list).JudgeAtOnce(seq));
        byte[] onDisk = File.ReadAllBytes(ConfigPath);

        Assert.Equal(UndoStoppedStepVerdict.NotMade, Door(list).JudgeAtOnce(seq));

        Assert.Equal(onDisk, File.ReadAllBytes(ConfigPath));
        Assert.Equal(0, InFlightCount(list));
    }

    /// <summary>A step already closed as made is said as made, never offered.</summary>
    [Fact]
    public void AStepAlreadyClosedAsMadeIsFinished()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        Assert.IsType<UndoStepStoppedByATestException>(WriteTheYear(course, 2027, list, Door(list, StopAt("beforeApplied"))));
        long seq = NewestSeq(list);

        Assert.Equal(UndoStoppedStepVerdict.Finished, Door(list).JudgeAtOnce(seq));
        Assert.Equal(UndoStoppedStepVerdict.Finished, Door(list).JudgeAtOnce(seq));
    }

    /// <summary>
    /// The list's lock is held by another process as the swap stops: the
    /// step cannot be judged, so the door answers "could not finish" and the
    /// step stays in flight; Put It Back, once the lock is free, puts the old
    /// year back. MUST FAIL with that branch answered as made.
    /// </summary>
    [Fact]
    public void ALockNotHadLeavesTheStepInFlightForTheOffer()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        AnotherHolder? holder = null;
        UndoSeams stop = StopTheSwapPartWay(StoppedWith.TheNewValue);
        var seams = new UndoSeams
        {
            BetweenKeepingAndRenaming = stop.BetweenKeepingAndRenaming,
            PutBackFailsAt = index =>
            {
                holder ??= new AnotherHolder(new UndoJournal(ListFolder, TimeProvider.System, UndoJournalChecks.ProcessIsAlive,
                                                             _ => true, isLive: true, memory: new UndoProcessMemory()));
                return true;
            },
        };
        Exception? thrown;
        try { thrown = WriteTheYear(course, 2027, list, Door(list, seams, finishWait: TimeSpan.FromMilliseconds(300))); }
        finally { holder?.Dispose(); }

        UndoStepCouldNotFinishException couldNotFinish = Assert.IsType<UndoStepCouldNotFinishException>(thrown);
        Assert.Equal(1, InFlightCount(list));
        Assert.Equal(2027, YearOnDisk());

        Assert.Equal(UndoPutBackVerdict.PutBack, Door(list).PutBackAtOnce(couldNotFinish.Seq));

        Assert.Equal(2026, YearOnDisk());
        Assert.Equal(0, InFlightCount(list));
    }

    // ---- Put It Back ----------------------------------------------------------------

    /// <summary>A member at neither value (another program wrote a third year since): Put It Back refuses and writes nothing; the step stays in flight.</summary>
    [Fact]
    public void PutItBackOfAMemberAtNeitherValueRefusesAndWritesNothing()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        var couldNotFinish = Assert.IsType<UndoStepCouldNotFinishException>(
            WriteTheYear(course, 2027, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable))));
        LetGoOfTheFile();
        File.WriteAllText(ConfigPath, File.ReadAllText(ConfigPath).Replace("2027", "2030", StringComparison.Ordinal));
        byte[] onDisk = File.ReadAllBytes(ConfigPath);

        Assert.Equal(UndoPutBackVerdict.CouldNotPutBack, Door(list).PutBackAtOnce(couldNotFinish.Seq));

        Assert.Equal(onDisk, File.ReadAllBytes(ConfigPath));
        Assert.Equal(1, InFlightCount(list));
    }

    /// <summary>A member that cannot be read now: Put It Back refuses and writes nothing.</summary>
    [Fact]
    public void PutItBackOfAMemberThatCannotBeReadRefuses()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        var couldNotFinish = Assert.IsType<UndoStepCouldNotFinishException>(
            WriteTheYear(course, 2027, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable))));

        UndoPutBackVerdict verdict = Door(list).PutBackAtOnce(couldNotFinish.Seq);

        LetGoOfTheFile();
        Assert.Equal(UndoPutBackVerdict.CouldNotPutBack, verdict);
        Assert.Equal(2027, YearOnDisk());
        Assert.Equal(1, InFlightCount(list));
    }

    /// <summary>
    /// A step closed meanwhile (here judged as made once the file could be
    /// read) is never swapped: Put It Back refuses and the new year stays.
    /// MUST FAIL with Put It Back swapping a step already closed.
    /// </summary>
    [Fact]
    public void PutItBackNeverSwapsAStepClosedMeanwhile()
    {
        UndoForThisProcess list = List();
        Course course = CourseIn2026(list);
        var couldNotFinish = Assert.IsType<UndoStepCouldNotFinishException>(
            WriteTheYear(course, 2027, list, Door(list, StopTheSwapPartWay(StoppedWith.Unreadable))));
        LetGoOfTheFile();
        Assert.Equal(UndoStoppedStepVerdict.Finished, Door(list).JudgeAtOnce(couldNotFinish.Seq));

        Assert.Equal(UndoPutBackVerdict.CouldNotPutBack, Door(list).PutBackAtOnce(couldNotFinish.Seq));

        Assert.Equal(2027, YearOnDisk());
        Assert.Equal(UndoStepState.Done, StateOf(list, couldNotFinish.Seq));
    }

    // ---- Shadow, and the words ------------------------------------------------------

    /// <summary>Shadow (the switch off) keeps today's behaviour: the step is left part way, in flight, never judged. MUST FAIL with the judgement run in shadow too.</summary>
    [Fact]
    public void ShadowLeavesTheStepPartWayAsToday()
    {
        UndoForThisProcess list = List(UndoMode.Shadow);
        Course course = CourseIn2026(list);

        Exception? thrown = WriteTheYear(course, 2027, list, Door(list, StopTheSwapPartWay(StoppedWith.TheNewValue)));

        Assert.IsType<UndoStepLeftPartWayException>(thrown);
        Assert.Equal(1, InFlightCount(list));
    }

    /// <summary>Neither new exception names the file (the mac's <c>testCouldNotFinishNamesNoFile</c>).</summary>
    [Fact]
    public void CouldNotFinishAndNotMadeNameNoFile()
    {
        var refusal = new UndoRefusal(UndoRefusalKind.ChangedSince, "courses/ICS3U/course_config.json");
        Assert.DoesNotContain("course_config", new UndoStepCouldNotFinishException(2, refusal).Message, StringComparison.Ordinal);
        Assert.DoesNotContain("course_config", new UndoStepNotMadeException().Message, StringComparison.Ordinal);
    }

    // ---- The contract's cases ---------------------------------------------------------

    /// <summary>
    /// <c>referenceCourses.settingStoppedCases</c>, run from the JSON through
    /// <see cref="ReferenceCourseUpkeep.WriteSchoolYear"/> with a live door
    /// stopped after its swap: what the teacher reads, whether the step is
    /// left in flight, and what Undo offers then. <c>settingCouldNotBeChanged</c>
    /// is the alert's title (W8c-1b), the step left in flight, its number the
    /// one Put It Back takes.
    /// </summary>
    [Fact]
    public void TheContractsStoppedSettingCases()
    {
        JsonArray cases = ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["settingStoppedCases"]!.AsArray();
        Assert.True(cases.Count >= 5);
        int number = 0;
        foreach (JsonNode? row in cases)
        {
            number++;
            string name = (string)row!["name"]!;
            FreshFolders("case" + number);
            StoppedWith holding = FileHolds((string)row["fileHolds"]!);
            UndoForThisProcess list = List();
            Course course = CourseIn2026(list);

            string? said = ReferenceCourseUpkeep.WriteSchoolYear(course, 2027, Today, list, Door(list, StopTheSwapPartWay(holding)));

            LetGoOfTheFile();
            switch ((string)row["said"]!)
            {
                case "nothing":
                    Assert.True(said is null, name + ": " + said);
                    break;
                case "couldNotSetSchoolYear":
                    Assert.True(said == ReferenceCourse.CouldNotSetSchoolYear(ReferenceCourse.ShownCode(course)), name + ": " + said);
                    break;
                case "settingCouldNotBeChanged":
                    Assert.True(said == ReferenceCourse.SettingCouldNotBeChanged("school year"), name + ": " + said);
                    Assert.Equal(UndoPutBackVerdict.PutBack, Door(list).PutBackAtOnce(2));
                    Assert.True(YearOnDisk() == 2026, name + ": Put It Back did not put the old year back");
                    break;
                default:
                    Assert.Fail(name + ": said '" + (string)row["said"]! + "' is not a value this test knows");
                    break;
            }
            bool inFlight = (bool)row["leftInFlight"]!;
            if (inFlight)
            {
                // Left in flight for the offer: Put It Back above closed it.
                Assert.True(StateOf(list, 2) == UndoStepState.RolledBack, name + ": not left in flight for Put It Back");
                continue;
            }
            Assert.True(InFlightCount(list) == 0, name + ": left in flight");
            UndoOutcome undo = Door(list).Undo();
            switch ((string)row["undoOffers"]!)
            {
                case "theChange":
                    Assert.True(undo.Kind == UndoOutcomeKind.Undone && undo.Seq == 2, name + ": " + undo);
                    break;
                case "theStepBefore":
                    Assert.True(undo.Kind == UndoOutcomeKind.Undone && undo.Seq == 1, name + ": " + undo);
                    break;
                case "nothing":
                    Assert.True(undo.Kind == UndoOutcomeKind.NothingToUndo, name + ": " + undo);
                    break;
                default:
                    Assert.Fail(name + ": undoOffers is not a value this test knows");
                    break;
            }
        }
    }

    /// <summary>Another process holding the list's lock until disposed.</summary>
    private sealed class AnotherHolder : IDisposable
    {
        private readonly ManualResetEventSlim _taken = new();
        private readonly ManualResetEventSlim _release = new();
        private readonly Thread _thread;

        internal AnotherHolder(UndoJournal journal)
        {
            _thread = new Thread(() => journal.WithLock(_ => { _taken.Set(); _release.Wait(); })) { IsBackground = true };
            _thread.Start();
            Assert.True(_taken.Wait(TimeSpan.FromSeconds(30)), "the other holder never got the lock");
        }

        public void Dispose()
        {
            _release.Set();
            _thread.Join();
        }
    }
}
