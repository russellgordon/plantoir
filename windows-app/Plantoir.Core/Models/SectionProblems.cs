using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Every section's record of its problems that this app has read, and what the
/// teacher has done about them here (#734, the mac's <c>SectionProblems.swift</c>).
/// </summary>
/// <remarks>
/// <para><b>The RECORDS are on disk</b>, written by the shared Python; this
/// store only reads them, at the moments one can have changed: a
/// <c>PLANTOIR_PROBLEMS:</c> marker in a run this app watched
/// (<see cref="NoteMarker"/>), a section view appearing, the window becoming
/// active (an MCP server's, a terminal's or a scheduled run's build), the
/// scheduled-deploy watcher moving, and the working folder's courses loading.
/// Never from a view's drawing: the sidebar's marker reads
/// <see cref="HasMarker"/>, which is memory only.</para>
///
/// <para><b>Read off the interface thread</b> (<see cref="ReloadAsync"/>): the
/// files are read on a worker and the result applied on the caller's thread.
/// A file whose size and time have not moved since the last read is not read
/// again, so the window coming to the front costs a stat per section, not a
/// parse.</para>
///
/// <para><b>Keyed by <see cref="SectionKey"/></b> — #706/#728's canonical
/// folder, course case-insensitively, section — so a folder typed two ways is
/// one entry. A course is read WHOLE, because another section's record decides
/// what this one's rows say (<c>rowState</c>).</para>
///
/// <para>What a teacher has ANSWERED is on disk
/// (<see cref="ProblemsAcknowledgements"/>), so a relaunch does not raise
/// yesterday's alert. Ticks and the tab each section shows are kept for the
/// session only, here rather than in the view, because a view is rebuilt on
/// every change of selection and Show must survive that.</para>
///
/// <para>Process-wide state: its tests run in the
/// <c>SharedActivityState</c> collection.</para>
/// </remarks>
public static class SectionProblems
{
    /// <summary>Which of a section's two tabs is showing.</summary>
    public enum Tab { Website, Problems }

    /// <summary>What one file read gave: the record (or none), and the size and time it was read at.</summary>
    public sealed record FileRead(int Section, SectionProblemsRecord? Record, long Length, DateTime WrittenUtc);

    private sealed record Kept(SectionProblemsRecord? Record, long Length, DateTime WrittenUtc);

    private static readonly object Gate = new();
    private static readonly Dictionary<SectionKey, Kept> Records = new();
    private static readonly Dictionary<SectionKey, Tab> Tabs = new();
    private static readonly Dictionary<SectionKey, HashSet<string>> Unticked = new();
    private static readonly Dictionary<SectionKey, string> AlertsUp = new();

    /// <summary>
    /// The alert keys answered in THIS run, beside the file: an answer the file
    /// could not keep (a replace refused by a scanner) still holds until the
    /// app closes. The file is what a relaunch reads.
    /// </summary>
    private static readonly HashSet<(SectionKey, string)> AnsweredHere = new();

    /// <summary>
    /// Where a working folder's records are: where the LAUNCHERS built
    /// (<see cref="BuildOutputLocation.WhereTheLaunchersBuild"/>), which under
    /// <c>--state-dir</c> is not <see cref="BuildOutputLocation.BuildsRootFor"/>
    /// (#664). A test points it at a folder of its own.
    /// </summary>
    public static Func<string, string> BuildsRootFor { get; set; } = BuildOutputLocation.WhereTheLaunchersBuild;

    /// <summary>A section's record may have changed: the folder and course, on the thread that applied it.</summary>
    public static event Action<string, string>? Changed;

    /// <summary>
    /// A run in this app printed a <c>PLANTOIR_PROBLEMS:</c> marker — the
    /// section view's own preview, a deploy that outlived its view, the in-app
    /// assistant's build. Raised on the runner's interface thread.
    /// </summary>
    public static event Action<SectionProblemsMarker>? MarkerArrived;

    /// <summary>
    /// Says <see cref="Changed"/> without a read: a view taken away under its
    /// alert hands Show to the section's view now showing.
    /// </summary>
    public static void SayChanged(string folder, string courseCode) => Changed?.Invoke(folder, courseCode);

    /// <summary>Called by <see cref="ScriptRunner"/> when a run prints a marker.</summary>
    public static void NoteMarker(SectionProblemsMarker marker) => MarkerArrived?.Invoke(marker);

    // ---- Reading -----------------------------------------------------------

    /// <summary>
    /// Reads every section of a course from disk — PURE I/O, safe on a worker
    /// thread. A section whose file has not moved since the last read hands
    /// back what was read then, without parsing. And it puts each changed set
    /// on the trail once (<see cref="NoteOnTheTrailOnce"/>), here rather than
    /// on the interface thread, because that reads and writes a file too.
    /// </summary>
    public static IReadOnlyList<FileRead> ReadCourse(string folder, string courseCode, IEnumerable<int> sections)
    {
        var reads = new List<FileRead>();
        string root;
        try { root = BuildsRootFor(folder); }
        catch (Exception) { return reads; }
        foreach (int section in sections.Distinct())
        {
            string path = SectionProblemsRecord.PathFor(root, courseCode, section);
            long length = -1;
            DateTime written = DateTime.MinValue;
            try
            {
                var info = new FileInfo(path);
                if (info.Exists) { length = info.Length; written = info.LastWriteTimeUtc; }
            }
            catch (Exception) { }
            Kept? known;
            lock (Gate) Records.TryGetValue(SectionKey.For(folder, courseCode, section), out known);
            SectionProblemsRecord? record = known is not null && known.Length == length && known.WrittenUtc == written
                ? known.Record
                : length < 0 ? null : SectionProblemsRecord.Read(path);
            if (record is not null) NoteOnTheTrailOnce(record, folder, courseCode, section);
            reads.Add(new FileRead(section, record, length, written));
        }
        return reads;
    }

    /// <summary>
    /// Keeps what <see cref="ReadCourse"/> read, and raises <see cref="Changed"/>
    /// once when anything moved. On the interface thread.
    /// </summary>
    /// <returns>Whether anything moved.</returns>
    public static bool Apply(string folder, string courseCode, IReadOnlyList<FileRead> reads)
    {
        bool moved = false;
        lock (Gate)
        {
            foreach (var read in reads)
            {
                var key = SectionKey.For(folder, courseCode, read.Section);
                bool knew = Records.TryGetValue(key, out var known);
                if (knew && known!.Length == read.Length && known.WrittenUtc == read.WrittenUtc
                    && ReferenceEquals(known.Record, read.Record))
                    continue;
                // No record before and none now is no change, though it is kept.
                bool same = (knew ? known!.Record : null) is null && read.Record is null;
                Records[key] = new Kept(read.Record, read.Length, read.WrittenUtc);
                if (!same) moved = true;
            }
        }
        if (moved) Changed?.Invoke(folder, courseCode);
        return moved;
    }

    /// <summary>Reads and keeps a course's records, on this thread. For tests and for callers already off the interface thread's hot path.</summary>
    public static bool Reload(string folder, Course course) =>
        Apply(folder, course.Code, ReadCourse(folder, course.Code, course.SectionNumbers));

    /// <summary>Reads on a worker; keeps on the caller's thread (its synchronisation context).</summary>
    public static async Task<bool> ReloadAsync(string folder, string courseCode, IReadOnlyList<int> sections)
    {
        var reads = await Task.Run(() => ReadCourse(folder, courseCode, sections));
        return Apply(folder, courseCode, reads);
    }

    /// <summary>Every course's records, read on a worker.</summary>
    public static async Task ReloadAllAsync(string folder, IReadOnlyList<Course> courses)
    {
        var snapshot = courses.Select(course => (course.Code, Sections: course.SectionNumbers.ToList())).ToList();
        var reads = await Task.Run(() => snapshot
            .Select(course => (course.Code, Reads: ReadCourse(folder, course.Code, course.Sections)))
            .ToList());
        foreach (var (code, courseReads) in reads) Apply(folder, code, courseReads);
    }

    // ---- What the window asks ---------------------------------------------

    /// <summary>A section's record, as last read; null when it has none.</summary>
    public static SectionProblemsRecord? Record(string? folder, string courseCode, int section)
    {
        lock (Gate)
            return Records.TryGetValue(SectionKey.For(folder, courseCode, section), out var kept) ? kept.Record : null;
    }

    /// <summary>The records of the course's OTHER sections.</summary>
    public static IReadOnlyList<SectionProblemsRecord> OtherRecords(string? folder, Course course, int section) =>
        course.SectionNumbers.Where(other => other != section)
            .Select(other => Record(folder, course.Code, other))
            .OfType<SectionProblemsRecord>()
            .ToList();

    /// <summary>Whether the section's sidebar row wears the warning (<c>sectionMarker</c>). Memory only.</summary>
    public static bool HasMarker(string? folder, string courseCode, int section) =>
        SectionProblemsRules.HasMarker(Record(folder, courseCode, section));

    /// <summary>The section's record when its alert is due (<c>alert</c>), else null.</summary>
    public static SectionProblemsRecord? RecordWithAnAlertDue(string? folder, string courseCode, int section)
    {
        if (folder is null || Record(folder, courseCode, section) is not { } found) return null;
        lock (Gate)
            if (AnsweredHere.Contains((SectionKey.For(folder, courseCode, section), found.AlertKey))) return null;
        IReadOnlySet<string> answered;
        lock (ProblemsAcknowledgements.Gate)
            answered = ProblemsAcknowledgements.Read(folder).Answered(courseCode, section);
        return SectionProblemsRules.AlertIsDue(found, answered) ? found : null;
    }

    /// <summary>
    /// The teacher answered the alert — any button: remembered by its alert
    /// key, so it is not raised again for this record, and written on the
    /// trail as the event's second line.
    /// </summary>
    public static void Answer(SectionProblemsRecord record, string answer, string folder, string courseCode, int section)
    {
        lock (Gate) AnsweredHere.Add((SectionKey.For(folder, courseCode, section), record.AlertKey));
        lock (ProblemsAcknowledgements.Gate)
        {
            var kept = ProblemsAcknowledgements.Read(folder);
            kept.RememberAnswered(record.AlertKey, courseCode, section);
            kept.Write(folder);
        }
        ActivityTrail.Note(ActivityTrail.Event.ProblemsChanged, SectionProblemsRules.AnswerLine(answer), courseCode, section);
    }

    /// <summary>
    /// One "problems changed" line per alert key whose set changed, the first
    /// time this app reads it — from a run it watched or later — and never
    /// again after a relaunch: the key is remembered in <c>noted</c>, beside
    /// the answers.
    /// </summary>
    public static void NoteOnTheTrailOnce(SectionProblemsRecord record, string folder, string courseCode, int section)
    {
        if (!record.SetChanged) return;
        lock (ProblemsAcknowledgements.Gate)
        {
            var kept = ProblemsAcknowledgements.Read(folder);
            if (kept.Noted(courseCode, section).Contains(record.AlertKey)) return;
            kept.RememberNoted(record.AlertKey, courseCode, section);
            kept.Write(folder);
        }
        ActivityTrail.Note(ActivityTrail.Event.ProblemsChanged, SectionProblemsRules.TrailLine(record), courseCode, section);
    }

    // ---- One alert per section in this app --------------------------------

    /// <summary>
    /// Claims the alert for a record, so two windows showing one section do
    /// not raise it twice. False when another view of the section has it up.
    /// </summary>
    public static bool ClaimTheAlert(string folder, string courseCode, int section, string alertKey)
    {
        lock (Gate)
        {
            var key = SectionKey.For(folder, courseCode, section);
            if (AlertsUp.ContainsKey(key)) return false;
            AlertsUp[key] = alertKey;
            return true;
        }
    }

    /// <summary>The alert has gone, answered or not.</summary>
    public static void ReleaseTheAlert(string folder, string courseCode, int section)
    {
        lock (Gate) AlertsUp.Remove(SectionKey.For(folder, courseCode, section));
    }

    // ---- The tab, and the ticks (session only) ----------------------------

    /// <summary>The tab a section shows: Problems only while it has rows.</summary>
    public static Tab TabFor(string? folder, string courseCode, int section)
    {
        if (!HasMarker(folder, courseCode, section)) return Tab.Website;
        lock (Gate) return Tabs.TryGetValue(SectionKey.For(folder, courseCode, section), out var tab) ? tab : Tab.Website;
    }

    public static void Show(Tab tab, string? folder, string courseCode, int section)
    {
        lock (Gate) Tabs[SectionKey.For(folder, courseCode, section)] = tab;
    }

    /// <summary>Whether a row is ticked. Ticked means included, and every row starts ticked.</summary>
    public static bool IsTicked(string rowId, string? folder, string courseCode, int section)
    {
        lock (Gate)
            return !(Unticked.TryGetValue(SectionKey.For(folder, courseCode, section), out var set) && set.Contains(rowId));
    }

    public static void SetTicked(bool ticked, string rowId, string? folder, string courseCode, int section)
    {
        lock (Gate)
        {
            var key = SectionKey.For(folder, courseCode, section);
            if (!Unticked.TryGetValue(key, out var set)) Unticked[key] = set = new HashSet<string>(StringComparer.Ordinal);
            if (ticked) set.Remove(rowId); else set.Add(rowId);
        }
    }

    /// <summary>Starts from nothing — for tests.</summary>
    public static void Reset()
    {
        lock (Gate)
        {
            Records.Clear();
            Tabs.Clear();
            Unticked.Clear();
            AlertsUp.Clear();
            AnsweredHere.Clear();
        }
    }
}
