namespace Plantoir.Core.Assist;

/// <summary>
/// Every sentence the assistant says to a teacher about deploying, previewing
/// and agreeing to things — matching contracts/assist-wording.json.
/// </summary>
public static class AssistWording
{
    // MARK: - Agreeing to something

    /// <summary>The deploy approval card, said before "Shall I deploy?".</summary>
    public const string DeployApproval =
        "Students will see what is deployed. Be certain to review changes you have made.";

    /// <summary>The question under the deploy card.</summary>
    public const string DeployQuestion = "Shall I deploy?";

    /// <summary>The question under a plan card.</summary>
    public const string PlanQuestion = "Shall I go ahead?";

    /// <summary>What the teacher's own bubble says when they press the deploy card's Go.</summary>
    public const string DeployAccepted = "Deploy";

    /// <summary>The same, for a plan.</summary>
    public const string PlanAccepted = "Go";

    /// <summary>The same, for either card's Cancel.</summary>
    public const string Cancelled = "Cancel";

    /// <summary>A cancelled DEPLOY.</summary>
    public const string DeployWasCancelled = "Deploy cancelled.";

    /// <summary>A cancelled PLAN.</summary>
    public const string PlanWasCancelled = "Left as it was — nothing was changed.";

    // MARK: - Deploying

    public static string Deployed(string course, string section) =>
        $"{course} Section {section} is deployed. Students can reach it now.";

    public static string CouldNotBuildBeforeDeploying(string course, string section) =>
        $"{course} Section {section} could not be built, so nothing was sent to students. {WhereTheOutputIs}";

    public static string DeployDidNotFinish(string course, string section) =>
        $"The deploy of {course} Section {section} did not finish. {WhereTheOutputIs}";

    /// <summary>
    /// Said only when a course has MORE THAN ONE deploy destination
    /// configured and every one of them succeeded — a course with exactly
    /// one destination (the overwhelming majority) always uses
    /// <see cref="Deployed"/> above instead, unchanged, so nothing about a
    /// teacher's experience changes unless they opted into redundancy.
    /// </summary>
    public static string DeployedToMultipleDestinations(string course, string section, int destinationCount) =>
        $"{course} Section {section} is deployed to all {destinationCount} destinations you " +
        "configured. Students can reach it now.";

    /// <summary>
    /// Said when a multi-destination deploy finished with SOME destinations
    /// succeeding and others not. <paramref name="failedDestinations"/> is
    /// already joined into words ("Cloudflare Pages" or "Cloudflare Pages
    /// and your folder") by the caller, which is the one place that knows
    /// the list — this table only ever holds whole sentences, never
    /// list-joining logic.
    /// </summary>
    public static string DeployPartiallySucceeded(string course, string section, string failedDestinations) =>
        $"{course} Section {section} deployed to some of its destinations, but not " +
        $"{failedDestinations}. {WhereTheOutputIs}";

    /// <summary>Said when a multi-destination deploy finished and NONE of its destinations succeeded.</summary>
    public static string DeployToMultipleDestinationsDidNotFinish(string course, string section) =>
        $"The deploy of {course} Section {section} did not finish, on any of its destinations. {WhereTheOutputIs}";

    public static string SectionIsBusy(string course, string section) =>
        $"{course}-S{section} is already busy in Plantoir. Wait for that to finish, then deploy.";

    public static string CourseIsBusy(string course) =>
        $"{course} is busy in Plantoir — a preview or a deploy is running. Wait for that to finish, then ask again.";

    // MARK: - Previewing

    public static string PreviewIsRebuilding(string course, string section) =>
        $"The preview for {course} Section {section} is rebuilding now, and will appear in that section's window when it is ready.";

    public static string BuiltWithNoWindowOpen(string course, string section) =>
        $"Rebuilt the site for {course} Section {section}. Open that section in Plantoir and press Preview to look it over — no window is showing it at the moment.";

    public static string RebuiltForACallerWithNoWindow(string course, string section) =>
        $"Rebuilt the preview for {course} Section {section}. Open that section in Plantoir to look it over.";

    public static string PreviewDidNotBuild(string course, string section) =>
        $"The preview for {course} Section {section} did not finish building. {WhereTheOutputIs}";

    // MARK: - Taking something back

    public static string Undid(string whatHappened) =>
        $"Earlier, you {whatHappened}. Then you asked me to undo that, and I have done so.";

    public static string UndidPartly(string whatHappened, int leftAlone)
    {
        string pages = leftAlone == 1 ? "one page" : $"{leftAlone} pages";
        return $"Earlier, you {whatHappened}. You have asked me to undo that, and I have put back everything I still recognised — but I left {pages} alone, because they have been edited since.";
    }

    public static string CouldNotUndo(string whatHappened, int leftAlone)
    {
        string pages = leftAlone == 1 ? "that page has" : $"those {leftAlone} pages have";
        return $"Earlier, you {whatHappened}, and you have asked me to undo that — but I have not changed anything, because {pages} been edited since. Putting my old copy back would throw away that newer work.";
    }

    public const string UndoIsStillAvailable =
        "That change is still on the list, so you can ask me to undo it again once you have dealt with the pages I left alone.";

    public const string NothingToUndo =
        "There is nothing on my undo list — I have not changed any pages in this conversation yet. Anything older is in Plantoir's Backups list.";

    public const string ACreatedPageCanBeTakenBack =
        "“Undo that” takes the page away again, as long as you have not written anything in it yet. Once you have, it is yours and I will leave it alone.";

    public const string UndoDoesNotReachTheLiveSite =
        "If you had already deployed this section, undoing it here does not change what students see. Deploy again when you want the live site to match.";

    // MARK: - Asking for the class dates

    public const string MayIAskForYourDates = "May I ask you for your class dates?";

    public const string DatesNotGivenYet =
        "Right you are. I will not be able to date new classes until I have them — say “I have a revised list of class dates” whenever you would like to give them.";

    // MARK: - Shared fragments

    public const string WhereTheOutputIs = "The output is in that section's window in Plantoir.";

    public const string NothingToDo = "I am not sure what to do with that.";
}
