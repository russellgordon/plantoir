using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

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
                        $"remembered timetable set aside: it names {DateText.Iso(impossible)}, which cannot be a " +
                        "class date; the assistant will ask for the timetable again",
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
    /// </summary>
    public static bool Write(string workspacePath, string courseCode, int sectionNumber,
                             IEnumerable<DateOnly> dates, string source, DateOnly today)
    {
        var ordered = dates.Distinct().OrderBy(date => date).ToList();
        if (ordered.Count == 0) return false;
        // What Read would not believe is not written: see Unbelievable.
        if (Unbelievable(ordered, today) is not null) return false;

        try
        {
            string path = FileFor(workspacePath, courseCode, sectionNumber);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, JsonSerializer.Serialize(new Stored
            {
                Section = sectionNumber,
                Dates = ordered.Select(date => DateText.Iso(date)).ToList(),
                Source = source,
                Recorded = DateText.Iso(today),
            }, new JsonSerializerOptions { WriteIndented = true }));
            return true;
        }
        catch { return false; }
    }

    /// <summary>The shape on disk, kept separate so the in-memory type stays clean.</summary>
    private sealed class Stored
    {
        [JsonPropertyName("section")] public int Section { get; set; }
        [JsonPropertyName("dates")] public List<string>? Dates { get; set; }
        [JsonPropertyName("source")] public string? Source { get; set; }
        [JsonPropertyName("recorded")] public string? Recorded { get; set; }
    }
}
