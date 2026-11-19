using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// "Close Obsidian to open {course}?" (#1003, the mac's #995, finding D21 of
/// #975): asked before Plantoir closes a running Obsidian to add a course it
/// has never seen to Obsidian's list. Obsidian keeps that list in memory and
/// writes it back whole when it quits, so a course can be added only while it
/// is closed. Until #1003 Windows simply quit it (<c>FolderActions.OpenInObsidian</c>),
/// with every course open in it, and nobody was asked. The words and the rule
/// are <c>contracts/shared-rules.json</c> → <c>obsidianNeverClosedUnasked</c>.
/// </summary>
/// <remarks><paramref name="Page"/> is the file to open when one is named (a section's previewed page, How I Teach); null opens <paramref name="Folder"/>.</remarks>
public sealed record ObsidianClosingRequest(Course Course, string Folder, string? Page = null);

/// <summary>The question's words (<c>obsidianNeverClosedUnasked.wording</c>) and the alert when the answer cannot finish (<c>couldNotOpen</c>).</summary>
public static class ObsidianClosingWording
{
    public const string Title = "Close Obsidian to open {course}?";
    public const string Message = "Obsidian has not opened {course} before. It can add a course to its list only while it is closed, so Plantoir closes Obsidian, adds {course}, and opens it again.";
    public const string ClosesLabel = "Closes";
    public const string ClosesValue = "Obsidian, with every course open in it";
    public const string OpensAgainLabel = "Opens again";
    public const string OpensAgainValue = "{course}, and everything else Obsidian had open";
    public const string KeptLabel = "Kept";
    public const string KeptValue = "Everything you have written";

    /// <summary>The question's two buttons: the go-ahead says Obsidian closes (ruling Q13), and Cancel backs out.</summary>
    public const string CloseAndOpen = "Close Obsidian and Open";
    public const string Cancel = "Cancel";

    /// <summary>The add-ons offer's yes, in place of Add Them, whenever that yes closes Obsidian.</summary>
    public const string OfferAddClosingObsidian = "Close Obsidian and Add Them";

    /// <summary>Russell's ruling 2 on #995 (2026-11-19): the alert when Close Obsidian and Open cannot finish.</summary>
    public const string CouldNotOpenTitle = "Could not open {course} in Obsidian";
    public const string CouldNotOpenDidNotClose = "Obsidian did not close, so {course} could not be added to its list. Close Obsidian yourself, then open the course again.";
    public const string CouldNotOpenNotAdded = "Obsidian closed, but {course} could not be added to its list. Close Obsidian yourself, then open the course again.";
    public const string CouldNotOpenOk = "OK";

    public static string Filling(string sentence, string course) => sentence.Replace("{course}", course);

    public static string TitleText(string course) => Filling(Title, course);

    /// <summary>The sentence, a blank line, then the three facts a line each (#834's shape, as the add-ons offer gives them).</summary>
    public static string MessageText(string course) => string.Join("\n",
        Filling(Message, course),
        "",
        ClosesLabel + ": " + Filling(ClosesValue, course),
        OpensAgainLabel + ": " + Filling(OpensAgainValue, course),
        KeptLabel + ": " + Filling(KeptValue, course));

    /// <summary>The alert's sentence for an answer that could not finish; only the two failures have one.</summary>
    public static string CouldNotOpenText(ObsidianClosingTrail.Outcome outcome, string course) => outcome switch
    {
        ObsidianClosingTrail.Outcome.DidNotClose => Filling(CouldNotOpenDidNotClose, course),
        ObsidianClosingTrail.Outcome.NotAdded => Filling(CouldNotOpenNotAdded, course),
        _ => throw new ArgumentOutOfRangeException(nameof(outcome), outcome, "only a failure has an alert"),
    };
}

/// <summary>What each answer leaves on the trail (<c>obsidianNeverClosedUnasked.trail</c>), under "asked to close Obsidian to open a course".</summary>
public static class ObsidianClosingTrail
{
    public enum Outcome { Opened, Cancelled, NotNeeded, DidNotClose, NotAdded }

    public static string Line(Outcome outcome, string course) => outcome switch
    {
        Outcome.Opened => course + " · closed Obsidian to add the course to its list, and opened it",
        Outcome.Cancelled => course + " · chose Cancel: Obsidian was not closed and the course did not open",
        Outcome.NotNeeded => course + " · opened in Obsidian without closing it: by the answer, Obsidian had quit or knew the course",
        Outcome.DidNotClose => course + " · Obsidian did not close, so the course was not added to its list and did not open",
        Outcome.NotAdded => course + " · Obsidian closed, but the course could not be added to its list, so it did not open",
        _ => throw new ArgumentOutOfRangeException(nameof(outcome)),
    };

    public static void Note(Outcome outcome, string course) =>
        ActivityTrail.Note(ActivityTrail.Event.ObsidianClosingAsked, Line(outcome, course));
}

/// <summary>When handing Obsidian a file means closing it first (<c>obsidianNeverClosedUnasked.closeCases</c>), and the close itself.</summary>
public static class ObsidianClosingRule
{
    /// <summary>
    /// Whether handing Obsidian this file means asking first: Obsidian is
    /// running and no vault in its list is the file's folder or holds it.
    /// Closed, Obsidian reads its list fresh when the link starts it, so
    /// nothing is asked. A list that cannot be read holds nothing, so it asks:
    /// the safe direction, since the other way closes Obsidian unasked.
    /// Matched as Windows matches paths (<see cref="ObsidianFigureAddOnsOffer.VaultThatOpens"/>:
    /// either separator, any case, a whole folder name).
    /// </summary>
    public static bool MustAsk(string targetPath, bool obsidianRunning, string? registryText)
    {
        if (!obsidianRunning) return false;
        return ObsidianFigureAddOnsOffer.VaultThatOpens(targetPath, registryText) is null;
    }

    /// <summary>
    /// The answer Close Obsidian and Open, and only that answer (the mac's
    /// <c>FolderActions.closeObsidianAndRegister</c>): notes what Obsidian's
    /// list marks open, quits it and waits, and - only once it is no longer
    /// running - writes the course into its list and opens again what was
    /// open, the course left for the caller to open last. An Obsidian still
    /// running after the wait (a question of its own on screen) is never
    /// written under, since it would write its own list back over ours, and
    /// is handed nothing, since it does not know the course. Answers whether
    /// Obsidian closed. Every step is handed in, so a test drives the rule
    /// without an Obsidian; <c>FolderActions.CloseObsidianAndRegister</c>
    /// hands the real ones.
    /// </summary>
    public static async Task<bool> CloseAndRegisterAsync(
        string vaultPath,
        Func<IReadOnlyList<string>> vaultsMarkedOpen,
        Func<Task> quit,
        Func<bool> stillRunning,
        Action<string> register,
        Func<IReadOnlyList<string>, Task> reopen)
    {
        IReadOnlyList<string> wereOpen = vaultsMarkedOpen();
        await quit();
        if (stillRunning()) return false;
        register(vaultPath);
        var others = new List<string>();
        foreach (string path in wereOpen)
        {
            if (!ObsidianFigureAddOnsOffer.SamePath(path, vaultPath)) others.Add(path);
        }
        await reopen(others);
        return true;
    }
}
