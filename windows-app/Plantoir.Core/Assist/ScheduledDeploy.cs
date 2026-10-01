using System;
using System.Globalization;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// A deploy the teacher wants to happen while they are asleep.
///
/// "Deploy tomorrow's class at 6:30 AM" — so the class is live before the
/// students are, without the teacher being at their desk at half six.
///
/// The honest part of this is what it does NOT promise. It asks Windows to
/// run a task at a time; it cannot make a computer that is switched off run
/// anything, and it deliberately does not set a wake timer. A wake timer
/// depends on the hardware, the power plan, and on the machine being asleep
/// rather than shut down or hibernating, and it fails SILENTLY when any of
/// those is not true — which for a teacher means walking into class to find
/// yesterday's site still up. A plain warning they can act on beats a promise
/// that might not be kept.
/// </summary>
public sealed class ScheduledDeploy
{
    /// <summary>
    /// The form Plantoir itself WRITES a scheduled moment in — the assistant's
    /// "deploy tomorrow's class at 6:30" card, and what the model is told to
    /// send.
    /// </summary>
    public const string WrittenForm = "yyyy-MM-dd HH:mm";

    /// <summary>
    /// The moment a <c>when</c> names, or null when it names none. Every
    /// reader of a scheduled moment goes through here.
    /// </summary>
    /// <remarks>
    /// <para><b>ONE reader, because the halves of a round trip have to agree
    /// and each half looks right on its own.</b> The string is usually one
    /// Plantoir wrote a moment earlier, invariantly; a bare
    /// <c>DateTime.TryParse</c> reads its year in the machine's DEFAULT
    /// CALENDAR. Measured on a Thai-locale machine: <c>"2026-09-20 06:30"</c>
    /// comes back as <b>1483-09-20</b> — which is in the past, so
    /// <see cref="Problem"/> answers "…has already passed. Pick a time still
    /// to come." and NOTHING IS SCHEDULED, while the approval card the
    /// teacher had just read named a weekday from the fifteenth century.</para>
    ///
    /// <para>Three steps, most specific first. <b>The form the app writes</b>,
    /// exact and invariant. Then an <b>invariant lenient</b> parse, which
    /// covers what a model sends when it is close but not exact — a <c>T</c>
    /// separator, a missing leading zero, "6:30 AM". Only then the machine's
    /// own culture, for a genuinely human-written shape, where there is no
    /// fixed form to pin it to and the teacher's own conventions are the best
    /// guess available.</para>
    ///
    /// <para>Formatting is NOT symmetrical with this and should not be: a
    /// moment shown to a teacher is written in their culture, because that
    /// sentence is theirs. What must be invariant is the wire.</para>
    ///
    /// <para>Same family as the writer sites in
    /// <see href="https://github.com/russellgordon/plantoir/issues/144">issue
    /// #144</see>, met from the reading end — which is how a culture audit
    /// scoped to writers alone misses half of a round trip.</para>
    /// </remarks>
    public static DateTime? ReadTheMoment(string when)
    {
        if (DateTime.TryParseExact(when, WrittenForm, CultureInfo.InvariantCulture,
                                          DateTimeStyles.None, out var written))
        {
            return written;
        }
        if (DateTime.TryParse(when, CultureInfo.InvariantCulture, DateTimeStyles.None, out var close))
        {
            return close;
        }
        return DateTime.TryParse(when, out var human) ? human : null;
    }

    /// <summary>
    /// Why this section cannot be scheduled, in plain words, or null if it can.
    ///
    /// Shared by the assistant and by the sidebar's own "Schedule Deploy…", so
    /// the two paths cannot drift. A refusal that only one of them makes is a
    /// refusal a teacher can walk around by using the other door — and the
    /// thing being walked around here is a deploy that would sit waiting on a
    /// question at half six in the morning.
    /// </summary>
    public static string? Problem(Models.Course course, int sectionNumber, DateTime when, DateTime now, string cloudflareAccountID = "")
    {
        if (when <= now)
            return $"{when:dddd d MMMM, h:mm tt} has already passed. Pick a time still to come.";

        return RefusalOf(course, sectionNumber, cloudflareAccountID) is { } refusal
            ? SentenceFor(refusal, course, sectionNumber, cloudflareAccountID)
            : null;
    }

    /// <summary>
    /// One of <c>scheduledDeployRefusals</c>' keys, and the destination it is
    /// about when it names one.
    /// </summary>
    public sealed record Refusal(string Key, string? Destination = null);

    /// <summary>
    /// Every refusal <c>scheduledDeployRefusals</c> makes EXCEPT a time already
    /// passed, in its order, as a key. ONE decision for the schedule sheet (which
    /// words it as a whole sentence, <see cref="Problem"/>) and for the run that
    /// checks it all again when it fires (#347,
    /// <c>scheduledDeployCancellation.theDestination</c>), so the two cannot
    /// drift apart — a second copy of these checks is exactly the option (b)
    /// #347 rejected.
    /// </summary>
    public static Refusal? RefusalOf(Models.Course course, int sectionNumber, string cloudflareAccountID)
    {
        // A course kept for reference is never deployed (#241's marker; this
        // app keeps none for reference yet, but a folder can arrive with one).
        if (course.Configuration.Values["kept_for_reference"] is Newtonsoft.Json.Linq.JValue { Type: Newtonsoft.Json.Linq.JTokenType.Boolean } kept
            && kept.ToObject<bool>())
            return new Refusal("keptForReference");

        // The PRIMARY destination — unchanged order from before a course could
        // have more than one.
        if (course.Configuration.DeployTarget == "local_folder"
            && Models.CourseConfiguration.DeployFolderProblem(course.Configuration.DeployFolderPath) is not null)
            return new Refusal("deployFolderNeedsAttention");

        if (course.Configuration.DeploysToCloudflare
            && Models.CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID) is not null)
            return new Refusal("cloudflareAccountMissing");

        // Every ADDITIONAL destination gets the same two checks — a
        // redundancy target with no valid folder or credential would
        // otherwise sit silently broken until the scheduled moment, exactly
        // the surprise asking everything up front exists to prevent.
        foreach (var target in course.Configuration.AdditionalDeployTargets)
        {
            if (target.Type == "local_folder"
                && Models.CourseConfiguration.DeployFolderProblem(target.Path) is not null)
                return new Refusal("additionalDeployFolderNeedsAttention");
            if (target.Type == "cloudflare_pages"
                && Models.CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID) is not null)
                return new Refusal("additionalCloudflareAccountMissing");
        }

        if (!Models.DeployCommand.HasDeployedBefore(sectionNumber, course))
            return new Refusal("neverDeployed", Models.DeployCommand.DestinationDescription(
                course.Configuration.AllDeployDestinations[0]));

        // Same reasoning, for any additional destination that has never
        // gone out — a brand-new Netlify or Cloudflare destination also
        // asks what to call the site, and local_folder never does
        // (HasDeployedBefore reports it as always ready).
        foreach (var target in course.Configuration.AdditionalDeployTargets)
        {
            if (!Models.DeployCommand.HasDeployedBefore(sectionNumber, course, target.Type))
                return new Refusal("additionalDestinationNeverDeployed", Models.DeployCommand.DestinationDescription(
                    new Models.CourseConfiguration.DeployDestination(target.Type, target.Path)));
        }

        return null;
    }

    /// <summary>The schedule sheet's whole sentence for a refusal — unchanged wording.</summary>
    private static string SentenceFor(Refusal refusal, Models.Course course, int sectionNumber, string cloudflareAccountID) =>
        refusal.Key switch
        {
            "keptForReference" =>
                $"{course.Code} is kept for reference, and a course kept for reference is never deployed.",
            "deployFolderNeedsAttention" =>
                $"{course.Code} deploys to a folder, and that folder needs attention first: " +
                Models.CourseConfiguration.DeployFolderProblem(course.Configuration.DeployFolderPath),
            "cloudflareAccountMissing" =>
                $"{course.Code} deploys to Cloudflare Pages, which needs your Account ID. " +
                $"{Models.CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID)} Add it in this course’s settings, under Deploying, then schedule this again.",
            "additionalDeployFolderNeedsAttention" =>
                $"{course.Code} also deploys to a folder, and that folder needs attention first: " +
                course.Configuration.AdditionalDeployTargets
                    .Where(target => target.Type == "local_folder")
                    .Select(target => Models.CourseConfiguration.DeployFolderProblem(target.Path))
                    .First(problem => problem is not null),
            "additionalCloudflareAccountMissing" =>
                $"{course.Code} also deploys to Cloudflare Pages, which needs your Account ID. " +
                $"{Models.CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID)} Add it in this course’s settings, under Deploying, then schedule this again.",
            "neverDeployed" =>
                // Names the destination (#344 / mac #322): a teacher who
                // expected somewhere else sees the disagreement at once.
                $"{course.Code} Section {sectionNumber} has never been deployed to {refusal.Destination}, so deploying " +
                "it there asks what to call the website. Nobody would be there to answer that at the scheduled " +
                $"time, and it would wait. Deploy it to {refusal.Destination} once from Plantoir, and after that " +
                "it can be scheduled.",
            "additionalDestinationNeverDeployed" =>
                $"{course.Code} Section {sectionNumber} has never been deployed to {refusal.Destination}, " +
                "so deploying it there asks what to call that site. Nobody would be there to answer " +
                "that at the scheduled time, and it would wait. Deploy it there once from Plantoir, " +
                "and after that it can be scheduled.",
            _ => throw new ArgumentOutOfRangeException(nameof(refusal)),
        };

    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }
    public required DateTime When { get; init; }

    /// <summary>
    /// The classes a caller NAMED (plan_scheduled_deploy's <c>classes</c>), each
    /// with whether it is published — null when no page in the section is called
    /// that. Only named classes: the section-wide list of unpublished classes
    /// was REMOVED from scheduling on Russell's decision of 2026-09-30 (#400,
    /// mac #396, <c>scheduledDeployRefusals.alsoSaid</c>) — classes later in the
    /// year are unpublished on purpose all year, so it fired on every schedule,
    /// and its "deploying now" was wrong on a sheet that deploys later.
    /// </summary>
    public IReadOnlyList<(string Title, bool? Published)> ClassesNamed { get; init; } = [];

    /// <summary>
    /// EVERY destination the deploy goes to, primary first and then each
    /// additional in the order saved, joined "A", "A and B", "A, B and C" — in
    /// the sheet's words (a folder by its path). Built from the same list the
    /// run deploys to, <see cref="Models.CourseConfiguration.AllDeployDestinations"/>
    /// (<c>scheduledDeployRefusals.planOpening</c>, #400). It used to name the
    /// primary alone, so MPM2D's Netlify-and-Cloudflare sheet said "to Netlify".
    /// </summary>
    public required string Destination { get; init; }

    /// <summary>Every destination, in the sheet's words, joined the way a teacher says a list.</summary>
    public static string EveryDestination(Models.CourseConfiguration configuration) =>
        Scripting.MultiDestinationDeployRunner.JoinedWithAnd(
            configuration.AllDeployDestinations.Select(Models.DeployCommand.DestinationDescription).ToList());

    /// <summary>
    /// The first sentence of the sidebar's Schedule Deploy dialog. It names no
    /// moment (the time is picked below it), so it CONTAINS "to " + every
    /// destination rather than adopting planOpening's message (#400).
    /// </summary>
    public static string DialogOpening(Models.Course course, int sectionNumber) =>
        $"{course.Code} Section {sectionNumber} will deploy on its own to {EveryDestination(course.Configuration)} " +
        "at the time you pick. This computer must be switched on and awake then — plugged in if it is a laptop, " +
        "with the lid open. Plantoir does not wake it up.";

    /// <summary>
    /// What the teacher is agreeing to — including everything that has to be
    /// true of the computer, said plainly and up front.
    /// </summary>
    public string Describe()
    {
        var lines = new List<string>
        {
            $"Deploy {CourseCode} Section {SectionNumber} to {Destination} at " +
            $"{When:dddd d MMMM, h:mm tt}.",
            "",
            "For this to happen, at that moment this computer must be:",
            "  • switched on, and awake — not asleep, shut down, or hibernating",
            "  • plugged in, if it is a laptop",
            "  • with the lid open, if closing it puts it to sleep",
            "",
            "Plantoir does not wake the computer up. If it is asleep at that time, " +
            "nothing happens and the site stays as it is.",
        };

        // The only class check left (#400): the classes the caller NAMED, each
        // said as published or not — the mac's plan_scheduled_deploy lines, so
        // the two outside assistants read the same thing.
        if (ClassesNamed.Count > 0)
        {
            lines.Add("");
            lines.Add("The classes this deploy is meant to carry:");
            foreach (var (title, published) in ClassesNamed)
            {
                lines.Add(published switch
                {
                    null => $"  {title} — no page in this section is called that.",
                    true => $"  {title} — published, so the deploy would carry it.",
                    false => $"  {title} — NOT published, so the deploy would ship without it.",
                });
            }
        }

        return string.Join("\n", lines);
    }
}
