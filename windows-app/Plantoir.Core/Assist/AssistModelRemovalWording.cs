namespace Plantoir.Core.Assist;

/// <summary>
/// The question before a downloaded assistant is removed (#987, finding D22;
/// <c>shared-rules.json</c> → <c>assistantModelChoice.removal.words</c>, the
/// mac's <c>AssistModelLibrary.removeQuestion</c>). Apple's HIG, Alerts: "when
/// people take an uncommon destructive action that they can't undo, it's
/// important to display an alert in case they initiated the action
/// accidentally." Cancel answers Escape; neither button is the default, so
/// Enter does nothing.
/// </summary>
public static class AssistModelRemovalWording
{
    /// <summary>The question: a full question, so sentence case and a question mark.</summary>
    public static string Question(AssistModelTier tier) => $"Remove {tier.DisplayName()}?";

    /// <summary>The sentence under it: what goes, and how to have it back. <paramref name="size"/> is the download's size as this app writes one.</summary>
    public static string Message(string size) =>
        $"Its {size} download is deleted from this PC. To use it again, download it again here.";

    /// <summary>The button beside a download, which opens the question (so it ends in an ellipsis).</summary>
    public const string RemoveCommand = "Remove…";

    /// <summary>The question's button that removes it, trailing.</summary>
    public const string RemoveButton = "Remove";

    /// <summary>The question's button that backs out, with Escape.</summary>
    public const string CancelButton = "Cancel";
}
