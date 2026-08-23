import Foundation

/// One step of a long-running task: the text shown to the teacher, and
/// the marker in the output that means the step has been reached.
struct TaskMilestone {

    // MARK: - Stored properties

    /// Brief, meaningful label, e.g. "Building your site".
    let label: String

    /// A phrase that appears in the output when this step begins.
    let marker: String
}

/// The ordered milestones for each kind of task. Progress is "how many
/// milestones have been reached", so the bar advances in real steps
/// rather than spinning indefinitely.
enum TaskMilestones {

    // MARK: - Stored properties

    /// Creating a course: the wizard's own progression.
    static let courseCreation: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Getting ready…", marker: "Welcome to the Course Setup Script"),
        TaskMilestone(label: "Preparing your course folder…", marker: "'Media' folder"),
        TaskMilestone(label: "Choosing appearance…", marker: "Quartz Locale"),
        TaskMilestone(label: "Setting up sections…", marker: "timetable section numbers"),
        TaskMilestone(label: "Creating folders and files…", marker: "Select folders/files to HIDE"),
        TaskMilestone(label: "Finishing up…", marker: "set up successfully"),
    ]

    /// Installing the example course.
    static let exampleCourse: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Getting things ready…", marker: "Starting container if needed"),
        TaskMilestone(label: "Copying the example course…", marker: "Example Course installed to"),
        TaskMilestone(label: "Finishing up…", marker: "EXAMPLE_COURSE_CODE="),
    ]

    /// Previewing a section.
    static let preview: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Starting up…", marker: "Starting container if needed"),
        TaskMilestone(label: "Gathering your content…", marker: "Copying shared folders"),
        TaskMilestone(label: "Applying your settings…", marker: "Updated pageTitle"),
        TaskMilestone(label: "Preparing components…", marker: "Installing dependencies"),
        TaskMilestone(label: "Building your site…", marker: "Quartz v4"),
        // "Launching Quartz preview" — build_site.py's own print — fires BEFORE
        // `quartz build --serve` even starts, so it used to complete every
        // milestone at once and pin the bar on this step for the whole real
        // build (TODO.md item 1, found 2026-08-19). "Done processing" is
        // patches/build.ts's own line, printed once the fresh site is actually
        // written to disk — verified against a real `preview.ps1 --build-only`
        // transcript on Windows 2026-08-23 ("Quartz v4.5.0" then "Done
        // processing N files in Ns"). **This edit was authored on Windows and
        // has NOT been built or tested on a mac — see MAC-HANDOFF.md.**
        TaskMilestone(label: "Opening the preview…", marker: "Done processing"),
    ]

    /// Publishing a section to Netlify.
    static let deploy: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Starting up…", marker: "Ensuring container is running"),
        TaskMilestone(label: "Checking your site…", marker: "Deploying from local build"),
        TaskMilestone(label: "Connecting to Netlify…", marker: "Netlify site"),
        TaskMilestone(label: "Comparing what changed…", marker: "delta deploy manifest"),
        TaskMilestone(label: "Uploading your pages…", marker: "Delta deploy created"),
        TaskMilestone(label: "Finishing up…", marker: "Deploy complete"),
    ]

    /// Publishing when the site has to be rebuilt first — one task from
    /// the teacher's point of view, so one progress bar.
    static let buildAndDeploy: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Starting up…", marker: "Starting container if needed"),
        TaskMilestone(label: "Gathering your content…", marker: "Copying shared folders"),
        TaskMilestone(label: "Building your site…", marker: "Quartz v4"),
        TaskMilestone(label: "Connecting to Netlify…", marker: "Netlify site"),
        TaskMilestone(label: "Uploading your pages…", marker: "Delta deploy created"),
        TaskMilestone(label: "Finishing up…", marker: "Deploy complete"),
    ]

    /// Deploying a section to Cloudflare Pages. Netlify is never involved,
    /// so the progress must not mention it. There is no "comparing what
    /// changed" step: Cloudflare's own tool works out which assets it
    /// already holds, rather than the manifest exchange Netlify uses.
    static let deployToCloudflare: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Starting up…", marker: "Ensuring container is running"),
        TaskMilestone(label: "Checking your site…", marker: "Deploying from local build"),
        TaskMilestone(label: "Connecting to Cloudflare…", marker: "Cloudflare project"),
        TaskMilestone(label: "Uploading your pages…", marker: "Uploading the built site"),
        TaskMilestone(label: "Finishing up…", marker: "Deploy complete"),
    ]

    /// Deploying to Cloudflare when the site has to be rebuilt first.
    static let buildAndDeployToCloudflare: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Starting up…", marker: "Starting container if needed"),
        TaskMilestone(label: "Gathering your content…", marker: "Copying shared folders"),
        TaskMilestone(label: "Building your site…", marker: "Quartz v4"),
        TaskMilestone(label: "Connecting to Cloudflare…", marker: "Cloudflare project"),
        TaskMilestone(label: "Uploading your pages…", marker: "Uploading the built site"),
        TaskMilestone(label: "Finishing up…", marker: "Deploy complete"),
    ]

    /// Publishing a section to a folder on this Mac. Netlify is never
    /// involved, and neither is the container: the built site already
    /// sits on this Mac, so the whole publish is a quick local copy.
    static let deployToFolder: [TaskMilestone] = [
        TaskMilestone(label: "Checking your site…", marker: "Host timezone offset"),
        TaskMilestone(label: "Copying your files…", marker: "to a folder"),
        TaskMilestone(label: "Finishing up…", marker: "PUBLISHED_FOLDER="),
    ]

    /// Publishing to a folder when the site has to be rebuilt first.
    static let buildAndDeployToFolder: [TaskMilestone] = [
        TaskMilestone(label: "Getting this Mac ready…", marker: "Setting up this Mac"),
        TaskMilestone(label: "Building your website builder…", marker: "Building your website builder"),
        TaskMilestone(label: "Starting up…", marker: "Starting container if needed"),
        TaskMilestone(label: "Gathering your content…", marker: "Copying shared folders"),
        TaskMilestone(label: "Building your site…", marker: "Quartz v4"),
        TaskMilestone(label: "Copying your files…", marker: "to a folder"),
        TaskMilestone(label: "Finishing up…", marker: "PUBLISHED_FOLDER="),
    ]

}
