using System;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// The two questions asked before a running task is stopped (#1009, the
/// mac's #988, Russell's rulings of 2026-11-19): "Stop the deploy?" for a
/// section's deploy and "Stop this share?" for a share of unit plans. A
/// preview stops at once and has no question, so a preview's panel holds
/// <c>null</c> where a question would be.
/// </summary>
public enum StopQuestion { Deploy, Share }

/// <summary>Where a change to a stop question's setting was made, for its trail line.</summary>
public enum StopQuestionChangedFrom
{
    /// <summary>The question's own Don't ask again box, ticked with the stop.</summary>
    DontAskAgain,

    /// <summary>File ▸ Settings ▸ Deploying ▸ Stopping.</summary>
    Settings,
}

/// <summary>
/// What a teacher reads in the two stop questions and in Settings ▸ Deploying
/// ▸ Stopping: <c>shared-rules.json</c> → <c>stopQuestions</c>, the copy both
/// apps read (<c>StopQuestionsContractTests</c> pins every word here to it).
/// The mac's <c>DeployStopWording</c>, <c>ShareStopWording</c> and
/// <c>StopQuestionSettingsWording</c>.
/// </summary>
public static class StopQuestionWording
{
    public const string DeployTitle = "Stop the deploy?";
    public const string DeployMessage = "The website may be left partly updated until you deploy again.";
    public const string DeployStopButton = "Stop Deploy";
    public const string DeploySettingLabel = "Ask before stopping a deploy";

    public const string ShareTitle = "Stop this share?";
    /// <summary>True today; becomes <c>messageOnceAllOrNothing</c> when #992's all-or-nothing share lands.</summary>
    public const string ShareMessage = "The unit plans may be left partly shared until you share them again.";
    public const string ShareStopButton = "Stop Share";
    public const string ShareSettingLabel = "Ask before stopping a share of unit plans";

    /// <summary>Both questions' cancelling button: "Always use 'Cancel' to title a button that cancels the alert's action."</summary>
    public const string CancelButton = "Cancel";

    /// <summary>The box on each question (the app's Obsidian offer says exactly this too).</summary>
    public const string DontAskAgain = "Don't ask again";

    /// <summary>The section's header in File ▸ Settings ▸ Deploying.</summary>
    public const string SectionHeader = "Stopping";

    /// <summary>
    /// The section's footer, Windows' words (<c>stopQuestions.windowsWording.footer</c>):
    /// Windows has no Command-Period, so it names Escape alone.
    /// </summary>
    public const string Footer = "When one is off, Cancel stops that task at once, and so does the Escape key.";

    public static string Title(StopQuestion question) => question == StopQuestion.Deploy ? DeployTitle : ShareTitle;
    public static string Message(StopQuestion question) => question == StopQuestion.Deploy ? DeployMessage : ShareMessage;
    public static string StopButton(StopQuestion question) => question == StopQuestion.Deploy ? DeployStopButton : ShareStopButton;
    public static string SettingLabel(StopQuestion question) => question == StopQuestion.Deploy ? DeploySettingLabel : ShareSettingLabel;

    /// <summary>
    /// The trail line for a change to one question's setting
    /// (<c>stopQuestions.trail</c>, the event "stop question setting changed"),
    /// the same line the mac writes.
    /// </summary>
    public static string TrailLine(StopQuestion question, bool asked, StopQuestionChangedFrom place)
    {
        string onOrOff = asked ? "on" : "off";
        return place == StopQuestionChangedFrom.Settings
            ? $"Settings ▸ Deploying — {SettingLabel(question)} {onOrOff}"
            : $"{SettingLabel(question)} {onOrOff}, from Don't ask again in “{Title(question)}”";
    }

    /// <summary>
    /// Turns a question on or off, saving at once, and writes its one trail
    /// line when that changed anything. The Settings row and the question's
    /// box are the same setting. <paramref name="note"/> is the trail (a test
    /// passes its own recorder).
    /// </summary>
    public static void SetAsked(StopQuestion question, bool asked, AppSettings settings, StopQuestionChangedFrom place,
                                Action<string>? note = null)
    {
        if (!settings.ChangeAsksBeforeStopping(question, asked)) return;
        string line = TrailLine(question, asked, place);
        if (note is not null) note(line);
        else ActivityTrail.Note(ActivityTrail.Event.StopQuestionSettingChanged, line);
    }
}

/// <summary>
/// A task panel's stop question while it is being asked (#1009, the mac's
/// <c>StopQuestionAsking</c>): whether it is open, and its Don't ask again
/// box. The question's two buttons call <see cref="ChooseStop"/> and
/// <see cref="ChooseCancel"/>, so what each remembers is tested without a
/// window, case by case from <c>stopQuestions.cases</c>.
/// </summary>
/// <remarks>
/// The box counts only when the teacher goes on to stop; Cancel remembers
/// nothing; each question has its own setting; while a question is off,
/// Cancel stops that task at once, as a preview's does.
/// </remarks>
public sealed class StopQuestionAsking
{
    private readonly AppSettings _settings;
    private readonly Action<string>? _note;

    /// <param name="question">The question this panel asks before stopping its task; null for a preview, which stops at once.</param>
    /// <param name="settings">Where whether the question is still asked is read and remembered.</param>
    /// <param name="note">The trail; null writes the real one.</param>
    public StopQuestionAsking(StopQuestion? question, AppSettings settings, Action<string>? note = null)
    {
        Question = question;
        _settings = settings;
        _note = note;
    }

    public StopQuestion? Question { get; }

    /// <summary>True while the question is showing.</summary>
    public bool IsAsking { get; private set; }

    /// <summary>The question's Don't ask again box: unticked each time the question opens, read only by <see cref="ChooseStop"/>.</summary>
    public bool DontAskAgain { get; set; }

    /// <summary>Whether stopping asks first now: there is a question and the teacher has not turned it off.</summary>
    public bool AsksBeforeStopping => Question is { } question && _settings.AsksBeforeStopping(question);

    /// <summary>
    /// The panel's Cancel was pressed, by click, by UI Automation or by its
    /// key. Returns whether the task should stop now: true when nothing is
    /// asked. Otherwise the question opens with its box unticked, if the task
    /// can still be stopped, and nothing stops yet.
    /// </summary>
    public bool PressCancel(bool taskCanStillBeStopped)
    {
        if (!AsksBeforeStopping) return true;
        if (taskCanStillBeStopped)
        {
            DontAskAgain = false;
            IsAsking = true;
        }
        return false;
    }

    /// <summary>
    /// Stop Deploy or Stop Share. A ticked box turns this question off, and
    /// only this one, writing its trail line; an unticked one changes nothing.
    /// The caller then stops the task.
    /// </summary>
    public void ChooseStop()
    {
        if (DontAskAgain && Question is { } question)
            StopQuestionWording.SetAsked(question, false, _settings, StopQuestionChangedFrom.DontAskAgain, _note);
        IsAsking = false;
        DontAskAgain = false;
    }

    /// <summary>The question's Cancel (its Close button, which Escape presses): the task runs on and nothing is remembered.</summary>
    public void ChooseCancel()
    {
        IsAsking = false;
        DontAskAgain = false;
    }

    /// <summary>The task ended while the question was open: nothing is left to stop, so the question goes.</summary>
    public void TaskEnded() => IsAsking = false;
}

/// <summary>
/// Whether the Escape key, arriving at the task panel's visible Cancel
/// (a <c>KeyboardAccelerator</c> on that button, #1009), presses it. Decided
/// as each key arrives. While an editable text box has the focus the key is
/// the box's (Russell's ruling on #988: "while any text box has the focus,
/// Escape and Command-Period both belong to the box; the Cancel button still
/// stops the task by click"); read-only text, such as the console's output,
/// is not a box. A Cancel that is not on screen (its row collapsed, or the
/// Problems tab over it) holds no key, and nor does one under a dialog.
/// </summary>
public static class StopKey
{
    public static bool GoesToCancel(bool cancelIsShown, bool taskIsRunning, bool aDialogIsOpen, bool anEditableTextBoxHasTheFocus) =>
        cancelIsShown && taskIsRunning && !aDialogIsOpen && !anEditableTextBoxHasTheFocus;
}
