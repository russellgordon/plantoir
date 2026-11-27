using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>What a press of Restore Course decided, in the press's own turn (the mac's <c>restoreCourseIsPressed</c>).</summary>
public enum RestoreCoursePress
{
    /// <summary>A deploy of the course is running: nothing is stopped or started, the offer stays open with both buttons and says the restore's busy sentence.</summary>
    HeldBackByADeploy,
    /// <summary>The offer is answered: the dialog closes, then <see cref="StartOfYearRestoreOffer.RestoreCourseAsync"/> runs.</summary>
    Closes,
    /// <summary>The offer was already answered: nothing happens.</summary>
    AlreadyAnswered,
}

/// <summary>
/// What Restore Course needs of the app: the previews of the course, the
/// whole-course restore Restore from Backup… runs (never a second one), and
/// the course's sections as the restore left them.
/// </summary>
/// <param name="StopEveryPreviewOfTheCourse">Stops every running preview of the course in any window, each stop awaited; returns the sections it stopped.</param>
/// <param name="RestoreWholeCourse">The app's whole-course restore: archive first, the restore, the trail line, reload, select the course; its own error on failure.</param>
/// <param name="SectionsOfTheCourseNow">The course's sections as it is on disk now.</param>
/// <param name="IsPreviewing">Whether this section of the course is previewing now.</param>
/// <param name="StartPreview">Starts this section's preview.</param>
public sealed record StartOfYearRestoreAnswers(
    Func<Task<IReadOnlyList<int>>> StopEveryPreviewOfTheCourse,
    Func<BackupItem, Task> RestoreWholeCourse,
    Func<IReadOnlyCollection<int>> SectionsOfTheCourseNow,
    Func<int, bool> IsPreviewing,
    Action<int> StartPreview);

/// <summary>
/// The Get Ready sheet's offer after Go stopped part way (#899 W8c-2b, the
/// mac's <c>StartOfYearSheetModel</c> stopped-part-way stage and
/// <c>StartOfYearPreparation.restoreCourse</c>; Russell's ruling of
/// 2026-11-26): <c>stoppedPartWay</c>, then <c>restoreOffer</c>, answered
/// once by Leave As It Is (changes nothing) or Restore Course (no second
/// question: Archived keeps the course as it is now, so it can be got back).
/// </summary>
public sealed class StartOfYearRestoreOffer
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly Func<bool> _aDeployOfTheCourseRuns;
    private bool _answered;
    private bool _restoreRan;

    // ---- Computed properties ---------------------------------------------------------

    /// <summary>The stop Go made, with the backup it made.</summary>
    public StartOfYearStoppedPartWay Stop { get; }

    /// <summary>Whether either button has answered the offer.</summary>
    public bool IsAnswered => _answered;

    /// <summary>What the sheet says, in order: <c>stoppedPartWay</c>, then <c>restoreOffer</c>. No hidden name.</summary>
    public IReadOnlyList<string> Sentences =>
    [
        StartOfYearWording.Fill(StartOfYearWording.StoppedPartWay, ("section", Stop.Section.ToString()), ("course", Stop.CourseCode)),
        StartOfYearWording.Fill(StartOfYearWording.RestoreOffer, ("course", Stop.CourseCode), ("backup", Path.GetFileName(Stop.Backup.FilePath))),
    ];

    /// <summary>The restore's own busy sentence, said while a deploy holds Restore Course back.</summary>
    public string HeldBackSentence => CourseRestorer.BusyTitle(Stop.CourseCode) + "\n" + CourseRestorer.BusyMessage;

    // ---- Initializer -----------------------------------------------------------------

    /// <param name="aDeployOfTheCourseRuns">Asked in the press's own turn (<c>CourseActivity.IsPublishing</c>).</param>
    public StartOfYearRestoreOffer(StartOfYearStoppedPartWay stop, Func<bool> aDeployOfTheCourseRuns)
    {
        Stop = stop;
        _aDeployOfTheCourseRuns = aDeployOfTheCourseRuns;
    }

    // ---- Functions -------------------------------------------------------------------

    /// <summary>
    /// Restore Course pressed, decided in the press's own turn: while a deploy
    /// of the course runs it is held back and the offer stays unanswered;
    /// otherwise the offer is answered and the dialog closes.
    /// </summary>
    public RestoreCoursePress RestoreCourseIsPressed()
    {
        if (_answered) return RestoreCoursePress.AlreadyAnswered;
        if (_aDeployOfTheCourseRuns()) return RestoreCoursePress.HeldBackByADeploy;
        _answered = true;
        return RestoreCoursePress.Closes;
    }

    /// <summary>Leave As It Is: answers the offer and changes nothing; the backup stays in Backups. False when it was already answered.</summary>
    public bool LeaveAsItIs()
    {
        if (_answered) return false;
        _answered = true;
        return true;
    }

    /// <summary>
    /// After the dialog has closed on Restore Course: every running preview of
    /// the course is stopped, the whole-course restore runs with the backup Go
    /// made, and each stopped preview is started again once, if the course as
    /// restored still has that section and it is not already running. Runs
    /// once, and only after <see cref="RestoreCourseIsPressed"/> closed the offer.
    /// </summary>
    public async Task RestoreCourseAsync(StartOfYearRestoreAnswers answers)
    {
        if (!_answered || _restoreRan) return;
        _restoreRan = true;
        IReadOnlyList<int> stopped = await answers.StopEveryPreviewOfTheCourse();
        await answers.RestoreWholeCourse(Stop.Backup);
        IReadOnlyCollection<int> sectionsNow = answers.SectionsOfTheCourseNow();
        var started = new HashSet<int>();
        foreach (int section in stopped)
        {
            if (!sectionsNow.Contains(section)) continue;
            if (!started.Add(section)) continue;
            if (answers.IsPreviewing(section)) continue;
            answers.StartPreview(section);
        }
    }
}
