using System.Text.Json;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// The teacher's one answer about Obsidian's add-ons for diagrams and graphs
/// (#581; the mac's <c>ObsidianFigureAddOnsAnswer</c>), app-wide: one yes
/// covers every course. Stored as the contract's <c>answer.values</c>
/// (<see cref="AppSettings.ObsidianFigureAddOns"/>): never rename one.
/// </summary>
public enum ObsidianFigureAddOnsAnswer { NotAsked, Yes, No }

public static class ObsidianFigureAddOnsAnswers
{
    /// <summary>The stored text as the contract's <c>answer.cases</c> read it: anything else is notAsked.</summary>
    public static ObsidianFigureAddOnsAnswer Reading(string? stored) => stored switch
    {
        "yes" => ObsidianFigureAddOnsAnswer.Yes,
        "no" => ObsidianFigureAddOnsAnswer.No,
        _ => ObsidianFigureAddOnsAnswer.NotAsked,
    };

    /// <summary>The value stored for an answer.</summary>
    public static string Stored(ObsidianFigureAddOnsAnswer answer) => answer switch
    {
        ObsidianFigureAddOnsAnswer.Yes => "yes",
        ObsidianFigureAddOnsAnswer.No => "no",
        _ => "notAsked",
    };
}

/// <summary>
/// The words of #581, in one place — <c>obsidianAddOnsForFigures.wording</c>,
/// with <c>windowsWording</c>'s two sentences where this app says Enter
/// instead of Return. Pinned against the contract by
/// <c>ObsidianFigureAddOnsTests</c>, rule 1's ban applied outside Obsidian's
/// own quoted labels.
/// </summary>
public static class ObsidianFigureAddOnsWording
{
    public const string OfferTitle = "Show diagrams and graphs in Obsidian too?";
    /// <summary><c>windowsWording.offerMessage</c>: Enter, not Return.</summary>
    public const string OfferMessage = "{course} has diagrams or graphs that your class website draws. Plantoir can add the Obsidian add-ons that draw them, so you see the same pictures while you write. Your answer applies to every course that has them.\n\nThe first time each course opens with them, Obsidian asks whether you trust the author of its pages — that is you. Click “Trust author and enable plugins”: pressing Enter chooses the other button. Obsidian then opens its settings in a window of its own, showing the add-ons switched on; close that window and carry on.";
    public const string OfferWhileOpen = "{course} is open in Obsidian now, so Obsidian closes and opens it again to show them. What you've written is kept.";
    public const string OfferAdd = "Add Them";
    public const string OfferNotNow = "Not Now";
    public const string DontAskAgain = "Don't ask again";
    public const string ReopenTitle = "Reopen Obsidian to show diagrams and graphs?";
    public const string ReopenMessage = "{course} has diagrams or graphs that Obsidian can't draw yet. Obsidian sees the add-ons that draw them only when it opens the course again, so it closes and opens again. What you've written is kept.\n\nIf Obsidian asks whether you trust the author, click “Trust author and enable plugins”.";
    public const string Reopen = "Reopen Obsidian";
    public const string Later = "Later";
    public const string PaneTitle = "Obsidian";
    public const string SettingLabel = "Add the add-ons that draw diagrams and graphs to courses that have them";
    /// <summary><c>windowsWording.settingFooter</c>: Enter, not Return.</summary>
    public const string SettingFooter = "Plantoir adds them when you open such a course in Obsidian from Plantoir, and after you preview it. The first time each course opens with them, Obsidian asks whether you trust its author: click “Trust author and enable plugins” — pressing Enter chooses “Browse vault in Restricted Mode”. If a course still shows a drawing's text, open Obsidian's Settings ▸ “Community plugins” and click “Exit Restricted mode”. Turning this off adds nothing new and leaves what was added in place.";

    /// <summary>The offer's whole message: the sentence about closing Obsidian added when the course is open in it now.</summary>
    public static string OfferText(string course, bool courseIsOpen)
    {
        string text = Filling(OfferMessage, course);
        if (courseIsOpen) text += "\n\n" + Filling(OfferWhileOpen, course);
        return text;
    }

    public static string Filling(string sentence, string course) => sentence.Replace("{course}", course);
}

/// <summary>
/// The rules of #581's asking, as pure functions, so the contract's cases run
/// against them without a window: <c>offerCases</c>, <c>previewCases</c>,
/// <c>whichVaultOpens.cases</c>, and what counts as open in Obsidian.
/// </summary>
public static class ObsidianFigureAddOnsOffer
{
    /// <summary>Everything Open in Obsidian knows when it decides.</summary>
    public sealed record Situation(
        bool Reference, bool ObsidianInstalled, ObsidianFigureAddOnsAnswer Answer, bool SuppressedThisRun,
        bool WouldAdd, bool VaultIsTheCourse, bool CourseOpenInObsidian, bool ReopenDeclinedThisRun);

    /// <summary>What Open in Obsidian does (<c>offerCases.decision</c>).</summary>
    public enum Decision { JustOpen, NotTheVault, Offer, OfferWhileOpen, InstallThenOpen, AskReopen }

    /// <summary>What a finished preview does (<c>previewCases.decision</c>).</summary>
    public enum PreviewDecision { Nothing, Install }

    /// <summary>Whether Open in Obsidian scans at all: never for a reference course, without Obsidian, with the answer no, or after Not Now this run.</summary>
    public static bool Scans(bool reference, bool obsidianInstalled, ObsidianFigureAddOnsAnswer answer, bool suppressedThisRun)
    {
        if (reference || !obsidianInstalled) return false;
        if (answer == ObsidianFigureAddOnsAnswer.No) return false;
        if (answer == ObsidianFigureAddOnsAnswer.NotAsked && suppressedThisRun) return false;
        return true;
    }

    public static Decision Decide(Situation situation)
    {
        if (!Scans(situation.Reference, situation.ObsidianInstalled, situation.Answer, situation.SuppressedThisRun)) return Decision.JustOpen;
        if (!situation.WouldAdd) return Decision.JustOpen;
        if (!situation.VaultIsTheCourse) return Decision.NotTheVault;
        if (situation.Answer == ObsidianFigureAddOnsAnswer.NotAsked)
            return situation.CourseOpenInObsidian ? Decision.OfferWhileOpen : Decision.Offer;
        if (!situation.CourseOpenInObsidian) return Decision.InstallThenOpen;
        return situation.ReopenDeclinedThisRun ? Decision.JustOpen : Decision.AskReopen;
    }

    /// <summary><c>previewCases</c>: only after the yes, never into a course open in Obsidian, never without Obsidian.</summary>
    public static PreviewDecision AfterAPreview(bool reference, bool obsidianInstalled, ObsidianFigureAddOnsAnswer answer,
                                                bool wouldAdd, bool vaultIsTheCourse, bool courseOpenInObsidian)
    {
        if (reference || !obsidianInstalled || answer != ObsidianFigureAddOnsAnswer.Yes) return PreviewDecision.Nothing;
        if (!wouldAdd || !vaultIsTheCourse || courseOpenInObsidian) return PreviewDecision.Nothing;
        return PreviewDecision.Install;
    }

    /// <summary>Each registered vault: its path and whether the registry marks it open. Null when the registry is not an object with a <c>vaults</c> object.</summary>
    public static List<(string Path, bool Open)>? Vaults(string? registryText)
    {
        if (registryText is null) return null;
        try
        {
            using var document = JsonDocument.Parse(registryText);
            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty("vaults", out var vaults) || vaults.ValueKind != JsonValueKind.Object) return null;
            var found = new List<(string, bool)>();
            foreach (var entry in vaults.EnumerateObject())
            {
                if (entry.Value.ValueKind != JsonValueKind.Object) continue;
                if (!entry.Value.TryGetProperty("path", out var path) || path.ValueKind != JsonValueKind.String) continue;
                bool open = entry.Value.TryGetProperty("open", out var flag) && flag.ValueKind == JsonValueKind.True;
                found.Add((path.GetString()!, open));
            }
            return found;
        }
        catch { return null; }
    }

    /// <summary>The paths the registry marks open, sorted so the reopening order is the same every time.</summary>
    public static List<string> OpenVaultPaths(string? registryText) =>
        (Vaults(registryText) ?? new()).Where(vault => vault.Open).Select(vault => vault.Path)
            .OrderBy(path => path, StringComparer.Ordinal).ToList();

    /// <summary>The vaults counted as open: every one the registry marks open, while Obsidian is running — windows never counted.</summary>
    public static List<string> VaultsOpen(bool obsidianRunning, string? registryText) =>
        obsidianRunning ? OpenVaultPaths(registryText) : new List<string>();

    /// <summary>
    /// Whether the course counts as open in Obsidian: Obsidian is RUNNING and
    /// its registry marks the course open — or the registry cannot be read at
    /// all while it runs (Obsidian rewrites it in place, so a read can land
    /// mid-write; not knowing is not "closed"). However many windows are on
    /// screen: a hidden or minimised Obsidian holds the list in memory all the
    /// same (the mac's implementation review B1, measured).
    /// </summary>
    public static bool CourseIsOpen(string coursePath, bool obsidianRunning, string? registryText)
    {
        if (!obsidianRunning) return false;
        if (Vaults(registryText) is null) return true;
        return OpenVaultPaths(registryText).Any(path => SamePath(path, coursePath));
    }

    /// <summary>
    /// The vault Obsidian opens for a path: the LONGEST registered vault that
    /// is the path or holds it (read from Obsidian 1.13.7's main.js), or null
    /// when none does — and then Plantoir registers the course itself.
    /// Compared as Windows compares paths: either separator, any case.
    /// </summary>
    public static string? VaultThatOpens(string targetPath, string? registryText)
    {
        string? best = null;
        string target = Normal(targetPath);
        foreach (var (path, _) in Vaults(registryText) ?? new())
        {
            string vault = Normal(path);
            bool holds = string.Equals(target, vault, StringComparison.OrdinalIgnoreCase)
                         || target.StartsWith(vault + "\\", StringComparison.OrdinalIgnoreCase);
            if (holds && vault.Length > (best is null ? -1 : Normal(best).Length)) best = path;
        }
        return best;
    }

    /// <summary>Whether the vault that opens for <paramref name="targetPath"/> is the course (none: the course will be registered as one).</summary>
    public static bool VaultIsTheCourse(string targetPath, string coursePath, string? registryText) =>
        VaultThatOpens(targetPath, registryText) is not { } vault || SamePath(vault, coursePath);

    public static bool SamePath(string one, string other) =>
        string.Equals(Normal(one), Normal(other), StringComparison.OrdinalIgnoreCase);

    private static string Normal(string path) => path.Replace('/', '\\').TrimEnd('\\');
}

/// <summary>
/// The trail's words for #581 (<c>obsidianAddOnsForFigures.trail</c>): add-ons
/// by name and version, never a page's words.
/// </summary>
public static class ObsidianFigureAddOnsTrail
{
    /// <summary>How the offer was answered.</summary>
    public enum Answered { AddThem, NotNow, NotNowDontAskAgain }

    /// <summary>What started a pass.</summary>
    public enum Trigger { OpenInObsidian, AfterAPreview, AfterReopening }

    public static string Offered(string course, Answered answered) =>
        course + " · asked to add Obsidian's add-ons for diagrams and graphs — " + answered switch
        {
            Answered.AddThem => ObsidianFigureAddOnsWording.OfferAdd,
            Answered.NotNow => ObsidianFigureAddOnsWording.OfferNotNow,
            _ => ObsidianFigureAddOnsWording.OfferNotNow + ", don't ask again",
        };

    public static string NotTheVault(string course) =>
        course + " · did not offer Obsidian's add-ons for diagrams and graphs: Obsidian opens this course as part of a larger vault, which never reads the course's own settings";

    public static string Reopened(string course) => course + " · reopened Obsidian to show the add-ons for diagrams and graphs";

    public static string ReopenDeclined(string course) =>
        course + " · chose Later: Obsidian was not reopened and its add-ons for diagrams and graphs were not added";

    public static string DidNotClose(string course) =>
        course + " · Obsidian did not close, so its add-ons for diagrams and graphs were not added";

    public static string SettingChanged(bool on) => "Settings ▸ Obsidian — add-ons for diagrams and graphs " + (on ? "on" : "off");

    public static string TriggerWords(Trigger trigger) => trigger switch
    {
        Trigger.OpenInObsidian => "at Open in Obsidian",
        Trigger.AfterAPreview => "after a preview",
        _ => "after reopening Obsidian",
    };

    /// <summary>The line for a pass, or null when there is nothing worth a line: no results, or every add-on simply already there.</summary>
    public static string? Pass(string course, Trigger trigger, IReadOnlyList<ObsidianFigureAddOns.Result> results)
    {
        if (results.Count == 0) return null;
        if (results.All(result => result.Outcome.Kind == ObsidianFigureAddOns.OutcomeKind.AlreadyThere)) return null;
        string start = course + " · Obsidian add-ons for diagrams and graphs (" + TriggerWords(trigger) + "): ";
        if (results[0].Outcome.IsARefusal) return start + RefusalWords(results[0].Outcome);
        return start + string.Join("; ", results.Select(Words));
    }

    /// <summary>One add-on's part of the line (<c>trail.pass.parts</c>).</summary>
    public static string Words(ObsidianFigureAddOns.Result result)
    {
        string named = result.AddOn.Name, pinned = result.AddOn.Version;
        var outcome = result.Outcome;
        return outcome.Kind switch
        {
            ObsidianFigureAddOns.OutcomeKind.Added => $"{named} {pinned} added",
            ObsidianFigureAddOns.OutcomeKind.AlreadyThere => $"{named} {pinned} already there",
            ObsidianFigureAddOns.OutcomeKind.AlreadyThereSwitchedOff => $"{named} {pinned} already there and switched off in Obsidian, so left off",
            ObsidianFigureAddOns.OutcomeKind.LeftAloneTheirs => $"{named} left alone (the teacher's own copy, {outcome.Version})",
            ObsidianFigureAddOns.OutcomeKind.LeftAloneOtherVersion => $"{named} left alone ({outcome.Version}, not the {pinned} Plantoir added)",
            ObsidianFigureAddOns.OutcomeKind.LeftAloneUnreadable => $"{named} left alone (what is there could not be read)",
            ObsidianFigureAddOns.OutcomeKind.CouldNotWrite => $"{named} could not be added: {outcome.Reason}",
            _ => $"{named} — {RefusalWords(outcome)}",
        };
    }

    /// <summary>The words for a pass refused before any add-on was looked at (<c>trail.pass.refusals</c>).</summary>
    public static string RefusalWords(ObsidianFigureAddOns.Outcome outcome) => outcome.Kind switch
    {
        ObsidianFigureAddOns.OutcomeKind.RefusedListUnreadable => "nothing added: Obsidian's list of add-ons could not be read",
        ObsidianFigureAddOns.OutcomeKind.RefusedLink => "nothing added: Obsidian's settings folder or its add-ons folder is a link",
        ObsidianFigureAddOns.OutcomeKind.RefusedCarriedCopy => "nothing added: this copy of Plantoir's add-ons is missing or does not match",
        ObsidianFigureAddOns.OutcomeKind.RefusedSettingsNotSeeded => "nothing added: Obsidian's settings for the course could not be set up first",
        _ => "nothing added",
    };
}

/// <summary>
/// What #581 remembers for this run of Plantoir only: Not Now, Later, the
/// lines already written, and the courses being opened right now. Touched on
/// the UI thread only (the route's awaits return there).
/// </summary>
public static class ObsidianFigureAddOnsThisRun
{
    /// <summary>Not Now was chosen: no question again until Plantoir next starts.</summary>
    public static bool Suppressed { get; set; }

    /// <summary>Courses (by folder path, any case) whose reopen question was answered Later.</summary>
    public static HashSet<string> ReopenDeclined { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Lines written already, so a refusal, a left-alone or a failed write is said once per course per run.</summary>
    public static HashSet<string> LinesWritten { get; } = new(StringComparer.Ordinal);

    /// <summary>Courses Open in Obsidian is working on — a second click while the first scans does nothing.</summary>
    public static HashSet<string> BeingOpened { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Forgets everything — for a test.</summary>
    public static void Forget()
    {
        Suppressed = false;
        ReopenDeclined.Clear();
        LinesWritten.Clear();
        BeingOpened.Clear();
    }

    /// <summary>Writes a pass's line if it is worth one: always when something was added, otherwise once per course per run.</summary>
    public static void NotePass(string course, ObsidianFigureAddOnsTrail.Trigger trigger, IReadOnlyList<ObsidianFigureAddOns.Result> results)
    {
        if (ObsidianFigureAddOnsTrail.Pass(course, trigger, results) is not { } line) return;
        if (results.All(result => result.Outcome.Kind != ObsidianFigureAddOns.OutcomeKind.Added))
        {
            string remembered = ObsidianFigureAddOnsTrail.Pass(course, ObsidianFigureAddOnsTrail.Trigger.OpenInObsidian, results) ?? line;
            if (!LinesWritten.Add(remembered)) return;
        }
        ActivityTrail.Note(ActivityTrail.Event.ObsidianAddOnsAdded, line);
    }

    /// <summary>The "did not offer" line, once per course per run.</summary>
    public static void NoteNotTheVault(string course)
    {
        string line = ObsidianFigureAddOnsTrail.NotTheVault(course);
        if (LinesWritten.Add(line)) ActivityTrail.Note(ActivityTrail.Event.ObsidianAddOnsOffered, line);
    }
}
