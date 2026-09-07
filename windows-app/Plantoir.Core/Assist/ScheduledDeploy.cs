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

        // The PRIMARY destination — unchanged wording and order from before
        // a course could have more than one, so every existing check
        // against this function still passes byte for byte.
        if (course.Configuration.DeployTarget == "local_folder")
        {
            if (Models.CourseConfiguration.DeployFolderProblem(course.Configuration.DeployFolderPath) is { } folderProblem)
                return $"{course.Code} deploys to a folder, and that folder needs attention first: {folderProblem}";
        }

        if (course.Configuration.DeploysToCloudflare)
        {
            if (Models.CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID) is { } accountProblem)
                return $"{course.Code} deploys to Cloudflare Pages, which needs your Account ID. {accountProblem} Add it in this course’s settings, under Deploying, then schedule this again.";
        }

        // Every ADDITIONAL destination gets the same two checks — a
        // redundancy target with no valid folder or credential would
        // otherwise sit silently broken until the scheduled moment, exactly
        // the surprise asking everything up front exists to prevent.
        foreach (var target in course.Configuration.AdditionalDeployTargets)
        {
            if (target.Type == "local_folder")
            {
                if (Models.CourseConfiguration.DeployFolderProblem(target.Path) is { } folderProblem)
                    return $"{course.Code} also deploys to a folder, and that folder needs attention first: {folderProblem}";
            }
            if (target.Type == "cloudflare_pages")
            {
                if (Models.CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID) is { } accountProblem)
                    return $"{course.Code} also deploys to Cloudflare Pages, which needs your Account ID. {accountProblem} Add it in this course’s settings, under Deploying, then schedule this again.";
            }
        }

        if (!Models.DeployCommand.HasDeployedBefore(sectionNumber, course))
            return $"{course.Code} Section {sectionNumber} has never been deployed, so deploying it asks " +
                   "what to call the website. Nobody would be there to answer that at the scheduled time, " +
                   "and it would wait. Deploy it once from Plantoir, and after that it can be scheduled.";

        // Same reasoning, for any additional destination that has never
        // gone out — a brand-new Netlify or Cloudflare destination also
        // asks what to call the site, and local_folder never does
        // (HasDeployedBefore reports it as always ready).
        foreach (var target in course.Configuration.AdditionalDeployTargets)
        {
            if (!Models.DeployCommand.HasDeployedBefore(sectionNumber, course, target.Type))
            {
                string destinationName = Models.DeployCommand.DestinationDescription(
                    new Models.CourseConfiguration.DeployDestination(target.Type, target.Path));
                return $"{course.Code} Section {sectionNumber} has never been deployed to {destinationName}, " +
                       "so deploying it there asks what to call that site. Nobody would be there to answer " +
                       "that at the scheduled time, and it would wait. Deploy it there once from Plantoir, " +
                       "and after that it can be scheduled.";
            }
        }

        return null;
    }

    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }
    public required DateTime When { get; init; }

    /// <summary>The name the task carries, so it can be found and cancelled.</summary>
    public string TaskName => $"Plantoir deploy {CourseCode} section {SectionNumber}";

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
    /// <para>Walks the same folders <c>AssistWorkspace.ClassPages</c> walks
    /// and leaves out the same <c>index.md</c>, for the same reason: a
    /// section's front page is not a class. Named by FILE name, as this
    /// app's own tool names them (<c>AssistWorkspace.PlanScheduledDeploy</c>);
    /// the mac uses the page's title, a recorded difference.</para>
    /// </summary>
    public static List<string> UnpublishedClassesIn(Course course, int sectionNumber)
    {
        var names = new List<string>();
        foreach (string folder in course.Configuration.PerSectionFolders)
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
