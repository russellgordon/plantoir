namespace Plantoir.Core.Scripting;

/// <summary>A label shown to the teacher and the marker searched for in output.</summary>
public sealed record TaskMilestone(string Label, string Marker);

/// <summary>
/// The ordered milestone lists for each task, with markers matched against
/// what the WINDOWS launchers really print (the .ps1 output differs from the
/// .sh output in its host-side lines; the in-container Python lines are
/// shared). Every label ends with an ellipsis — the shared invariant.
/// </summary>
public static class TaskMilestones
{
    public static readonly IReadOnlyList<TaskMilestone> CourseCreation = new[]
    {
        new TaskMilestone("Getting things ready…", "Detected host timezone offset"),
        new TaskMilestone("Getting ready…", "Welcome to the Course Setup Script"),
        new TaskMilestone("Preparing your course folder…", "'Media' folder"),
        new TaskMilestone("Choosing appearance…", "Quartz Locale"),
        new TaskMilestone("Setting up sections…", "timetable section numbers"),
        new TaskMilestone("Creating folders and files…", "Select folders/files to HIDE"),
        new TaskMilestone("Finishing up…", "set up successfully"),
    };

    public static readonly IReadOnlyList<TaskMilestone> ExampleCourse = new[]
    {
        new TaskMilestone("Getting things ready…", "Detected host timezone offset"),
        new TaskMilestone("Copying the example course…", "Example Course installed to"),
        new TaskMilestone("Finishing up…", "EXAMPLE_COURSE_CODE="),
    };

    public static readonly IReadOnlyList<TaskMilestone> Preview = new[]
    {
        new TaskMilestone("Getting things ready…", "Running the website builder on this PC"),
        new TaskMilestone("Gathering your content…", "Copying shared folders"),
        new TaskMilestone("Applying your settings…", "Updated pageTitle"),
        new TaskMilestone("Preparing components…", "Installing dependencies"),
        new TaskMilestone("Building your site…", "Quartz v4"),
        new TaskMilestone("Opening the preview…", "Launching Quartz preview"),
    };

    public static readonly IReadOnlyList<TaskMilestone> Deploy = new[]
    {
        new TaskMilestone("Getting things ready…", "Host timezone offset"),
        new TaskMilestone("Starting up…", "from this PC"),
        new TaskMilestone("Checking your site…", "Deploying from local build"),
        new TaskMilestone("Connecting to Netlify…", "Netlify site"),
        new TaskMilestone("Comparing what changed…", "delta deploy manifest"),
        new TaskMilestone("Uploading your pages…", "Delta deploy created"),
        new TaskMilestone("Finishing up…", "Deploy complete"),
    };

    /// <summary>Rebuild + publish presented as ONE task with one bar.</summary>
    public static readonly IReadOnlyList<TaskMilestone> BuildAndDeploy = new[]
    {
        new TaskMilestone("Getting things ready…", "Running the website builder on this PC"),
        new TaskMilestone("Gathering your content…", "Copying shared folders"),
        new TaskMilestone("Building your site…", "Quartz v4"),
        new TaskMilestone("Connecting to Netlify…", "Netlify site"),
        new TaskMilestone("Uploading your pages…", "Delta deploy created"),
        new TaskMilestone("Finishing up…", "Deploy complete"),
    };

    /// <summary>
    /// Folder-mode publish: the site is already built on the host, so the
    /// launcher only mirrors changed files into the chosen folder — quick,
    /// containerless, and never mentioning Netlify (row 102d).
    /// </summary>
    public static readonly IReadOnlyList<TaskMilestone> DeployToFolder = new[]
    {
        new TaskMilestone("Checking your site…", "Host timezone offset"),
        new TaskMilestone("Copying your files…", "to a folder"),
        new TaskMilestone("Finishing up…", "PUBLISHED_FOLDER="),
    };

    /// <summary>Rebuild + folder publish presented as ONE task with one bar.</summary>
    public static readonly IReadOnlyList<TaskMilestone> BuildAndDeployToFolder = new[]
    {
        new TaskMilestone("Getting things ready…", "Running the website builder on this PC"),
        new TaskMilestone("Gathering your content…", "Copying shared folders"),
        new TaskMilestone("Building your site…", "Quartz v4"),
        new TaskMilestone("Copying your files…", "to a folder"),
        new TaskMilestone("Finishing up…", "PUBLISHED_FOLDER="),
    };

    /// <summary>
    /// Cloudflare publish. The phrases match what deploy.py prints on that
    /// path — and, like folder mode, never say Netlify.
    /// </summary>
    public static readonly IReadOnlyList<TaskMilestone> DeployToCloudflare = new[]
    {
        new TaskMilestone("Getting things ready…", "Host timezone offset"),
        new TaskMilestone("Starting up…", "from this PC"),
        new TaskMilestone("Checking your site…", "Deploying from local build"),
        new TaskMilestone("Connecting to Cloudflare…", "Cloudflare project"),
        new TaskMilestone("Uploading your pages…", "Uploading the built site"),
        new TaskMilestone("Finishing up…", "Deploy complete"),
    };

    /// <summary>Rebuild + Cloudflare publish presented as ONE task with one bar.</summary>
    public static readonly IReadOnlyList<TaskMilestone> BuildAndDeployToCloudflare = new[]
    {
        new TaskMilestone("Getting things ready…", "Running the website builder on this PC"),
        new TaskMilestone("Gathering your content…", "Copying shared folders"),
        new TaskMilestone("Building your site…", "Quartz v4"),
        new TaskMilestone("Connecting to Cloudflare…", "Cloudflare project"),
        new TaskMilestone("Uploading your pages…", "Uploading the built site"),
        new TaskMilestone("Finishing up…", "Deploy complete"),
    };

    public static IEnumerable<IReadOnlyList<TaskMilestone>> AllLists
    {
        get
        {
            yield return CourseCreation;
            yield return ExampleCourse;
            yield return Preview;
            yield return Deploy;
            yield return BuildAndDeploy;
            yield return DeployToFolder;
            yield return BuildAndDeployToFolder;
            yield return DeployToCloudflare;
            yield return BuildAndDeployToCloudflare;
        }
    }
}
