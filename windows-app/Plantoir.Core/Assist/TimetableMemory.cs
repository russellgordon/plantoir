using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Assist;

/// <summary>
/// The dates a section actually meets, written down once and reused.
///
/// A teacher answers "when does this class meet?" by finding a spreadsheet,
/// working out which column is their block, and handing it over. That is a
/// genuinely annoying five minutes, and until now every conversation asked for
/// it again — a new session, a new assistant, or simply tomorrow, and the
/// teacher was back in the timetable file.
///
/// So the answer is kept. Everything that needs to know when classes fall —
/// inserting a class and pushing the rest along, adding a test day to each
/// unit, laying down placeholder pages for a unit that has not been written
/// yet — reads it from here rather than asking again.
///
/// It lives INSIDE the course folder, under <c>.internal/</c>, for one
/// practical reason: it then travels with the course through backup, archive
/// and restore, which are already careful about that folder. A file kept
/// beside the app would come adrift from the course the first time a teacher
/// moved their work to a new machine, and be silently wrong rather than
/// missing — the worse of the two failures.
/// </summary>
public sealed class TimetableMemory
{
    /// <summary>Every date this section meets, in order, earliest first.</summary>
    public required IReadOnlyList<DateOnly> Dates { get; init; }

    /// <summary>
    /// Where these came from, in the teacher's terms — "timetable.xlsx, block
    /// H", "typed in by hand". Shown when the assistant says what it is about
    /// to use, so a teacher can recognise a stale answer and say so.
    /// </summary>
    public required string Source { get; init; }

    /// <summary>When this was written down.</summary>
    public required DateOnly Recorded { get; init; }

    /// <summary>The meeting dates from today onwards — the ones still to come.</summary>
    public IReadOnlyList<DateOnly> From(DateOnly day) =>
        Dates.Where(date => date >= day).ToList();

    /// <summary>
    /// How many meeting dates are left after <paramref name="taken"/> have been
    /// used. The insert-and-shift operations need this to answer "does this
    /// fit?" before they touch anything.
    /// </summary>
    public int SpareAfter(int taken) => Math.Max(0, Dates.Count - taken);

    // ---- On disk ---------------------------------------------------------

    private static string FileFor(string workspacePath, string courseCode, int sectionNumber) =>
        Path.Combine(Workspace.CoursesDirectory(workspacePath), courseCode.ToUpperInvariant(),
            ".internal", "timetable", $"section{sectionNumber}.json");

    /// <summary>
    /// The earliest class date a remembered timetable can hold and be
    /// believed. Generous on purpose — a teacher may type last year's dates —
    /// and still centuries clear of every wrong reading a calendar can
    /// produce: a Buddhist year read as Gregorian is 2569, a Gregorian year
    /// read as Buddhist is 1483, and an Umm al-Qura one is 1448.
    /// </summary>
    public static readonly DateOnly EarliestBelievable = new(2000, 1, 1);

    /// <summary>
    /// How far past today a remembered class may fall and be believed. A
    /// school year is one; three is generous. The nearest wrong reading is
    /// 543 years out, so any figure between the two works.
    /// </summary>
    public const int YearsAheadBelievable = 3;

    /// <summary>
    /// The first of <paramref name="dates"/> that cannot be a class date —
    /// before <see cref="EarliestBelievable"/> or more than
    /// <see cref="YearsAheadBelievable"/> years past <paramref name="today"/> —
    /// or null when every one of them can. <see cref="Write"/> refuses such a
    /// list and <see cref="Read"/> disbelieves such a file, so what one
    /// accepts the other believes: a tool that saved and then read back
    /// would otherwise find nothing where it had just written.
    /// </summary>
    /// <summary>
    /// Every date <see cref="Unbelievable"/> would refuse, once each, in the
    /// order given: the Class Dates dialog names them all, as the mac does
    /// (#1027 review 2, low 5).
    /// </summary>
    public static IReadOnlyList<DateOnly> EveryUnbelievable(IEnumerable<DateOnly> dates, DateOnly today)
    {
        DateOnly ceiling = today.AddYears(YearsAheadBelievable);
        var refused = new List<DateOnly>();
        foreach (var date in dates)
        {
            if ((date < EarliestBelievable || date > ceiling) && !refused.Contains(date)) refused.Add(date);
        }
        return refused;
    }

    public static DateOnly? Unbelievable(IEnumerable<DateOnly> dates, DateOnly today)
    {
        DateOnly ceiling = today.AddYears(YearsAheadBelievable);
        return dates.Where(date => date < EarliestBelievable || date > ceiling)
                    .Select(date => (DateOnly?)date)
                    .FirstOrDefault();
    }

    /// <summary>
    /// What was remembered for this section, or null if nothing was — or if
    /// what was remembered cannot be true.
    ///
    /// <para><b>Why a date can be unbelievable.</b> Until #144, <see cref="Write"/>
    /// rendered each date in the machine's default calendar, so a PC whose
    /// regional format is Thai wrote <c>2569-09-08</c> for 2026-09-08. This
    /// reader has always been invariant, and reads that as the Gregorian
    /// year 2569. Now that the writer is Gregorian too, such a file is still
    /// on that teacher's disk, and it would still answer "when are my next
    /// classes?" from five centuries ahead. A memory holding any date before
    /// <see cref="EarliestBelievable"/> or more than
    /// <see cref="YearsAheadBelievable"/> years past today is therefore
    /// treated as no memory at all: the assistant asks for the timetable
    /// again, and the next <see cref="Write"/> replaces the file with one it
    /// can read. That is the same shape as <c>ArchiveStamp</c>: a date that
    /// cannot be true is not allowed to decide anything.</para>
    /// </summary>
    /// <param name="today">
    /// The clock the ceiling is measured against. Passed by tests, which need
    /// an answer that does not change between one line and the next; the
    /// app leaves it null.
    /// </param>
    /// <param name="recording">
    /// Whether setting a file aside leaves a line on the trail. On by
    /// default; a test that only wants the answer turns it off.
    /// </param>
    /// <summary>
    /// The course's noun for the trail line a teacher reads (#1027; the mac's
    /// reader passes its course's): class when the settings cannot be read.
    /// </summary>
    private static Plantoir.Core.Models.ClassNoun NounOf(string workspacePath, string courseCode)
    {
        try
        {
            string config = Path.Combine(Workspace.CoursesDirectory(workspacePath), courseCode.ToUpperInvariant(), "course_config.json");
            return Plantoir.Core.Models.CourseConfiguration.Load(config).ClassNoun;
        }
        catch (Exception)
        {
            return Plantoir.Core.Models.ClassNoun.Class;
        }
    }

    public static TimetableMemory? Read(string workspacePath, string courseCode, int sectionNumber,
                                        DateOnly? today = null, bool recording = true)
    {
        try
        {
            string path = FileFor(workspacePath, courseCode, sectionNumber);
            if (!File.Exists(path)) return null;
            var stored = JsonSerializer.Deserialize<Stored>(File.ReadAllText(path));
            if (stored?.Dates is not { Count: > 0 }) return null;

            var dates = new List<DateOnly>();
            var unreadable = new List<string>();
            foreach (string text in stored.Dates)
            {
                if (DateOnly.TryParse(text, CultureInfo.InvariantCulture, out var date))
                    dates.Add(date);
                else
                    unreadable.Add(text);
            }
            if (unreadable.Count > 0 || dates.Count == 0) return null;

            dates.Sort();
            if (Unbelievable(dates, today ?? DateOnly.FromDateTime(DateTime.Now)) is { } impossible)
            {
                if (recording)
                    ActivityTrail.Note(ActivityTrail.Event.RememberedTimetableSetAside,
                        AssistWording.ClassDatesSetAside(DateText.Iso(impossible), NounOf(workspacePath, courseCode)),
                        courseCode.ToUpperInvariant(), sectionNumber);
                return null;
            }
            return new TimetableMemory
            {
                Dates = dates,
                Source = stored.Source ?? "not recorded",
                Recorded = DateText.TryReadDay(stored.Recorded, out var when) ? when : default,
            };
        }
        // A memory that cannot be read is a memory we do not have. Nothing here
        // is worth failing a conversation over — the assistant simply asks.
        catch { return null; }
    }

    /// <summary>
    /// Write these dates down for next time. Returns false when it could not be
    /// saved, which the caller reports honestly rather than claiming otherwise:
    /// a teacher told their timetable was remembered, who is then asked for it
    /// again tomorrow, has learnt not to trust what the assistant tells them.
    /// True when the dates are on disk, a step left part way included: a
    /// caller that speaks to the teacher uses <see cref="WriteDown(string, string, int, IEnumerable{DateOnly}, string, DateOnly, string?)"/>,
    /// which says what was kept.
    /// </summary>
    /// <param name="madeBy">Who makes the step (#899 W7b1; the mac's <c>applyRememberTimetable(_:by:)</c>): the
    /// Class Dates dialog's <c>sheet</c> by default, the tool's caller's surface (<c>AssistWorkspace.UndoMadeBy</c>) otherwise.</param>
    public static bool Write(string workspacePath, string courseCode, int sectionNumber,
                             IEnumerable<DateOnly> dates, string source, DateOnly today,
                             string? madeBy = null)
        => WriteDown(workspacePath, courseCode, sectionNumber, dates, source, today, madeBy).Remembered;

    /// <summary>
    /// <see cref="Write(string, string, int, IEnumerable{DateOnly}, string, DateOnly, string?)"/>, saying
    /// what came of it: whether the dates are remembered, and, when the step
    /// was left part way, which hidden file holds what the timetable held
    /// (#899 W7b1, review 1, MEDIUM 1).
    /// </summary>
    public static TimetableWriteOutcome WriteDown(string workspacePath, string courseCode, int sectionNumber,
                                                  IEnumerable<DateOnly> dates, string source, DateOnly today,
                                                  string? madeBy = null)
        => WriteDown(workspacePath, courseCode, sectionNumber, dates, source, today,
                     new UndoActionStep(new UndoStepMaker(madeBy ?? "sheet", "rememberTimetable"), workspacePath, courseCode, sectionNumber));

    /// <summary>The same, with the step's maker and a test's own list (this process's when null).</summary>
    internal static bool Write(string workspacePath, string courseCode, int sectionNumber,
                               IEnumerable<DateOnly> dates, string source, DateOnly today,
                               UndoStepMaker by, UndoForThisProcess? undo)
        => WriteDown(workspacePath, courseCode, sectionNumber, dates, source, today,
                     new UndoActionStep(by, workspacePath, courseCode, sectionNumber, undo: undo)).Remembered;

    /// <summary>
    /// The same, through a step the caller made (the workspace's, with its
    /// list, door and seams: the W7b1 review's LOW 5). The step must be new
    /// and is made here.
    /// </summary>
    internal static TimetableWriteOutcome WriteDown(string workspacePath, string courseCode, int sectionNumber,
                                                    IEnumerable<DateOnly> dates, string source, DateOnly today,
                                                    UndoActionStep step)
    {
        try
        {
            // ONE step through the door (#899 W7b1; the mac's
            // applyRememberTimetable): the section's timetable file, its
            // folder made by the swap, all or none.
            if (!PlanInto(step, workspacePath, courseCode, sectionNumber, dates, source, today))
                return TimetableWriteOutcome.NotSaved;
            step.Make();
            return TimetableWriteOutcome.Saved;
        }
        // The dates went in and what the file held could not be put back
        // over them: they ARE remembered, and the hidden file that holds what
        // it held is named (the mac's applyRememberTimetable rethrows
        // leftPartWay: its sheet says savedWithWhatItHeldKept, its assistant
        // saidWhenTheStepStopped). Never a plain "remembered".
        catch (UndoStepLeftPartWayException partWay) { return TimetableWriteOutcome.LeftPartWay(partWay); }
        catch { return TimetableWriteOutcome.NotSaved; }
    }

    /// <summary>
    /// Plans these dates as the section's timetable file in
    /// <paramref name="step"/>, without making it: the Class Dates step's
    /// one file, and a file of the re-date's and the rollover's own step
    /// (#899 W7b1 review 2, M1: one teacher action is one step), so a refused
    /// re-date leaves the timetable as it was. Never told to today's undo
    /// (it never was). The bytes are Windows' own, as before. False, and
    /// nothing planned, for no dates or a date Read would not believe (see
    /// <see cref="Unbelievable"/>).
    /// </summary>
    internal static bool PlanInto(UndoActionStep step, string workspacePath, string courseCode, int sectionNumber,
                                  IEnumerable<DateOnly> dates, string source, DateOnly today)
    {
        var ordered = dates.Distinct().OrderBy(date => date).ToList();
        if (ordered.Count == 0) return false;
        if (Unbelievable(ordered, today) is not null) return false;
        var datesWritten = new List<string>();
        foreach (DateOnly date in ordered) datesWritten.Add(DateText.Iso(date));
        step.Write(FileFor(workspacePath, courseCode, sectionNumber), JsonSerializer.Serialize(new Stored
        {
            Section = sectionNumber,
            Dates = datesWritten,
            Source = source,
            Recorded = DateText.Iso(today),
        }, new JsonSerializerOptions { WriteIndented = true }), todaysUndoKeepsIt: false);
        return true;
    }

    /// <summary>
    /// <c>shared-rules.json</c> → <c>undo.wording.classDatesKeptLead</c>, then
    /// one <c>classDatesKeptBesideIt</c> per kept file (the mac's
    /// <c>Problem.keptMessage</c>).
    /// </summary>
    internal static string KeptMessage(IReadOnlyList<string> keptOriginals)
    {
        var said = new System.Text.StringBuilder(KeptLead);
        foreach (string kept in keptOriginals)
        {
            string name = Path.GetFileName(kept);
            said.Append(' ').Append(KeptBesideIt("“" + (UndoSwap.PlaceOfStagedName(name) ?? name) + "”", name));
        }
        return said.ToString();
    }

    /// <summary>
    /// What the Class Dates sheet says when the dates went in part way: the
    /// mac's <c>Problem.savedWithWhatItHeldKept</c>,
    /// <c>wording.classDatesAreRemembered</c> in the course's noun and then
    /// <paramref name="whatWasKept"/> (<see cref="TimetableWriteOutcome.WhatWasKept"/>).
    /// </summary>
    public static string RememberedWithWhatItHeldKept(Course course, int sectionNumber, string whatWasKept) =>
        AssistWording.ClassDatesAreRemembered(course.Code, sectionNumber.ToString(CultureInfo.InvariantCulture),
                                              course.Configuration.ClassNoun) + " " + whatWasKept;

    /// <summary>
    /// Why a re-date could not read the section's timetable at plan time, in
    /// a teacher's words and naming no hidden path (#899 W7b1 review 3, LOW 1;
    /// the held sentence is Russell's ruling, 2026-11-25), said after
    /// "Nothing was changed: ". Another program holding it; the system's own
    /// words without the path when Windows refused the read; and, for
    /// Plantoir's own refusal (a folder where the file belongs, which carries
    /// no Windows error), no "Windows said" (W7b2-11 review 1, LOW 2). In no
    /// contract on either side: the mac's file system has no such lock.
    /// </summary>
    internal static string WhyTheClassDatesCouldNotBeRead(IOException error)
    {
        if (HeldFiles.IsSharingViolation(error))
            return "another program, such as a syncing service, is using this section’s class dates. Try again in a moment.";
        bool windowsRefusedIt = (error.HResult & unchecked((int)0xFFFF0000)) == unchecked((int)0x80070000);
        return windowsRefusedIt
            ? "this section's class dates could not be read. Windows said: " + HeldFiles.SystemWords(error)
            : "this section's class dates could not be read.";
    }

    /// <summary>
    /// <c>undo.wording.classDatesKeptLead</c>, retyped as every contract
    /// sentence on Windows is (as <see cref="UndoActionStep.KeptSentence"/> is
    /// beside it) and pinned against the contract by
    /// <c>UndoClassDatesStepTests.TheSheetsWordsForAKeptTimetableAreTheContracts</c>.
    /// </summary>
    internal const string KeptLead = "Another program may have changed their file as they were saved.";

    /// <summary><c>undo.wording.classDatesKeptBesideIt</c>, pinned by the same test; <paramref name="place"/> is already quoted.</summary>
    internal static string KeptBesideIt(string place, string kept) =>
        $"What {place} held just before is kept beside it as the hidden file “{kept}”.";

    /// <summary>The shape on disk, kept separate so the in-memory type stays clean.</summary>
    private sealed class Stored
    {
        [JsonPropertyName("section")] public int Section { get; set; }
        [JsonPropertyName("dates")] public List<string>? Dates { get; set; }
        [JsonPropertyName("source")] public string? Source { get; set; }
        [JsonPropertyName("recorded")] public string? Recorded { get; set; }
    }
}

/// <summary>
/// What came of writing a section's class dates down (#899 W7b1, review 1,
/// MEDIUM 1): saved, not saved, or saved with what the file held kept beside
/// it as a hidden file, which is then named.
/// </summary>
public sealed class TimetableWriteOutcome
{
    // ---- Stored properties ---------------------------------------------------------

    internal static readonly TimetableWriteOutcome Saved = new(true, null);
    internal static readonly TimetableWriteOutcome NotSaved = new(false, null);

    /// <summary>Whether the dates are on disk.</summary>
    public bool Remembered { get; }

    private readonly UndoStepLeftPartWayException? _stoppedPartWay;

    // ---- Computed properties -------------------------------------------------------

    /// <summary>The step left part way, when it was: the dates went in, and what the file held is kept beside it (its message names the kept file).</summary>
    public Exception? StoppedPartWay => _stoppedPartWay;

    /// <summary>
    /// Null unless the step was left part way; then the mac's
    /// <c>keptMessage</c>: <c>classDatesKeptLead</c> and the hidden file named.
    /// </summary>
    public string? WhatWasKept => _stoppedPartWay is { } partWay ? TimetableMemory.KeptMessage(partWay.KeptOriginals) : null;

    // ---- Initializer ---------------------------------------------------------------

    private TimetableWriteOutcome(bool remembered, UndoStepLeftPartWayException? stoppedPartWay)
    {
        Remembered = remembered;
        _stoppedPartWay = stoppedPartWay;
    }

    // ---- Functions -------------------------------------------------------------------

    internal static TimetableWriteOutcome LeftPartWay(UndoStepLeftPartWayException partWay) => new(true, partWay);
}
