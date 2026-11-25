using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Classes ▸ Roll Over to a New Year… (#954, the mac's #897 piece B): the one
/// rule that decides what its dialog asks about the website, and what its call
/// sends. The mac's <c>RollOverFromTheMenu</c>, rule for rule.
/// </summary>
/// <remarks>
/// <para>The built-in assistant asks the website question in words and sends
/// <c>website: "new"</c> or <c>"same"</c> once the teacher says one of two
/// sentences. The menu asks it in its dialog, with nothing chosen, and sends
/// the answer in the same argument, so the tool code is the same code. The
/// question is asked ONLY where there is a website to keep or leave: a section
/// never deployed, or one that deploys only to a folder, has no address
/// students saved. In the contract as <c>shared-rules.json</c> →
/// <c>subjectMenus.rollOverSheet</c>.</para>
/// </remarks>
public static class RollOverFromTheMenu
{
    // ---- Types ------------------------------------------------------------------

    /// <summary>What the dialog says about the website (<c>rollOverSheet.websites</c>).</summary>
    public enum Website
    {
        /// <summary>A marker the release walks is on disk: the question, nothing chosen.</summary>
        Asked,
        /// <summary>No marker, and a web host: no website yet. No question; "new".</summary>
        NotDeployedYet,
        /// <summary>No marker, and folders only: nothing to keep or replace. No question; "same".</summary>
        DeploysToAFolder,
        /// <summary>
        /// Cloudflare, and a record the section keeps there already holds the
        /// name a new website started this calendar year would get (the mac's
        /// implementation review's W1; the deploy path's fix is #915). No
        /// question; "same", and the dialog, the plan and the finished line say why.
        /// </summary>
        ANewWebsiteWouldReuseItsAddress,
    }

    /// <summary>The answer that keeps last year's website, as the call spells it.</summary>
    public const string KeepTheSameWebsite = "same";

    /// <summary>The answer that starts a new website, as the call spells it.</summary>
    public const string StartANewWebsite = "new";

    // ---- The rule ---------------------------------------------------------------

    /// <summary>The rule, over its three facts. A website a new one would replace comes first.</summary>
    public static Website WebsiteFor(bool sectionIsPinned, bool hasAHostedDestination, bool aNewWebsiteWouldReuseItsAddress)
    {
        if (aNewWebsiteWouldReuseItsAddress) return Website.ANewWebsiteWouldReuseItsAddress;
        if (sectionIsPinned) return Website.Asked;
        if (hasAHostedDestination) return Website.NotDeployedYet;
        return Website.DeploysToAFolder;
    }

    /// <summary>
    /// The rule, read from the disk and the course's settings: the markers
    /// through <see cref="AssistWorkspace.MarkersTheReleaseWalks"/> (the very
    /// paths <see cref="AssistWorkspace.ReleaseSite"/> moves), the destinations
    /// through <c>AllDeployDestinations</c>, and the Cloudflare names this
    /// section's records hold against <paramref name="year"/>.
    /// </summary>
    public static Website WebsiteFor(string workingFolder, Course course, int section, int year)
    {
        bool hosted = false;
        bool onCloudflare = false;
        foreach (var destination in course.Configuration.AllDeployDestinations)
        {
            if (destination.Type == "local_folder") continue;
            hosted = true;
            if (destination.Type == "cloudflare_pages") onCloudflare = true;
        }
        bool wouldReuse = false;
        if (onCloudflare)
            wouldReuse = ANewWebsiteWouldReuseItsAddress(CloudflareNamesKept(course, section), course.Code, section, year);
        return WebsiteFor(SectionIsPinned(workingFolder, course, section), hosted, wouldReuse);
    }

    /// <summary>
    /// Whether any marker the release walks is on disk for the section, of any
    /// destination type, the legacy one included, an unreadable one included
    /// (<c>rollOverSheet.factKeys.sectionIsPinned</c>).
    /// </summary>
    public static bool SectionIsPinned(string workingFolder, Course course, int section)
    {
        foreach (string marker in AssistWorkspace.MarkersTheReleaseWalks(workingFolder, course, section))
        {
            if (File.Exists(marker)) return true;
        }
        return false;
    }

    /// <summary>Whether the course deploys only to folders, so "the same website" would be untrue of it.</summary>
    public static bool DeploysOnlyToAFolder(Course course)
    {
        foreach (var destination in course.Configuration.AllDeployDestinations)
        {
            if (destination.Type != "local_folder") return false;
        }
        return true;
    }

    // ---- Cloudflare's name (cloudflareAddressReuse) -----------------------------

    /// <summary>
    /// The name <c>deploy.py</c>'s <c>suggest_pages_name</c> gives a NEW
    /// Cloudflare website, without the surname it may add.
    /// </summary>
    public static string CloudflareNameStem(string courseCode, int section, int year)
    {
        string code = courseCode.Length == 0 ? "course" : courseCode;
        return CleanedCloudflareName($"{code}-s{section}-{year}");
    }

    /// <summary>
    /// <c>sanitize_pages_name</c>, character for character: lower case,
    /// anything outside a to z, 0 to 9 to a hyphen, runs of hyphens to one,
    /// none at either end, at most 58 characters.
    /// </summary>
    public static string CleanedCloudflareName(string name)
    {
        var hyphenated = new StringBuilder();
        foreach (char character in name.ToLowerInvariant())
        {
            bool isLetter = character >= 'a' && character <= 'z';
            bool isDigit = character >= '0' && character <= '9';
            if (isLetter || isDigit) hyphenated.Append(character);
            else if (hyphenated.Length == 0 || hyphenated[^1] != '-') hyphenated.Append('-');
        }
        string trimmed = hyphenated.ToString().Trim('-');
        if (trimmed.Length > 58) trimmed = trimmed[..58].TrimEnd('-');
        return trimmed.Length == 0 ? "class-site" : trimmed;
    }

    /// <summary>
    /// Whether a new Cloudflare website started in <paramref name="year"/>
    /// would be given a name one of <paramref name="keptNames"/> holds: the
    /// stem itself, or the stem and a surname.
    /// </summary>
    public static bool ANewWebsiteWouldReuseItsAddress(IReadOnlyList<string> keptNames, string courseCode, int section, int year)
    {
        string stem = CloudflareNameStem(courseCode, section, year);
        foreach (string name in keptNames)
        {
            if (name == stem || name.StartsWith(stem + "-", StringComparison.Ordinal)) return true;
        }
        return false;
    }

    /// <summary>
    /// The <c>name</c> in each of this section's Cloudflare records: the one
    /// deploying reads (<c>.cloudflare_sites/section&lt;N&gt;.json</c>) and
    /// every one a rollover set aside beside it
    /// (<c>section&lt;N&gt;.previous-&lt;stamp&gt;.json</c>). A record that
    /// cannot be read gives no name.
    /// </summary>
    public static List<string> CloudflareNamesKept(Course course, int section)
    {
        var names = new List<string>();
        string folder = Path.Combine(course.DirectoryPath, ".cloudflare_sites");
        string[] entries;
        try { entries = Directory.Exists(folder) ? Directory.GetFiles(folder) : Array.Empty<string>(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return names; }
        string current = $"section{section}.json";
        string setAsidePrefix = $"section{section}.previous-";
        foreach (string entry in entries)
        {
            string fileName = Path.GetFileName(entry);
            bool isCurrent = string.Equals(fileName, current, StringComparison.OrdinalIgnoreCase);
            bool isSetAside = fileName.StartsWith(setAsidePrefix, StringComparison.OrdinalIgnoreCase)
                              && fileName.EndsWith(".json", StringComparison.OrdinalIgnoreCase);
            if (!isCurrent && !isSetAside) continue;
            try
            {
                if (JsonNode.Parse(File.ReadAllText(entry)) is JsonObject record
                    && record["name"] is JsonValue value && value.TryGetValue(out string? name)
                    && !string.IsNullOrEmpty(name))
                    names.Add(name);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
            {
                // A record that cannot be read gives no name.
            }
        }
        return names;
    }

    // ---- What the dialog sends, says and leaves on the trail ---------------------

    /// <summary>
    /// What the call's <c>website</c> carries, or null while the dialog cannot
    /// be sent: the question is up and unanswered. Never anything but "new" or
    /// "same", so <c>rolloverWebsiteNotDecided</c> cannot reach the menu.
    /// </summary>
    public static string? WebsiteSent(Website website, string? answer) => website switch
    {
        Website.Asked => answer is KeepTheSameWebsite or StartANewWebsite ? answer : null,
        Website.NotDeployedYet => StartANewWebsite,
        _ => KeepTheSameWebsite,
    };

    /// <summary>Whether the dates on file end before today: most likely last year's.</summary>
    public static bool DatesAreOld(DateOnly? last, DateOnly today) => last is { } day && day < today;

    /// <summary>A day as the dialog's dates line and the re-date's plan write it: "2026-09-08 (Tuesday)".</summary>
    public static string DayAsWritten(DateOnly day) => $"{DateText.Iso(day)} ({day.DayOfWeek})";

    /// <summary>
    /// The trail line's counts for a rollover from the menu: which way the
    /// website went (<c>activityTrail.mustRecord</c> → <c>ran from a menu</c>),
    /// read from what the call SENT.
    /// </summary>
    public static string Counts(Website website, string sent) => website switch
    {
        Website.Asked => sent == StartANewWebsite ? "website: new" : "website: kept",
        Website.NotDeployedYet => "website: not deployed yet",
        Website.DeploysToAFolder => "website: deploys to a folder",
        _ => "website: kept, a new one would have the same address",
    };
}
