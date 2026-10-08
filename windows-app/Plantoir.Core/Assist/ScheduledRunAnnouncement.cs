using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// The one notification a scheduled run sends when it finishes, whatever
/// happened (#212's rule, Windows' #324 toast, fixed by #448):
/// <c>shared-rules.json</c> → <c>scheduledPublishStopped.notification.announcing</c>.
/// </summary>
/// <remarks>
/// <para><b>Why what it needs is read BEFORE the run (#448).</b> Until #448 the
/// toast step re-read the job file after <see cref="ScheduledRun.Execute"/>
/// had finished — and a run that went all the way through, or stood down,
/// ends by clearing its own one-shot task, which deletes that job file
/// (<c>TaskScheduling.Cancel</c>). So the toast step found no job and returned
/// without a word: every scheduled deploy since #324 ran, deployed and told
/// nobody, and the trail did not say a notification had been tried.
/// Measured 2026-10-04 on two real runs (the installed 1.4.2 and a Debug
/// build): record written, task gone, no toast, no trail line.
/// <see cref="RunAndAnnounce"/> now reads the job first and hands the
/// course, section and folder to <see cref="Announce"/>.</para>
///
/// <para><b>Rejected:</b> having the run keep its job file until the toast is
/// posted (moving the clearing out of <c>Execute</c>). The clearing is what
/// makes the task one-shot, and it is guarded by the job's token
/// (<c>ClearIfStillMine</c>); splitting it from the run would put a second
/// caller in charge of a step whose failure leaves a deploy to recur.</para>
///
/// <para><b>Which endings announce.</b> <see cref="ScheduledRun.Ending.Deployed"/>
/// (the wrapper's record says succeeded, did not finish or needed an answer)
/// and <see cref="ScheduledRun.Ending.StoodDown"/> (too late, course busy, could
/// not run as set now). <see cref="ScheduledRun.Ending.NoLongerStands"/> wrote
/// no record — the teacher cancelled it or set it again — so there is no news
/// of THIS run, and announcing whatever record lay there would be an older
/// run's news under today's banner. For the same reason a record older than
/// the run is not announced: a wrapper that wrote nothing must not replay last
/// week's notice.</para>
/// </remarks>
public static class ScheduledRunAnnouncement
{
    /// <summary>Whether the system will show Plantoir's notifications. Windows asks no question, so there are two answers.</summary>
    public enum Permission { Allowed, NotAllowed }

    /// <summary>The system's notifications, so a test can stand in for them.</summary>
    public interface IPoster
    {
        /// <summary>What the system says about Plantoir's notifications. May throw: treated as allowed, and the post tried.</summary>
        Permission Permission { get; }

        /// <summary>Show it, replacing any with the same tag; true when it landed. May throw.</summary>
        bool Post(string tag, string launchArgument, string sentence);
    }

    /// <summary>What the announcement did — for the tests and the diagnostic log.</summary>
    public enum Said { Told, TurnedOff, CouldNotBeSent, NothingToSay }

    // The contract's `trailSays`, after the course/section prefix the trail puts on the line.
    public const string ToldLine = "told the teacher how a scheduled publish went, with a notification";
    public const string TurnedOffLine =
        "did not send a notification about a scheduled publish, because notifications are turned off for Plantoir";
    public const string CouldNotBeSentLine = "a notification about a scheduled publish could not be sent";

    /// <summary>File times on some volumes are kept to two seconds.</summary>
    private static readonly TimeSpan Slack = TimeSpan.FromSeconds(2);

    /// <summary>
    /// Run the job, then announce how it went. The job is read FIRST, because
    /// the run's own one-shot clearing deletes it (#448).
    /// </summary>
    public static ScheduledRun.Ending RunAndAnnounce(
        string jobPath, IPoster poster, ScheduledRun.World? world = null, string? taskToken = null,
        Action<string>? diagnostic = null)
    {
        world ??= new ScheduledRun.World();
        var job = ScheduledRun.ReadJob(jobPath);
        DateTime started = DateTime.Now;
        var ending = ScheduledRun.Execute(jobPath, world, taskToken);
        if (ending is not (ScheduledRun.Ending.Deployed or ScheduledRun.Ending.StoodDown)) return ending;
        if (job is null)
        {
            // Unreachable while Execute reads the same file; said rather than silent.
            diagnostic?.Invoke("scheduled toast: the job could not be read before the run");
            return ending;
        }
        Announce(new ScheduledPublishToast.Target(job.CourseCode, job.Section, job.WorkingFolder),
                 poster, world.OutcomeDirectory, started, diagnostic);
        return ending;
    }

    /// <summary>
    /// Post the section's own sentence (<see cref="ScheduledPublishOutcome.Sentence"/>)
    /// and write on the trail whether it went, was turned off, or could not be
    /// sent. A section with no record — or only one older than
    /// <paramref name="writtenSince"/> — has nothing to say and writes no line.
    /// </summary>
    public static Said Announce(ScheduledPublishToast.Target section, IPoster poster, string outcomeDirectory,
                                DateTime? writtenSince = null, Action<string>? diagnostic = null)
    {
        var record = ScheduledPublishOutcome.ReadFrom(outcomeDirectory, section.CourseCode, section.Section, section.WorkingFolder);
        if (record is null)
        {
            diagnostic?.Invoke("scheduled toast: no record for the section, so nothing to announce");
            return Said.NothingToSay;
        }
        if (writtenSince is { } since && record.When < since - Slack)
        {
            diagnostic?.Invoke("scheduled toast: the section's record is older than this run, so nothing to announce");
            return Said.NothingToSay;
        }

        Permission permission;
        try { permission = poster.Permission; }
        catch (Exception error)
        {
            diagnostic?.Invoke("scheduled toast setting: " + error.Message);
            permission = Permission.Allowed;
        }
        if (permission == Permission.NotAllowed)
        {
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishNotification, TurnedOffLine, section.CourseCode, section.Section);
            return Said.TurnedOff;
        }

        bool sent;
        try
        {
            sent = poster.Post(TagFor(section), ScheduledPublishToast.Format(section),
                               ScheduledPublishOutcome.Sentence(section.CourseCode, section.Section, record));
        }
        catch (Exception error)
        {
            diagnostic?.Invoke("scheduled toast post: " + error.Message);
            sent = false;
        }
        ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishNotification,
                           sent ? ToldLine : CouldNotBeSentLine, section.CourseCode, section.Section);
        return sent ? Said.Told : Said.CouldNotBeSent;
    }

    /// <summary>
    /// The toast's tag: the section-per-folder record name, so a later run of
    /// the same section replaces it and another folder's never does. At most
    /// 64 characters, the tag's limit.
    /// </summary>
    public static string TagFor(ScheduledPublishToast.Target section)
    {
        string name = Path.GetFileNameWithoutExtension(
            TaskScheduling.HealthRecordName(section.CourseCode, section.Section, section.WorkingFolder));
        return name.Length <= 64 ? name : name[..64];
    }
}
