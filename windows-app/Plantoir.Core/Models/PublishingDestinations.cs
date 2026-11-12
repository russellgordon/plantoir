namespace Plantoir.Core.Models;

/// <summary>
/// Where a NEW course deploys, and what a teacher is told while choosing
/// (#739, the mac's #668 — <c>PublishingDestinations.swift</c>). Every rule and
/// sentence here is pinned by <c>contracts/app-rules.json</c> →
/// <c>publishingDestinations</c> (<c>PublishingDestinationsContractTests</c>),
/// so the two apps show the same words and make the same choice.
/// </summary>
/// <remarks>
/// <para><b>Why Cloudflare for a new course.</b> Netlify moved accounts made
/// since September 2025 to a fixed monthly allowance shared by every site on
/// the account, which deploys use up; when it runs out every site on the
/// account is paused until the next month. Cloudflare Pages' free plan has no
/// limit on visitors. The dated figures, and what was rejected, are in
/// <c>documentation/07-deployment.md</c> → "Choosing a destination (#668)".</para>
///
/// <para><b>Why an absent key still means Netlify.</b> <see cref="NewCourseDefault"/>
/// and <see cref="WhenTheKeyIsAbsent"/> differ on purpose (the contract's
/// <c>whyTheyDiffer</c>): every course written before the other destinations
/// existed has no <c>deploy_target</c> and deploys to Netlify today, and
/// reading the absent key as Cloudflare would move a working class site to a
/// host the teacher has no account with. The new-course dialog therefore
/// WRITES <c>deploy_target</c> for every course it makes.</para>
///
/// <para>The sentences carry no figures (the hosts change them), say DEPLOY
/// for what spends the allowance (publishing marks a page and costs nothing),
/// and make no claim about Cloudflare's limits on deploys.</para>
/// </remarks>
public static class PublishingDestinations
{
    /// <summary>What the new-course dialog writes as <c>deploy_target</c> unless the teacher picks something else.</summary>
    public const string NewCourseDefault = "cloudflare_pages";

    /// <summary>What a <c>course_config.json</c> with no <c>deploy_target</c> deploys to (<see cref="CourseConfiguration.DeployTarget"/>).</summary>
    public const string WhenTheKeyIsAbsent = "netlify";

    /// <summary>The new-course dialog's caption over its Deploying section.</summary>
    public const string WizardCaption =
        "Cloudflare Pages is the usual choice — change it any time in Course Settings";

    /// <summary>Under Cloudflare Pages wherever it is chosen, primary or additional.</summary>
    public const string CloudflareCaption = "Recommended. Free, with no limit on visitors.";

    /// <summary>Under Netlify wherever it is chosen, primary or additional, in the new-course dialog and Course Settings.</summary>
    public const string NetlifyNote =
        "A note about Netlify’s free plan: Netlify accounts made since September 2025 get a fixed monthly allowance, and every deploy of every section uses part of it. When the allowance runs out, Netlify pauses every site on the account until the next month. Cloudflare Pages’ free plan has no limit on visitors, which is why Plantoir suggests it. If your Netlify account is older than that, or you deploy only now and then, Netlify works well.";

    /// <summary>
    /// The shorter form, in Schedule a deploy when the SAVED settings deploy to
    /// Netlify: a deploy that happens on its own is the easiest one to forget
    /// the cost of.
    /// </summary>
    public const string NetlifyScheduleNote =
        "This course deploys to Netlify. On Netlify’s free plan every deploy uses part of a monthly allowance, and when it runs out Netlify pauses every site on the account until the next month.";

    /// <summary>Under the orange "Paste your Cloudflare Account ID." in the new-course dialog, which no longer refuses Create for a missing ID.</summary>
    public const string AccountIdCanWait =
        "You can create the course without it and preview it as usual. It is needed before the first deploy.";

    /// <summary>
    /// The fixed fact about Cloudflare Pages, shown whenever it is chosen. Not
    /// a contract sentence (the mac's <c>CloudflareDetailFields.sizeNote</c>,
    /// word for word); here so <see cref="CloudflareNotice"/> can be tested.
    /// </summary>
    public const string CloudflareSizeNote =
        "One thing to know: Cloudflare won’t accept any single file larger than 25 MB. " +
        "Documents, images, and slide decks are almost always comfortably under that — a long video usually isn’t. " +
        "Most teachers embed video from YouTube or Vimeo rather than uploading it, which avoids the limit entirely.";

    /// <summary>One run of the Cloudflare notice: its words, and whether it is drawn in the caution colour.</summary>
    public readonly record struct NoticePart(string Text, bool Caution);

    /// <summary>
    /// The Cloudflare notice as ONE block (#739, the mac's #668 second fixes
    /// round), in reading order: the ID's problem in orange when there is one;
    /// then, where a missing ID may wait (the new-course dialog) and it IS
    /// missing, <see cref="AccountIdCanWait"/> in the secondary colour right
    /// after the sentence it qualifies; then the 25 MB fact in orange. With
    /// Cloudflare the default, a new teacher with no ID would otherwise meet two
    /// orange warnings on their first course.
    /// </summary>
    public static IReadOnlyList<NoticePart> CloudflareNotice(string? cloudflareAccountId, bool accountIdMayWait)
    {
        var parts = new List<NoticePart>();
        if (CourseConfiguration.CloudflareAccountProblem(cloudflareAccountId ?? "") is { } problem)
        {
            parts.Add(new NoticePart(problem + " ", Caution: true));
            if (accountIdMayWait && AccountIdIsMissing(cloudflareAccountId))
                parts.Add(new NoticePart(AccountIdCanWait + " ", Caution: false));
        }
        parts.Add(new NoticePart(CloudflareSizeNote, Caution: true));
        return parts;
    }

    /// <summary>The order the destination picker and the additional list offer the three (<c>pickerOrder</c>).</summary>
    public static IReadOnlyList<string> PickerOrder => CourseConfiguration.KnownDeployTargetTypes;

    /// <summary>
    /// Whether Netlify's note belongs on screen for these destinations: wherever
    /// Netlify is configured, primary or additional. An EMPTY primary is a
    /// course whose file names none, which deploys to Netlify.
    /// </summary>
    public static bool ShowsNetlifyNote(string primary, IEnumerable<string> additional)
    {
        if (primary.Length == 0 || primary == "netlify") return true;
        return additional.Contains("netlify");
    }

    /// <summary>Whether the Cloudflare caption belongs on screen: wherever Cloudflare Pages is configured, primary or additional.</summary>
    public static bool ShowsCloudflareCaption(string primary, IEnumerable<string> additional) =>
        primary == "cloudflare_pages" || additional.Contains("cloudflare_pages");

    /// <summary>
    /// <see cref="NetlifyScheduleNote"/> when these SAVED settings deploy to
    /// Netlify (primary or additional, an absent key counting as Netlify), else null.
    /// </summary>
    public static string? ScheduleNote(CourseConfiguration saved) =>
        ShowsNetlifyNote(saved.DeployTarget, saved.AdditionalDeployTargets.Select(t => t.Type))
            ? NetlifyScheduleNote
            : null;

    /// <summary>True when the ID is empty once trimmed — the case the new-course dialog lets wait, saying <see cref="AccountIdCanWait"/>.</summary>
    public static bool AccountIdIsMissing(string? rawId) => (rawId ?? "").Trim().Length == 0;

    /// <summary>
    /// Why the new-course dialog refuses Create over the Account ID, or null
    /// when it does not. A MISSING ID no longer refuses (#668): it is a warning,
    /// and the first deploy is where it is asked for
    /// (<c>MultiDestinationDeployRunner.RefusalReason</c>). An ID that cannot be
    /// one still refuses, because something is saved and it is wrong.
    /// </summary>
    public static string? WizardCreateRefusal(string? rawId) =>
        AccountIdIsMissing(rawId) ? null : CourseConfiguration.CloudflareAccountProblem(rawId ?? "");

    /// <summary>
    /// Whether the Deploy button's refusal offers Open Settings… beside OK: when
    /// what it says is the Account ID's problem, which is put right in File ▸
    /// Settings ▸ Deploying. A folder's refusal is put right in the course's own
    /// settings, so it does not (<c>deployWithoutAnAccountID.cases[].expectOpenSettings</c>).
    /// </summary>
    public static bool DeployRefusalOpensSettings(string refusal, string? cloudflareAccountId) =>
        CourseConfiguration.CloudflareAccountProblem(cloudflareAccountId ?? "") is { } problem
        && refusal.StartsWith(problem, StringComparison.Ordinal);

    /// <summary>
    /// The trail's words for "deploy refused for the Cloudflare Account ID", or
    /// null when the deploy is not refused for the Account ID — refused for a
    /// folder first, or not refused at all. Walks the destinations in the order
    /// <c>MultiDestinationDeployRunner.RefusalReason</c> does, so the line names
    /// the refusal the teacher was shown. By KIND only — missing, or not a whole
    /// ID — never the ID itself. The mac's
    /// <c>ActivityTrail.deployRefusedForTheAccountIDLine</c>, word for word.
    /// </summary>
    public static string? AccountIdRefusalTrailLine(
        IEnumerable<CourseConfiguration.DeployDestination> destinations, string? cloudflareAccountId)
    {
        foreach (var destination in destinations)
        {
            if (destination.Type == "local_folder"
                && CourseConfiguration.DeployFolderProblem(destination.Path) is not null)
                return null;
            if (destination.Type == "cloudflare_pages")
            {
                if (CourseConfiguration.CloudflareAccountProblem(cloudflareAccountId ?? "") is null) return null;
                return AccountIdIsMissing(cloudflareAccountId)
                    ? "deploy refused: no Cloudflare Account ID is saved in Settings"
                    : "deploy refused: the Cloudflare Account ID in Settings is not a whole ID";
            }
        }
        return null;
    }
}
