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

    // ---- A re-date's reply (#357 / mac #343; class-planning.json ->
    // reDatingASection.reportedCounts). The contract stores the sentences
    // with example numbers; the counts are the classes and the pages they
    // use whose dates were WRITTEN.

    public static string ReDated(int classes, int pages) =>
        $"Re-dated {classes} {(classes == 1 ? "class" : "classes")} and {pages} {(pages == 1 ? "page" : "pages")} they use.";

    public static string ReDatedOnlyPagesTheyUse(int pages) =>
        $"Every class was already on its day, so only the {pages} {(pages == 1 ? "page" : "pages")} they use " +
        $"{(pages == 1 ? "was" : "were")} re-dated.";

    public static string EveryPageIsAlreadyOnItsDay(string course, string section) =>
        $"Every page in {course} Section {section} is already on the day it should be.";

    /// <summary>Which of the three a re-date that wrote these counts says.</summary>
    internal static string ReDatedSummary(string course, string section, int classes, int pages) =>
        classes > 0 ? ReDated(classes, pages)
        : pages > 0 ? ReDatedOnlyPagesTheyUse(pages)
        : EveryPageIsAlreadyOnItsDay(course, section);

    public static string Deployed(string course, string section) =>
        $"{course} Section {section} is deployed. Students can reach it now.";

    // ---- A windowless deploy or rebuild that met a question (#391 / mac #378)
    // The launchers run --non-interactive with nobody at a window, so a
    // question (a site name, the surname, a token) is refused with exit 3
    // rather than waiting for ever on a terminal nobody reads.

    public static string DeployNeedsAnAnswer(string course, string section) =>
        $"{course} Section {section} needs one answer before it can be deployed from here, so nothing was sent to " +
        "students. Deploy it once from its window in Plantoir, where the question can be answered; after that it can " +
        "be deployed from here.";

    public static string DeployNeedsAnAnswerAt(string course, string section, string destinations) =>
        $"{course} Section {section} was not deployed to {destinations}: it needs one answer there that can only be " +
        "given from its window in Plantoir. Deploy it once from there; after that it can be deployed from here.";


    public static string PreviewBuildNeedsAnAnswer(string course, string section) =>
        $"The preview for {course} Section {section} needs one answer before it can be built from here. Build it " +
        "once from its window in Plantoir, where the question can be answered.";

    /// <summary>#386 / mac #381: a preview of a section this app is deploying.</summary>
    public static string SectionIsBeingDeployed(string course, string section) =>
        $"{course} Section {section} is being deployed right now. Preview it once the deploy has finished.";

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

    /// <summary>Where the copy went, after "back up this course".</summary>
    /// <remarks>
    /// Names the FILE and where to find it, not a path. This used to be
    /// "Backed up to courses/_backups/ICS3U/ICS3U_backup_….zip", which is a
    /// location on disk rather than an answer — and rule 1 of CLAUDE.md keeps
    /// the machinery out of what a teacher reads. It became a teacher's
    /// sentence rather than a caller's the day "back up this course" turned
    /// into a fixed phrasing. The contract has pinned these words since the
    /// tool arrived; the mac has always said them.
    /// </remarks>
    public static string BackedUpCourse(string course, string fileName) =>
        $"Backed up {course} to {fileName}. It is in Plantoir's Backups list, and restoring " +
        "from it puts the whole course back as it is right now.";

    /// <summary>
    /// Said instead of the briefing when this section has already had it, in
    /// this conversation.
    /// </summary>
    /// <remarks>
    /// <para><b>Written for the TEACHER, who is who reads it.</b> The sentence
    /// this replaced was addressed to a model — "Don’t repeat it — carry on
    /// with what the teacher asked" — which was harmless only while
    /// <c>explain_publishing</c> was MCP-only and a model was the only caller.
    /// A fixed phrasing ("what does publishing mean?") lets a teacher call it
    /// directly, and a tool result is rendered as an ordinary assistant
    /// bubble: there is no channel here that only a model sees. The mac made
    /// and corrected the same mistake, and the wording is the contract's, so
    /// both apps now say one thing.</para>
    ///
    /// <para>"In this conversation" is the truth on this side too, since
    /// 2026-09-09 — see <c>AssistWorkspace.NoteExplainedThisConversation</c>.
    /// It used to be a file on disk, which made the sentence a lie a month
    /// later and, worse, meant a teacher who ASKED the question got this
    /// instead of an answer.</para>
    /// </remarks>
    public static string PublishingAlreadyExplained(string course, string section) =>
        $"I explained that for {course} Section {section} earlier in this conversation.";

    public static string SectionIsBusy(string course, string section) =>
        $"{course}-S{section} is already busy in Plantoir. Wait for that to finish, then deploy.";

    public static string CourseIsBusy(string course) =>
        $"{course} is busy in Plantoir — a preview or a deploy is running. Wait for that to finish, then ask again.";

    /// <summary>
    /// Added after a sentence saying some destinations were not reached, when
    /// the others DID go out, so a teacher is not left thinking nothing happened
    /// (mac #378/#396; Bundle 1 ruling 8 placed it with #400). Its caller is the
    /// "needs an answer at" sentence #391 brings; until then only the contract
    /// walker reads it.
    /// </summary>
    public static string DeployWentOutTo(string destinations) =>
        $"It did go out to {destinations}.";

    /// <summary>
    /// What the WINDOW says when Preview or Deploy is declined because another
    /// program on this computer is building, publishing or previewing the
    /// course (#289, mac #156). An assistant is told <see cref="CourseIsBusy"/>
    /// instead: on Windows both assistants are <c>plantoir-mcp</c>, the process
    /// talking to the program whose course is busy.
    /// </summary>
    public static string CourseIsBeingBuiltElsewhere(string course) =>
        $"{course} is being previewed or published somewhere else on this computer right now — by an assistant " +
        "working from another app, another copy of Plantoir, or a deploy set for later. Both would build the same " +
        "pages in the same place, so doing it here as well would spoil both. Try again once that has finished.";

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

    /// <summary>
    /// Said after a section restore that left one shared page's setting as it
    /// was, because its settings have no column-0 place for a new line (#308,
    /// the mac's #182/#186). Past tense and counted, never named.
    /// </summary>
    public static string SharedPageWhoseSettingCouldNotBePutBack(string section) =>
        SharedPagesWhoseSettingsCouldNotBePutBack(1, section);

    /// <summary>The same, for several pages — the mac's one function, split by key here so the walk finds both.</summary>
    public static string SharedPagesWhoseSettingsCouldNotBePutBack(int count, string section) => count == 1
        ? $"One shared page kept the setting it has now for Section {section}: the settings at the top of it are written in a way I can’t add to, so I left that page exactly as it is."
        : $"{count} shared pages kept the settings they have now for Section {section}: the settings at the top of them are written in a way I can’t add to, so I left those pages exactly as they are.";

    // ---- Already in that state (#346, the mac's #174) ----------------------

    public const string AlreadyPublishedOne = "It's already been published.";
    public const string AlreadyHiddenOne = "It's already hidden.";
    public const string AlreadyPublishedSeveral = "They have already been published.";
    public const string AlreadyHiddenSeveral = "They have already been hidden.";
    public static string UnitAlreadyPublished(string unitWord, int unit) => $"{unitWord} {unit} has already been published.";
    public static string UnitAlreadyHidden(string unitWord, int unit) => $"{unitWord} {unit} is already hidden.";

    // ---- Making room (#346, the mac's #185) -------------------------------

    /// <summary>
    /// Said on the PLAN card when other classes will move — make-room's, and
    /// the duplicate's since #185 — so a teacher can still say no. Future
    /// tense: <see cref="ClassChangeWording.OtherClassesMoved"/> is the reply's
    /// past-tense twin and would be false before anything has moved.
    /// </summary>
    public const string MakingRoomCannotBeUndone =
        "Because other classes move, “Undo that” will not take this back afterwards — the copy made before any of it is in Plantoir's Backups list.";

    /// <summary>The make-room reply's last line. Windows said "…before you deploy it." until #346; it says the mac's now.</summary>
    public const string LookTheSectionOverBeforePublishing = "Look the section over in Plantoir before you publish.";

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

    // MARK: - Class planning (hoisted 2026-09-30, #157)
    //
    // Sentences this app already said inline, word for word as the contract
    // has them, moved here under their contract key so the walker compares
    // them. Nothing a teacher reads changed. Dates are handed in already
    // formatted, exactly as the call sites formatted them before.

    public const string EveryDateIsSpokenFor =
        "Every recorded date is spoken for, so another class cannot be dated until more dates are recorded.";

    public static string MadeRoom(int added, string unitWord, int unit, int day) =>
        $"Made room for {added} class{(added == 1 ? "" : "es")} at {unitWord} {unit}, Day {day}.";

    public static string MovedToLaterDays(int moved) => $"Moved to later class days — {moved}:";

    public static string MovesAndBecomesADraft(string page, string day) =>
        $"“{page}” moves to {day} and becomes a draft because it has no class date.";

    public static string PublishedTheClassOn(string day) => $"Published the class on {day}.";

    public static string ReDatingOntoTheDatesOnFile(string course, string section) =>
        $"{course} Section {section}: re-dating onto the class dates on file.";

    public static string TheNextWouldFallOn(string day, string dayName) =>
        $"The next class would fall on {day} ({dayName}).";

    // MARK: - The How I Teach page (#340, mac #209)

    public static string HowITeachAlreadyWritten(string course) =>
        $"Nothing was saved: {course} already has a How I Teach page, and a teacher's own page is never replaced without their agreement. Use plan_write_how_i_teach, show the teacher what it says, and pass the mark it gives as replacing only if they agree to replace their page.";

    public static string HowITeachBriefing(string course) =>
        $"These courses have a How I Teach page — the teacher's own account of how the course is taught. Read it with read_how_i_teach before drafting or revising anything in that course, and keep to it:\n  {course}";

    public const string HowITeachCarriesNoSettings =
        "Nothing was saved: pass the page's words only, without a --- settings block at the top. Plantoir writes the page's settings itself.";

    public static string HowITeachChangedSincePlanned(string course) =>
        $"Nothing was saved: the How I Teach page for {course} is not the one that was planned — it has changed since, or that is not its mark. Plan again with plan_write_how_i_teach and show the teacher before replacing it.";

    public static string HowITeachCutShort(string course, string path) =>
        $"The How I Teach page for {course} is longer than one answer can carry, so it stops here. The rest is in {path} — read it with your own tools.";

    public const string HowITeachDraftingBrief =
        "If you offer to draft it: offer first, and draft only if the teacher says yes. Before drafting, read the course's own pages with the plantoir tools — the section's landing page, class pages from at least two different units, and a few of its warm-ups, tasks and discussions where there are any; if a course kept for reference has the same code, read that too. Write in the teacher's own first person. Say what the pages SHOW — how a class is shaped, whether ideas are explored before they are named, how practice and feedback work, the kinds of page that keep coming back and what each is for, and how the pages speak to students — and never invent what they do not show. Aim for 200 to 500 words. Show the teacher the whole draft and change it until they agree. Then save it with plan_write_how_i_teach and write_how_i_teach, never with your own file tools, so it is kept off the website, backed up first and can be undone.";

    public static string HowITeachEmpty(string course) =>
        $"{course}’s How I Teach page has been started but has nothing written in it yet, so there is nothing to keep to. The teacher can write it in Obsidian, or you can offer to draft one; saving a draft fills the empty page, and needs no replacing mark.";

    public static string HowITeachIsNeverPublished(string course) =>
        $"The How I Teach page for {course} is never put on the website — it is for you and your assistant. To share something like it with students, make a page with a different name.";

    public const string HowITeachListedAsNotWritten =
        "  How I Teach page: not written yet";

    public const string HowITeachListedAsWritten =
        "  How I Teach page: yes";

    public static string HowITeachMissing(string course) =>
        $"{course} has no How I Teach page yet. It would be a page named exactly “How I Teach”, at the top of the {course} course folder beside its other pages — only a page with exactly that name, in exactly that place, is kept off the website. The teacher can write it there in Obsidian, or you can offer to draft one.";

    public const string HowITeachNeedsWords =
        "Nothing was saved: the page's text is empty. Pass the words of the page as text.";

    public static string HowITeachPlanCreates(string course, string path) =>
        $"This would save a new How I Teach page for {course} at {path}, set so it is never put on the website. Show the teacher the whole text and wait for them to agree before calling write_how_i_teach.";

    public static string HowITeachPlanReplaces(string course, string path, string words, string changed, string mark) =>
        $"{course} already has a How I Teach page, at {path} ({words} words, last changed {changed}). Saving would REPLACE what it says; any settings at its top are kept. Show the teacher the whole new text, tell them it replaces the page they have, and only if they agree call write_how_i_teach with replacing: “{mark}”.";

    public static string HowITeachRead(string course, string text) =>
        $"Here is the How I Teach page for {course}: the teacher's own account of how this course is taught. Keep to it in anything you draft or revise for {course}. It is never put on the website.\n\n{text}";

    public static string HowITeachSaved(string course) =>
        $"Saved the How I Teach page for {course}. It’s in the course folder beside your other pages, so you can change it in Obsidian any time. It’s never put on your website.";

    public const string HowITeachTooLong =
        "Nothing was saved: that is longer than a How I Teach page can be (8000 characters). Make it shorter and show the teacher again.";

    // MARK: - Shared fragments

    public const string WhereTheOutputIs = "The output is in that section's window in Plantoir.";

    public const string NothingToDo = "I am not sure what to do with that.";
}
