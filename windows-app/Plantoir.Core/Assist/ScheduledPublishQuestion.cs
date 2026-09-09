using System;
using System.IO;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// A publish set to happen on its own that stopped because it needed an answer.
///
/// <para><b>The failure this exists to end.</b> A scheduled deploy runs at half
/// six in the morning with the app closed, so every question <c>deploy.py</c>
/// or a launcher can ask is a question nobody will answer. Until
/// <c>--non-interactive</c> there were two ways that ended, and both were seen:
/// the run WAITED — measured at 45 minutes, still alive when it was swept up —
/// or it took a default silently and published the teacher's site to an address
/// nobody chose. Under the flag it refuses instead and exits 3. This is how a
/// teacher finds out.</para>
///
/// <para><b>Modelled on <see cref="ScheduledHealthFindings"/> deliberately</b>,
/// because that is the same problem solved once already: something happened
/// overnight with nobody there, and the next person to open the app has to be
/// told. Two properties are copied with it, both load-bearing — the record is
/// CONSUMED when read, so a teacher is told once rather than every time the app
/// opens; and a run that gets through CLEARS it, so a question they have since
/// answered stops being reported.</para>
///
/// <para><b>Its own directory, not the completion sentinels'.</b>
/// <see cref="ScheduledDeployCompletion.ConsumePendingFrom"/> enumerates
/// <c>scheduled\pending\*.json</c> and deletes every file it touches, parsed or
/// not, so a record filed beside a completion record would be swept away before
/// anything read it.</para>
/// </summary>
public static class ScheduledPublishQuestion
{
    /// <summary>
    /// <c>%LOCALAPPDATA%\Plantoir\scheduled\unanswered</c> — beside the wrapper
    /// scripts rather than in a temp folder, because nothing here should be
    /// swept away before the app looks at it.
    /// </summary>
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

    /// <summary>What a scheduled publish could not get past, or null.</summary>
    /// <param name="Destination">
    /// Which destination stopped — a course can publish to several, and only
    /// one of them may have needed anything.
    /// </param>
    /// <param name="When">
    /// When the RUN wrote it, not when the app read it. A trail line dated to
    /// whenever somebody happened to open the app would file an overnight
    /// problem under the wrong night.
    /// </param>
    public sealed record Unanswered(string Destination, DateTime When);

    /// <summary>
    /// What the wrapper writes when a leg exits with <c>deploy.py</c>'s
    /// "needs an answer" code.
    /// </summary>
    /// <remarks>
    /// One line, holding the destination and nothing else. Deliberately NOT the
    /// question's text: the launcher prints that to a console nobody is
    /// watching, and capturing it would mean rewriting the wrapper's deploy
    /// legs as <c>Start-Process</c> with redirected output — four documented
    /// traps (see the build leg's own comment block) for a sentence the app can
    /// say better itself, since it knows the course, the section and the
    /// destination already.
    /// </remarks>
    public static void Record(string directory, string courseCode, int sectionNumber, string destination)
    {
        System.IO.Directory.CreateDirectory(directory);
        File.WriteAllText(
            Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber)),
            destination + Environment.NewLine);
    }

    /// <summary>
    /// What last night's scheduled publish could not answer for this section,
    /// consuming the record so it is reported once.
    /// </summary>
    public static Unanswered? Take(string courseCode, int sectionNumber) =>
        TakeFrom(Directory(), courseCode, sectionNumber);

    /// <summary>The same, against an arbitrary directory — what the tests use.</summary>
    public static Unanswered? TakeFrom(string directory, string courseCode, int sectionNumber)
    {
        string path = Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber));
        string destination;
        DateTime writtenAt;
        try
        {
            if (!File.Exists(path)) return null;
            writtenAt = File.GetLastWriteTime(path);
            destination = File.ReadAllText(path).Trim();
        }
        catch
        {
            // Unreadable is not reportable. Better to say nothing than to
            // report a question that may not have been asked.
            return null;
        }

        // Consumed whatever it held, INCLUDING an empty file: a record that
        // cannot be read is still a record that would otherwise be re-read
        // every time the app opened.
        try { File.Delete(path); } catch { }

        if (destination.Length == 0) return null;
        return new Unanswered(destination, writtenAt);
    }

    /// <summary>
    /// Write a consumed record back, for a reader that could not show it.
    /// </summary>
    /// <remarks>
    /// <b>Consuming is not the same as delivering.</b> <see cref="Take"/>
    /// deletes the record as it reads it, so a caller that then fails to get
    /// the sentence on screen — a dialog refused because another one is already
    /// open, a dispatcher shutting down — has destroyed the only thing that
    /// would have told the teacher tomorrow. The folder-problem queue makes the
    /// same move for the same reason. Costs one morning to put back; costs the
    /// record for ever not to.
    /// </remarks>
    public static void PutBack(string courseCode, int sectionNumber, Unanswered stopped) =>
        PutBackIn(Directory(), courseCode, sectionNumber, stopped);

    /// <summary>The same, against an arbitrary directory — what the tests use.</summary>
    public static void PutBackIn(
        string directory, string courseCode, int sectionNumber, Unanswered stopped)
    {
        try
        {
            Record(directory, courseCode, sectionNumber, stopped.Destination);
            // The MOMENT matters as much as the fact: the trail line and the
            // sentence are dated from it, and a record put back with today's
            // timestamp would file last night's problem under this morning.
            File.SetLastWriteTime(
                Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber)),
                stopped.When);
        }
        catch { }
    }

    /// <summary>
    /// Throw away this section's record, for a run that got through.
    /// </summary>
    /// <remarks>
    /// Called by the wrapper on a leg that succeeded, so a question the teacher
    /// has since answered stops being reported. Without it the record would
    /// outlive the problem and a teacher would be told, weeks later, about a
    /// publish that has been working ever since.
    /// </remarks>
    public static void Clear(string directory, string courseCode, int sectionNumber)
    {
        try
        {
            File.Delete(Path.Combine(directory, TaskScheduling.HealthRecordName(courseCode, sectionNumber)));
        }
        catch { }
    }

    /// <summary>
    /// The sentence a teacher reads, and the one on the trail.
    /// </summary>
    /// <remarks>
    /// Said by the app rather than copied out of the launcher's console,
    /// because the app knows all three facts already and the console's
    /// wording is written for whoever is standing at a terminal.
    /// </remarks>
    public static string Sentence(string courseCode, int sectionNumber, string destination) =>
        $"{courseCode} Section {sectionNumber} was set to publish on its own, and it stopped " +
        $"because publishing to {destination} needed an answer nobody was there to give. " +
        "Publish this section once yourself, answer the question, and it can publish on its own " +
        "after that.";
}
