using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Models;

/// <summary>
/// The offer the alert makes when a one-file settings change stopped part way
/// and Plantoir could not finish it at once (#899 W8c-1b; the mac's
/// <c>SettingPutBackOffer</c>, Russell's ruling of 2026-11-26): which step,
/// which setting, and what it held. Its words are the contract's, read by key
/// (<c>referenceCourses.wording</c>), never retyped.
/// </summary>
/// <param name="Seq">The step left in flight, the one Put It Back takes.</param>
/// <param name="Setting">The setting's name in lower case, as the alert says it: "school year", "course name", "folder name", or "course settings" for several at once.</param>
/// <param name="ValueBefore">The value before, as the teacher reads it; null when the settings go back together.</param>
public sealed record SettingPutBackOffer(long Seq, string Setting, string? ValueBefore)
{
    // ---- Computed properties -------------------------------------------------------

    /// <summary>The alert's title: <c>settingCouldNotBeChanged</c>.</summary>
    public string Title => ReferenceCourse.SettingCouldNotBeChanged(Setting);

    /// <summary>The alert's text: <c>settingCanBePutBack</c> with the one value, or <c>settingsCanBePutBack</c>.</summary>
    public string InformativeText =>
        ValueBefore is { } value ? ReferenceCourse.SettingCanBePutBack(value) : ReferenceCourse.SettingsCanBePutBack;

    /// <summary>The close button (Escape): Not Now.</summary>
    public string NotNowButton => ReferenceCourse.NotNowButton;

    /// <summary>The primary and default button (Enter): Put It Back.</summary>
    public string PutItBackButton => ReferenceCourse.PutItBackButton;
}

/// <summary>The teacher's answer to the alert.</summary>
public enum SettingPutBackAnswer
{
    NotNow,
    PutItBack,
}

/// <summary>
/// How a settings change went once it reached the door (the mac's
/// <c>SettingWriteResult</c>): saved (a stop the door finished by content
/// included), refused with the caller's own sentence, or could not finish,
/// with the offer to make.
/// </summary>
public abstract record SettingWriteResult
{
    public sealed record Saved : SettingWriteResult;

    public sealed record Refused(string Sentence) : SettingWriteResult;

    public sealed record CouldNotFinish(SettingPutBackOffer Offer) : SettingWriteResult;
}

/// <summary>
/// A change that stopped part way and could not be finished, thrown by a
/// caller whose result is otherwise an exception (Save Course Settings,
/// Rename folder): carries the offer. Its message is the alert's title, and
/// names no file.
/// </summary>
public sealed class SettingCouldNotFinishException(SettingPutBackOffer offer) : Exception(offer.Title)
{
    public SettingPutBackOffer Offer { get; } = offer;
}

/// <summary>
/// The ONE place the alert's answer is decided and acted on (#899 W8c-1b), for
/// all three callers, so a test drives it without a window.
/// </summary>
public static class SettingPutBack
{
    // ---- Stored properties ---------------------------------------------------------

    /// <summary>
    /// What a failure on these paths says instead of a file's name (the mac's
    /// <c>JournaledStepError.notMade</c>, the settings sweep's LOW A2), as
    /// <c>referenceCourses.wording.settingCouldNotBeChangedNote</c> quotes it
    /// ("Could not save: The file couldn’t be saved.").
    /// </summary>
    public const string NamingNoFile = "The file couldn’t be saved.";

    // ---- Functions -------------------------------------------------------------------

    /// <summary>
    /// The answer once the alert has closed. The button pressed decides it,
    /// whichever order the dialog's closing and its button's action run: a
    /// press of Put It Back seen before the close, or a close reported as Put
    /// It Back's, is Put It Back; a close alone (Not Now, Escape) is Not Now,
    /// and writes nothing (the mac's HIGH 1).
    /// </summary>
    public static SettingPutBackAnswer AnswerOnceClosed(bool putItBackWasPressed, bool closedByPutItBack) =>
        putItBackWasPressed || closedByPutItBack ? SettingPutBackAnswer.PutItBack : SettingPutBackAnswer.NotNow;

    /// <summary>The trail's line for the offer (the mac's <c>SettingStopTrail.offered</c>).</summary>
    public static string OfferedLine(string setting, string course) =>
        "the " + setting + " for " + course + " could not be changed — stopped part way, offered to put back";

    /// <summary>The trail's line for Not Now (<c>SettingStopTrail.notNow</c>).</summary>
    public static string NotNowLine(string setting, string course) =>
        "the " + setting + " for " + course + " was left as it stopped (Not Now): the next launch settles it";

    /// <summary>The trail's line for Put It Back (<c>SettingStopTrail.putItBack</c>).</summary>
    public static string PutItBackLine(string setting, string course, bool putBack) =>
        putBack
            ? "the " + setting + " for " + course + " was put back as it was (Put It Back)"
            : "the " + setting + " for " + course + " could not be put back either (Put It Back): left for the next launch";

    /// <summary>
    /// Acts on the answer. Not Now leaves the step for the next launch's
    /// recovery and its line. Put It Back writes the old value back through
    /// the door (<see cref="UndoDoor.PutBackAtOnce"/>), has the caller read the
    /// settings from the file again, and leaves its line; null when put back,
    /// else <paramref name="failedSentence"/>, the caller's own failure
    /// sentence with no file name.
    /// </summary>
    internal static string? Answer(SettingPutBackAnswer answer, SettingPutBackOffer offer, string course,
                                   ActivityTrail.Event trailEvent, string trailSetting, string failedSentence,
                                   Action readTheFileAgain, UndoDoor? door)
    {
        if (answer == SettingPutBackAnswer.NotNow)
        {
            ActivityTrail.Note(trailEvent, NotNowLine(trailSetting, course));
            return null;
        }
        UndoDoor theDoor = door ?? UndoForThisProcess.Current.Door();
        bool putBack = theDoor.PutBackAtOnce(offer.Seq) == UndoPutBackVerdict.PutBack;
        try { readTheFileAgain(); } catch { }
        ActivityTrail.Note(trailEvent, PutItBackLine(trailSetting, course, putBack));
        return putBack ? null : failedSentence;
    }

    /// <summary>Set School Year's answer: its line by "school year"; a failed Put It Back says <c>couldNotSetSchoolYear</c>.</summary>
    public static string? AnswerForTheSchoolYear(SettingPutBackAnswer answer, SettingPutBackOffer offer, Course course) =>
        AnswerForTheSchoolYear(answer, offer, course, null);

    internal static string? AnswerForTheSchoolYear(SettingPutBackAnswer answer, SettingPutBackOffer offer, Course course, UndoDoor? door) =>
        Answer(answer, offer, course.Code, ActivityTrail.Event.SettingsCouldNotBeSaved, "school year",
               ReferenceCourse.CouldNotSetSchoolYear(ReferenceCourse.ShownCode(course)),
               () => ReadAgain(course), door);

    /// <summary>Save's answer: its line by the offer's setting; a failed Put It Back says Save's failure line, naming no file.</summary>
    public static string? AnswerForASave(SettingPutBackAnswer answer, SettingPutBackOffer offer, Course course) =>
        AnswerForASave(answer, offer, course, null);

    internal static string? AnswerForASave(SettingPutBackAnswer answer, SettingPutBackOffer offer, Course course, UndoDoor? door) =>
        Answer(answer, offer, course.Code, ActivityTrail.Event.SettingsCouldNotBeSaved, offer.Setting,
               CourseConfiguration.SaveFailureLine(new UndoStepNotMadeException()),
               () => ReadAgain(course), door);

    /// <summary>
    /// A rename's answer: its line by "folder name" and the old name, under
    /// <c>folder renamed</c>; a failed Put It Back says <c>renameFolderStoppedPartWay</c>,
    /// naming no file.
    /// </summary>
    public static string? AnswerForARename(SettingPutBackAnswer answer, SettingPutBackOffer offer, Course course) =>
        AnswerForARename(answer, offer, course, null);

    internal static string? AnswerForARename(SettingPutBackAnswer answer, SettingPutBackOffer offer, Course course, UndoDoor? door) =>
        Answer(answer, offer, course.Code, ActivityTrail.Event.FolderRenamed, "folder name " + (offer.ValueBefore ?? ""),
               SpecialNames.RenameFolderStoppedPartWay.Replace("{old}", offer.ValueBefore ?? "").Replace("{said}", NamingNoFile),
               () => ReadAgain(course), door);

    /// <summary>The copy in memory read from the file again: what Put It Back wrote is what it now holds.</summary>
    private static void ReadAgain(Course course)
    {
        if (!course.Configuration.RevertToFile(course.ConfigFilePath)) course.Configuration.DiscardChanges();
    }
}
