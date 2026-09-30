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
                $"{course.Code} Section {sectionNumber} has never been deployed, so deploying it asks " +
                "what to call the website. Nobody would be there to answer that at the scheduled time, " +
                "and it would wait. Deploy it once from Plantoir, and after that it can be scheduled.",
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


    /// <summary>Classes that are not published yet, and so would not reach students.</summary>
    public required IReadOnlyList<string> UnpublishedClasses { get; init; }

    /// <summary>
    /// Every class page of a section that is still unpublished — the ones a
    /// deploy would put the site up without. For the sidebar's own "Schedule
    /// Deploy…", which has no list of named classes the way the assistant's
    /// tool does. Date-independent, as the contract's
    /// <c>scheduledDeployRefusals.alsoSaid</c> rule has it ("list the class
    /// pages students cannot see yet, by name") and as the mac's
    /// <c>unpublishedClasses(course:sectionNumber:)</c> has always done: a
    /// class dated after the deploy is still a page students cannot see.
    ///
    /// <para>Walks the same folders <c>AssistWorkspace.ClassPages</c> walks —
    /// the ones the SHARED membership rule counts
    /// (<c>contracts/class-planning.json</c> → <c>classFolder.membership</c>),
    /// not every <c>per_section_folder</c> — and leaves out the same
    /// <c>index.md</c>, for the same reason: a section's front page is not a
    /// class. That sentence was false between the two of them until
    /// 2026-09-19, when both stopped walking the whole list; a test now pins
    /// the two together on one fixture, because a comment claiming agreement
    /// is exactly what stops anybody checking. Named by FILE name, as this
    /// app's own tool names them (<c>AssistWorkspace.PlanScheduledDeploy</c>);
    /// the mac uses the page's title, a recorded difference.</para>
    /// </summary>
    public static List<string> UnpublishedClassesIn(Course course, int sectionNumber)
    {
        var names = new List<string>();
        foreach (string folder in ClassFolderRule.Names(course.Configuration.ClassFolder,
                                                        course.Configuration.PerSectionFolders))
        {
            string root = Path.Combine(course.SectionDirectory(sectionNumber), folder);
            if (!Directory.Exists(root)) continue;
            foreach (string page in PagePaths.MarkdownPages(root, sectionNumber))
            {
                if (string.Equals(Path.GetFileName(page), "index.md", StringComparison.OrdinalIgnoreCase))
                    continue;
                string text;
                try { text = File.ReadAllText(page); } catch { continue; }
                if (PageFrontmatter.IsDraft(text, sectionNumber))
                    names.Add(Path.GetFileNameWithoutExtension(page));
            }
        }
        names.Sort(StringComparer.OrdinalIgnoreCase);
        return names;
    }

    /// <summary>
    /// The sentence that goes with that list — the same content
    /// <see cref="Describe"/> gives the assistant, in prose rather than in
    /// bullets, because a dialog is not a chat transcript. Null when nothing
    /// is unpublished.
    /// </summary>
    public static string? UnpublishedClassesSentence(IReadOnlyList<string> unpublished)
    {
        if (unpublished.Count == 0) return null;
        int count = unpublished.Count;
        string listed = string.Join(", ", unpublished.Take(8));
        if (count > 8) listed += $" …and {count - 8} more";
        string are = count == 1 ? "class is" : "classes are";
        string them = count == 1 ? "it" : "them";
        return $"One thing first — {count} {are} not published yet: {listed}. " +
               $"Deploying now would put the site up without {them}. " +
               "Publish first, look the preview over, then schedule this.";
    }

    /// <summary>Where the deploy would land.</summary>
    public required string Destination { get; init; }

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

        if (UnpublishedClasses.Count > 0)
        {
            lines.Add("");
            // The failure this exists to prevent: a deploy that runs perfectly
            // and ships a class students still cannot see.
            lines.Add($"One thing first — {UnpublishedClasses.Count} " +
                      $"class{(UnpublishedClasses.Count == 1 ? " is" : "es are")} not published yet:");
            foreach (string page in UnpublishedClasses.Take(8)) lines.Add($"  {page}");
            if (UnpublishedClasses.Count > 8)
                lines.Add($"  …and {UnpublishedClasses.Count - 8} more.");
            lines.Add("Deploying now would put the site up without " +
                      $"{(UnpublishedClasses.Count == 1 ? "it" : "them")}. " +
                      "Publish first, look the preview over, then schedule this.");
        }

        return string.Join("\n", lines);
    }
}
