namespace Plantoir.Core.Models;

/// <summary>
/// What a teacher reads when taking away a scheduled deploy (#987, Russell
/// 2026-11-18: "the verb for taking away a scheduled deploy is Remove, not
/// cancel"; <c>shared-rules.json</c> → <c>scheduledDeployCancellation.removingOne</c>,
/// the mac's <c>ScheduledDeployRemovalWording</c>). Cancel leads and answers
/// Escape; Remove trails; neither is the default.
/// </summary>
public static class ScheduledDeployRemovalWording
{
    /// <summary>
    /// Section ▸ Remove Scheduled Deploy, and the same item in a section's
    /// right-click menu. No ellipsis since #990 (Russell, 2026-11-20): it only
    /// asks for a confirmation, and an ellipsis goes on a command only when
    /// more information must be provided.
    /// </summary>
    public const string MenuItem = "Remove Scheduled Deploy";

    /// <summary>The question's title: a full question, so sentence case and a question mark.</summary>
    public const string Question = "Remove the scheduled deploy?";

    /// <summary>The button that removes it.</summary>
    public const string RemoveButton = "Remove";

    /// <summary>The button that backs out, with Escape.</summary>
    public const string CancelButton = "Cancel";

    /// <summary>The message when the time is not known.</summary>
    public const string MessageWithoutTime = "This section will no longer deploy on its own.";

    /// <summary>The message under the question: which section, when, and what removing it means.</summary>
    public static string Message(string courseCode, int sectionNumber, string time, string day) =>
        $"{courseCode} Section {sectionNumber} is set to deploy on its own at {time} on {day}. " +
        "Removing it means it will not go out then, and the site stays as it is until you deploy it yourself.";
}
