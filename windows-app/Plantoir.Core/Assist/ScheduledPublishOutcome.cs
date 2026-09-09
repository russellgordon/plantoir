using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// How a publish that was set to happen on its own turned out — it needed an
/// answer, it did not finish, or it worked.
///
/// <para><b>The failure this exists to end.</b> A scheduled deploy runs at half
/// six in the morning with the app closed, so nothing it does is seen by
/// anybody. The run writes a record; the app reads it the next time it opens.
/// That handover IS the feature: without it a run that did not get through is
/// indistinguishable from one that was never scheduled, which is exactly the
/// shape of "my site did not update on Tuesday and I do not know why".</para>
///
/// <para><b>Why the good news is recorded too.</b> Read the other way round,
/// the same argument applies: a scheduled publish that leaves NO trace cannot
/// be told from one that never happened, so without a success record the trail
/// can answer "why did my site not update?" and cannot answer "did it?".
/// Russell's instruction, 2026-09-09, after a real timed run showed the
/// failures recorded and the successes silent.</para>
///
/// <para><b>This class was <c>ScheduledPublishQuestion</c> until 2026-09-09</b>,
/// when it recorded only the one kind. Russell widened it to ANY failed
/// scheduled publish — a revoked token, a network that was down — because the
/// SILENCE is the complaint rather than the cause, and recording only the
/// question case leaves an ordinary overnight failure exactly as silent as it
/// was before.</para>
///
/// <para><b>Modelled on <see cref="ScheduledHealthFindings"/> deliberately</b>,
/// because that is the same problem solved once already. Two properties are
/// copied with it, both load-bearing — the record is CONSUMED when read, so a
/// teacher is told once rather than every time the app opens; and a run that
/// gets all the way through clears an earlier failure, so a question they have
/// since answered stops being reported.</para>
///
/// <para><b>Its own directory, not the completion sentinels'.</b>
/// <see cref="ScheduledDeployCompletion.ConsumePendingFrom"/> enumerates
/// <c>scheduled\pending\*.json</c> and deletes every file it touches, parsed or
/// not, so a record filed beside a completion record would be swept away before
/// anything read it.</para>
/// </summary>
public static class ScheduledPublishOutcome
{
    /// <summary>What a scheduled run turned out to be.</summary>
    public enum Kind
    {
        /// <summary>
        /// The publishing launcher exited 3: a question was put to nobody.
        /// <c>deploy.py</c>'s NEEDS_AN_ANSWER, distinct from 1 precisely so a
        /// caller can tell the two apart and say something useful.
        /// </summary>
        NeededAnAnswer,

        /// <summary>
        /// The BUILD stopped for a question, before any destination was
        /// reached.
        /// </summary>
        /// <remarks>
        /// <para>A scheduled publish builds before it publishes, and
        /// <c>preview.ps1</c> asks two questions of its own — so under
        /// <c>--non-interactive</c> it can refuse with the same exit 3 the
        /// publishing launcher uses, having reached no destination at all.</para>
        ///
        /// <para>It is a separate kind rather than <see cref="NeededAnAnswer"/>
        /// with the destination left blank because the sentence a teacher reads
        /// is different: there is nothing to name, and telling them "publishing
        /// to Netlify needed an answer" when Netlify was never contacted would
        /// send them to look in the wrong place. Proposed to
        /// <c>shared-rules.json</c> from this side; the mac's launchd path can
        /// reach the identical state, and GitHub issue #133 asks them to adopt
        /// the sentence.</para>
        /// </remarks>
        BuildNeededAnAnswer,

        /// <summary>
        /// Any other non-zero exit — a revoked token, a network that was down,
        /// a build that failed for an ordinary reason.
        /// </summary>
        DidNotFinish,

        /// <summary>It worked, and went out to everywhere it was meant to.</summary>
        Succeeded,
    }

    /// <summary>
    /// <c>%LOCALAPPDATA%\Plantoir\scheduled\unanswered</c> — beside the
    /// wrapper scripts rather than in a temp folder, because nothing here
    /// should be swept away before the app looks at it.
    /// </summary>
    /// <remarks>
    /// <para><b>The folder's name is historical, and keeping it was a
    /// decision.</b> It was called <c>unanswered</c> while an unanswered
    /// question was the only thing recorded; since 2026-09-09 it holds
    /// ordinary failures and successes too. Renaming it to something honest
    /// was implemented and then REJECTED: a task SCHEDULED before that date
    /// points at a wrapper <c>.ps1</c> already on disk that writes the old
    /// path, and nothing rewrites that wrapper until the teacher schedules
    /// that section again — so a rename buys a better name and costs a second
    /// directory read for ever, on pain of the first overnight run after an
    /// update going silent, which is the exact bug this feature exists to
    /// close. The record itself says what it is, on its first line, which is
    /// where anybody reading one will actually look.</para>
    ///
    /// <para>The path is deliberately NOT shared with the mac, which keeps its
    /// own under <c>~/Library/Application Support/Plantoir/scheduled/stopped</c>.
    /// What is shared is the behaviour; a path is not a rule.</para>
    /// </remarks>
    public static string Directory() => AppDataRoot.Combine("scheduled", "unanswered");

    /// <summary>
    /// One record per course and section, named by
    /// <see cref="TaskScheduling.HealthRecordName"/>.
    /// </summary>
    /// <remarks>
    /// The same naming function the health records use, rather than a second
    /// one that means the same thing: the two live in different directories, so
    /// they cannot collide, and one function is one place for a rename to
    /// reach. A writer and a reader that disagree about a filename fail in the
    /// quietest way available — written faithfully every night, read never.
    /// </remarks>
    public static string SentinelPath(string courseCode, int sectionNumber) =>
        Path.Combine(Directory(), TaskScheduling.HealthRecordName(courseCode, sectionNumber));

    /// <summary>How a scheduled publish turned out, or null if nothing is waiting.</summary>
    /// <param name="Outcome">Which of the four it was.</param>
    /// <param name="Destination">
    /// Which destination it is about — the one that stopped, or for a success
    /// every destination it went to. A course can publish to several, and only
    /// one of them may have gone wrong.
    /// </param>
    /// <param name="When">
    /// When the RUN wrote it, not when the app read it. The trail line and the
    /// sentence are dated from this; a line dated to whenever somebody happened
    /// to open the app would file an overnight problem under the wrong night.
    /// </param>
    /// <param name="Course">
    /// The course this is about, as the wrapper knew it.
    /// </param>
    /// <param name="Section">The section number, likewise.</param>
    /// <remarks>
    /// <b>Course and section are IN the record, not read back off its
    /// filename.</b> The name comes from
    /// <see cref="TaskScheduling.HealthRecordName"/>, which passes the code
    /// through <c>SafeName</c> and maps every non-alphanumeric character to a
    /// hyphen. That is fine forward — the section view looks its own record up
    /// — and lossy backward, and the sweep that writes trail lines has only the
    /// filename to go on. A course code is free text up to twelve characters
    /// (<c>CourseCodeRule</c>), so one containing a space would have put a
    /// course that does not exist on the trail. Found by review before it
    /// shipped.
    /// </remarks>
    public sealed record Result(
        Kind Outcome, string Destination, DateTime When, string Course, int Section);

    // ---- The file the wrapper writes ------------------------------------

    /// <summary>
    /// The word the wrapper writes on the first line, and this reads back.
    /// </summary>
    /// <remarks>
    /// Deliberately not <c>Enum.ToString()</c>/<c>Enum.Parse</c> round-tripping:
    /// these strings are a FILE FORMAT that a PowerShell script writes, so
    /// renaming a C# enum member must not silently change what a wrapper
    /// already on disk is understood to have said.
    /// </remarks>
    public static string Word(Kind kind) => kind switch
    {
        Kind.NeededAnAnswer => "needed-an-answer",
        Kind.BuildNeededAnAnswer => "build-needed-an-answer",
        Kind.DidNotFinish => "did-not-finish",
        Kind.Succeeded => "succeeded",
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    private static Kind? KindFor(string word) => word switch
    {
        "needed-an-answer" => Kind.NeededAnAnswer,
        "build-needed-an-answer" => Kind.BuildNeededAnAnswer,
        "did-not-finish" => Kind.DidNotFinish,
        "succeeded" => Kind.Succeeded,
        _ => null,
    };

    /// <summary>
    /// What the wrapper writes when a scheduled run ends, however it ended.
    /// </summary>
    /// <remarks>
    /// <para>Two lines: the kind, then the destination. Deliberately NOT the
    /// question's text or the launcher's error: the launcher prints those to a
    /// console nobody is watching, and capturing them would mean rewriting the
    /// wrapper's deploy legs as <c>Start-Process</c> with redirected output —
    /// four documented traps (see the build leg's own comment block) for a
    /// sentence the app can say better itself, since it knows the course, the
    /// section and the destination already.</para>
    /// </remarks>
    public static void Record(
        string directory, string courseCode, int sectionNumber, Kind kind, string destination)
    {
        System.IO.Directory.CreateDirectory(directory);
        File.WriteAllText(
            Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber)),
            string.Join(Environment.NewLine,
                Word(kind), destination, courseCode, sectionNumber.ToString()) + Environment.NewLine);
    }

    /// <summary>What the mark saying a record's trail line has been written is called.</summary>
    internal const string NotedSuffix = ".noted";

    // ---- Reading it -----------------------------------------------------

    /// <summary>
    /// How last night's scheduled publish for this section turned out.
    /// </summary>
    /// <remarks>
    /// <para><b>Reading does NOT consume, and that changed on 2026-09-09.</b>
    /// The record used to be deleted as it was read, so the teacher was told
    /// once. That is right for a thing that is shown in a dialog and wrong for
    /// a thing that is shown in the section, and it had a cost that was only
    /// obvious once Dismiss existed: it made "not shown" and "shown and read"
    /// the same state, so a view that could not get the sentence on screen had
    /// destroyed the only thing that would have told the teacher tomorrow —
    /// which is why there used to be a <c>PutBack</c> to undo it.</para>
    ///
    /// <para>The message now STANDS until one of the two things
    /// <c>shared-rules.json</c> → <c>scheduledPublishStopped.clearedBy</c>
    /// names happens: a scheduled run that gets all the way through replaces
    /// it, or the teacher dismisses it. Not showing it is then simply not
    /// showing it, and tomorrow morning still works.</para>
    /// </remarks>
    public static Result? Read(string courseCode, int sectionNumber) =>
        ReadFrom(Directory(), courseCode, sectionNumber);

    /// <summary>The same, against an arbitrary directory — what the tests use.</summary>
    public static Result? ReadFrom(string directory, string courseCode, int sectionNumber)
    {
        string path = Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber));
        string text;
        DateTime writtenAt;
        try
        {
            if (!File.Exists(path)) return null;
            writtenAt = File.GetLastWriteTime(path);
            text = File.ReadAllText(path);
        }
        catch
        {
            // Unreadable is not reportable. Better to say nothing than to
            // report a run that may have gone perfectly well.
            return null;
        }

        // The caller's course and section stand in for a record written before
        // 2026-09-09, which carried neither. Here that is exact — the caller
        // asked for this section by name — where the sweep has only the
        // filename and says so.
        var result = Parse(text, writtenAt, courseCode, sectionNumber);

        // An unusable record IS deleted, because nothing else ever will: no
        // sentence can be shown for it, so no Dismiss can be pressed, and it
        // would otherwise be re-read every time the app opened, for ever.
        if (result is null)
        {
            try { File.Delete(path); } catch { }
            try { File.Delete(path + NotedSuffix); } catch { }
        }

        return result;
    }

    /// <summary>
    /// The four-line record, and the one-line one written before 2026-09-09.
    /// </summary>
    /// <remarks>
    /// <para>Four lines: the kind, the destinations, the course, the section.
    /// The last two are there so the sweep that writes trail lines never has
    /// to read a course code back off a filename that
    /// <see cref="TaskScheduling.HealthRecordName"/> has already flattened.</para>
    ///
    /// <para><b>The old format has no kind word</b> — it was a single line
    /// holding just the destination, because a question was the only thing
    /// recorded. A wrapper written before 2026-09-09 and still registered goes
    /// on writing it (see <see cref="Directory"/> for why that folder keeps its
    /// old name), so a first line that is not one of the four words is read as
    /// that old shape rather than thrown away. Getting this wrong would swallow
    /// exactly the record a teacher most needs on the first morning after an
    /// update.</para>
    /// </remarks>
    internal static Result? Parse(
        string text, DateTime writtenAt, string fallbackCourse, int fallbackSection)
    {
        var lines = text.Replace("\r\n", "\n").Split('\n');
        string first = lines.Length > 0 ? lines[0].Trim() : "";
        if (first.Length == 0) return null;

        if (KindFor(first) is not { } kind)
            return new Result(Kind.NeededAnAnswer, first, writtenAt, fallbackCourse, fallbackSection);

        // "|" separates them, and the APP joins. A run that got through went to
        // every destination and the teacher should be told all of them, but
        // "Netlify and Cloudflare Pages" is a sentence rather than a list — and
        // the one place that knows how to say a list out loud is
        // MultiDestinationDeployRunner.JoinedWithAnd, which the Deploy button
        // already uses. Joining in the wrapper's PowerShell would have been a
        // second copy of that, in generated shell, where nothing tests it.
        //
        // "|" because it is the one character Windows forbids in a path, and a
        // local-folder destination IS a path.
        string destination = MultiDestinationDeployRunner.JoinedWithAnd(
            (lines.Length > 1 ? lines[1] : "")
                .Split('|')
                .Select(part => part.Trim())
                .Where(part => part.Length > 0)
                .ToList());
        // A success names where it went; a build refusal has nowhere to name.
        // Only the two destination-shaped failures are unusable without one.
        if (destination.Length == 0
            && kind is Kind.NeededAnAnswer or Kind.DidNotFinish) return null;

        string course = lines.Length > 2 ? lines[2].Trim() : "";
        if (course.Length == 0) course = fallbackCourse;

        int section = fallbackSection;
        if (lines.Length > 3 && int.TryParse(lines[3].Trim(), out int written)) section = written;

        return new Result(kind, destination, writtenAt, course, section);
    }

    /// <summary>
    /// Throw this section's record away — what a teacher's Dismiss does.
    /// </summary>
    /// <remarks>
    /// <b>Dismiss is a decision, not a convenience.</b> A record used to be
    /// cleared only by a scheduled run that got all the way through, which left
    /// the message standing after somebody had already fixed the problem by
    /// hand — and the next scheduled run that would have cleared it could be a
    /// week away.
    /// </remarks>
    public static void Dismiss(string courseCode, int sectionNumber) =>
        Clear(Directory(), courseCode, sectionNumber);

    /// <summary>Throw away this section's record, and the mark saying it has been noted.</summary>
    public static void Clear(string directory, string courseCode, int sectionNumber)
    {
        string path = Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber));
        try { File.Delete(path); } catch { }
        // The sidecar goes with it. Left behind, it would suppress the trail
        // line for the NEXT run whose record happened to be written within the
        // same second.
        try { File.Delete(path + NotedSuffix); } catch { }
    }

    // ---- The trail ------------------------------------------------------

    /// <summary>
    /// Put a line on the breadcrumb trail for every scheduled run that has
    /// finished since the last time this looked, dated to when the RUN
    /// happened.
    /// </summary>
    /// <remarks>
    /// <para><b>Why this is a SWEEP and not something the section view does.</b>
    /// The contract says the line is written by the RUN rather than by the app
    /// when a teacher opens the section, so that a teacher who never opens that
    /// section still has it — and that teacher is precisely the one who writes
    /// in to say their site did not update. On the mac the run IS Plantoir, so
    /// that sentence is literal there. Here the run is a PowerShell wrapper
    /// with no app process alive, so the closest honest thing is to sweep every
    /// section's record the moment the app opens: opening the app at all is
    /// enough, and nothing has to be opened section by section.</para>
    ///
    /// <para><b>Rejected: writing the line from the wrapper's own PowerShell.</b>
    /// It is nearer the contract's words and it would put the trail's line
    /// FORMAT in a second home — inside generated shell, where nothing tests
    /// it and the redaction rules do not reach. The line's date is the property
    /// that mattered, and a sweep keeps it: it is read from the record's own
    /// modification time, not from the moment of reading.</para>
    ///
    /// <para><b>Once per run, not once per launch.</b> The record now STANDS
    /// until dismissed, so a sweep with no memory would write the same line
    /// every time the app started. A sidecar <c>.noted</c> file marks what has
    /// been said; a record newer than its sidecar is a NEW run and is said
    /// again. Deliberately a sidecar rather than a flag inside the record: the
    /// mac tried marking the record itself, which rewrote it, changed its
    /// modification date, and so dated an overnight problem to the morning
    /// somebody looked at it.</para>
    /// </remarks>
    public static void NoteFinishedRunsOnTrail() => NoteFinishedRunsOnTrailIn(Directory());

    /// <summary>The same, against an arbitrary directory — what the tests use.</summary>
    public static void NoteFinishedRunsOnTrailIn(string directory)
    {
        IEnumerable<string> files;
        try
        {
            // The extension is re-checked in managed code rather than left to
            // the search pattern: on Windows a pattern of "*.txt" also matches
            // 8.3 SHORT names, so the ".noted" sidecars beside these records
            // can come back from it. A sweep that treated one as a record would
            // read an empty file, find it unusable, and delete the mark that
            // stops the trail line being written again every launch.
            files = System.IO.Directory.EnumerateFiles(directory, "*.txt")
                .Where(path => path.EndsWith(".txt", StringComparison.OrdinalIgnoreCase))
                .ToList();
        }
        catch { return; }   // nothing has ever run, or the folder is not there yet — both fine

        foreach (string file in files)
        {
            try
            {
                string noted = file + NotedSuffix;
                var writtenAt = File.GetLastWriteTime(file);
                if (File.Exists(noted) && File.GetLastWriteTime(noted) >= writtenAt) continue;

                // The filename only says which FILE to read. What goes on the
                // trail comes out of the record, which carries the course code
                // as the wrapper knew it — HealthRecordName flattens every
                // non-alphanumeric character to a hyphen, so reading a course
                // back off a filename can name a course that does not exist.
                // The filename is the fallback for a record written before
                // 2026-09-09, which carried neither; those are all one kind and
                // all from codes that were already scheduled, so the flattening
                // is the same risk that shape always had.
                var (fallbackCourse, fallbackSection) =
                    SectionFromRecordName(Path.GetFileName(file)) ?? ("", 0);
                if (fallbackSection == 0) continue;

                if (ReadFrom(directory, fallbackCourse, fallbackSection) is not { } result) continue;

                ActivityTrail.Note(
                    EventFor(result.Outcome), TrailSentence(result),
                    result.Course, result.Section, result.When);

                File.WriteAllText(noted, "");
                File.SetLastWriteTime(noted, DateTime.Now);
            }
            catch
            {
                // A record nobody can parse is litter, not a crash. The next
                // sweep meets it again and ReadFrom deletes it.
            }
        }
    }

    /// <summary>
    /// The course and section a record's filename is about, or null.
    /// </summary>
    /// <remarks>
    /// The inverse of <see cref="TaskScheduling.HealthRecordName"/>, which is
    /// <c>&lt;COURSE&gt;-section&lt;N&gt;.txt</c>. Split on the LAST
    /// <c>-section</c>, because <c>SafeName</c> can put hyphens in the course
    /// half and the section marker is always last. Used only to decide WHICH
    /// record to open, and as the fallback for a record too old to name itself.
    /// </remarks>
    internal static (string Course, int Section)? SectionFromRecordName(string fileName)
    {
        const string marker = "-section";
        string stem = Path.GetFileNameWithoutExtension(fileName);
        int at = stem.LastIndexOf(marker, StringComparison.Ordinal);
        if (at <= 0) return null;
        if (!int.TryParse(stem[(at + marker.Length)..], out int section)) return null;
        if (section <= 0) return null;
        return (stem[..at], section);
    }

    /// <summary>
    /// The trail's version of the sentence — what happened, and where.
    /// </summary>
    /// <remarks>
    /// Shorter than the teacher-facing sentence and in the trail's own voice:
    /// the course and section are columns of their own, so repeating them in
    /// the text would read twice. NEVER the question's own text — that comes
    /// from a launcher's console, and a line naming a credential prompt would
    /// put a teacher's own words on the trail.
    /// </remarks>
    internal static string TrailSentence(Result result) => result.Outcome switch
    {
        Kind.NeededAnAnswer =>
            $"the publish set to happen on its own stopped — {result.Destination} needed an answer",
        Kind.BuildNeededAnAnswer =>
            "the publish set to happen on its own stopped — building the pages needed an answer",
        Kind.DidNotFinish =>
            $"the publish set to happen on its own did not finish — {result.Destination} stopped",
        Kind.Succeeded =>
            $"the publish set to happen on its own went out to {result.Destination}",
        _ => throw new ArgumentOutOfRangeException(nameof(result)),
    };

    // ---- What a teacher reads -------------------------------------------

    /// <summary>
    /// The sentence a teacher reads, and the one on the trail.
    /// </summary>
    /// <remarks>
    /// Said by the app rather than copied out of the launcher's console,
    /// because the app knows every fact already and the console's wording is
    /// written for whoever is standing at a terminal. Pinned against
    /// <c>contracts/shared-rules.json</c> → <c>scheduledPublishStopped.sentences</c>.
    /// </remarks>
    public static string Sentence(string courseCode, int sectionNumber, Result result) =>
        result.Outcome switch
        {
            Kind.NeededAnAnswer =>
                $"{courseCode} Section {sectionNumber} was set to publish on its own, and it stopped " +
                $"because publishing to {result.Destination} needed an answer nobody was there to give. " +
                "Publish this section once yourself, answer the question, and it can publish on its own " +
                "after that.",

            Kind.BuildNeededAnAnswer =>
                $"{courseCode} Section {sectionNumber} was set to publish on its own, and it stopped " +
                "before it started, because building the pages needed an answer nobody was there to " +
                "give. Preview this section once yourself, answer the question, and it can publish on " +
                "its own after that.",

            Kind.DidNotFinish =>
                $"{courseCode} Section {sectionNumber} was set to publish on its own, and it did not " +
                $"finish — publishing to {result.Destination} stopped, so nothing went up there. " +
                "Publish it yourself to see what happens.",

            Kind.Succeeded =>
                $"{courseCode} Section {sectionNumber} published on its own to {result.Destination}. " +
                "Your students have the new pages.",

            _ => throw new ArgumentOutOfRangeException(nameof(result)),
        };

    /// <summary>Whether this outcome asks for the teacher's attention.</summary>
    /// <remarks>
    /// The two failures get a warning beside their section in the list as well
    /// as the sentence inside it — a teacher who does not know WHICH section
    /// failed cannot open the right one. A SUCCESS is news rather than a
    /// problem: it gets the sentence and no badge, because a badge on every
    /// section that published fine overnight is a badge nobody reads by
    /// Wednesday.
    /// </remarks>
    public static bool NeedsAttention(Kind kind) => kind != Kind.Succeeded;

    /// <summary>The trail event this outcome leaves.</summary>
    /// <remarks>
    /// A build that stopped for a question is filed under "needed an answer"
    /// like any other: the event is about a question going unasked, which is
    /// what happened, and splitting it would put a distinction on the trail
    /// that means nothing to the person reading it.
    /// </remarks>
    public static ActivityTrail.Event EventFor(Kind kind) => kind switch
    {
        Kind.NeededAnAnswer or Kind.BuildNeededAnAnswer =>
            ActivityTrail.Event.ScheduledPublishNeededAnAnswer,
        Kind.DidNotFinish =>
            ActivityTrail.Event.ScheduledPublishDidNotFinish,
        Kind.Succeeded =>
            ActivityTrail.Event.ScheduledPublishFinished,
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };
}
