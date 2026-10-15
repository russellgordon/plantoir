namespace Plantoir.Core.Models;

/// <summary>
/// File ▸ Settings ▸ Deploying: the Cloudflare Account ID, the one deploying
/// answer that belongs to the teacher rather than to a course (#491, the
/// mac's #457 item 4 — <c>DeployingSettingsView.swift</c>).
/// </summary>
/// <remarks>
/// <para><b>Why there.</b> The ID identifies the PERSON, not the class: one
/// account serves every course that deploys to Cloudflare Pages, and the value
/// was always stored app-wide (<see cref="AppSettings.CloudflareAccountId"/>).
/// But it was EDITED inside a course's settings and the new-course wizard, so
/// changing it in one course silently changed it for every other — a setting
/// in the wrong place. Russell ruled 2026-10-15: one Settings window, File ▸
/// Settings…, with a Deploying section; the course and the wizard show the ID
/// read-only with Open Settings…. No data moved, so nothing is migrated.</para>
///
/// <para><b>The wording split, deliberate.</b> The app's own sentences say
/// "File ▸ Settings ▸ Deploying", where the item is on Windows; the launchers'
/// non-interactive refusal says "Plantoir ▸ Settings ▸ Deploying" on both
/// platforms (#490's ruling: one sentence for both launchers). Do not "fix"
/// either to match the other.</para>
/// </remarks>
public static class DeployingSettings
{
    /// <summary>Where the ID is edited on Windows, as the app's sentences name it.</summary>
    public const string Place = "File ▸ Settings ▸ Deploying";

    /// <summary>What the read-only displays show in place of an ID that is not set.</summary>
    public const string ShownWhenEmpty = "Not set yet";

    /// <summary>The caption above the read-only displays, said first: the value below is shown, not edited.</summary>
    public const string KeptIn = "Kept in " + Place + ", for every course that deploys to Cloudflare Pages.";

    /// <summary>The in-app deploy's refusal remedy (<c>MultiDestinationDeployRunner.RefusalReason</c>).</summary>
    public const string AddItThenDeployAgain = "Add it in " + Place + ", then deploy again.";

    /// <summary>Schedule a Deploy's refusal remedy (<c>ScheduledDeploy</c>).</summary>
    public const string AddItThenScheduleAgain = "Add it in " + Place + ", then schedule this again.";

    /// <summary>The ID as a read-only display shows it: trimmed, or <see cref="ShownWhenEmpty"/>.</summary>
    public static string Shown(string? id)
    {
        string trimmed = (id ?? "").Trim();
        return trimmed.Length == 0 ? ShownWhenEmpty : trimmed;
    }

    /// <summary>
    /// What is wrong with a typed ID, or null — null for an EMPTY one, which
    /// is not wrong on the Settings pane: a teacher who never deploys to
    /// Cloudflare has no reason to fill it in, and the course that needs one
    /// says so itself.
    /// </summary>
    public static string? Problem(string? id)
    {
        string trimmed = (id ?? "").Trim();
        return trimmed.Length == 0 ? null : CourseConfiguration.CloudflareAccountProblem(trimmed);
    }

    /// <summary>
    /// The trail line for a change made on the pane, or null when nothing
    /// changed (whitespace aside). NEVER the ID itself: only whether one is now
    /// set, cleared, or not yet a valid ID (<c>activityTrail.mustRecord</c> →
    /// "Cloudflare account ID changed in Settings"). The mac's three lines,
    /// word for word.
    /// </summary>
    public static string? TrailLine(string? before, string? after)
    {
        string was = (before ?? "").Trim();
        string now = (after ?? "").Trim();
        if (was == now) return null;
        if (now.Length == 0) return "Settings ▸ Deploying — the Cloudflare Account ID was cleared";
        if (CourseConfiguration.CloudflareAccountProblem(now) is not null)
            return "Settings ▸ Deploying — the Cloudflare Account ID was changed, and is not a valid ID yet";
        return "Settings ▸ Deploying — the Cloudflare Account ID was changed";
    }
}
