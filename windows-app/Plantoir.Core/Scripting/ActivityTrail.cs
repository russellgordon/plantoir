using System;
using System.IO;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

public static class ActivityTrail
{
    public enum Event
    {
        AppOpened,
        Machine,
        Helpers,
        WorkingFolderOpened,
        SettingsSaved,

        /// <summary>
        /// Course Settings held Save back because the unsaved edit moves where
        /// the course publishes to a destination with a problem (#387, mac
        /// #373). Carries the course and which check; once per visit.
        /// </summary>
        SettingsSaveHeldBack,

        /// <summary>Show on Front Page rewrote the section's class line (#406, mac #397). File names only.</summary>
        PutTodaysClassOnTheFrontPage,

        /// <summary>The question was answered and the front page was NOT changed — which answer, and why (#406).</summary>
        LeftTheFrontPageAsItWas,
        SettingsCouldNotBeSaved,
        TaskStarted,
        TaskFinished,
        AskedForACredential,
        AssistantOpened,
        AssistantReady,
        AssistantWouldNotStart,
        AssistantAsked,
        AssistantMatchedAFixedPhrase,
        AssistantChoseATool,
        AssistantCouldNotAnswer,
        /// <summary>
        /// The model named a tool that exists but was not on the list it was
        /// shown, and the turn was refused with nothing run (#350 / mac #327).
        /// Carries the course, the section and the tool IN WORDS — never the
        /// teacher's sentence and never the argument values.
        /// </summary>
        AssistantNamedAToolItWasNotOffered,
        /// <summary>
        /// A publish or hide named no page the section has (only words
        /// meaning every page, or names that all matched nothing) and was
        /// refused (#352 / mac #197). Carries the word or HOW MANY names
        /// missed; never the names themselves.
        /// </summary>
        AssistantNamedNoPage,
        /// <summary>The links checklist was shown (#392/#399/#405): counts per group, listed under another page, shown ticked, the occasion. Never a page's name.</summary>
        OfferedToPublishPagesThatLinksLeadTo,
        /// <summary>The links checklist's Publish: counts, and the PLACES of the published pages (at most ten), never page content.</summary>
        PublishedPagesThatLinksLedTo,
        /// <summary>Not Now, or Publish with rows left: every page left hidden, the followers in brackets. Written only when above 0.</summary>
        LeftPagesHiddenThatLinksLeadTo,
        /// <summary>
        /// The model's call named a course other than this window's, and the
        /// turn was refused (#180). Carries this window's course and section,
        /// the course AS THE MODEL SPELT IT, and the tool it had chosen —
        /// never the teacher's sentence and never the argument values. The
        /// pair of codes is what tells the guard doing its job apart from a
        /// model slip refused at the teacher's expense.
        /// </summary>
        AssistantWasAskedAboutAnotherCourse,
        /// <summary>
        /// The model's reply could not be acted on and nothing was run from
        /// it (#196). One event, two sentences: the engine STOPPED it part
        /// way (a question about how much it was asked to write), or it
        /// finished and its arguments could not be read (a question about the
        /// model). Carries course, section and the tool it had begun to name —
        /// never what it had begun to write, which is page titles.
        /// </summary>
        AssistantAnswerWasCutOff,
        /// <summary>
        /// The model answered with the teacher's own request (#217); nothing
        /// ran and the turn was taken back out of the conversation. Carries
        /// course and section only — never the sentence (<c>assistant asked</c>
        /// has it) and never page content. Not folded into "answer was cut
        /// off": this answer FINISHED, and a line describing something else is
        /// worse than none.
        /// </summary>
        AssistantRepeatedTheRequestBack,
        AppSettingsOpened,
        AssistantModelChosen,
        AssistantModelDownloadStarted,
        AssistantModelDownloaded,
        AssistantModelDownloadFailed,
        AssistantModelRemoved,
        AssistantModelDownloadStopped,
        AssistantConfirmationChanged,
        SectionContentMarkedPublished,
        /// <summary>
        /// A section's leftover website-builder processes were ended.
        /// Carries the course, the section, and HOW MANY — the count is the
        /// point. Stopping a preview, closing a window or cancelling a
        /// publish asks the launcher to end whatever that section still has
        /// running, and nothing else on the trail separates "there was
        /// nothing left to stop" from "a build was still going and was
        /// ended". Those are the two competing explanations when a teacher
        /// reports a publish that stopped halfway.
        /// </summary>
        SectionProcessesReclaimed,
        /// <summary>
        /// A course folder was renamed from inside Plantoir. Carries the OLD
        /// and NEW folder names and the course - never anything from inside
        /// the folder. A rename is the one moment Plantoir witnesses the
        /// change, so it is the one line that can explain a course whose
        /// configuration stopped matching what is on disk.
        /// </summary>
        FolderRenamed,
        /// <summary>
        /// Adding a name to a course's folder list CREATED the folder. Recorded
        /// because the old behaviour was to write a configuration entry
        /// pointing at nothing, and a teacher who remembers the old behaviour
        /// needs to be able to see which it was.
        /// </summary>
        FolderCreated,
        /// <summary>
        /// A course was made — by the New Course wizard (written BEFORE the
        /// launcher starts, so a creation that fails part-way still says what
        /// was asked for) or by Add Example Course (written AFTER, from the
        /// code the run reported). Carries the code and which of the three
        /// starting points it began from; never the name the teacher typed.
        /// Before this a creation left only "started setup.ps1" with empty
        /// arguments, which is how mac #248 stayed invisible for five weeks.
        /// </summary>
        CourseCreated,
        /// <summary>
        /// Course Settings' "Create and Open" made an EMPTY How I Teach page,
        /// or could not, and why (#360, mac #329). Opening a page that is
        /// there writes nothing.
        /// </summary>
        HowITeachPageStarted,
        /// <summary>
        /// The assistant zipped a course: the backup's file name, its size in
        /// MB and how long it took in seconds, one decimal each — or that it
        /// could not, and why (#360, mac #351). One line per REAL zip; the
        /// conversation's copy reused by a later write writes nothing.
        /// </summary>
        AssistantBackedUpACourse,
        /// <summary>
        /// Which curriculum coverage maps a build wrote (#345, mac #128): each
        /// map's title, the folder it was built from and how many expectations
        /// it shows — or that it wrote none. From the build's PLANTOIR_MAPS:
        /// line, for a run the app starts and for a scheduled publish.
        /// </summary>
        CurriculumMapsBuilt,
        /// <summary>
        /// A section was got ready for the start of the year (#355, mac #96):
        /// where it was asked from, how many classes and other pages went into
        /// draft (first used later / nothing students can see links to), how
        /// many were left, the backup's file name, whether the preview was
        /// rebuilt. Never a page's name — the backup is how anyone finds them.
        /// </summary>
        SectionMadeReadyForTheStartOfTheYear,
        /// <summary>A start-of-year change was undone: from where, how many pages put back, how many left because they changed since.</summary>
        StartOfYearChangeUndone,
        /// <summary>
        /// Getting ready was asked for and nothing was changed, with the reason
        /// (changedSinceShown, deployUnderWay, backupFailed, writeFailed,
        /// noFirstClass, missingPlanCode, nothingToDo) — "I pressed the button
        /// and nothing happened" leaves no file changed to show it.
        /// </summary>
        StartOfYearNotDone,
        /// <summary>
        /// The APP reopened a working folder at launch rather than the teacher
        /// choosing one (#320). Carries the path (redacted) and which it was —
        /// the window's own folder or the last working folder. A window opened
        /// beside another (Ctrl+N) inherits a folder and writes nothing.
        /// </summary>
        WorkingFolderReopened,
        /// <summary>
        /// A remembered working folder could not be reopened, so the window shows
        /// the picker with a sentence. Carries the reason key, which folder it
        /// was, and the path (redacted): the drive gets plugged back in and the
        /// permission granted, so they cannot be looked for afterwards.
        /// </summary>
        WorkingFolderNotReopened,
        /// <summary>
        /// Course Settings' Revert took back unsaved exclusion changes. Carries
        /// the course and HOW MANY — never the names, which the click lines
        /// beside it already carry. Russell, 2026-09-06: <c>item excluded</c>
        /// is written on the click, so a Revert that takes the removal back
        /// needs its own line or the trail says a folder was excluded when it
        /// never was. Written only when the count is at least one.
        /// </summary>
        ExclusionsReverted,
        /// <summary>
        /// A working folder was recognised as kept in sync by a cloud service.
        /// Carries the service's name — never the folder's path, which is a
        /// teacher's own filing and is redacted from the trail anyway.
        /// </summary>
        SyncedFolderNoticed,
        /// <summary>
        /// The teacher chose to use the synced folder anyway. Recorded because
        /// it is a decision Plantoir then remembers and stops asking about,
        /// and a teacher reporting "it never warned me" is asking about
        /// exactly this line.
        /// </summary>
        SyncedFolderAccepted,
        /// <summary>
        /// A folder a feature depends on was missing, renamed or emptied.
        /// Carries the check's NAME, never its wording.
        /// </summary>
        FolderProblemFound,
        /// <summary>
        /// A folder a feature depends on was put back, at the teacher's
        /// request. Separate from FolderProblemFound: one says something is
        /// wrong, the other says somebody acted on it.
        /// </summary>
        FolderProblemRepaired,
        /// <summary>
        /// A repair the teacher ASKED for that did not happen. Carries the
        /// course, the section and what was in the way -- never anything from
        /// inside it. Written today from ONE place only: the refusal when a
        /// folder named index.md sits where the front page belongs. A repair
        /// that simply failed (read-only volume, permissions) still records
        /// nothing, deliberately; the event is named for the OUTCOME rather
        /// than for its one cause so that gap can be closed later without a
        /// rename on either platform.
        /// </summary>
        FolderProblemNotRepaired,
        /// <summary>
        /// A build rewrote some of the teacher's own pages with their class's
        /// date (#279; the rule is the shared Python's). Carries the course,
        /// the section, the count and the pages' places in the course folder
        /// -- never anything written on them. Read from the build's
        /// PLANTOIR_DATED: line: from the console for a run the app watches
        /// (ScriptRunner), and from a scheduled publish's record
        /// (ScheduledHealthFindings).
        /// </summary>
        PagesDatedByTheBuild,
        /// <summary>
        /// An outside assistant read a course's How I Teach page (#340, mac
        /// #209): the course and the word count, or that there was none or it
        /// was empty -- never a word of it.
        /// </summary>
        HowITeachPageRead,
        /// <summary>
        /// An outside assistant saved a course's How I Teach page: created or
        /// replaced, the word counts, and the backup made first. Never the
        /// words -- the question it answers is "did I write this, or did an
        /// assistant?".
        /// </summary>
        HowITeachPageWritten,
        /// <summary>
        /// A build dropped a How I Teach page the course's settings had listed
        /// for the site (the build's PLANTOIR_KEPT_OFF: line), so a page
        /// earlier builds published is now kept back. The pages' places only.
        /// </summary>
        HowITeachPageKeptOff,
        /// <summary>
        /// A teacher put a section back to how it was when an assistant
        /// conversation started. Carries the course, the section and the
        /// backup's file name -- never a page. The one line that explains a
        /// section whose pages are older than the conversation that changed
        /// them; without it the trail shows six changes and then nothing.
        /// </summary>
        SectionRestored,
        AssistantEngineSaid,
        // The three below are named by contracts/shared-rules.json ->
        // activityTrail.mustRecord, which SharedRules_ActivityTrailEvents_Exist
        // pins as a set. They are declared here, with the site-health work, so
        // that suite is green; their call sites arrive with the Course
        // Settings exclusion and protection work. Declaring an event with no
        // caller is exactly what left FolderProblemFound dead for months --
        // so this is a note that they are owed a caller, not a precedent.

        /// <summary>
        /// A teacher removes a folder or file in Course Settings, taking it
        /// out of previews and deploys. Carries the course, the scope and the
        /// name -- never anything written on the page.
        /// </summary>
        ItemExcluded,
        /// <summary>
        /// A teacher adds a previously excluded folder or file back. To be
        /// recorded ONLY when the name really was excluded: an ordinary add is
        /// not a re-inclusion, and a trail line saying it was would be
        /// believed.
        /// </summary>
        ItemReIncluded,
        /// <summary>
        /// A teacher tries to remove or untick something a feature depends on
        /// and is shown why it cannot go. "I could not remove the folder" is a
        /// report support will receive; this line says which rule refused.
        /// </summary>
        RemovalBlocked,
        /// <summary>
        /// A rollover cut a section loose from last year's website. Carries
        /// the course, the section and — when there was a website to move away
        /// from — where last year's details were kept.
        /// </summary>
        /// <remarks>
        /// The same act turns off any publish that was set to happen on its
        /// own, so a teacher whose overnight publish stops happening has one
        /// line explaining both.
        /// </remarks>
        SectionStartedANewWebsite,
        /// <summary>
        /// A rollover kept last year's website. The OTHER answer, and the one
        /// a problem report is more likely to be about: a teacher writing in
        /// weeks later to say last year's class site was replaced is
        /// describing this branch.
        /// </summary>
        SectionKeptItsWebsite,
        /// <summary>
        /// A publish set to happen on its own stopped because it needed an
        /// answer. Carries the course, the section and which destination
        /// stopped — never the question's own text.
        /// </summary>
        /// <remarks>
        /// The one thing that can happen to a scheduled publish that a teacher
        /// would otherwise never find out about: it runs with the app closed,
        /// so a question it could not ask is seen by nobody. The question's
        /// TEXT is deliberately left out — it comes from a launcher's console,
        /// and a line naming a credential prompt would put a teacher's own
        /// words on the trail.
        /// </remarks>
        ScheduledPublishNeededAnAnswer,
        /// <summary>
        /// A publish set to happen on its own did not finish, for any reason
        /// other than a question — a revoked token, a network that was down, a
        /// build that failed. Carries the course, the section and which
        /// destination stopped.
        /// </summary>
        /// <remarks>
        /// <para>The same silence as <see cref="ScheduledPublishNeededAnAnswer"/>
        /// from a different cause, and a SEPARATE event on purpose. That one's
        /// own wording says a question went unasked, so filing a revoked token
        /// under it would make the trail say something untrue about the one run
        /// a teacher is trying to understand.</para>
        ///
        /// <para>Added 2026-09-09 when Russell widened the readout to ANY
        /// failed scheduled publish: a teacher should learn their overnight
        /// publish did not happen whatever the reason, because the SILENCE is
        /// the complaint rather than the cause. Recording only the question
        /// case leaves an ordinary overnight failure exactly as silent as it
        /// was before.</para>
        /// </remarks>
        ScheduledPublishDidNotFinish,
        /// <summary>
        /// A publish set to happen on its own went out. Carries the course, the
        /// section, and where it published.
        /// </summary>
        /// <remarks>
        /// The positive case, here for the same reason as the two failures read
        /// the other way round: a scheduled publish that leaves NO trace cannot
        /// be told from one that never happened. Without this line the trail
        /// can answer "why did my site not update?" and cannot answer "did
        /// it?", and a teacher wondering whether last night's publish went out
        /// has nowhere to look.
        /// </remarks>
        ScheduledPublishFinished,
        /// <summary>
        /// A build was declined because ANOTHER program on this computer holds
        /// the course's build, publish or preview lease (#289, mac #156).
        /// Carries the course, the section, what was asked for, what the other
        /// holds and its process id — never anything written on a page.
        /// Also (#386, mac #381): a PREVIEW refused because this copy of the
        /// app was deploying that same section (lineWhenItsSectionIsBeingDeployed).
        /// </summary>
        BuildDeclinedCourseBusyElsewhere,
        /// <summary>
        /// A publish set for later found the course being built or published
        /// elsewhere and waited for it (#289). Carries how long, for whom, and
        /// whether it then went ahead or stood down — a publish that went out
        /// ten minutes late looks, from outside, exactly like one that misfired.
        /// </summary>
        ScheduledPublishWaitedForTheCourse,
        /// <summary>
        /// A deploy the teacher set to happen on its own was turned off by
        /// something other than them asking: the course or the section was
        /// removed (#239), the day it was set for had gone by, the course was
        /// still busy after the wait, or it could not deploy the way the course
        /// is set now. Carries the course, the section and WHICH.
        /// </summary>
        ScheduledDeployTurnedOff,
        /// <summary>
        /// A new scheduled deploy replaced one already set for the section
        /// (#261). Carries course, section, the old moment and the new one —
        /// written where the task is written, from a reading taken before the
        /// old one was removed, and only once the new one was accepted.
        /// </summary>
        ScheduledDeployReplaced,
        /// <summary>
        /// A scheduled deploy could not be set (#261). Carries course, section,
        /// the moment asked for and, when one was already set, whether it
        /// still stands.
        /// </summary>
        ScheduledDeployCouldNotBeSet,
        /// <summary>
        /// A publish set for later read the course's settings when it ran
        /// (#347, mac #323) and found them different from what the teacher was
        /// told, or stood down over them. Written only when something differs.
        /// </summary>
        ScheduledPublishReadTheCoursesSettings,
        /// <summary>
        /// Quitting asked first, because a publish or a preview build was under
        /// way (#231). Carries what, in the words shown, and which button was
        /// pressed — "I closed it and it would not close" is the Keep Working
        /// branch and nothing else explains it. Never written when Windows is
        /// logging off: nothing is asked then.
        /// </summary>
        QuitAskedAboutWorkUnderWay,
        /// <summary>
        /// A deploy, or setting one, read the SAVED settings while some window
        /// held unsaved Course Settings edits (#357 / mac #335). Carries the
        /// act, the destination KINDS used and whether the unsaved edits named
        /// a different kind — never a path or a site name.
        /// </summary>
        DeployUsedTheSavedSettings,
        /// <summary>A preview started while Course Settings held unsaved edits in any window (#272 / mac #265).</summary>
        PreviewStartedWithUnsavedSettings,
        /// <summary>
        /// Course Settings' Preview Again rebuilt the open previews of the
        /// course (#272): which sections, or that none was still open.
        /// </summary>
        PreviewAgainAfterSettingsSaved,
        /// <summary>
        /// A remembered timetable named a date that cannot be a class date —
        /// the file was written by this app before #144, on a PC whose
        /// regional format uses another calendar — and was set aside, so the
        /// assistant asks for the timetable again and rewrites it. Windows
        /// only (`appliesOn: ["windows"]`): only this app ever wrote such a
        /// file.
        /// </summary>
        RememberedTimetableSetAside,
        SectionAdded,
        PageSettingsLeftAsTheyWere,
        /// <summary>
        /// Making room for a class could not finish every page (#422): a
        /// rename whose new name was taken, a save that failed. Carries the
        /// course, section and counts by kind — never a page's name.
        /// </summary>
        MakingRoomDidNotFinishEveryPage,
        ClassCopyNotMade,
        WordForAUnitRenamed,
        /// <summary>
        /// A preview never appeared (#233 / mac #225, #278 / mac #235): its
        /// server started and it then said nothing for the contract's 45 s,
        /// or no address was ever announced — or, from preview.ps1, every
        /// address was taken (#286). Carries the course, the section, how long
        /// it was quiet and which of the things was true.
        /// </summary>
        PreviewDidNotAppear,
        /// <summary>
        /// deploy.py made a section's Cloudflare Pages project again because it
        /// was gone from the account (#395). Carries the project and the
        /// address the site answers at now — the address can change.
        /// </summary>
        CloudflareProjectMadeAgain,
        /// <summary>
        /// Keep a Copy for Reference… made a reference course (#241): the
        /// folder it was given, the code and year it shows, how many sections,
        /// which course it came from, and — only when there were any — the
        /// Obsidian add-ons left behind, by folder name.
        /// </summary>
        CourseKeptForReference,
        /// <summary>
        /// Keep a Copy was pressed and no copy was made (#241 / mac #287):
        /// written ONCE, from the catch around the whole act, with the
        /// sentence the teacher was shown.
        /// </summary>
        CourseCouldNotBeKeptForReference,
        /// <summary>Set School Year… re-filed a reference course: the code, the folder, the year before and after.</summary>
        ReferenceCourseSchoolYearChanged,
        /// <summary>
        /// A pass found a reference course's pages unlocked and locked them
        /// again, or some would not stay locked — written only when a pass
        /// actually did something. The answer to "my reference course let me
        /// edit a page".
        /// </summary>
        ReferenceCoursePagesLockedAgain,
        /// <summary>Import Courses for Reference… brought a course in (#244): the folder it was read from, the folder it was given, code, year, sections.</summary>
        CourseImportedForReference,
        /// <summary>A course the import summary lists as not imported, with the sentence it showed — written before every early way out.</summary>
        CourseCouldNotBeImportedForReference,
        /// <summary>A staging folder an unfinished import left was removed when the working folder was read.</summary>
        UnfinishedImportForReferenceTidiedAway,
        /// <summary>The teacher pressed Stop: the course in hand was not kept, and was removed.</summary>
        CourseImportForReferenceStopped,
        /// Copy a Page from This Course… finished (#247 / mac #207): ONE line at
        /// the end of a copy, in every outcome — the course the pages came from
        /// by folder name, the course and folder they landed in, the counts, and
        /// the backup's file name. Never a page's title or a picture's name: on
        /// disk a copied page looks exactly like one the teacher typed, and this
        /// is the only answer to "where did this come from?".
        /// </summary>
        PagesCopiedFromAnotherCourse,
        /// <summary>
        /// Several backups (or one) were deleted from All Backups (#283 / mac
        /// #242): the course codes, how many, what they took together when every
        /// size is known, each deleted file's NAME, and any kept because an open
        /// assistant conversation can restore from it or that could not be
        /// deleted. A teacher's backups are never pruned, so a backup that has
        /// gone was deleted by somebody — and this line is the only answer to
        /// "my backups vanished".
        /// </summary>
        BackupsDeleted,
        /// <summary>
        /// The scheduled-publish toast (#324 / mac #212, #306): posted or could
        /// not be sent, and what a CLICK on it did — the section shown, in which
        /// window, or only Plantoir brought forward and why. Never the toast's
        /// text, never the working folder's path.
        /// </summary>
        ScheduledPublishNotification,
        /// <summary>
        /// The first launch whose version differs from the last launch's (#337 /
        /// mac #204): from which version to which, and how — by its own updater
        /// or by hand. "It broke after the update" needs to know WHEN.
        /// </summary>
        AppUpdated,
        /// <summary>#337: a new version found (once per version per launch): found, running, who asked, important.</summary>
        UpdateFound,
        /// <summary>#337: Check for Updates… found nothing new (only when the teacher asked).</summary>
        UpdateCheckFoundNothingNew,
        /// <summary>#337: the teacher's answer to the offer: install, skip this version, not now.</summary>
        UpdateAnswered,
        /// <summary>#337: the install waited, naming the work in the teacher's words, and the version waiting.</summary>
        UpdateHeldWhileWorkIsUnderWay,
        /// <summary>#337: from which version to which, and when — the last line the old version writes.</summary>
        UpdateInstalling,
        /// <summary>#337: a quit with work under way set the prepared update aside.</summary>
        UpdateSetAside,
        /// <summary>#337: the update stopped, in a plain category with the detail in brackets; the daily check's at most once per launch.</summary>
        UpdateStopped,
    }

    public static string KeyFor(Event @event) => @event switch
    {
        Event.AppOpened => "app opened",
        Event.Machine => "machine described",
        Event.Helpers => "helpers described",
        Event.WorkingFolderOpened => "working folder opened",
        Event.SettingsSaved => "settings saved",
        Event.SettingsSaveHeldBack => "settings save held back",
        Event.PutTodaysClassOnTheFrontPage => "put today's class on the front page",
        Event.LeftTheFrontPageAsItWas => "left the front page as it was",
        Event.SettingsCouldNotBeSaved => "settings could not be saved",
        Event.TaskStarted => "task started",
        Event.TaskFinished => "task finished",
        Event.AskedForACredential => "asked for a publishing credential",
        Event.AssistantOpened => "assistant opened",
        Event.AssistantReady => "assistant ready",
        Event.AssistantWouldNotStart => "assistant would not start",
        Event.AssistantAsked => "assistant asked",
        Event.AssistantMatchedAFixedPhrase => "assistant matched a fixed phrase",
        Event.AssistantChoseATool => "assistant chose a tool",
        Event.AssistantCouldNotAnswer => "assistant could not answer",
        Event.AssistantNamedAToolItWasNotOffered => "assistant named a tool it was not offered",
        Event.AssistantNamedNoPage => "assistant named no page it could find",
        Event.OfferedToPublishPagesThatLinksLeadTo => "offered to publish pages that links lead to",
        Event.PublishedPagesThatLinksLedTo => "published pages that links led to",
        Event.LeftPagesHiddenThatLinksLeadTo => "left pages hidden that links lead to",
        Event.AssistantWasAskedAboutAnotherCourse => "assistant was asked about another course",
        Event.AssistantAnswerWasCutOff => "assistant answer was cut off",
        Event.AssistantRepeatedTheRequestBack => "assistant repeated the request back",
        Event.AppSettingsOpened => "app settings opened",
        Event.AssistantModelChosen => "assistant model chosen",
        Event.AssistantModelDownloadStarted => "assistant model download started",
        Event.AssistantModelDownloaded => "assistant model downloaded",
        Event.AssistantModelDownloadFailed => "assistant model download failed",
        Event.AssistantModelRemoved => "assistant model removed",
        Event.AssistantModelDownloadStopped => "assistant model download stopped",
        Event.AssistantConfirmationChanged => "assistant confirmation changed",
        Event.SectionContentMarkedPublished => "section content marked published",
        Event.SectionProcessesReclaimed => "section processes reclaimed",
        Event.FolderRenamed => "folder renamed",
        Event.FolderCreated => "folder created",
        Event.CourseCreated => "course created",
        Event.HowITeachPageStarted => "How I Teach page started",
        Event.AssistantBackedUpACourse => "assistant backed up a course",
        Event.CurriculumMapsBuilt => "curriculum maps built",
        Event.SectionMadeReadyForTheStartOfTheYear => "section made ready for the start of the year",
        Event.StartOfYearChangeUndone => "start of the year change undone",
        Event.StartOfYearNotDone => "start of the year not done",
        Event.WorkingFolderReopened => "working folder reopened",
        Event.WorkingFolderNotReopened => "working folder not reopened",
        Event.ExclusionsReverted => "exclusions reverted",
        Event.SyncedFolderNoticed => "synced folder noticed",
        Event.SyncedFolderAccepted => "synced folder accepted",
        Event.FolderProblemFound => "folder problem found",
        Event.FolderProblemRepaired => "folder problem repaired",
        Event.FolderProblemNotRepaired => "folder problem not repaired",
        Event.PagesDatedByTheBuild => "pages dated by the build",
        Event.HowITeachPageRead => "How I Teach page read",
        Event.HowITeachPageWritten => "How I Teach page written",
        Event.HowITeachPageKeptOff => "How I Teach page kept off the website",
        Event.SectionRestored => "section restored",
        Event.AssistantEngineSaid => "assistant engine said",
        Event.ItemExcluded => "item excluded",
        Event.ItemReIncluded => "item re-included",
        Event.RemovalBlocked => "removal blocked",
        Event.SectionStartedANewWebsite => "section started a new website",
        Event.SectionKeptItsWebsite => "section kept its website",
        Event.ScheduledPublishNeededAnAnswer => "scheduled publish needed an answer",
        Event.ScheduledPublishDidNotFinish => "scheduled publish did not finish",
        Event.ScheduledPublishFinished => "scheduled publish finished",
        Event.BuildDeclinedCourseBusyElsewhere => "build declined, course busy elsewhere",
        Event.ScheduledPublishWaitedForTheCourse => "scheduled publish waited for the course",
        Event.ScheduledDeployTurnedOff => "scheduled deploy turned off",
        Event.ScheduledDeployReplaced => "scheduled deploy replaced",
        Event.ScheduledDeployCouldNotBeSet => "scheduled deploy could not be set",
        Event.ScheduledPublishReadTheCoursesSettings => "scheduled publish read the course's settings",
        Event.QuitAskedAboutWorkUnderWay => "quit asked about work under way",
        Event.DeployUsedTheSavedSettings => "deploy used the saved settings",
        Event.PreviewStartedWithUnsavedSettings => "preview started with unsaved settings",
        Event.PreviewAgainAfterSettingsSaved => "preview again after settings saved",
        Event.RememberedTimetableSetAside => "remembered timetable set aside",
        Event.SectionAdded => "section added",
        Event.PageSettingsLeftAsTheyWere => "page settings left as they were",
        Event.MakingRoomDidNotFinishEveryPage => "making room did not finish every page",
        Event.ClassCopyNotMade => "class copy not made",
        Event.WordForAUnitRenamed => "word for a unit renamed",
        Event.PreviewDidNotAppear => "preview did not appear",
        Event.CloudflareProjectMadeAgain => "cloudflare project made again",
        Event.CourseKeptForReference => "course kept for reference",
        Event.CourseCouldNotBeKeptForReference => "course could not be kept for reference",
        Event.ReferenceCourseSchoolYearChanged => "reference course school year changed",
        Event.ReferenceCoursePagesLockedAgain => "reference course pages locked again",
        Event.CourseImportedForReference => "course imported for reference",
        Event.CourseCouldNotBeImportedForReference => "course could not be imported for reference",
        Event.UnfinishedImportForReferenceTidiedAway => "unfinished import for reference tidied away",
        Event.CourseImportForReferenceStopped => "course import for reference stopped",
        Event.PagesCopiedFromAnotherCourse => "pages copied from another course",
        Event.BackupsDeleted => "backups deleted",
        Event.ScheduledPublishNotification => "scheduled publish notification",
        Event.AppUpdated => "app updated",
        Event.UpdateFound => "update found",
        Event.UpdateCheckFoundNothingNew => "update check found nothing new",
        Event.UpdateAnswered => "update answered",
        Event.UpdateHeldWhileWorkIsUnderWay => "update held while work is under way",
        Event.UpdateInstalling => "update installing",
        Event.UpdateSetAside => "update set aside",
        Event.UpdateStopped => "update stopped",
        _ => throw new ArgumentOutOfRangeException(nameof(@event)),
    };

    public static string DefaultLogDirectory =>
        Plantoir.Core.Models.AppDataRoot.Combine("Logs");

    public static string DefaultLogPath => Path.Combine(DefaultLogDirectory, "activity.txt");

    private static string? _customLogPath;
    private static readonly object _lock = new();

    public static void SetCustomLogPathForTesting(string? path)
    {
        lock (_lock)
        {
            _customLogPath = path;
        }
    }

    public static string CurrentLogPath => _customLogPath ?? DefaultLogPath;

    public const string PromptPrefix = "  asked: ";

    public static void Note(Event @event, string what, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safeWhat = LogRedactor.Redacting(what);
        string entry = $"{DateText.Stamp(when)} · {safeWhat}";
        Append(entry);
    }

    public static void Note(Event @event, string what, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safeWhat = LogRedactor.Redacting(what);
        string entry = $"{DateText.Stamp(when)} · {course}/{section} · {safeWhat}";
        Append(entry);
    }

    public static void NotePrompt(string prompt, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        string safePrompt = LogRedactor.Redacting(prompt.Trim());
        string entry = $"{DateText.Stamp(when)} · {course}/{section} · asked a question\n{PromptPrefix}{safePrompt}";
        Append(entry);
    }

    /// <summary>The words for `page settings left as they were`, the mac's <c>pageSettingsLeftAsTheyWereLine</c> word for word.</summary>
    public static string PageSettingsLeftAsTheyWereLine(string act, int pages) =>
        $"left the settings of {(pages == 1 ? "1 page" : $"{pages} pages")} as they were while {act}: no room at the top for a new setting";

    public static void NoteLaunch()
    {
        Note(Event.AppOpened, "Plantoir opened — " + ProblemReportEnvironment.AppDescription);
        Note(Event.Machine, "running on " + ProblemReportEnvironment.SystemDescription);
        Note(Event.Helpers, "using " + ProblemReportEnvironment.HelperDescription);
    }

    public static void NoteLaunch(string appVersion, string buildNumber, int processId, string executablePath)
    {
        string safePath = LogRedactor.Redacting(executablePath);
        Note(Event.AppOpened, $"Plantoir {appVersion} ({buildNumber}) opened (PID {processId}, {safePath})");
        Note(Event.Machine, "running on " + ProblemReportEnvironment.SystemDescription);
        Note(Event.Helpers, "using " + ProblemReportEnvironment.HelperDescription);
    }

    /// <summary>
    /// The one lock every WRITER of the trail takes, across processes: the
    /// app, <c>plantoir-mcp.exe</c> and a scheduled run are separate
    /// processes writing one file, and <c>lock</c> covers threads of one.
    /// </summary>
    /// <remarks>
    /// <para><b>Measured, #303 (this Windows PC: Intel Core i5-8365U, 4 cores /
    /// 8 threads, 15.7 GB, NTFS, Windows 11 Pro 25H2 build 26200,
    /// 2026-09-30).</b> Two processes calling <see cref="Note(Event, string, DateTime?)"/>
    /// 500 times each, started on the same tick, five rounds: the old
    /// <c>File.AppendAllText</c> (which opens with <c>FileShare.Read</c>, so the
    /// second writer's open throws a sharing violation into an empty
    /// <c>catch</c>) kept <b>4,444 of 5,000</b>; three processes × three lines ×
    /// 100 bursts, the mac's shape, kept <b>682 of 900</b>. With this mutex:
    /// every line, both shapes (numbers in documentation/09 → "Two writers at
    /// once").</para>
    /// <para><b>REJECTED, measured:</b> <c>FileShare.ReadWrite</c> with one
    /// <c>Write</c> per line and no lock. The issue's first candidate, on the
    /// reasoning that an append-mode write lands at end-of-file — but .NET's
    /// <c>FileMode.Append</c> opens for ordinary write and keeps its OWN
    /// position, so two writers open at the same end and the second
    /// overwrites the first: 4,512 of 5,000, and 180 of 270. A retry loop on
    /// the sharing violation was rejected unmeasured, as the issue says: a
    /// guessed delay that still drops the line after its last retry.</para>
    /// <para><c>Local\</c>, not <c>Global\</c>: the trail is per user
    /// (<c>%LOCALAPPDATA%</c>), and every writer runs in the teacher's own
    /// session. Tests redirect the PATH, not the lock — one lock for every
    /// trail file on the machine costs nothing at one line at a time.</para>
    /// </remarks>
    private const string WritersMutexName = @"Local\PlantoirActivityTrail";

    private static void Append(string line)
    {
        lock (_lock)
        {
            try
            {
                string path = CurrentLogPath;
                string? dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                byte[] bytes = System.Text.Encoding.UTF8.GetBytes(line + Environment.NewLine);

                using var writers = new System.Threading.Mutex(false, WritersMutexName);
                bool held = false;
                try
                {
                    try { held = writers.WaitOne(TimeSpan.FromSeconds(5)); }
                    catch (System.Threading.AbandonedMutexException) { held = true; }   // a writer died holding it: ours now

                    // Written even when the wait timed out: a line that might
                    // interleave is better than a line certainly lost. Five
                    // seconds is far beyond one line's append (sub-millisecond).
                    using var stream = new FileStream(path, FileMode.Append, FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete);
                    stream.Write(bytes, 0, bytes.Length);
                }
                finally
                {
                    if (held) writers.ReleaseMutex();
                }
            }
            catch
            {
                // Never fail caller if log write fails
            }
        }
    }
}
