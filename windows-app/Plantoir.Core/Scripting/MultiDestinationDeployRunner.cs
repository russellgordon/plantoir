using System.ComponentModel;
using System.Runtime.CompilerServices;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

/// <summary>
/// Runs a deploy against every one of a course's configured destinations, in
/// sequence — real redundancy needs a second copy actually live, not a
/// manual switch after something breaks (see
/// <see cref="CourseConfiguration.AdditionalDeployTargets"/>). Every place a
/// deploy can start delegates the actual sequencing HERE, so none of them
/// can drift the way <see cref="DeployCommand.Arguments(string,int,CourseConfiguration,string)"/>
/// itself once warned against: built separately in two places, one silently
/// sending a Cloudflare course to Netlify. Mirrors the mac's
/// `MultiDestinationDeployRunner.swift`.
///
/// For the overwhelming majority of courses — exactly one destination —
/// this behaves exactly like running a single <see cref="ScriptRunner"/>
/// always did: one leg, one console, one progress bar, one outcome.
/// </summary>
public sealed class MultiDestinationDeployRunner : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>
    /// One destination's own attempt: its own <see cref="ScriptRunner"/>, so
    /// its own console, progress, and published-site link stay correctly
    /// scoped to IT. Sharing one <see cref="ScriptRunner"/> across
    /// destinations would let the second destination's "Live URL:" line
    /// silently overwrite the first's, since a runner's URL-parsing only
    /// ever looks at that runner's own transcript.
    /// </summary>
    public sealed class Leg
    {
        public CourseConfiguration.DeployDestination Destination { get; }
        public ScriptRunner Runner { get; }
        public bool IsFinished { get; internal set; }
        public bool Succeeded { get; internal set; }

        /// <summary>
        /// True only when this leg's SHARED build step failed (attempted on
        /// the first leg only, and only when the site was stale) — kept
        /// distinct from a DEPLOY failure so the teacher hears "could not be
        /// built" rather than "did not finish", which would wrongly suggest
        /// the build was fine and only the upload failed.
        /// </summary>
        public bool BuildFailed { get; internal set; }

        public Leg(CourseConfiguration.DeployDestination destination, SynchronizationContext? uiContext)
        {
            Destination = destination;
            Runner = new ScriptRunner(uiContext);
        }
    }

    public List<Leg> Legs { get; private set; } = new();
    public int CurrentLegIndex { get; private set; }
    public bool IsRunning { get; private set; }
    public DateTime? StartedAt { get; private set; }
    public bool WasCancelled { get; private set; }
    public bool WasStoppedByUser { get; private set; }

    public Leg? CurrentLeg => CurrentLegIndex >= 0 && CurrentLegIndex < Legs.Count ? Legs[CurrentLegIndex] : null;

    /// <summary>
    /// The one runner to bind a progress panel to: whichever leg is
    /// current, or the first leg before anything has started. For a course
    /// with exactly one destination this is indistinguishable from binding
    /// to a plain <see cref="ScriptRunner"/>, which is the point.
    /// </summary>
    public ScriptRunner ActiveRunner => CurrentLeg?.Runner ?? Legs.FirstOrDefault()?.Runner ?? new ScriptRunner();

    /// <summary>True once anything at all has been shown for this run, across any leg.</summary>
    public bool HasAnyOutput => Legs.Any(leg => leg.Runner.Transcript.Lines.Count > 0);

    public readonly record struct Outcome(bool AnySucceeded, IReadOnlyList<CourseConfiguration.DeployDestination> FailedDestinations)
    {
        public bool AllSucceeded => AnySucceeded && FailedDestinations.Count == 0;
    }

    /// <summary>
    /// What actually happened, once every leg that ran has finished. A leg
    /// the run never reached (stopped early by a cancel or a failed shared
    /// build) is not counted as failed — it simply never ran.
    /// </summary>
    public Outcome CurrentOutcome
    {
        get
        {
            var failed = new List<CourseConfiguration.DeployDestination>();
            bool anySucceeded = false;
            foreach (var leg in Legs.Where(leg => leg.IsFinished))
            {
                if (leg.Succeeded) anySucceeded = true;
                else if (!leg.BuildFailed) failed.Add(leg.Destination);
            }
            return new Outcome(anySucceeded, failed);
        }
    }

    private readonly SynchronizationContext? _ui;

    public MultiDestinationDeployRunner(SynchronizationContext? uiContext = null)
    {
        _ui = uiContext ?? SynchronizationContext.Current;
    }

    /// <summary>
    /// Claims the console for the deploy panel before anything else touches
    /// the preview runner. Stopping a running preview sets the preview
    /// runner's own <see cref="ScriptRunner.WasStoppedByUser"/> flag and
    /// flips its <see cref="ScriptRunner.IsRunning"/> false — without this,
    /// the panel-choosing comparison in <c>SectionDetailView.RefreshChrome</c>
    /// (which panel is "current" by comparing each runner's
    /// <see cref="StartedAt"/>) would still favour the just-stopped preview
    /// for the beat before <see cref="RunAsync"/> gives this runner a real
    /// timestamp, flashing "Stopped" before the deploy panel takes over.
    /// Mirrors the mac's `deployRunner.startedAt = Date()` pre-claim in
    /// `deployAndWait()` (row 317).
    /// </summary>
    public void ClaimConsole()
    {
        StartedAt = DateTime.UtcNow;
        Notify(nameof(StartedAt));
    }

    /// <summary>
    /// Cancels whichever leg is currently running. The remaining,
    /// not-yet-started legs are simply never reached — <see cref="RunAsync"/>'s
    /// own loop checks <see cref="WasCancelled"/> after every wait and stops.
    /// </summary>
    public void Cancel()
    {
        WasCancelled = true;
        if (CurrentLeg is { Runner.IsRunning: true } leg) leg.Runner.CancelByUser();
    }

    /// <summary>
    /// Refuses up front, against EVERY configured destination, rather than
    /// discovering a missing credential halfway through a redundancy run —
    /// exactly the surprise redundancy exists to prevent.
    /// </summary>
    public static string? RefusalReason(
        IReadOnlyList<CourseConfiguration.DeployDestination> destinations, string cloudflareAccountID)
    {
        foreach (var destination in destinations)
        {
            if (destination.Type == "local_folder")
            {
                if (CourseConfiguration.DeployFolderProblem(destination.Path) is { } folderProblem)
                    return $"{folderProblem} Fix it in this course's settings, under Deploying, then deploy again.";
            }
            if (destination.Type == "cloudflare_pages")
            {
                if (CourseConfiguration.CloudflareAccountProblem(cloudflareAccountID) is { } accountProblem)
                    return $"{accountProblem} Add it in this course's settings, under Deploying, then deploy again.";
            }
        }
        return null;
    }

    /// <summary>The milestones for one leg's OWN deploy — always the deploy-only list, never the build-and-deploy list.</summary>
    public static IReadOnlyList<TaskMilestone> DeployOnlyMilestones(string destinationType) => destinationType switch
    {
        "local_folder" => TaskMilestones.DeployToFolder,
        "cloudflare_pages" => TaskMilestones.DeployToCloudflare,
        _ => TaskMilestones.Deploy,
    };

    /// <summary>The milestones for the FIRST leg, when the site also has to be rebuilt first.</summary>
    public static IReadOnlyList<TaskMilestone> BuildAndDeployMilestones(string destinationType) => destinationType switch
    {
        "local_folder" => TaskMilestones.BuildAndDeployToFolder,
        "cloudflare_pages" => TaskMilestones.BuildAndDeployToCloudflare,
        _ => TaskMilestones.BuildAndDeploy,
    };

    /// <summary>
    /// Runs the whole sequence: an optional shared build, then each
    /// destination's own deploy, one after another.
    ///
    /// A destination FAILING does not stop the others — that is the whole
    /// point of redundancy: if one host is down, the others still go out. A
    /// destination being CANCELLED, or the shared build failing, stops the
    /// whole run — a failed build would just publish the same stale content
    /// to every remaining destination, which is not redundancy, it is the
    /// same mistake published twice.
    /// </summary>
    public async Task RunAsync(
        Course course,
        int sectionNumber,
        IReadOnlyList<CourseConfiguration.DeployDestination> destinations,
        string cloudflareAccountID,
        string workingDirectory,
        bool needsBuild)
    {
        Legs = destinations.Select(d => new Leg(d, _ui)).ToList();
        CurrentLegIndex = 0;
        IsRunning = true;
        StartedAt = DateTime.UtcNow;
        WasCancelled = false;
        WasStoppedByUser = false;
        Notify(nameof(IsRunning));

        // The fingerprint for the " — Edited" marker is taken NOW, before
        // anything runs — before the build, not merely before the first
        // upload. A publish takes minutes; a page edited while it uploads
        // did not go out, and stamping the finishing state would wrongly
        // mark that edit as published. See "When the stamp is written" in
        // WINDOWS-HANDOFF.md. Excludes any destination that publishes into
        // the course's own folder, so a course cannot fingerprint its own
        // output and stay "Edited" forever.
        string? publishedFingerprint = null;
        try
        {
            var excluded = SectionPublishState.SelfPublishingSubpaths(course.DirectoryPath, destinations);
            publishedFingerprint = SectionPublishState.Fingerprint(course.DirectoryPath, sectionNumber, excluded);
        }
        catch { /* a fingerprinting failure must never stop the deploy itself */ }

        try
        {
            for (int index = 0; index < Legs.Count; index++)
            {
                CurrentLegIndex = index;
                Notify(nameof(CurrentLegIndex));
                var leg = Legs[index];
                var destination = leg.Destination;
                var runner = leg.Runner;

                // Each destination wears ONLY its own custom domain — a
                // domain meant for Netlify must never leak onto the
                // Cloudflare leg's own link just because they deployed
                // together.
                string domainForThisDestination = CourseConfiguration.NormalizedCustomDomain(
                    course.Configuration.CustomDomain(sectionNumber, destination.Type));
                runner.CustomDomainForLinks = domainForThisDestination.Length == 0 ? null : domainForThisDestination;

                bool buildsFirst = index == 0 && needsBuild;
                if (buildsFirst)
                {
                    runner.Milestones = BuildAndDeployMilestones(destination.Type);
                    runner.Run("preview.ps1", new[] { course.Code, sectionNumber.ToString(), "--build-only" }, workingDirectory);
                    if (runner.LaunchProblem is not null)
                    {
                        leg.IsFinished = true;
                        leg.BuildFailed = true;
                        break;
                    }
                    // Set BEFORE the build finishes, not after — the deploy
                    // script starts on this SAME runner the moment the build
                    // succeeds, a few lines down. Without this, the gap
                    // between the build's own IsRunning flipping false and
                    // this loop noticing reads to TaskProgressView as the
                    // whole leg being "Done", because that IS what a
                    // finished runner with a clean exit code normally means
                    // (row 318b).
                    runner.IsBetweenPhases = true;
                    bool built = await runner.WaitUntilFinished();
                    if (runner.WasCancelled || runner.WasStoppedByUser)
                    {
                        runner.IsBetweenPhases = false;
                        WasCancelled = WasCancelled || runner.WasCancelled;
                        WasStoppedByUser = WasStoppedByUser || runner.WasStoppedByUser;
                        leg.IsFinished = true;
                        break;
                    }
                    if (!built)
                    {
                        runner.IsBetweenPhases = false;
                        leg.IsFinished = true;
                        leg.BuildFailed = true;
                        break;
                    }
                    // Still true here on the success path — cleared by the
                    // deploy Run() call below, as part of its normal reset.
                }
                else
                {
                    runner.Milestones = DeployOnlyMilestones(destination.Type);
                }

                var arguments = DeployCommand.Arguments(course.Code, sectionNumber, destination, cloudflareAccountID);
                runner.Run(DeployCommand.ScriptName, arguments, workingDirectory, keepTranscript: buildsFirst);
                if (runner.LaunchProblem is not null)
                {
                    leg.IsFinished = true;
                    continue;
                }
                bool deployed = await runner.WaitUntilFinished();
                leg.IsFinished = true;
                leg.Succeeded = deployed;
                if (runner.WasCancelled || runner.WasStoppedByUser)
                {
                    WasCancelled = WasCancelled || runner.WasCancelled;
                    WasStoppedByUser = WasStoppedByUser || runner.WasStoppedByUser;
                    break;
                }
            }
        }
        finally
        {
            // The stamp is written BEFORE IsRunning flips to false and
            // notifies — a listener that refreshes the " — Edited" marker on
            // "a run finishing" must see the new stamp already on disk, or
            // it reads the stale one and the marker stays up until the next
            // unrelated refresh.
            RecordWhatWentOut(course, sectionNumber, publishedFingerprint);
            IsRunning = false;
            Notify(nameof(IsRunning));
        }
    }

    /// <summary>
    /// Stamps <c>.publish_state/section&lt;N&gt;.json</c> and notes it on the
    /// activity trail — but only when EVERY configured destination
    /// succeeded. A course publishing to two hosts, one of which failed, has
    /// not published, and its marker must stay up: that is the whole point
    /// of redundant destinations meaning something. Mirrors the mac's
    /// `recordWhatWentOut`.
    /// </summary>
    private void RecordWhatWentOut(Course course, int sectionNumber, string? fingerprint)
    {
        if (fingerprint is null) return;
        if (!CurrentOutcome.AllSucceeded) return;

        var destinationTypes = new List<string>();
        var destinationNames = new List<string>();
        foreach (var leg in Legs)
        {
            if (!leg.Succeeded) continue;
            destinationTypes.Add(leg.Destination.Type);
            destinationNames.Add(DeployCommand.DestinationDescription(leg.Destination));
        }

        bool recorded = SectionPublishState.RecordPublish(
            course.DirectoryPath, sectionNumber, fingerprint, destinationTypes);

        string joined = JoinedWithAnd(destinationNames);
        string sentence = recorded
            ? $"marked {course.Code}-S{sectionNumber}'s pages as published to {joined}"
            : $"published {course.Code}-S{sectionNumber} to {joined}, but could not note it down — the window will still say Edited";
        ActivityTrail.Note(ActivityTrail.Event.SectionContentMarkedPublished, sentence, course.Code, sectionNumber);
    }

    // ---- Turning an outcome into words ------------------------------------

    /// <summary>
    /// Joins destination names the way a teacher would say them out loud:
    /// "Cloudflare Pages", or "Cloudflare Pages and your folder".
    /// </summary>
    public static string JoinedWithAnd(IReadOnlyList<string> items)
    {
        if (items.Count == 0) return "";
        if (items.Count == 1) return items[0];
        string result = "";
        for (int index = 0; index < items.Count; index++)
        {
            if (index == 0) result = items[index];
            else if (index == items.Count - 1) result += " and " + items[index];
            else result += ", " + items[index];
        }
        return result;
    }

    /// <summary>
    /// The final <see cref="AssistResult"/> for a
    /// finished run — the single place that decides which sentence a
    /// teacher hears, whether that is the unchanged single-destination
    /// wording (<paramref name="destinationCount"/> &lt;= 1, true for the
    /// overwhelming majority of courses) or one of the multi-destination
    /// sentences.
    /// </summary>
    public static AssistResult Result(string course, string section, int destinationCount, Outcome outcome)
    {
        if (destinationCount <= 1)
        {
            return outcome.AnySucceeded
                ? new AssistResult(true, AssistWording.Deployed(course, section), null)
                : new AssistResult(false, AssistWording.DeployDidNotFinish(course, section), null);
        }
        if (outcome.AllSucceeded)
        {
            return new AssistResult(
                true, AssistWording.DeployedToMultipleDestinations(course, section, destinationCount), null);
        }
        if (outcome.AnySucceeded)
        {
            var failedNames = outcome.FailedDestinations.Select(DeployCommand.DestinationDescription).ToList();
            return new AssistResult(
                false, AssistWording.DeployPartiallySucceeded(course, section, JoinedWithAnd(failedNames)), null);
        }
        return new AssistResult(
            false, AssistWording.DeployToMultipleDestinationsDidNotFinish(course, section), null);
    }

    private void Notify([CallerMemberName] string? property = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}
