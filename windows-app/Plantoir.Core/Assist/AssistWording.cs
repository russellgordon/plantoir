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

    // MARK: - Rolling a section over to a new year

    /// <summary>The question a rollover asks, and the only one it asks.</summary>
    /// <remarks>
    /// Neither answer is guessed, which is the whole decision (Russell,
    /// 2026-09-08). A teacher who keeps one address across years has every
    /// link anybody saved still working; a teacher who starts fresh leaves
    /// last year's site up for last year's students. Both are ordinary things
    /// to want, and the sentence says nothing about which is better.
    /// </remarks>
    public const string RolloverWebsiteQuestion =
        "Should this be a new website, or the same one students used last year?";

    /// <summary>
    /// The sentence that means "roll over, and start a new website".
    /// </summary>
    /// <remarks>
    /// Named rather than typed, because the assistant's own reply offers it
    /// back to the teacher word for word — a phrasing a teacher is TOLD to say
    /// and a phrasing <see cref="AssistCardCommand"/> accepts must be the same
    /// string, or the feature invites a sentence it then does not understand.
    /// </remarks>
    public const string RolloverSayToStartANewWebsite =
        "roll this section over onto a new website";

    /// <summary>The sentence that means "roll over, and keep last year's website".</summary>
    public const string RolloverSayToKeepTheSameWebsite =
        "roll this section over, keeping the same website";

    /// <summary>The half of the new-website sentence with no filename in it.</summary>
    /// <remarks>
    /// Named so a contract case can assert it. The whole sentence carries the
    /// kept file's name, which has a timestamp in it, so no fixed string can
    /// ever match the whole thing — and a test that cannot name the sentence
    /// ends up matching prose it typed itself, which is the copy that keeps
    /// passing after the product's words change.
    /// </remarks>
    public const string RolloverIsOnANewWebsite =
        "This section is no longer tied to last year's website.";

    /// <summary>Confirming a new website, when the section had one to be cut loose from.</summary>
    public static string RolloverStartedANewWebsite(string keptAs) =>
        RolloverIsOnANewWebsite + " Last year's details are kept at " + keptAs +
        ", so you can go back to it. The next time you publish this section, Plantoir will ask " +
        "what to call the new website.";

    /// <summary>Confirming a new website for a section that had never been published.</summary>
    public const string RolloverHadNoWebsiteYet =
        "This section had not been published anywhere yet, so there was no website to move away " +
        "from. The first time you publish it, Plantoir will ask what to call it.";

    /// <summary>Confirming the same website.</summary>
    public const string RolloverKeptTheSameWebsite =
        "This section still publishes to the same website as last year, so every link anybody " +
        "saved keeps working. Nothing goes out until you publish.";

    /// <summary>What a teacher is told when the question was never answered.</summary>
    /// <remarks>
    /// The honest half of the feature, and the reason it is a sentence rather
    /// than silence. The re-dating has already happened by the time the
    /// question appears, so an offer a teacher ignores — or one that cannot
    /// appear at all, which is every request arriving over MCP — must not
    /// leave them believing the website was dealt with.
    /// </remarks>
    public const string RolloverWebsiteNotDecided =
        "I have not changed which website this section publishes to — publishing it will still " +
        "go to last year's website. Ask me to roll it over again if you would like to choose.";

    /// <summary>A destination that could not be released, so the section is still pinned to it.</summary>
    /// <remarks>
    /// Its own sentence because the alternative said the opposite. A marker
    /// that exists and cannot be moved used to produce the same empty result
    /// as one that was never there, so a teacher was told "this section had
    /// not been published anywhere yet" about a section that is still
    /// publishing over last year's site — a lie about the one fact this whole
    /// feature turns on.
    /// </remarks>
    public static string RolloverCouldNotStartANewWebsite(string stillPinned) =>
        "I could not move this section off " + stillPinned + ", so publishing it will still " +
        "replace last year's website there. Try again, or check whether that file is locked or " +
        "open somewhere else.";

    /// <summary>
    /// Added when releasing a website turned off a publish that was set to
    /// happen on its own.
    /// </summary>
    /// <remarks>
    /// A section cut loose has no agreed website, and a scheduled run has
    /// nobody to ask, so it would silently create a website nobody named while
    /// the address students actually read stopped updating.
    /// </remarks>
    public const string RolloverTurnedOffTheScheduledPublish =
        "This section was set to publish on its own. Starting a new website turned that off — " +
        "set it again from the section's menu once you have published the new website for the " +
        "first time.";

    /// <summary>When turning that scheduled publish off did NOT work.</summary>
    /// <remarks>
    /// The dangerous state, and so the one that must not be described by the
    /// sentence above. A publish still set to run has nobody to ask what the
    /// new website should be called, so it would go ahead and make one — the
    /// exact outcome turning it off exists to prevent.
    /// </remarks>
    public const string RolloverCouldNotTurnOffTheScheduledPublish =
        "This section was also set to publish on its own, and Plantoir could not turn that off. " +
        "It may still try to publish, and it has no way to ask what the new website should be " +
        "called — turn it off from the section's menu.";

    // MARK: - Shared fragments

    public const string WhereTheOutputIs = "The output is in that section's window in Plantoir.";

    public const string NothingToDo = "I am not sure what to do with that.";
}
