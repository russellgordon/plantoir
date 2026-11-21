using System;
using System.IO;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

public static class ActivityTrail
{
    public enum Event
    {
        AppOpened,

        /// <summary>
        /// Plantoir closed (#565, mac #560): why — quit by the teacher, to
        /// install a new version, or asked to close by Windows — and the pid
        /// of its own "app opened" line. Written once, and only by a process
        /// that wrote that line (<see cref="NoteClosed"/>).
        /// </summary>
        AppClosed,
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
        /// <summary>
        /// A Claude or Codex session's server took its assist lease on the
        /// course its door was opened from (#468, mac #458). Written by
        /// <c>plantoir-mcp</c> for a DOOR only, never for this app's own
        /// window's server; the course and nothing else. There is no matching
        /// "let go" line: every ordinary way of ending a session kills the
        /// server (measured on the mac), so its absence would be read as a
        /// session still open.
        /// </summary>
        OutsideSessionHeldACourse,
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
        /// <summary>
        /// One teacher action asked the model
        /// <c>assistantLapLimit.mostModelRequestsPerTurn</c> times without
        /// finishing (#720, the mac's #689): the turn was stopped, nothing more
        /// ran, and it was taken back out of the conversation. Carries course,
        /// section, the count and the tool it last chose in words — never the
        /// sentence and never argument values. Not "answer was cut off": every
        /// answer in the turn finished, and none was the last.
        /// </summary>
        AssistantWentRoundWithoutFinishing,
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
        /// request — or, since #584, a section front page's title the BUILD
        /// put quotes around without being asked (<c>PLANTOIR_REPAIRED:</c>,
        /// <see cref="Plantoir.Core.Models.BuildRepairReport"/>). Separate from
        /// FolderProblemFound: one says something is wrong, the other says
        /// somebody acted on it.
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

        /// <summary>
        /// Undo's recovery settled a step whose work stopped part way (#899
        /// W3, <c>undo.rule.recovery</c>): it put back what had taken effect,
        /// or found a file changed by hand since and cleared the list. Counts
        /// only, never page text. Written only while the list is live (in
        /// shadow recovery never writes into a working folder).
        /// </summary>
        UndoRolledBack,
        /// <summary>
        /// Undo's recovery found a teacher's folder a stopped step had set
        /// aside (#899 W6, U2b's kinds): being put back in its place though it
        /// changed while aside, with what changed, or kept under a visible
        /// name beside its place because something else holds that place,
        /// both named. Written just before the rename. Never page text.
        /// </summary>
        UndoFoundAFolderSetAside,
        /// <summary>
        /// Undo's recovery closed a step that stopped part way and could not
        /// be put back (what it needs is no longer in the list, and no kept
        /// original matches), and cleared the list: naming each kept original
        /// left beside its page, read after the tidy (#899 W4c, the mac's U3c).
        /// </summary>
        UndoCouldNotPutBack,
        /// <summary>
        /// Undo's recovery settled a step and left a kept original beside a
        /// page because it is the only copy of what it holds, each with its
        /// page, its hidden name and why (#899 W4c). Never page text.
        /// </summary>
        UndoKeptWhatAPageHeld,
        /// <summary>
        /// An Undo or Redo put a page back from what was kept beside it, and
        /// the list would not take all the step needs, so what it could not
        /// keep stays beside the page, named (#899 W4c). Never page text.
        /// </summary>
        UndoKeptWhatItReplaced,
        /// <summary>
        /// An Undo or Redo refused because the newest step is one recovery
        /// has just tried and left part way (a file in use, a page it cannot
        /// read now), naming the file; the list kept (#899 W4c, W3's LOW 4).
        /// </summary>
        UndoRefusedForAChangeLeftPartWay,
        /// <summary>
        /// The list could not take a daily action's step, or a file it writes
        /// cannot be named in one: the action's key, the course and section, a
        /// word for why, and what became of the change (#899 W7a). Never page text.
        /// </summary>
        UndoCouldNotRecordAStep,
        /// <summary>
        /// A whole course was put back, from one of its backups (Restore…) or
        /// from Archived: the code it shows, its folder, the zip's FILE NAME,
        /// what became of the course as it was first (the archive made of it,
        /// or that there was none; a restore from Archived uses its archive
        /// up), and whether the course that came back is kept for reference.
        /// Written once the restore has happened; a refused one writes
        /// nothing. Never a page. Windows had the restores and wrote no line
        /// for either until step 0 of v2.0.0 (the mac's #572 closed the same
        /// gap): <c>CourseRestorer.RestoredTrailLine</c>.
        /// </summary>
        CourseRestoredFromABackup,
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
        /// An outside assistant (Claude or Codex, through plantoir-mcp) made a
        /// change, asked for a rebuild, or deployed while a preview of the
        /// course was only being SERVED (#436, mac #433). The change and the
        /// rebuild left the open preview exactly as it was; the deploy went
        /// ahead and may have closed that section's preview. Carries the
        /// course, the section and which of the three — never a page.
        /// </summary>
        OutsideAssistantWorkedWhileAPreviewWasOpen,
        /// <summary>
        /// The window read a serving preview's end as closed by another
        /// program's deploy — an outside assistant's deploy_section or a
        /// deploy set for later — rather than as a failure (#436, mac #433's
        /// stack review): it had been serving, its output shows the server
        /// ended the way build_site.stop_preview_serving ends it, and another
        /// program held a build lease on the course. Course and section only.
        /// </summary>
        PreviewClosedForADeploy,
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
        /// <summary>
        /// #473: the app copied its tools into a working folder in the
        /// background (or could not finish): the folder (redacted), files
        /// brought up to date, files that failed, seconds, and the outcome in
        /// the sentence; since #559 also how many files were compared and how
        /// many read in full. Written when something changed or failed, or
        /// any file was read in full to compare it (#559). Both platforms
        /// since the mac's #476; the counts are Windows-only until #663.
        /// </summary>
        WorkingFolderToolsCopied,
        /// <summary>
        /// File ▸ Open Recent ▸ Clear Menu emptied the list of working folders
        /// opened (#488, the mac's #457): how many it held. The list is only
        /// ever added to otherwise, so "Open Recent is empty and I never cleared
        /// it" has no answer without this line.
        /// </summary>
        RecentWorkingFoldersCleared,
        /// <summary>
        /// One of the assistant's functions run from the menu bar (#489, the
        /// mac's #457 batch B): where the item is (Section ▸ Publish Pages…),
        /// how it ended — carried out, changed nothing, took the last change
        /// back, took part of the last change back (an undo that kept its
        /// entry, #550), cancelled at the plan, rebuilt, not rebuilt — and
        /// counts, never a page's title. "Carried out" covers a change that
        /// wrote and then stopped part way, too (#550, the mac's #531). The
        /// assistant's own lines are written by its
        /// conversation, which the menu does not have; without this a page
        /// published from the menu is a page nobody can say who published.
        /// </summary>
        RanFromAMenu,
        /// <summary>
        /// The copy the Section menu saves before EVERY change it makes (#489):
        /// the backup's FILE NAME (<c>_menu-section&lt;N&gt;</c>), its size and
        /// seconds; or that it could not, and why. Answers "where did this zip
        /// come from" and "why did Publish take ten seconds".
        /// </summary>
        SectionMenuBackedUpACourse,
        /// <summary>
        /// The question about classes dated after the next class (#475):
        /// where it was asked (Deploy, the in-app assistant's deploy, Section ▸
        /// Publish Pages…), how many were flagged, and the answer — how many
        /// hidden, how many kept published, or cancelled. Counts, never a
        /// title. Answers "why did my class disappear from the site?" and "why
        /// does it keep asking me?".
        /// </summary>
        LaterClassesAsked,
        /// <summary>
        /// A scheduled deploy went out with classes dated after the next class
        /// (#475): nobody is awake to ask, so it goes as it is, and this
        /// records the PLACES (at most ten, then how many more). Written only
        /// once the wrapper's success record says it deployed.
        /// </summary>
        LaterClassesWentOut,
        /// <summary>
        /// An assistant's deploy was refused while classes dated after the next
        /// class wait on an answer in the section's window (#475): how many.
        /// Without it, "why didn't Claude deploy it?" has no answer on the trail.
        /// </summary>
        LaterClassesHeldADeployBack,
        /// <summary>
        /// File ▸ Settings ▸ Deploying changed the Cloudflare Account ID (#491,
        /// the mac's #457 item 4): cleared, changed, or changed to something not
        /// yet a valid ID — NEVER the ID. Written when the teacher leaves the
        /// field, switches section, closes Settings or quits, so typing writes
        /// one line rather than one per key. A deploy to Cloudflare that suddenly
        /// fails for every course is answered by this line.
        /// </summary>
        CloudflareAccountIdChangedInSettings,
        /// <summary>
        /// The Deploy button (or the in-app assistant pressing it) was refused
        /// because the Cloudflare Account ID is missing or not a whole ID (#739,
        /// the mac's #668): by KIND, never the ID
        /// (<see cref="Plantoir.Core.Models.PublishingDestinations.AccountIdRefusalTrailLine"/>).
        /// Since a new course starts on Cloudflare Pages, this is the refusal
        /// every new teacher meets at their first deploy. A windowless MCP
        /// deploy refuses with the same sentence and writes no line.
        /// </summary>
        DeployRefusedForTheCloudflareAccountId,
        /// <summary>
        /// Help ▸ Plantoir Help (or F1) opened the support page in the browser
        /// (#491). A teacher who looked for help just before something went
        /// wrong is a teacher whose report should say so.
        /// </summary>
        PlantoirHelpOpened,

        // ---- Printable pages (#496; the mac's #454), one block ----
        /// <summary>
        /// The preview handed a page to the teacher's web browser (#496): the
        /// course and section, the page the teacher was ON, and why — to print
        /// it (the way of printing and, when landscape, the paper) or a link
        /// that opens in a new window, by its KIND only (the page's own PDF,
        /// another page of the site, another site). Never where a link led.
        /// </summary>
        PreviewPageOpenedInBrowser,
        /// <summary>
        /// Plantoir asked before adding its section to a teacher's own
        /// AGENTS.md or CLAUDE.md at the working folder's root (#496): the
        /// file's NAME and the answer, added or not now.
        /// </summary>
        GuidanceFileAskedAbout,
        /// <summary>
        /// The guidance for assistants could not be written into a working
        /// folder (#496): how many problems, and the first (a file or a
        /// skill's folder, and the system's reason). It holds nothing back,
        /// so this line and a quiet notice are its only record.
        /// </summary>
        GuidanceCouldNotBeWritten,

        // ---- Preview at Last Viewed (#514; the mac's #504), one block ----
        /// <summary>
        /// A teacher's press of Preview asked for the page last viewed, or
        /// the page is opened, or the front page opened instead and why —
        /// gone, did not answer, nothing remembered, the front page was the
        /// page last viewed, today's class was just put on it. The page's
        /// PLACE (its decoded path), never its words. Falling back is silent
        /// on screen, so this line is its only record.
        /// </summary>
        PreviewStartedAtThePageLastViewed,
        /// <summary>
        /// File ▸ Settings ▸ Preview changed where a press of Preview opens
        /// (#514): the front page or the page last viewed. One line per
        /// change, so "Preview opened somewhere odd" can be answered.
        /// </summary>
        PreviewStartPageChosenInSettings,

        /// <summary>
        /// What a build did about the section's My Progress page (#599, mac
        /// #545): made it and how many pages count, or made none and why. Read
        /// from the build's <c>PLANTOIR_MY_PROGRESS:</c> line by the console
        /// reader and by the scheduled publish's log reader. Never a page's words.
        /// </summary>
        MyProgressPageBuilt,

        // ---- Obsidian's add-ons for diagrams and graphs (#581; the mac's #495) ----
        /// <summary>
        /// Open in Obsidian asked the one question about the add-ons, and the
        /// answer (Add Them, Not Now, Not Now and don't ask again) — or did NOT
        /// ask because Obsidian opens the course inside a larger vault, said
        /// once per course per run. A teacher who asks "why does Obsidian show
        /// my graph as code?" is answered by it.
        /// </summary>
        ObsidianAddOnsOffered,
        /// <summary>
        /// A pass over a course: which add-ons were added, by name and version,
        /// at Open in Obsidian, after a preview or after reopening — or why
        /// nothing was (a refusal, the teacher's own copy, a failed write),
        /// said once per course per run. Never a page's words.
        /// </summary>
        ObsidianAddOnsAdded,
        /// <summary>
        /// The reopen question was answered: Obsidian was reopened, Later was
        /// chosen, or Obsidian did not close and so nothing was written.
        /// </summary>
        ObsidianReopenedForAddOns,
        /// <summary>File ▸ Settings ▸ Obsidian turned the add-ons on or off — the only way back from "Don't ask again".</summary>
        ObsidianAddOnsSettingChanged,
        /// <summary>
        /// "Stop the deploy?" or "Stop this share?" was turned off by its
        /// "Don't ask again" box with the stop, or on or off in File ▸
        /// Settings ▸ Deploying ▸ Stopping (#1009, the mac's #988). While one
        /// is off Escape stops that task at once, so "Escape stopped my deploy
        /// without asking" is answered here. Words: <c>stopQuestions.trail</c>.
        /// </summary>
        StopQuestionSettingChanged,
        /// <summary>
        /// "Close Obsidian to open {course}?" was answered (#1003, the mac's
        /// #995): the course and what came of it - opened after closing
        /// Obsidian, Cancel, nothing to close by then, Obsidian did not close,
        /// or it closed and the course could not be added to its list.
        /// </summary>
        ObsidianClosingAsked,

        // ---- Open in Obsidian opens the page the preview shows (#681; the mac's #518) ----
        /// <summary>
        /// A SECTION's Open in Obsidian went ahead: the place of the file it
        /// opened for the page the preview showed (with "(hidden from
        /// students)" when that file is hidden), or why it opened the section
        /// as before. Written once per press by
        /// <see cref="Plantoir.Core.Models.PreviewedPageSource.NoteThePress"/>;
        /// never for a course press, never for a press turned away while the
        /// add-ons scan runs. Never anything written on the page.
        /// </summary>
        PageOpenedInObsidian,

        // ---- Runnable Swift on Windows (#570; the mac's #493) ----
        /// <summary>
        /// The first preview with a Swift block got Swift ready on this PC:
        /// how many seconds it took and how much was downloaded, read from
        /// <c>swift_windows_fetch.py</c>'s <c>PLANTOIR_SWIFT:</c> line by
        /// <see cref="Plantoir.Core.Models.SwiftGotReady"/>. Dates when the PC
        /// gained about 0.9 GB.
        /// </summary>
        SwiftGotReady,
        /// <summary>
        /// Getting Swift ready failed, and why (offline, noRoom, damaged, busy,
        /// unpack, waited): every Swift block then says it is not ready, and this line
        /// says whether it was the network, the disk or the download.
        /// </summary>
        SwiftCouldNotBeGotReady,
        /// <summary>
        /// A section's set of problems CHANGED (#734, the mac's #717): written
        /// once per alert key, by <see cref="Plantoir.Core.Models.SectionProblems"/>
        /// when the app first reads the record — counts and the kinds' names,
        /// never a page — and, as a second line of the same event, the answer
        /// the teacher gave the alert (Show, the repair, or Not Now).
        /// </summary>
        ProblemsChanged,
        /// <summary>
        /// Fix with Claude… or Fix with Codex… on a section's Problems tab
        /// opened its door (#736, the mac's #717 part two): which assistant,
        /// how many problems went and their KINDS, how many the message
        /// names and how many were left out — never a page or a row's words
        /// (<see cref="Plantoir.Core.Assist.FixWithAssistant.TrailLine"/>).
        /// Written after the door's own "assistant opened" line; a door that
        /// did not open writes nothing here.
        /// </summary>
        AskedAnAssistantToFixProblems,
        /// <summary>
        /// A deploy BUILT the section's site first (#799, the mac's #768 and
        /// #748 part 2): the course and section and WHY, one of
        /// <c>buildFreshness.reuseTheLastBuild.reasons</c>, never a page, a
        /// path or a command (<see cref="BuiltBeforeDeployingWords"/>). Written
        /// once per build, by whichever code ran it: the app after its own
        /// build first (<see cref="MultiDestinationDeployRunner"/>, and the
        /// windowless deploy in <c>AssistWorkspace</c>), the scheduled wrapper
        /// after its build, and <c>deploy.ps1</c> after its own. It answers
        /// "why was this morning's deploy slow?" days later.
        /// </summary>
        SiteBuiltAgainBeforeDeploying,
        /// <summary>
        /// A one-section restore moved a file and then could not move every
        /// file back, so the section may hold some files from the backup and
        /// some as they were (#911, the mac's #897 C): the course, the section
        /// and where the set-aside files are kept, as a path inside the
        /// working folder. Never a page. <see cref="SectionRestoreStoppedPartWayLine"/>.
        /// </summary>
        SectionRestoreStoppedPartWay,
    }

    public static string KeyFor(Event @event) => @event switch
    {
        Event.AppOpened => "app opened",
        Event.AppClosed => "app closed",
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
        Event.OutsideSessionHeldACourse => "outside session held a course",
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
        Event.AssistantWentRoundWithoutFinishing => "assistant went round without finishing",
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
        Event.UndoRolledBack => "undo rolled back",
        Event.UndoFoundAFolderSetAside => "undo found a folder set aside",
        Event.UndoCouldNotPutBack => "undo could not put back a change that stopped",
        Event.UndoKeptWhatAPageHeld => "undo kept what a page held",
        Event.UndoKeptWhatItReplaced => "undo kept what it replaced",
        Event.UndoRefusedForAChangeLeftPartWay => "undo refused for a change left part way",
        Event.UndoCouldNotRecordAStep => "undo could not record a step",
        Event.CourseRestoredFromABackup => "course restored from a backup",
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
        Event.OutsideAssistantWorkedWhileAPreviewWasOpen => "outside assistant worked while a preview was open",
        Event.PreviewClosedForADeploy => "preview closed for a deploy",
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
        Event.WorkingFolderToolsCopied => "working folder tools copied",
        Event.RecentWorkingFoldersCleared => "recent working folders cleared",
        Event.RanFromAMenu => "ran from a menu",
        Event.SectionMenuBackedUpACourse => "section menu backed up a course",
        Event.LaterClassesAsked => "asked about classes dated after the next class",
        Event.LaterClassesWentOut => "deployed with classes dated after the next class",
        Event.LaterClassesHeldADeployBack => "a deploy was held back for classes dated after the next class",
        Event.CloudflareAccountIdChangedInSettings => "Cloudflare account ID changed in Settings",
        Event.DeployRefusedForTheCloudflareAccountId => "deploy refused for the Cloudflare Account ID",
        Event.PlantoirHelpOpened => "opened Plantoir Help",
        Event.PreviewPageOpenedInBrowser => "preview page opened in the web browser",
        Event.GuidanceFileAskedAbout => "asked before adding guidance to a file",
        Event.GuidanceCouldNotBeWritten => "guidance for assistants could not be written",
        Event.PreviewStartedAtThePageLastViewed => "preview started at the page last viewed",
        Event.PreviewStartPageChosenInSettings => "preview start page chosen in Settings",
        Event.MyProgressPageBuilt => "my progress page built",
        Event.ObsidianAddOnsOffered => "obsidian add-ons offered",
        Event.ObsidianAddOnsAdded => "obsidian add-ons added",
        Event.ObsidianReopenedForAddOns => "obsidian reopened for add-ons",
        Event.ObsidianAddOnsSettingChanged => "obsidian add-ons setting changed",
        Event.StopQuestionSettingChanged => "stop question setting changed",
        Event.ObsidianClosingAsked => "asked to close Obsidian to open a course",
        Event.PageOpenedInObsidian => "page opened in Obsidian",
        Event.SwiftGotReady => "Swift got ready on this computer",
        Event.SwiftCouldNotBeGotReady => "Swift could not be got ready",
        Event.ProblemsChanged => "problems changed",
        Event.AskedAnAssistantToFixProblems => "asked an assistant to fix problems",
        Event.SiteBuiltAgainBeforeDeploying => "site built again before deploying",
        Event.SectionRestoreStoppedPartWay => "section restore stopped part way",
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

    /// <summary>The folder <see cref="CurrentLogPath"/> is in: what every
    /// launcher is handed as PLANTOIR_TRAIL_DIR (#682,
    /// <see cref="LauncherEnvironment"/>). A launcher always writes
    /// <c>activity.txt</c> there, which is why a test that wants a launcher's
    /// lines in its scratch trail names that file.
    ///
    /// <para>A test that sets its trail at <c>%TEMP%\plantoir-trail-&lt;guid&gt;.txt</c>
    /// (BuildMachineLinesTests, ConPtyLongLineTests, MachineLineLengthContractTests
    /// and others) makes <c>%TEMP%</c> itself the log directory for its run.
    /// Harmless: those tests run no launcher that writes a trail line, and
    /// nothing reads <c>%TEMP%\activity.txt</c>. A test that DOES want a
    /// launcher's lines gives its trail a folder of its own, ending in
    /// <c>activity.txt</c>.</para></summary>
    public static string CurrentLogDirectory => Path.GetDirectoryName(CurrentLogPath)!;

    public const string PromptPrefix = "  asked: ";

    public static void Note(Event @event, string what, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        Append(SafeTrailLine($"{DateText.Stamp(when)} · {what}", keepingLineBreaks: false));
    }

    /// <summary>A line about one course: <see cref="Place"/> puts the course,
    /// and the section when one was named, in front of <paramref name="what"/>.</summary>
    public static void Note(Event @event, string what, string course, int section, DateTime? moment = null)
    {
        DateTime when = moment ?? DateTime.Now;
        Append(SafeTrailLine($"{DateText.Stamp(when)} · {Place(course, section)}{what}", keepingLineBreaks: false));
    }

    /// <summary>
    /// The assistant's question: a stamped line naming the course, then the
    /// teacher's sentence on ONE line behind <see cref="PromptPrefix"/>
    /// (<c>courseNameCharacters.trailLines.promptCases</c>, #821). The
    /// sentence is put on one line before it goes behind the prefix, so a
    /// sentence on two lines can no longer put its second line on the trail
    /// with no prefix, where a report sent with the prompts left out still
    /// carried it. The record's own line break between its two lines stays.
    /// </summary>
    public static void NotePrompt(string prompt, string course, int section, DateTime? moment = null)
    {
        Append(PromptRecord(prompt, course, section, moment ?? DateTime.Now));
    }

    /// <summary>
    /// The record <see cref="NotePrompt"/> writes, without writing it. Each of
    /// its two lines goes through <see cref="SafeTrailLine"/> on its RAW text
    /// (<c>trailLines.order</c>: redact, clean, redact again), never cleaned
    /// first: cleaning the sentence before redacting it turned a NUL inside a
    /// token into a space and wrote the token's tail (lane E review 1, M1).
    /// The joined record is then put through once more, keeping its one line
    /// break; redacting again changes nothing (<c>redactedAgainCases</c>).
    /// </summary>
    public static string PromptRecord(string prompt, string course, int section, DateTime moment)
    {
        string head = SafeTrailLine($"{DateText.Stamp(moment)} · {Place(course, section)}asked a question", keepingLineBreaks: false);
        string asked = PromptPrefix + SafeTrailLine(prompt, keepingLineBreaks: false).Trim();
        return SafeTrailLine(head + "\n" + asked, keepingLineBreaks: true);
    }

    /// <summary>
    /// What goes in front of a line about one course: <c>ICS3U/2 · </c> for a
    /// section, <c>ICS3U · </c> when no section was named, and nothing when
    /// there is no course either (<c>shared-rules.json</c> →
    /// <c>activityTrail.lineShape.placeCases</c>, #946, the mac's #879 and its
    /// <c>ActivityTrail.place</c>). A section is numbered from 1, so 0 or less
    /// is "none was named": a line that names no section used to be written
    /// <c>ICS3U/0</c>, a section that does not exist. Every trail line about
    /// a course gets its place here, from the window, the headless door and
    /// the built-in assistant alike; no caller builds its own.
    /// </summary>
    public static string Place(string course, int section)
    {
        string trimmedCourse = course.Trim();
        if (trimmedCourse.Length == 0) return "";
        if (section <= 0) return $"{trimmedCourse} · ";
        return $"{trimmedCourse}/{section} · ";
    }

    /// <summary>
    /// <paramref name="line"/> as the trail may hold it: one line (unless
    /// <paramref name="keepingLineBreaks"/>) and redacted
    /// (<c>courseNameCharacters.trailLines.order</c>, #821, the mac's
    /// <c>ProblemReportStore.safeTrailLine</c>). Every line this file writes
    /// goes through here and nowhere else.
    ///
    /// <para>A line with nothing to clean is redacted once, as it always was.
    /// A line that holds a control is redacted, cleaned, and redacted again.
    /// The first pass takes a secret with a control INSIDE it whole (the
    /// redactor's <c>\S+</c> reads a NUL, an ESC or a DEL as part of the
    /// value; cleaning first turned it into a space and the tail was written:
    /// <c>Bearer abc123</c> NUL <c>SECRETTAIL</c>). The second pass takes a
    /// secret a control was HIDING (a NUL after <c>Bearer</c>, an isolate
    /// inside <c>CLOUDFLARE_API_TOKEN</c>, an override before an email's
    /// <c>@</c>). Each order alone leaks one shape; both together leak
    /// neither, and redacting twice changes nothing
    /// (<c>problemReportRedaction.redactedAgainCases</c>).</para>
    ///
    /// <para><b>Not caught by any order</b> (<c>trailLines.knownLimits</c>,
    /// written down so nobody believes the trail catches them, and not
    /// tested as passing): a rule that matches a run of particular
    /// characters (an email, a Netlify token, an account ID, the
    /// 40-character run) cut short by a control in the middle of the value,
    /// and <c>labelledSecret</c> / <c>bearerHeader</c> when that control is
    /// white space to the redactor (tab, LF, CR, VT, FF, U+0085, U+2028,
    /// U+2029).</para>
    /// </summary>
    public static string SafeTrailLine(string line, bool keepingLineBreaks)
    {
        string cleanedLine = OneLineText.Cleaned(line, keepingLineBreaks);
        if (cleanedLine == line) return LogRedactor.Redacting(line);
        string redactedOnce = LogRedactor.Redacting(line);
        string cleanedAfterRedacting = OneLineText.Cleaned(redactedOnce, keepingLineBreaks);
        return LogRedactor.Redacting(cleanedAfterRedacting);
    }

    // ---- The headless path's task lines (#774) ------------------------------

    /// <summary>
    /// <c>task started</c>'s words, as the window's <c>ScriptRunner</c> writes
    /// them: "started preview.ps1 COMP 1 --build-only". The arguments are
    /// written as they are and redacted with the whole line on the way in
    /// (<see cref="SafeTrailLine"/>), so <c>--account</c> and any token never
    /// reach the file. Shared with <c>plantoir-mcp.exe</c>'s
    /// <c>LauncherRunner</c>, which has no <c>ScriptRunner</c> (ConPTY and a
    /// window's synchronisation context), so the headless door and the window
    /// say the same sentence.
    /// </summary>
    public static string TaskStartedWords(string launcherFile, IReadOnlyList<string> arguments) =>
        arguments.Count > 0 ? $"started {launcherFile} {string.Join(" ", arguments)}" : $"started {launcherFile}";

    /// <summary><c>task finished</c>'s words: "finished deploy.ps1 — succeeded after 12s".</summary>
    public static string TaskFinishedWords(string launcherFile, string outcome, TimeSpan? elapsed) =>
        $"finished {launcherFile} — {outcome}{(elapsed is { } took ? DurationWords(took) : "")}";

    /// <summary>How long a task took, in the window's words: " after 12s", " after 3m 4s".</summary>
    public static string DurationWords(TimeSpan elapsed) =>
        elapsed.TotalSeconds < 60
            ? $" after {Math.Max(1, (int)elapsed.TotalSeconds)}s"
            : $" after {(int)elapsed.TotalMinutes}m {elapsed.Seconds}s";

    /// <summary>
    /// Exit 3: a launcher run with <c>--non-interactive</c> reached a question
    /// and refused rather than wait for an answer nobody could give
    /// (<c>activityTrail.mustRecord</c> → "task finished" → <c>why</c>, #378).
    /// The headless path always runs its launchers that way.
    /// </summary>
    public const string StoppedAtAQuestionNobodyCouldAnswer = "stopped at a question nobody was there to answer (exit 3)";

    /// <summary>A headless run whose caller stopped waiting for it (the assistant's call was cancelled): the launcher was ended part way.</summary>
    public const string StoppedBeforeItFinished = "stopped before it finished";

    /// <summary>The outcome of a headless run that exited: exit 3 in its own words, any other exit in the window's.</summary>
    public static string HeadlessOutcome(int exitCode) =>
        exitCode == 3
            ? StoppedAtAQuestionNobodyCouldAnswer
            : ScriptRunner.FinishedOutcome(exitCode, wasStoppedByUser: false, wasCancelled: false, wasClosedForADeploy: false);

    /// <summary>
    /// The course and section a launcher's arguments name: every launcher
    /// takes the course code first and the section number second
    /// (<c>PreviewCommand.BuildOnlyArguments</c>, <c>DeployCommand.Arguments</c>).
    /// No course when the first argument is a flag; section 0 (none, for
    /// <see cref="Place"/>) when the second is not a number.
    /// </summary>
    public static (string Course, int Section) PlaceOfLauncherArguments(IReadOnlyList<string> arguments)
    {
        if (arguments.Count == 0 || arguments[0].StartsWith('-')) return ("", 0);
        int section = 0;
        if (arguments.Count > 1)
            int.TryParse(arguments[1], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out section);
        return (arguments[0], section);
    }

    /// <summary>The words for <c>section restore stopped part way</c>: the mac's <c>sectionRestoreStoppedPartWayLine</c> word for word.</summary>
    public static string SectionRestoreStoppedPartWayLine(string keptAt) =>
        "a section restore stopped part way and could not move every file back; the section may hold " +
        "some files from the backup and some as they were; the files set aside are kept in " + keptAt;

    /// <summary>
    /// The words for <c>section restored</c> from Restore from Backup…'s
    /// "Restore Section N" (#911, the mac's <c>restoredOneSectionFromTheMenuLine</c>
    /// word for word): the backup's file name, the archive made of the whole
    /// course first, and counts of shared pages hidden and not saved, never which.
    /// </summary>
    public static string RestoredOneSectionFromTheMenuLine(string backupFileName, string? archiveFileName, int pagesMadeSinceHidden, int pagesNotSaved)
    {
        string line = $"put the section back from {backupFileName}, from Restore from Backup…";
        if (archiveFileName is not null) line += $"; the course as it was is in Archived as {archiveFileName}";
        if (pagesMadeSinceHidden == 1) line += "; 1 shared page made since the backup is now hidden from this section";
        else if (pagesMadeSinceHidden > 1) line += $"; {pagesMadeSinceHidden} shared pages made since the backup are now hidden from this section";
        if (pagesNotSaved == 1) line += "; 1 shared page could not be saved and is as it was";
        else if (pagesNotSaved > 1) line += $"; {pagesNotSaved} shared pages could not be saved and are as they were";
        return line;
    }

    /// <summary>The words for `page settings left as they were`, the mac's <c>pageSettingsLeftAsTheyWereLine</c> word for word.</summary>
    public static string PageSettingsLeftAsTheyWereLine(string act, int pages) =>
        $"left the settings of {(pages == 1 ? "1 page" : $"{pages} pages")} as they were while {act}: no room at the top for a new setting";

    /// <summary>
    /// The words of <c>site built again before deploying</c> after the course
    /// and section, which <see cref="Note(Event, string, string, int, DateTime?)"/>
    /// puts in front: the contract's <c>line</c> with <c>whyWords</c> for
    /// <paramref name="reason"/>, or <c>lineWhenItHadNotBeenBuilt</c> for
    /// <c>neverBuilt</c>. A reason the contract does not name gets the
    /// toolchain's words, which is what deploy.ps1 says for a check that
    /// failed, never a sentence of its own. Pinned against the contract by
    /// <c>BuiltBeforeDeployingTrailTests</c>.
    /// </summary>
    public static string BuiltBeforeDeployingWords(string reason) => reason switch
    {
        "neverBuilt" => "built the website before deploying it — it had not been built yet",
        _ => "built the website again before deploying it — " + reason switch
        {
            "pages" => "something in the course had changed since it was last built",
            "preview" => "the last build was made by a preview",
            "clock" => "its last build was dated later than now, so the computer's clock had changed",
            "frontPageUnreadable" => "its front page could not be read",
            _ => "Plantoir had been updated since it was last built",
        },
    };

    /// <summary>Writes <c>site built again before deploying</c> for one build.</summary>
    public static void NoteBuiltBeforeDeploying(string course, int section, string reason) =>
        Note(Event.SiteBuiltAgainBeforeDeploying, BuiltBeforeDeployingWords(reason), course, section);

    public static void NoteLaunch()
    {
        Note(Event.AppOpened, "Plantoir opened — " + ProblemReportEnvironment.AppDescription);
        Note(Event.Machine, "running on " + ProblemReportEnvironment.SystemDescription);
        Note(Event.Helpers, "using " + ProblemReportEnvironment.HelperDescription);
        System.Threading.Interlocked.Exchange(ref _openedLineWritten, 1);
    }

    // 1 once this process wrote "Plantoir opened"; 1 once it wrote "Plantoir closed".
    private static int _openedLineWritten;
    private static int _closedLineWritten;

    /// <summary>
    /// "Plantoir closed — quit by the teacher · pid 4711" (#565, mac #560;
    /// <c>mustRecord</c> → "app closed"). On the SAME guard as the opened line:
    /// only a process that wrote "Plantoir opened" writes it, so a scheduled
    /// run or a marketing capture leaves no unpaired close; and only ONCE,
    /// because every window hears the end of a session and the last window's
    /// close may follow it.
    /// </summary>
    /// <param name="sessionEndingWait">Given only at the end of a session
    /// (WM_ENDSESSION), where Windows ends a process that does not answer
    /// within a few seconds (#565 plan review, item 5): the whole wait — this
    /// process's own lock and the writers' lock together — is capped at it,
    /// and the line is tried once, since there is no later moment to retry.
    /// Without it (the ordinary quit) the line waits for this process's lock
    /// as every line does, and is counted as written only once it has been.</param>
    /// <returns>True when the line was written by this call.</returns>
    public static bool NoteClosed(QuitConfirmation.ClosingReason reason, TimeSpan? sessionEndingWait = null)
    {
        if (System.Threading.Volatile.Read(ref _openedLineWritten) == 0) return false;
        string line = ClosedLine(reason, Environment.ProcessId);
        if (sessionEndingWait is { } wait)
        {
            if (System.Threading.Interlocked.Exchange(ref _closedLineWritten, 1) == 1) return false;
            return Note(Event.AppClosed, line, wait, capsThisProcess: true);
        }
        if (System.Threading.Volatile.Read(ref _closedLineWritten) == 1) return false;
        if (!Note(Event.AppClosed, line, WritersWait, capsThisProcess: false)) return false;
        System.Threading.Volatile.Write(ref _closedLineWritten, 1);
        return true;
    }

    /// <summary>A line written with its own wait for the writers' lock; true when it was written.</summary>
    private static bool Note(Event @event, string what, TimeSpan lockWait, bool capsThisProcess) =>
        Append(SafeTrailLine($"{DateText.Stamp(DateTime.Now)} · {what}", keepingLineBreaks: false), lockWait, capsThisProcess);

    /// <summary>The close line's words; the contract's <c>line</c> is this with reason "quit by the teacher".</summary>
    public static string ClosedLine(QuitConfirmation.ClosingReason reason, int processId) =>
        $"Plantoir closed — {QuitConfirmation.Words(reason)} · pid {processId}";

    /// <summary>For tests: forget that this process wrote either line.</summary>
    internal static void ResetOpenAndCloseForTests(bool opened)
    {
        System.Threading.Volatile.Write(ref _openedLineWritten, opened ? 1 : 0);
        System.Threading.Volatile.Write(ref _closedLineWritten, 0);
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

    private static readonly TimeSpan WritersWait = TimeSpan.FromSeconds(5);

    private static void Append(string line) => Append(line, WritersWait, capsThisProcess: false);

    /// <param name="capsThisProcess">True for the end-of-session line only: the
    /// wait then caps this process's own lock too. Every other line waits for
    /// it as long as it takes, as before. Said by every caller, never defaulted.</param>
    /// <returns>True when the line reached the file.</returns>
    private static bool Append(string line, TimeSpan wait, bool capsThisProcess)
    {
        // The wait caps BOTH locks: this process's own (another thread may be
        // inside its own mutex wait) and the writers' mutex across processes,
        // so the end-of-session line's 500 ms is the whole wait (#565 review).
        // A line that cannot get this process's lock in time is dropped rather
        // than written beside another thread's half-written one.
        var started = System.Diagnostics.Stopwatch.StartNew();
        if (!System.Threading.Monitor.TryEnter(_lock, capsThisProcess ? wait : System.Threading.Timeout.InfiniteTimeSpan)) return false;
        try
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
                    TimeSpan left = capsThisProcess ? wait - started.Elapsed : wait;
                    try { held = writers.WaitOne(left > TimeSpan.Zero ? left : TimeSpan.Zero); }
                    catch (System.Threading.AbandonedMutexException) { held = true; }   // a writer died holding it: ours now

                    // Written even when the wait timed out: a line that might
                    // interleave is better than a line certainly lost. Five
                    // seconds is far beyond one line's append (sub-millisecond).
                    using var stream = new FileStream(path, FileMode.Append, FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete);
                    stream.Write(bytes, 0, bytes.Length);
                    return true;
                }
                finally
                {
                    if (held) writers.ReleaseMutex();
                }
            }
            catch
            {
                // Never fail caller if log write fails
                return false;
            }
        }
        finally
        {
            System.Threading.Monitor.Exit(_lock);
        }
    }
}
